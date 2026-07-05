//+------------------------------------------------------------------+
//|                                    Infrastructure/MT5Adapter.mqh |
//|                AtlasEA v1.0 - MetaTrader 5 Broker Adapter        |
//+------------------------------------------------------------------+
#ifndef ATLAS_MT5_ADAPTER_MQH
#define ATLAS_MT5_ADAPTER_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"

//+------------------------------------------------------------------+
//| MT5Adapter                                                       |
//|   - captures ticks and trade events from the terminal            |
//|   - wraps OrderSend with retry logic for REQUOTE / OFF_QUOTES    |
//|   - translates MQL retcodes into Atlas fill statuses             |
//|   - emits ExecutionEvents onto the bus                           |
//+------------------------------------------------------------------+
class MT5Adapter : public IBrokerAdapter
{
private:
    IEventBus  *m_event_bus;
    ILogger    *m_logger;
    AtlasConfig m_config;
    int         m_total_retries;

    bool   IsRetryableError(int retcode) const;
    int    TranslateRetcode(int retcode) const;     // -> ATLAS_FILL_*
    double CalculateSlippage(double req, double fill, int order_type) const;
    void   EmitExecutionEvent(const OrderRequest &req, const MqlTradeResult &result, int fill_status);

public:
                MT5Adapter(IEventBus *bus);

    //--- Interface-compatible lifecycle (overrides) ---
    virtual bool   Initialize(void) override { return true; }
    virtual void   Shutdown(void) override { m_event_bus = NULL; }

    //--- Extended init with config (called by Bootstrapper) ---
    bool        Initialize(const AtlasConfig &config);

    //--- Set logger (called by Bootstrapper) ---
    void        SetLogger(ILogger *logger) { m_logger = logger; }

    //--- IBrokerAdapter overrides ---
    virtual RawTick     CaptureTick(void) override;
    virtual void        CaptureTrade(void) override;
    virtual bool        SendOrder(const OrderRequest &req) override;
    virtual int         CloseAllPositionsForMagic(const string reason) override;
    virtual bool        ModifyPositionSLTP(const string position_id, double sl, double tp) override;
    virtual bool        ClosePosition(const string position_id) override;
    virtual bool        ClosePartialPosition(const string position_id, double volume) override;
    virtual PositionSnapshotEvent QueryBrokerPositions(void) override;
    virtual int         CountPositionsForMagic(void) override;
    virtual double      AccountEquity(void) override;
    virtual double      AccountBalance(void) override;
    virtual double      AccountMargin(void) override;
    virtual double      AccountMarginLevel(void) override;
    virtual double      SymbolPoint(void) override;
    virtual int         SymbolDigits(void) override;
    virtual double      SymbolBid(void) override;
    virtual double      SymbolAsk(void) override;
    virtual double      SymbolVolumeMin(void) override;
    virtual double      SymbolVolumeMax(void) override;
    virtual double      SymbolVolumeStep(void) override;
    virtual long        SymbolStopsLevel(void) override;
    virtual double      SymbolContractSize(void) override;
    virtual long        SymbolFillingMode(void) override;
    virtual double      SymbolTickValue(void) override;
    virtual double      SymbolTickSize(void) override;
    virtual double      SymbolMarginInitial(void) override;
    virtual long        AccountLeverage(void) override;
    virtual int         CreateATR(int period) override;
    virtual int         CreateMA(int period, int ma_method, int applied_price) override;
    virtual int         CreateRSI(int period, int applied_price) override;
    virtual int         CreateMACD(int fast, int slow, int signal, int applied_price) override;
    virtual int         CreateStochastic(int k, int d, int slow, int ma_method, int price_field) override;
    virtual int         CreateCCI(int period, int applied_price) override;
    virtual int         CreateADX(int period) override;
    virtual int         CreateBands(int period, double deviation, int applied_price) override;
    virtual int         CopyBuffer(int handle, int buffer_num, int start, int count, double &buffer[]) override;
    virtual int         CopyRates(int start, int count, MqlRates &rates[]) override;
    virtual void        ReleaseIndicator(int handle) override;
    virtual int         PeriodSeconds(void) override;

    int         TotalRetries(void) const { return m_total_retries; }

