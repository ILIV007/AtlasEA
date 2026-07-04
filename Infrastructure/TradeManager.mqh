//+------------------------------------------------------------------+
//|                                  Infrastructure/TradeManager.mqh |
//|                AtlasEA v1.0 - Position / Fill Manager            |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_MANAGER_MQH
#define ATLAS_TRADE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IPositionStore.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"

//+------------------------------------------------------------------+
//| TradeManager                                                     |
//|   - mirrors broker positions into IContextStore                   |
//|   - reconciles internal state vs broker on every OnTrade         |
//|   - recalculates floating PnL on heartbeat                       |
//+------------------------------------------------------------------+
class TradeManager : public IPositionStore
{
private:
    IEventBus      *m_event_bus;
    AtlasConfig     m_config;
    IContextStore  *m_context;
    ILogger        *m_logger;
    IBrokerAdapter *m_broker;
    datetime        m_last_update;

    double CalculatePnL(int type, double volume, double open_price, double bid, double ask) const;

public:
                TradeManager(IEventBus *bus);

    //--- IPositionStore overrides ---
    virtual bool   Initialize(void) override { return true; }
    virtual void   Shutdown(void) override { m_event_bus = NULL; m_context = NULL; }
    virtual void   ProcessFill(const ExecutionEvent &event) override;
    virtual void   ReconcilePositions(const PositionSnapshotEvent &snap) override;
    virtual void   UpdatePricesOnHeartbeat(const MarketState &state) override;
    virtual void   GetOpenPositions(PositionState &pos[], int &count) const override;

    //--- Extended init (called by Bootstrapper) ---
    void SetDependencies(IEventBus *bus, ILogger *logger, IContextStore *context,
                         IBrokerAdapter *broker, const AtlasConfig &config);
    bool Initialize(const AtlasConfig &config, IContextStore *context);

    //--- Design by Contract: validate internal invariants ---
    //    "If initialized": we infer initialization from the presence of any
    //    dependency pointer (SetDependencies wires them as a group). When
    //    initialized, both m_logger and m_broker must be non-NULL.
    ValidationResult Validate(void) const
    {
        bool initialized = (m_logger != NULL || m_broker != NULL || m_context != NULL);
        if(initialized)
        {
            if(m_logger == NULL)
                return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                                              "TradeManager initialized but m_logger is NULL",
                                              "m_logger");
            if(m_broker == NULL)
                return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                                              "TradeManager initialized but m_broker is NULL",
                                              "m_broker");
        }
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
TradeManager::TradeManager(IEventBus *bus)
{
    m_event_bus  = bus;
    m_context    = NULL;
    m_logger     = NULL;
    m_broker     = NULL;
    m_last_update = 0;
}

//+------------------------------------------------------------------+
void TradeManager::SetDependencies(IEventBus *bus, ILogger *logger, IContextStore *context,
                                    IBrokerAdapter *broker, const AtlasConfig &config)
{
    m_event_bus = bus;
    m_logger   = logger;
    m_context  = context;
    m_broker   = broker;
    m_config   = config;
}

//+------------------------------------------------------------------+
bool TradeManager::Initialize(const AtlasConfig &config, IContextStore *context)
{
    m_config  = config;
    m_context = context;
    return true;
}

//+------------------------------------------------------------------+
double TradeManager::CalculatePnL(int type, double volume, double open_price, double bid, double ask) const
{
    double diff = 0.0;
    if(type == POSITION_TYPE_BUY)
        diff = bid - open_price;
    else
        diff = open_price - ask;

    //--- Use broker adapter for tick value/size if available
    if(m_broker != NULL)
    {
        double point = m_broker.SymbolPoint();
        double contract = m_broker.SymbolContractSize();
        if(point > 0.0 && contract > 0.0)
            return diff / point * contract * volume / contract;
    }
    //--- fallback: raw price diff * volume
    return diff * volume;
}

//+------------------------------------------------------------------+
void TradeManager::ProcessFill(const ExecutionEvent &event)
{
    if(m_context == NULL) return;
    if(event.fill_status == ATLAS_FILL_FILLED || event.fill_status == ATLAS_FILL_PARTIAL)
    {
        m_context.IncrementOrdersFilled();
        m_context.IncrementDailyTradeCount();
    }
}

//+------------------------------------------------------------------+
//| ReconcilePositions - replace internal mirror with broker truth   |
//+------------------------------------------------------------------+
void TradeManager::ReconcilePositions(const PositionSnapshotEvent &snap)
{
    if(m_context == NULL) return;
    m_context.SetPositions(snap.broker_positions, snap.count);
}

//+------------------------------------------------------------------+
void TradeManager::UpdatePricesOnHeartbeat(const MarketState &state)
{
    if(m_context == NULL) return;

    double total_pnl = 0.0;
    int count = m_context.GetPositionCount();
    for(int i = 0; i < count; i++)
    {
        PositionState pos;
        m_context.GetPosition(i, pos);
        if(pos.symbol != state.symbol) continue;
        double pnl = CalculatePnL(pos.type, pos.volume, pos.open_price, state.bid, state.ask);
        total_pnl += pnl;
    }
    m_context.SetTotalFloatingPnl(total_pnl);
    m_last_update = TimeCurrent();
}

//+------------------------------------------------------------------+
void TradeManager::GetOpenPositions(PositionState &pos[], int &count) const
{
    if(m_context == NULL) { count = 0; return; }
    count = m_context.GetPositionCount();
    for(int i = 0; i < count; i++)
        m_context.GetPosition(i, pos[i]);
}

#endif // ATLAS_TRADE_MANAGER_MQH
//+------------------------------------------------------------------+
