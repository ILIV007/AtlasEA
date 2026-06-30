//+------------------------------------------------------------------+
//|                                           Engines/RiskEngine.mqh |
//|                AtlasEA v1.0 - Risk Management & Kill Switch      |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_ENGINE_MQH
#define ATLAS_RISK_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"

//+------------------------------------------------------------------+
//| RiskEngine                                                       |
//|   - tracks daily drawdown against peak equity                    |
//|   - computes net exposure vs equity                              |
//|   - kill switch is NON-BYPASSABLE once triggered                 |
//|   - renders RiskDecision for each AggregatedVote                 |
//+------------------------------------------------------------------+
class RiskEngine
{
private:
    AtlasConfig    m_config;
    AtlasContext  *m_context;

    bool   CheckDailyDrawdown(void);
    bool   CheckExposureLimit(double new_volume);
    bool   CheckMarginSafety(void) const;
    bool   CheckCooldowns(void);
    double CalculateApprovedVolume(const AggregatedVote &vote) const;
    RiskDecision RenderDecision(const AggregatedVote &vote, int status,
                                int reason_code, const string reason);
    void   CloseAllPositions(const string &reason);

public:
                RiskEngine(void);
    bool        Initialize(const AtlasConfig &config, AtlasContext *context);
    RiskDecision EvaluateRisk(const AggregatedVote &vote);
    void        UpdateRiskState(const ExecutionEvent &event);
    void        TriggerKillSwitch(const string &reason);
    void        ResetDailyLimits(void);
    void        UpdateExposure(void);
};

//+------------------------------------------------------------------+
RiskEngine::RiskEngine(void) { m_context = NULL; }

//+------------------------------------------------------------------+
bool RiskEngine::Initialize(const AtlasConfig &config, AtlasContext *context)
{
    m_config  = config;
    m_context = context;
    return true;
}

//+------------------------------------------------------------------+
void RiskEngine::ResetDailyLimits(void)
{
    if(m_context == NULL) return;
    m_context.daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_context.daily_peak_equity  = m_context.daily_start_equity;
    m_context.daily_drawdown_pct = 0.0;
    m_context.daily_realized_pnl = 0.0;
    m_context.daily_trade_count  = 0;
    m_context.daily_loss_count   = 0;
    m_context.trading_day_start  = TimeCurrent();
    Print("[RiskEngine] Daily limits reset. Start equity=", DoubleToString(m_context.daily_start_equity, 2));
}

//+------------------------------------------------------------------+
//| TriggerKillSwitch - NON-BYPASSABLE                               |
//| Once set, EvaluateRisk always rejects with KILLSWITCH reason.    |
//+------------------------------------------------------------------+
void RiskEngine::TriggerKillSwitch(const string &reason)
{
    if(m_context == NULL) return;
    if(m_context.kill_switch_active) return;
    m_context.kill_switch_active = true;
    m_context.kill_switch_reason = reason;
    m_context.kill_switch_time   = TimeCurrent();
    Print("[RiskEngine] *** KILL SWITCH ACTIVATED *** ", reason);
    CloseAllPositions(reason);
}

//+------------------------------------------------------------------+
void RiskEngine::CloseAllPositions(const string &reason)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != m_config.magic_number) continue;

        MqlTradeRequest req; MqlTradeResult res;
        ZeroMemory(req); ZeroMemory(res);
        req.action    = TRADE_ACTION_DEALS;
        req.position  = ticket;
        req.symbol    = PositionGetString(POSITION_SYMBOL);
        req.volume    = PositionGetDouble(POSITION_VOLUME);
        long ptype    = PositionGetInteger(POSITION_TYPE);
        req.type      = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        req.price     = (ptype == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(req.symbol, SYMBOL_BID)
                        : SymbolInfoDouble(req.symbol, SYMBOL_ASK);
        req.deviation = (ulong)m_config.slippage_points;
        req.magic     = (ulong)m_config.magic_number;
        req.comment   = "AtlasEA_KillSwitch";
        req.type_filling = ORDER_FILLING_IOC;
        OrderSend(req, res);
    }
}