    //--- Design by Contract: validate internal invariants ---
    //    The adapter is mostly stateless (a thin wrapper around the MT5
    //    terminal API). The only mutable state is m_total_retries, which
    //    must be non-negative. m_event_bus may legitimately be NULL (after
    //    Shutdown or before Initialize) — no structural check is possible
    //    on it; we just report Ok() since both states are valid.
    ValidationResult Validate(void) const
    {
        if(m_total_retries < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "m_total_retries < 0",
                                          "m_total_retries");
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
MT5Adapter::MT5Adapter(IEventBus *bus)
{
    m_event_bus     = bus;
    m_logger        = NULL;
    m_total_retries = 0;
}

//+------------------------------------------------------------------+
bool MT5Adapter::Initialize(const AtlasConfig &config)
{
    m_config = config;
    return true;
}

//+------------------------------------------------------------------+
//| CaptureTick - read the latest MqlTick and normalize              |
//+------------------------------------------------------------------+
RawTick MT5Adapter::CaptureTick(void)
{
    RawTick t;
    t.bid       = 0.0;
    t.ask       = 0.0;
    t.last      = 0.0;
    t.volume    = 0;
    t.timestamp = TimeCurrent();

    MqlTick mt;
    if(SymbolInfoTick(m_config.symbol, mt))
    {
        t.bid       = mt.bid;
        t.ask       = mt.ask;
        t.last      = mt.last;
        t.volume    = (long)mt.volume;
        t.timestamp = mt.time;
    }
    return t;
}

//+------------------------------------------------------------------+
bool MT5Adapter::IsRetryableError(int retcode) const
{
    return (retcode == TRADE_RETCODE_REQUOTE        ||
            retcode == TRADE_RETCODE_PRICE_OFF      ||
            retcode == TRADE_RETCODE_PRICE_CHANGED  ||
            retcode == TRADE_RETCODE_TIMEOUT        ||
            retcode == TRADE_RETCODE_CONNECTION     ||
            retcode == TRADE_RETCODE_ERROR);
}

//+------------------------------------------------------------------+
int MT5Adapter::TranslateRetcode(int retcode) const
{
    switch(retcode)
    {
        case TRADE_RETCODE_DONE:           return ATLAS_FILL_FILLED;
        case TRADE_RETCODE_DONE_PARTIAL:   return ATLAS_FILL_PARTIAL;
        case TRADE_RETCODE_REQUOTE:
        case TRADE_RETCODE_PRICE_OFF:
        case TRADE_RETCODE_PRICE_CHANGED:
        case TRADE_RETCODE_INVALID_PRICE:  return ATLAS_FILL_REJECTED;
        case TRADE_RETCODE_TIMEOUT:        return ATLAS_FILL_TIMEOUT;
        default:                           return ATLAS_FILL_REJECTED;
    }
}

//+------------------------------------------------------------------+
double MT5Adapter::CalculateSlippage(double req, double fill, int order_type) const
{
    if(order_type == ORDER_TYPE_BUY) return fill - req;
    return req - fill;
}

//+------------------------------------------------------------------+
void MT5Adapter::EmitExecutionEvent(const OrderRequest &req,
                                    const MqlTradeResult &result,
                                    int fill_status)
{
    if(m_event_bus == NULL) return;

    AtlasEvent ev;
    ev.type          = EV_TRADE_EXECUTED;
    ev.source_module = "MT5Adapter";
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = req.snapshot_id;
    ev.payload_size  = 0;

    //--- priority for fills so risk state updates immediately
    if(fill_status == ATLAS_FILL_FILLED || fill_status == ATLAS_FILL_PARTIAL)
        m_event_bus.EmitPriorityEvent(ev);
    else
        m_event_bus.EmitEvent(ev);
}

//+------------------------------------------------------------------+
//| SendOrder - OrderSend wrapper with retry on REQUOTE / OFF_QUOTES |
//+------------------------------------------------------------------+
bool MT5Adapter::SendOrder(const OrderRequest &req)
{
    MqlTradeRequest mt_req;
    MqlTradeResult  mt_res;
    ZeroMemory(mt_req);
    ZeroMemory(mt_res);

    mt_req.action     = TRADE_ACTION_DEALS;
    mt_req.symbol     = req.symbol;
    mt_req.volume     = req.volume;
    mt_req.type       = (ENUM_ORDER_TYPE)req.order_type;
    mt_req.price      = req.entry_price;
    mt_req.sl         = req.stop_loss;
    mt_req.tp         = req.take_profit;
    mt_req.deviation  = (ulong)m_config.slippage_points;
    mt_req.magic      = (ulong)req.magic_number;
    mt_req.comment    = req.comment;
    //--- pick the most permissive filling mode the symbol supports
    long fill_flags = SymbolInfoInteger(req.symbol, SYMBOL_FILLING_MODE);
    if((fill_flags & SYMBOL_FILLING_FOK) != 0)
        mt_req.type_filling = ORDER_FILLING_FOK;
    else if((fill_flags & SYMBOL_FILLING_IOC) != 0)
        mt_req.type_filling = ORDER_FILLING_IOC;
    else
        mt_req.type_filling = ORDER_FILLING_RETURN;

    for(int attempt = 0; attempt <= m_config.max_retries; attempt++)
    {
        ZeroMemory(mt_res);
        bool sent = OrderSend(mt_req, mt_res);
        int  ret  = (int)mt_res.retcode;

        if(sent && (ret == TRADE_RETCODE_DONE || ret == TRADE_RETCODE_DONE_PARTIAL))
        {
            int fill = (ret == TRADE_RETCODE_DONE) ? ATLAS_FILL_FILLED : ATLAS_FILL_PARTIAL;
            EmitExecutionEvent(req, mt_res, fill);
            if(m_logger != NULL)
                m_logger.Info("MT5Adapter", "Order filled. req=" + req.request_id +
                      " vol=" + DoubleToString(mt_res.volume, m_config.volume_digits) +
                      " price=" + DoubleToString(mt_res.price, _Digits) +
                      " attempt=" + IntegerToString(attempt));
            return true;
        }

        //--- non-retryable or last attempt
        if(!IsRetryableError(ret) || attempt == m_config.max_retries)
        {
            EmitExecutionEvent(req, mt_res, TranslateRetcode(ret));
            if(m_logger != NULL)
                m_logger.Error("MT5Adapter", "Order FAILED. req=" + req.request_id +
                      " retcode=" + IntegerToString(ret) + " (" + mt_res.comment + ")" +
                      " attempt=" + IntegerToString(attempt));
            return false;
        }

        //--- refresh price for retry
        if(ret == TRADE_RETCODE_REQUOTE || ret == TRADE_RETCODE_PRICE_CHANGED || ret == TRADE_RETCODE_PRICE_OFF)
        {
            MqlTick t;
            if(SymbolInfoTick(req.symbol, t))
            {
                if(req.order_type == ORDER_TYPE_BUY)  mt_req.price = t.ask;
                else                                  mt_req.price = t.bid;
            }
        }

        m_total_retries++;
        Sleep(m_config.retry_delay_ms);
    }

    //--- exhausted retries
    EmitExecutionEvent(req, mt_res, ATLAS_FILL_TIMEOUT);
    return false;
}

//+------------------------------------------------------------------+
//| QueryBrokerPositions - pull all positions matching our magic     |
//+------------------------------------------------------------------+
PositionSnapshotEvent MT5Adapter::QueryBrokerPositions(void)
{
    PositionSnapshotEvent snap;
    snap.count     = 0;
    snap.timestamp = TimeCurrent();

    int total = PositionsTotal();
    for(int i = 0; i < total && i < ATLAS_MAX_POSITIONS; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0)                       continue;
        if(!PositionSelectByTicket(ticket))   continue;
        if(PositionGetInteger(POSITION_MAGIC) != m_config.magic_number) continue;
        if(PositionGetString(POSITION_SYMBOL) != m_config.symbol)       continue;

        int idx = snap.count;
        snap.broker_positions[idx].position_id     = IntegerToString(ticket);
        snap.broker_positions[idx].symbol          = PositionGetString(POSITION_SYMBOL);
        snap.broker_positions[idx].type            = (int)PositionGetInteger(POSITION_TYPE);
        snap.broker_positions[idx].volume          = PositionGetDouble(POSITION_VOLUME);
        snap.broker_positions[idx].open_price      = PositionGetDouble(POSITION_PRICE_OPEN);
        snap.broker_positions[idx].current_sl      = PositionGetDouble(POSITION_SL);
        snap.broker_positions[idx].current_tp      = PositionGetDouble(POSITION_TP);
        snap.broker_positions[idx].pnl             = PositionGetDouble(POSITION_PROFIT);
        snap.broker_positions[idx].open_time       = (datetime)PositionGetInteger(POSITION_TIME);
        snap.broker_positions[idx].broker_verified = true;
        snap.count++;
    }
    return snap;
}

//+------------------------------------------------------------------+
//| CaptureTrade - invoked from OnTrade() to emit a trade event      |
//+------------------------------------------------------------------+
void MT5Adapter::CaptureTrade(void)
{
    if(m_event_bus == NULL) return;
    PositionSnapshotEvent snap = QueryBrokerPositions();

    AtlasEvent ev;
    ev.type          = EV_TRADE_EXECUTED;
    ev.source_module = "MT5Adapter";
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = 0;
    ev.payload_size  = 0;
    m_event_bus.EmitPriorityEvent(ev);
}

//+------------------------------------------------------------------+
//| Missing IBrokerAdapter method implementations                     |
//+------------------------------------------------------------------+

int MT5Adapter::CloseAllPositionsForMagic(const string reason)
{
    int closed = 0;
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
        req.price     = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(req.symbol, SYMBOL_BID)
                                                     : SymbolInfoDouble(req.symbol, SYMBOL_ASK);
        req.deviation = (ulong)m_config.slippage_points;
        req.magic     = (ulong)m_config.magic_number;
        req.comment   = "AtlasEA_KillSwitch";
        req.type_filling = ORDER_FILLING_IOC;
        if(OrderSend(req, res)) closed++;
    }
    return closed;
}

