//+------------------------------------------------------------------+
//|                                     Engines/ExecutionEngine.mqh  |
//|                AtlasEA v1.0 - Order Request Builder              |
//+------------------------------------------------------------------+
#ifndef ATLAS_EXECUTION_ENGINE_MQH
#define ATLAS_EXECUTION_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Core/AtlasContext.mqh"

//+------------------------------------------------------------------+
//| ExecutionEngine                                                  |
//|   - validates RiskDecision                                       |
//|   - enforces idempotency (decision_id dedup)                     |
//|   - normalizes volume to broker step/min/max                     |
//|   - enforces SL/TP stops-level distance                          |
//|   - builds the final OrderRequest                                |
//+------------------------------------------------------------------+
class ExecutionEngine
{
private:
    AtlasConfig    m_config;
    AtlasContext  *m_context;

    bool   ValidateDecision(const RiskDecision &dec) const;
    bool   CheckIdempotency(const string &decision_id) const;
    double NormalizeVolume(double v) const;
    double ValidateStopLoss(double sl, int direction, double entry) const;
    double ValidateTakeProfit(double tp, int direction, double entry) const;
    double GetMinStopDistance(void) const;
    string BuildBrokerComment(const string &req_id, const string &dec_id) const;

public:
                ExecutionEngine(void);
    bool        Initialize(const AtlasConfig &config, AtlasContext *context);
    bool        BuildOrderRequest(const RiskDecision &dec, const MarketState &state, OrderRequest &req);
};

//+------------------------------------------------------------------+
ExecutionEngine::ExecutionEngine(void) { m_context = NULL; }

//+------------------------------------------------------------------+
bool ExecutionEngine::Initialize(const AtlasConfig &config, AtlasContext *context)
{
    m_config  = config;
    m_context = context;
    return true;
}

//+------------------------------------------------------------------+
bool ExecutionEngine::ValidateDecision(const RiskDecision &dec) const
{
    if(dec.status != ATLAS_DECISION_APPROVED)    return false;
    if(dec.approved_volume <= 0.0)               return false;
    if(dec.order_type == ATLAS_ORDER_NONE)       return false;
    if(dec.approved_price <= 0.0)                return false;
    if(dec.approved_sl <= 0.0)                   return false;
    if(dec.approved_tp <= 0.0)                   return false;
    return true;
}

//+------------------------------------------------------------------+
bool ExecutionEngine::CheckIdempotency(const string &decision_id) const
{
    if(m_context == NULL) return false;
    return !m_context.IsDecisionProcessed(decision_id);
}

//+------------------------------------------------------------------+
double ExecutionEngine::NormalizeVolume(double v) const
{
    double min_lot = SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MAX);
    double step    = SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_STEP);
    if(step <= 0.0) step = 0.01;
    double rounded = MathRound(v / step) * step;
    if(rounded < min_lot) rounded = min_lot;
    if(rounded > max_lot) rounded = max_lot;
    rounded = NormalizeDouble(rounded, m_config.volume_digits);
    return rounded;
}

//+------------------------------------------------------------------+
double ExecutionEngine::GetMinStopDistance(void) const
{
    long   stop_level = SymbolInfoInteger(m_config.symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double point      = SymbolInfoDouble(m_config.symbol, SYMBOL_POINT);
    double dist       = (double)stop_level * point;
    //--- add a small buffer so we never sit exactly on the stops-level
    return dist + point * 2.0;
}

//+------------------------------------------------------------------+
double ExecutionEngine::ValidateStopLoss(double sl, int direction, double entry) const
{
    double min_dist = GetMinStopDistance();
    int    digits   = (int)SymbolInfoInteger(m_config.symbol, SYMBOL_DIGITS);
    if(direction == ATLAS_ORDER_BUY)
    {
        double max_sl = entry - min_dist;
        if(sl <= 0.0 || sl >= max_sl) sl = max_sl;
    }
    else  // SELL
    {
        double min_sl = entry + min_dist;
        if(sl <= 0.0 || sl <= min_sl) sl = min_sl;
    }
    return NormalizeDouble(sl, digits);
}

//+------------------------------------------------------------------+
double ExecutionEngine::ValidateTakeProfit(double tp, int direction, double entry) const
{
    double min_dist = GetMinStopDistance();
    int    digits   = (int)SymbolInfoInteger(m_config.symbol, SYMBOL_DIGITS);
    if(direction == ATLAS_ORDER_BUY)
    {
        double min_tp = entry + min_dist;
        if(tp <= 0.0 || tp <= min_tp) tp = min_tp;
    }
    else  // SELL
    {
        double max_tp = entry - min_dist;
        if(tp <= 0.0 || tp >= max_tp) tp = max_tp;
    }
    return NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
string ExecutionEngine::BuildBrokerComment(const string &req_id, const string &dec_id) const
{
    //--- broker comment max 31 chars in MT5
    string c = "ATLAS_" + req_id;
    if(StringLen(c) > 31) c = StringSubstr(c, 0, 31);
    return c;
}

//+------------------------------------------------------------------+
//| BuildOrderRequest - the main entry point                         |
//+------------------------------------------------------------------+
bool ExecutionEngine::BuildOrderRequest(const RiskDecision &dec,
                                        const MarketState &state,
                                        OrderRequest &req)
{
    if(m_context == NULL)               return false;
    if(!ValidateDecision(dec))          return false;
    if(!CheckIdempotency(dec.decision_id)) return false;

    req.request_id    = "REQ_" + IntegerToString((long)TimeCurrent()) + "_" + IntegerToString(MathRand());
    req.decision_id   = dec.decision_id;
    req.symbol        = m_config.symbol;
    req.direction     = dec.order_type;
    req.order_type    = (dec.order_type == ATLAS_ORDER_BUY) ? (int)ORDER_TYPE_BUY : (int)ORDER_TYPE_SELL;
    req.volume        = NormalizeVolume(dec.approved_volume);

    //--- entry price: use current market for market orders
    double bid = SymbolInfoDouble(m_config.symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(m_config.symbol, SYMBOL_ASK);
    req.entry_price   = (req.direction == ATLAS_ORDER_BUY) ? ask : bid;

    //--- enforce stops-level distance
    req.stop_loss     = ValidateStopLoss(dec.approved_sl,    req.direction, req.entry_price);
    req.take_profit   = ValidateTakeProfit(dec.approved_tp,  req.direction, req.entry_price);

    req.magic_number  = m_config.magic_number;
    req.snapshot_id   = dec.snapshot_id;
    req.comment       = BuildBrokerComment(req.request_id, dec.decision_id);

    //--- mark decision as processed (idempotency)
    m_context.MarkDecisionProcessed(dec.decision_id);
    return true;
}

#endif // ATLAS_EXECUTION_ENGINE_MQH
//+------------------------------------------------------------------+