//+------------------------------------------------------------------+
//| CheckDailyDrawdown - updates peak and computes current DD        |
//+------------------------------------------------------------------+
bool RiskEngine::CheckDailyDrawdown(void)
{
    if(m_context == NULL) return false;
    if(m_context.daily_start_equity <= 0.0) return false;

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity > m_context.daily_peak_equity)
        m_context.daily_peak_equity = equity;

    double dd = (m_context.daily_peak_equity - equity) / m_context.daily_start_equity * 100.0;
    m_context.daily_drawdown_pct = dd;

    if(dd >= ATLAS_KILL_SWITCH_DRAWDOWN)
    {
        TriggerKillSwitch("absolute_drawdown: " + DoubleToString(dd, 2) + "%");
        return false;
    }
    if(dd >= m_config.max_daily_drawdown_pct)
    {
        TriggerKillSwitch("daily_drawdown: " + DoubleToString(dd, 2) + "%");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| CheckExposureLimit - sum (volume * contract_size) / equity       |
//+------------------------------------------------------------------+
bool RiskEngine::CheckExposureLimit(double new_volume)
{
    if(m_context == NULL) return false;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0) return false;

    double contract_size = SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double current_vol   = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != m_config.symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != m_config.magic_number) continue;
        current_vol += PositionGetDouble(POSITION_VOLUME);
    }
    double total_vol      = current_vol + new_volume;
    double exposure_value = total_vol * contract_size;
    m_context.current_exposure_pct = exposure_value / equity;

    return (m_context.current_exposure_pct <= m_config.max_exposure_limit);
}

//+------------------------------------------------------------------+
bool RiskEngine::CheckMarginSafety(void) const
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    if(margin <= 0.0) return true;
    double level = equity / margin * 100.0;
    return (level > ATLAS_MARGIN_LEVEL_MIN);
}