//+------------------------------------------------------------------+
//| ModifyPositionSLTP - modify SL/TP of an open position            |
//+------------------------------------------------------------------+
bool MT5Adapter::ModifyPositionSLTP(const string position_id, double sl, double tp)
{
    ulong ticket = (ulong)StringToInteger(position_id);
    if(ticket == 0) return false;
    if(!PositionSelectByTicket(ticket)) return false;

    MqlTradeRequest req; MqlTradeResult res;
    ZeroMemory(req); ZeroMemory(res);
    req.action   = TRADE_ACTION_SLTP;
    req.position = ticket;
    req.symbol   = PositionGetString(POSITION_SYMBOL);
    req.sl       = sl;
    req.tp       = tp;
    req.magic    = (ulong)m_config.magic_number;
    return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| ClosePosition - fully close a position at market                 |
//+------------------------------------------------------------------+
bool MT5Adapter::ClosePosition(const string position_id)
{
    ulong ticket = (ulong)StringToInteger(position_id);
    if(ticket == 0) return false;
    if(!PositionSelectByTicket(ticket)) return false;

    MqlTradeRequest req; MqlTradeResult res;
    ZeroMemory(req); ZeroMemory(res);
    req.action    = TRADE_ACTION_DEALS;
    req.position  = ticket;
    req.symbol    = PositionGetString(POSITION_SYMBOL);
    req.volume    = PositionGetDouble(POSITION_VOLUME);
    long ptype    = PositionGetInteger(POSITION_TYPE);
    req.type      = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    req.price     = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(req.symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(req.symbol, SYMBOL_ASK);
    req.deviation = (ulong)m_config.slippage_points;
    req.magic     = (ulong)m_config.magic_number;
    req.comment   = "AtlasEA_Close";
    req.type_filling = ORDER_FILLING_IOC;
    return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| ClosePartialPosition - partially close a position                |
//+------------------------------------------------------------------+
bool MT5Adapter::ClosePartialPosition(const string position_id, double volume)
{
    ulong ticket = (ulong)StringToInteger(position_id);
    if(ticket == 0) return false;
    if(!PositionSelectByTicket(ticket)) return false;

    double pos_vol = PositionGetDouble(POSITION_VOLUME);
    if(volume <= 0.0 || volume >= pos_vol) return false;

    //--- Normalize to volume step
    double step = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_VOLUME_STEP);
    if(step > 0.0) volume = MathRound(volume / step) * step;
    if(volume <= 0.0) return false;

    MqlTradeRequest req; MqlTradeResult res;
    ZeroMemory(req); ZeroMemory(res);
    req.action    = TRADE_ACTION_DEALS;
    req.position  = ticket;
    req.symbol    = PositionGetString(POSITION_SYMBOL);
    req.volume    = volume;
    long ptype    = PositionGetInteger(POSITION_TYPE);
    req.type      = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    req.price     = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(req.symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(req.symbol, SYMBOL_ASK);
    req.deviation = (ulong)m_config.slippage_points;
    req.magic     = (ulong)m_config.magic_number;
    req.comment   = "AtlasEA_Partial";
    req.type_filling = ORDER_FILLING_IOC;
    return OrderSend(req, res);
}

int MT5Adapter::CountPositionsForMagic(void)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) == m_config.magic_number) count++;
    }
    return count;
}

