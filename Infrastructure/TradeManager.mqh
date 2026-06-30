//+------------------------------------------------------------------+
//|                                  Infrastructure/TradeManager.mqh |
//|                AtlasEA v1.0 - Position / Fill Manager            |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_MANAGER_MQH
#define ATLAS_TRADE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Core/IEventBus.mqh"
#include "../Core/AtlasContext.mqh"

//+------------------------------------------------------------------+
//| TradeManager                                                     |
//|   - mirrors broker positions into AtlasContext                   |
//|   - reconciles internal state vs broker on every OnTrade         |
//|   - recalculates floating PnL on heartbeat                       |
//+------------------------------------------------------------------+
class TradeManager
{
private:
    IEventBus    *m_event_bus;
    AtlasConfig   m_config;
    AtlasContext *m_context;
    datetime      m_last_update;

    int    FindPositionByTicket(ulong ticket) const;
    double CalculatePnL(int type, double volume, double open_price, double bid, double ask) const;
    void   EmitThrottledUpdate(void);

public:
                TradeManager(IEventBus *bus);
    bool        Initialize(const AtlasConfig &config, AtlasContext *context);
    void        ProcessFill(const ExecutionEvent &event);
    void        ReconcilePositions(const PositionSnapshotEvent &snap);
    void        UpdatePricesOnHeartbeat(const MarketState &state);
    void        GetOpenPositions(PositionState &pos[], int &count) const;
};

//+------------------------------------------------------------------+
TradeManager::TradeManager(IEventBus *bus)
{
    m_event_bus  = bus;
    m_context    = NULL;
    m_last_update = 0;
}

//+------------------------------------------------------------------+
bool TradeManager::Initialize(const AtlasConfig &config, AtlasContext *context)
{
    m_config  = config;
    m_context = context;
    return true;
}

//+------------------------------------------------------------------+
int TradeManager::FindPositionByTicket(ulong ticket) const
{
    if(m_context == NULL) return -1;
    for(int i = 0; i < m_context.position_count; i++)
    {
        if((ulong)StringToInteger(m_context.positions[i].position_id) == ticket)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
double TradeManager::CalculatePnL(int type, double volume, double open_price, double bid, double ask) const
{
    double diff = 0.0;
    if(type == POSITION_TYPE_BUY)
        diff = bid - open_price;
    else
        diff = open_price - ask;

    double tick_value = SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size  = SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size > 0.0 && tick_value > 0.0)
        return diff / tick_size * tick_value * volume;
    //--- fallback: raw price diff * volume
    return diff * volume;
}

//+------------------------------------------------------------------+
void TradeManager::ProcessFill(const ExecutionEvent &event)
{
    if(m_context == NULL) return;
    if(event.fill_status == ATLAS_FILL_FILLED || event.fill_status == ATLAS_FILL_PARTIAL)
    {
        m_context.total_orders_filled++;
        m_context.daily_trade_count++;
    }
}

//+------------------------------------------------------------------+
//| ReconcilePositions - replace internal mirror with broker truth   |
//+------------------------------------------------------------------+
void TradeManager::ReconcilePositions(const PositionSnapshotEvent &snap)
{
    if(m_context == NULL) return;
    m_context.position_count = snap.count;
    for(int i = 0; i < snap.count && i < ATLAS_MAX_POSITIONS; i++)
        m_context.positions[i] = snap.broker_positions[i];
}

//+------------------------------------------------------------------+
void TradeManager::UpdatePricesOnHeartbeat(const MarketState &state)
{
    if(m_context == NULL) return;

    double total_pnl = 0.0;
    for(int i = 0; i < m_context.position_count; i++)
    {
        if(m_context.positions[i].symbol != state.symbol) continue;
        double pnl = CalculatePnL(m_context.positions[i].type,
                                  m_context.positions[i].volume,
                                  m_context.positions[i].open_price,
                                  state.bid, state.ask);
        m_context.positions[i].pnl = pnl;
        total_pnl += pnl;
    }
    m_context.total_floating_pnl = total_pnl;
    m_last_update = TimeCurrent();
}

//+------------------------------------------------------------------+
void TradeManager::GetOpenPositions(PositionState &pos[], int &count) const
{
    if(m_context == NULL) { count = 0; return; }
    count = m_context.position_count;
    for(int i = 0; i < count; i++)
        pos[i] = m_context.positions[i];
}

//+------------------------------------------------------------------+
void TradeManager::EmitThrottledUpdate(void)
{
    if(m_event_bus == NULL) return;
    if(TimeCurrent() - m_last_update < 5) return;
    AtlasEvent ev;
    ev.type          = EV_HEARTBEAT;
    ev.source_module = "TradeManager";
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = 0;
    ev.payload_size  = 0;
    m_event_bus.EmitEvent(ev);
    m_last_update = TimeCurrent();
}

#endif // ATLAS_TRADE_MANAGER_MQH
//+------------------------------------------------------------------+
