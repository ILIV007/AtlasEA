//+------------------------------------------------------------------+
//|                                    Infrastructure/MT5Adapter.mqh |
//|                AtlasEA v1.0 - MetaTrader 5 Broker Adapter        |
//+------------------------------------------------------------------+
#ifndef ATLAS_MT5_ADAPTER_MQH
#define ATLAS_MT5_ADAPTER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Core/IEventBus.mqh"

//+------------------------------------------------------------------+
//| MT5Adapter                                                       |
//|   - captures ticks and trade events from the terminal            |
//|   - wraps OrderSend with retry logic for REQUOTE / OFF_QUOTES    |
//|   - translates MQL retcodes into Atlas fill statuses             |
//|   - emits ExecutionEvents onto the bus                           |
//+------------------------------------------------------------------+
class MT5Adapter
{
private:
    IEventBus  *m_event_bus;
    AtlasConfig m_config;
    int         m_total_retries;

    bool   IsRetryableError(int retcode) const;
    int    TranslateRetcode(int retcode) const;     // -> ATLAS_FILL_*
    double CalculateSlippage(double req, double fill, int order_type) const;
    void   EmitExecutionEvent(const OrderRequest &req, const MqlTradeResult &result, int fill_status);

public:
                MT5Adapter(IEventBus *bus);
    bool        Initialize(const AtlasConfig &config);
    RawTick     CaptureTick(void);
    void        CaptureTrade(void);
    bool        SendOrder(const OrderRequest &req);
    PositionSnapshotEvent QueryBrokerPositions(void);
    int         TotalRetries(void) const { return m_total_retries; }
};

//+------------------------------------------------------------------+
MT5Adapter::MT5Adapter(IEventBus *bus)
{
    m_event_bus     = bus;
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
            retcode == TRADE_RETCODE_PRICE_CHANGED  ||
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
            Print("[MT5Adapter] Order filled. req=", req.request_id,
                  " vol=", DoubleToString(mt_res.volume, m_config.volume_digits),
                  " price=", DoubleToString(mt_res.price, _Digits),
                  " attempt=", attempt);
            return true;
        }

        //--- non-retryable or last attempt
        if(!IsRetryableError(ret) || attempt == m_config.max_retries)
        {
            EmitExecutionEvent(req, mt_res, TranslateRetcode(ret));
            Print("[MT5Adapter] Order FAILED. req=", req.request_id,
                  " retcode=", ret, " (", mt_res.comment, ")",
                  " attempt=", attempt);
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

#endif // ATLAS_MT5_ADAPTER_MQH
//+------------------------------------------------------------------+