double MT5Adapter::AccountEquity(void)      { return AccountInfoDouble(ACCOUNT_EQUITY); }
double MT5Adapter::AccountBalance(void)     { return AccountInfoDouble(ACCOUNT_BALANCE); }
double MT5Adapter::AccountMargin(void)      { return AccountInfoDouble(ACCOUNT_MARGIN); }
double MT5Adapter::AccountMarginLevel(void) { return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); }

double MT5Adapter::SymbolPoint(void)        { return SymbolInfoDouble(m_config.symbol, SYMBOL_POINT); }
int    MT5Adapter::SymbolDigits(void)       { return (int)SymbolInfoInteger(m_config.symbol, SYMBOL_DIGITS); }
double MT5Adapter::SymbolBid(void)          { return SymbolInfoDouble(m_config.symbol, SYMBOL_BID); }
double MT5Adapter::SymbolAsk(void)          { return SymbolInfoDouble(m_config.symbol, SYMBOL_ASK); }
double MT5Adapter::SymbolVolumeMin(void)    { return SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MIN); }
double MT5Adapter::SymbolVolumeMax(void)    { return SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MAX); }
double MT5Adapter::SymbolVolumeStep(void)   { return SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_STEP); }
long   MT5Adapter::SymbolStopsLevel(void)   { return SymbolInfoInteger(m_config.symbol, SYMBOL_TRADE_STOPS_LEVEL); }
double MT5Adapter::SymbolContractSize(void) { return SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_CONTRACT_SIZE); }
long   MT5Adapter::SymbolFillingMode(void)  { return SymbolInfoInteger(m_config.symbol, SYMBOL_FILLING_MODE); }
double MT5Adapter::SymbolTickValue(void)    { return SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE); }
double MT5Adapter::SymbolTickSize(void)     { return SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_SIZE); }
double MT5Adapter::SymbolMarginInitial(void) { return SymbolInfoDouble(m_config.symbol, SYMBOL_MARGIN_INITIAL); }
long   MT5Adapter::AccountLeverage(void)    { return AccountInfoInteger(ACCOUNT_LEVERAGE); }