//+------------------------------------------------------------------+
bool RiskEngine::CheckCooldowns(void)
{
    if(m_context == NULL) return true;
    if(m_context.cooldown_until > TimeCurrent()) return false;
    if(m_context.consecutive_losses >= ATLAS_KILL_SWITCH_LOSSES)
    {
        TriggerKillSwitch("consecutive_losses: " + IntegerToString(m_context.consecutive_losses));
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
double RiskEngine::CalculateApprovedVolume(const AggregatedVote &vote) const
{
    double base = m_config.base_volume;
    //--- scale by confidence (0.5x .. 1.0x of base)
    double scaled = base * (0.5 + vote.confidence * 0.5);
    if(scaled < m_config.min_volume) scaled = m_config.min_volume;
    if(scaled > m_config.max_volume) scaled = m_config.max_volume;
    return scaled;
}

//+------------------------------------------------------------------+
RiskDecision RiskEngine::RenderDecision(const AggregatedVote &vote,
                                        int status, int reason_code,
                                        const string reason)
{
    RiskDecision d;
    d.decision_id            = "DEC_" + IntegerToString((long)TimeCurrent()) + "_" + IntegerToString(MathRand());
    d.aggregation_id         = vote.aggregation_id;
    d.status                 = status;
    d.reason_code            = reason_code;
    d.rejection_reason       = reason;
    d.approved_volume        = 0.0;
    d.approved_price         = 0.0;
    d.approved_sl            = 0.0;
    d.approved_tp            = 0.0;
    d.order_type             = vote.direction;
    d.kill_switch_triggered  = (m_context != NULL && m_context.kill_switch_active);
    d.snapshot_id            = vote.snapshot_id;
    d.decision_time          = TimeCurrent();

    if(status == ATLAS_DECISION_APPROVED && vote.vote_count > 0)
    {
        double sum_entry = 0.0, sum_sl = 0.0, sum_tp = 0.0;
        for(int i = 0; i < vote.vote_count; i++)
        {
            sum_entry += vote.votes[i].suggested_entry;
            sum_sl    += vote.votes[i].suggested_sl;
            sum_tp    += vote.votes[i].suggested_tp;
        }
        d.approved_volume = CalculateApprovedVolume(vote);
        d.approved_price  = sum_entry / vote.vote_count;
        d.approved_sl     = sum_sl / vote.vote_count;
        d.approved_tp     = sum_tp / vote.vote_count;
    }
    return d;
}

//+------------------------------------------------------------------+
//| EvaluateRisk - the decision rendering pipeline                   |
//| Kill switch is checked FIRST and is NON-BYPASSABLE.              |
//+------------------------------------------------------------------+
RiskDecision RiskEngine::EvaluateRisk(const AggregatedVote &vote)
{
    if(m_context == NULL)
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_NO_CONTEXT, "no_context");

    //--- 1. Kill switch (non-bypassable, checked first)
    if(m_context.kill_switch_active)
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_KILLSWITCH,
                              "kill_switch: " + m_context.kill_switch_reason);

    //--- 2. No valid vote
    if(vote.direction == ATLAS_ORDER_NONE || vote.vote_count == 0)
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_NOVOTE, "no_valid_vote");

    //--- 3. Confidence floor
    if(vote.confidence < ATLAS_MIN_CONFIDENCE)
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_LOW_CONFIDENCE,
                              "low_confidence: " + DoubleToString(vote.confidence, 3));

    //--- 4. Daily drawdown
    if(!CheckDailyDrawdown())
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_DRAWDOWN,
                              "drawdown_limit: " + DoubleToString(m_context.daily_drawdown_pct, 2) + "%");

    //--- 5. Exposure
    double proposed_vol = CalculateApprovedVolume(vote);
    if(!CheckExposureLimit(proposed_vol))
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_EXPOSURE,
                              "exposure_exceeded: " + DoubleToString(m_context.current_exposure_pct, 3));

    //--- 6. Margin safety
    if(!CheckMarginSafety())
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_MARGIN, "margin_safety_failed");

    //--- 7. Cooldowns / consecutive losses
    if(!CheckCooldowns())
        return RenderDecision(vote, ATLAS_DECISION_REJECTED, ATLAS_RISK_REASON_COOLDOWN, "cooldown_active");

    //--- All checks passed -> approve
    return RenderDecision(vote, ATLAS_DECISION_APPROVED, ATLAS_RISK_REASON_OK, "");
}

//+------------------------------------------------------------------+
void RiskEngine::UpdateRiskState(const ExecutionEvent &event)
{
    if(m_context == NULL) return;
    m_context.daily_trade_count++;
    if(event.fill_status == ATLAS_FILL_FILLED || event.fill_status == ATLAS_FILL_PARTIAL)
    {
        m_context.total_orders_filled++;
        m_context.last_trade_time = event.execution_time;
    }
    if(event.fill_status == ATLAS_FILL_REJECTED)
    {
        m_context.consecutive_losses++;
        m_context.daily_loss_count++;
        //--- cooldown after consecutive losses
        if(m_context.consecutive_losses >= 3)
            m_context.cooldown_until = TimeCurrent() + 1800;  // 30 min
    }
    else if(event.fill_status == ATLAS_FILL_FILLED)
    {
        //--- reset consecutive-loss counter on a successful fill
        m_context.consecutive_losses = 0;
    }
}

//+------------------------------------------------------------------+
void RiskEngine::UpdateExposure(void)
{
    if(m_context == NULL) return;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0) return;
    double contract_size = SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double vol = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != m_config.symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != m_config.magic_number) continue;
        vol += PositionGetDouble(POSITION_VOLUME);
    }
    m_context.current_exposure_pct = (vol * contract_size) / equity;
    m_context.total_floating_pnl   = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) <= 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != m_config.magic_number) continue;
        m_context.total_floating_pnl += PositionGetDouble(POSITION_PROFIT);
    }
}

#endif // ATLAS_RISK_ENGINE_MQH
//+------------------------------------------------------------------+