int MT5Adapter::CreateATR(int period)              { return iATR(m_config.symbol, PERIOD_CURRENT, period); }
int MT5Adapter::CreateMA(int p, int m, int ap)     { return iMA(m_config.symbol, PERIOD_CURRENT, p, 0, m, ap); }
int MT5Adapter::CreateRSI(int p, int ap)            { return iRSI(m_config.symbol, PERIOD_CURRENT, p, ap); }
int MT5Adapter::CreateMACD(int f, int s, int sig, int ap) { return iMACD(m_config.symbol, PERIOD_CURRENT, f, s, sig, ap); }
int MT5Adapter::CreateStochastic(int k, int d, int sl, int m, int pf) { return iStochastic(m_config.symbol, PERIOD_CURRENT, k, d, sl, m, pf); }
int MT5Adapter::CreateCCI(int p, int ap)            { return iCCI(m_config.symbol, PERIOD_CURRENT, p, ap); }
int MT5Adapter::CreateADX(int p)                    { return iADX(m_config.symbol, PERIOD_CURRENT, p); }
int MT5Adapter::CreateBands(int p, double dev, int ap) { return iBands(m_config.symbol, PERIOD_CURRENT, p, 0, dev, ap); }

int MT5Adapter::CopyBuffer(int handle, int buf, int start, int count, double &buffer[])
{
    return ::CopyBuffer(handle, buf, start, count, buffer);
}

int MT5Adapter::CopyRates(int start, int count, MqlRates &rates[])
{
    return ::CopyRates(m_config.symbol, PERIOD_CURRENT, start, count, rates);
}

void MT5Adapter::ReleaseIndicator(int handle)
{
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
}

int MT5Adapter::PeriodSeconds(void)
{
    return ::PeriodSeconds(PERIOD_CURRENT);
}

#endif // ATLAS_MT5_ADAPTER_MQH
//+------------------------------------------------------------------+
