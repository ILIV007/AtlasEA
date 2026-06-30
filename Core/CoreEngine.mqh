//+------------------------------------------------------------------+
//|                                            Core/CoreEngine.mqh   |
//|                AtlasEA v1.0 - Core Orchestrator (Event Bus)      |
//+------------------------------------------------------------------+
#ifndef ATLAS_CORE_ENGINE_MQH
#define ATLAS_CORE_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/IEventBus.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Core/RingBuffer.mqh"
#include "../Core/ContextGuardian.mqh"
#include "../Engines/MarketEngine.mqh"
#include "../Engines/StrategyEngine.mqh"
#include "../Engines/RiskEngine.mqh"
#include "../Engines/ExecutionEngine.mqh"
#include "../Infrastructure/MT5Adapter.mqh"
#include "../Infrastructure/TradeManager.mqh"
#include "../Infrastructure/PersistenceManager.mqh"

//+------------------------------------------------------------------+
//| CoreEngine                                                       |
//|   - implements IEventBus (single event sink for the whole EA)    |
//|   - runs the 4-phase pipeline per tick:                          |
//|       Market -> Strategy -> Risk -> Execution                    |
//|   - enforces phase budget (max_ms_per_tick)                      |
//|   - assigns monotonic snapshot_id                                |
//|   - ContextGuardian enforces single-writer on shared state       |
//+------------------------------------------------------------------+
class CoreEngine : public IEventBus
{
private:
    AtlasConfig       m_config;
    AtlasContext      m_context;
    ContextGuardian   m_guardian;
    EventRingBuffer   m_event_queue;
    EventRingBuffer   m_priority_queue;

    MarketEngine      m_market_engine;
    StrategyEngine    m_strategy_engine;
    RiskEngine        m_risk_engine;
    ExecutionEngine   m_execution_engine;
    MT5Adapter       *m_mt5_adapter;
    TradeManager     *m_trade_manager;
    PersistenceManager m_persistence;

    long              m_current_snapshot_id;
    datetime          m_last_snapshot_time;
    datetime          m_last_heartbeat_time;
    datetime          m_last_daily_check;
    MarketState       m_last_market_state;
    bool              m_initialized;
    bool              m_shutdown_requested;

    //--- internal helpers
    void   ProcessEvent(const AtlasEvent &event);
    void   RunMarketPhase(const RawTick &tick);
    void   RunStrategyPhase(const MarketState &state);
    void   RunRiskPhase(const AggregatedVote &vote);
    void   RunExecutionPhase(const RiskDecision &decision);
    AggregatedVote AggregateVotes(const StrategyVote &votes[], int count);
    string GenerateId(const string &prefix);
    bool   CheckDailyReset(void);
    void   EmitSimpleEvent(ENUM_ATLAS_EVENT_TYPE type, const string &source, long snapshot_id);

public:
                CoreEngine(void);
               ~CoreEngine(void);

    bool        Initialize(const AtlasConfig &config);
    void        Shutdown(int reason);

    void        OnTick(void);
    void        OnTrade(void);
    void        OnTimer(void);

    //--- IEventBus interface
    virtual void EmitEvent(const AtlasEvent &event);
    virtual void EmitPriorityEvent(const AtlasEvent &event);

    int         ProcessQueueBudget(ulong max_ms, int max_events);
    long        AssignSnapshotId(void);
    void        TriggerSnapshot(void);
    bool        ValidateWriteAccess(int module_id, int contract_type);
};

//+------------------------------------------------------------------+
CoreEngine::CoreEngine(void)
{
    m_current_snapshot_id  = 0;
    m_last_snapshot_time   = 0;
    m_last_heartbeat_time  = 0;
    m_last_daily_check     = 0;
    m_initialized          = false;
    m_shutdown_requested   = false;
    m_mt5_adapter          = NULL;
    m_trade_manager        = NULL;
}

//+------------------------------------------------------------------+
CoreEngine::~CoreEngine(void)
{
    Shutdown(0);
    if(m_mt5_adapter != NULL)   { delete m_mt5_adapter;   m_mt5_adapter   = NULL; }
    if(m_trade_manager != NULL) { delete m_trade_manager; m_trade_manager = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize - wire up all engines and the event bus               |
//+------------------------------------------------------------------+
bool CoreEngine::Initialize(const AtlasConfig &config)
{
    m_config = config;

    m_guardian.Attach(GetPointer(m_context));

    m_mt5_adapter   = new MT5Adapter(this);
    m_trade_manager = new TradeManager(this);

    if(!m_market_engine.Initialize(m_config))      { Print("[Core] MarketEngine init failed");       return false; }
    if(!m_strategy_engine.Initialize(m_config))    { Print("[Core] StrategyEngine init failed");     return false; }
    if(!m_risk_engine.Initialize(m_config, GetPointer(m_context))) { Print("[Core] RiskEngine init failed"); return false; }
    if(!m_execution_engine.Initialize(m_config, GetPointer(m_context))) { Print("[Core] ExecutionEngine init failed"); return false; }
    if(!m_mt5_adapter.Initialize(m_config))        { Print("[Core] MT5Adapter init failed");         return false; }
    if(!m_trade_manager.Initialize(m_config, GetPointer(m_context))) { Print("[Core] TradeManager init failed"); return false; }
    if(!m_persistence.Initialize(m_config, GetPointer(m_context)))   { Print("[Core] PersistenceManager init failed"); return false; }

    //--- attempt state recovery
    m_persistence.RecoverState(m_context);

    //--- if kill switch was active on a previous (same-day) session, keep it
    //--- otherwise seed daily stats
    if(!m_context.kill_switch_active)
    {
        m_context.trading_day_start  = TimeCurrent();
        m_context.daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_context.daily_peak_equity  = m_context.daily_start_equity;
    }
    m_last_daily_check = TimeCurrent();

    EventSetTimer(m_config.heartbeat_interval_sec);

    m_initialized = true;
    Print("[CoreEngine] AtlasEA v1.0 initialized. Symbol=", m_config.symbol,
          " Magic=", m_config.magic_number,
          " KillSwitch=", m_context.kill_switch_active);
    return true;
}

//+------------------------------------------------------------------+
void CoreEngine::Shutdown(int reason)
{
    if(!m_initialized) return;
    m_shutdown_requested = true;

    EventKillTimer();

    EmitSimpleEvent(EV_SYSTEM_SHUTDOWN, "CoreEngine", m_current_snapshot_id);

    //--- drain the queues
    ProcessQueueBudget(1000, 200);

    //--- final snapshot
    m_persistence.WriteSnapshot(m_context, m_current_snapshot_id);
    m_persistence.FlushEventBuffer();

    m_market_engine.Shutdown();

    m_initialized = false;
    Print("[CoreEngine] Shutdown complete (reason=", reason, ")");
}

//+------------------------------------------------------------------+
long CoreEngine::AssignSnapshotId(void)
{
    m_current_snapshot_id++;
    m_context.current_snapshot_id = m_current_snapshot_id;
    return m_current_snapshot_id;
}

//+------------------------------------------------------------------+
bool CoreEngine::ValidateWriteAccess(int module_id, int contract_type)
{
    return m_guardian.ValidateWriteAccess(module_id, contract_type);
}

//+------------------------------------------------------------------+
void CoreEngine::EmitSimpleEvent(ENUM_ATLAS_EVENT_TYPE type, const string &source, long snapshot_id)
{
    AtlasEvent ev;
    ev.type          = type;
    ev.source_module = source;
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = snapshot_id;
    ev.payload_size  = 0;
    EmitEvent(ev);
}

//+------------------------------------------------------------------+
//| IEventBus implementation                                         |
//+------------------------------------------------------------------+
void CoreEngine::EmitEvent(const AtlasEvent &event)
{
    if(!m_event_queue.Enqueue(event))
    {
        //--- queue full -> emit an error to the priority queue
        AtlasEvent err;
        err.type          = EV_ERROR_OCCURRED;
        err.source_module = "CoreEngine";
        err.timestamp     = TimeCurrent();
        err.snapshot_id   = event.snapshot_id;
        err.payload_size  = 0;
        m_priority_queue.Enqueue(err);
    }
    m_context.total_events_emitted++;
}

//+------------------------------------------------------------------+
void CoreEngine::EmitPriorityEvent(const AtlasEvent &event)
{
    if(!m_priority_queue.Enqueue(event))
        EmitEvent(event);  // fall back to normal queue
    m_context.total_events_emitted++;
}

//+------------------------------------------------------------------+
string CoreEngine::GenerateId(const string &prefix)
{
    return prefix + "_" + IntegerToString((long)TimeCurrent()) + "_" + IntegerToString(MathRand());
}

//+------------------------------------------------------------------+
//| CheckDailyReset - roll daily risk stats on new trading day       |
//+------------------------------------------------------------------+
bool CoreEngine::CheckDailyReset(void)
{
    MqlDateTime now, start;
    TimeToStruct(TimeCurrent(), now);
    TimeToStruct(m_context.trading_day_start, start);
    if(now.day != start.day || now.mon != start.mon || now.year != start.year)
    {
        m_risk_engine.ResetDailyLimits();
        //--- clear kill switch on a new day (operator must explicitly re-enable)
        m_context.kill_switch_active = false;
        m_context.kill_switch_reason = "";
        m_context.consecutive_losses = 0;
        Print("[CoreEngine] New trading day - daily limits reset.");
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| OnTick - the main per-tick entry point                           |
//+------------------------------------------------------------------+
void CoreEngine::OnTick(void)
{
    if(!m_initialized || m_shutdown_requested) return;

    ulong start_ms = GetTickCount64();
    m_context.total_ticks_processed++;
    m_context.current_tick_time = TimeCurrent();

    //--- daily reset check (cheap)
    if(TimeCurrent() - m_last_daily_check > 60)
    {
        CheckDailyReset();
        m_last_daily_check = TimeCurrent();
    }

    //--- Phase 1: Market
    RawTick tick = m_mt5_adapter.CaptureTick();
    EmitSimpleEvent(EV_TICK_RECEIVED, "MT5Adapter", m_current_snapshot_id);
    RunMarketPhase(tick);

    //--- drain queued events within remaining budget
    ulong elapsed   = GetTickCount64() - start_ms;
    ulong remaining = (m_config.max_ms_per_tick > elapsed)
                      ? (m_config.max_ms_per_tick - elapsed) : 0;
    ProcessQueueBudget(remaining, m_config.max_events_per_tick);
}

//+------------------------------------------------------------------+
//| RunMarketPhase - capture tick -> MarketState                     |
//+------------------------------------------------------------------+
void CoreEngine::RunMarketPhase(const RawTick &tick)
{
    long snap_id = AssignSnapshotId();

    //--- single-writer enforcement
    if(!m_guardian.AcquireWriteAccess(ATLAS_MODULE_MARKET, ATLAS_CONTRACT_MARKET_STATE))
    {
        Print("[Core] Write access denied for MarketEngine");
        return;
    }
    MarketState state = m_market_engine.ProcessTick(tick, snap_id);
    m_guardian.ReleaseWriteAccess(ATLAS_MODULE_MARKET, ATLAS_CONTRACT_MARKET_STATE);

    m_last_market_state = state;

    EmitSimpleEvent(EV_MARKET_STATE_UPDATED, "MarketEngine", snap_id);

    if(state.is_valid && !m_context.kill_switch_active)
        RunStrategyPhase(state);
}

//+------------------------------------------------------------------+
//| RunStrategyPhase - evaluate strategies -> votes -> aggregate     |
//+------------------------------------------------------------------+
void CoreEngine::RunStrategyPhase(const MarketState &state)
{
    StrategyVote votes[ATLAS_MAX_VOTES];
    int count = m_strategy_engine.EvaluateStrategies(state, votes);
    if(count == 0) return;

    for(int i = 0; i < count; i++)
        EmitSimpleEvent(EV_STRATEGY_VOTE_SUBMITTED, "StrategyEngine", state.snapshot_id);

    AggregatedVote agg = AggregateVotes(votes, count);

    EmitSimpleEvent(EV_VOTES_AGGREGATED, "StrategyEngine", state.snapshot_id);

    RunRiskPhase(agg);
}

//+------------------------------------------------------------------+
//| AggregateVotes - confidence-weighted direction vote              |
//+------------------------------------------------------------------+
AggregatedVote CoreEngine::AggregateVotes(const StrategyVote &votes[], int count)
{
    AggregatedVote agg;
    agg.aggregation_id = GenerateId("AGG");
    agg.vote_count     = count;
    agg.snapshot_id    = (count > 0) ? votes[0].snapshot_id : 0;

    double sum_buy_conf  = 0.0;
    double sum_sell_conf = 0.0;

    for(int i = 0; i < count; i++)
    {
        agg.votes[i] = votes[i];
        if(votes[i].direction == ATLAS_ORDER_BUY)
            sum_buy_conf  += votes[i].confidence;
        else if(votes[i].direction == ATLAS_ORDER_SELL)
            sum_sell_conf += votes[i].confidence;
    }

    if(sum_buy_conf > sum_sell_conf && sum_buy_conf > 0.0)
    {
        agg.direction  = ATLAS_ORDER_BUY;
        agg.confidence = sum_buy_conf / count;
    }
    else if(sum_sell_conf > 0.0)
    {
        agg.direction  = ATLAS_ORDER_SELL;
        agg.confidence = sum_sell_conf / count;
    }
    else
    {
        agg.direction  = ATLAS_ORDER_NONE;
        agg.confidence = 0.0;
    }
    return agg;
}

//+------------------------------------------------------------------+
//| RunRiskPhase - render RiskDecision from AggregatedVote            |
//+------------------------------------------------------------------+
void CoreEngine::RunRiskPhase(const AggregatedVote &vote)
{
    RiskDecision dec = m_risk_engine.EvaluateRisk(vote);

    EmitSimpleEvent(EV_RISK_DECISION_RENDERED, "RiskEngine", vote.snapshot_id);

    if(dec.status == ATLAS_DECISION_APPROVED)
        RunExecutionPhase(dec);
    else if(dec.kill_switch_triggered || m_context.kill_switch_active)
        EmitSimpleEvent(EV_KILL_SWITCH_ACTIVATED, "RiskEngine", vote.snapshot_id);
}

//+------------------------------------------------------------------+
//| RunExecutionPhase - build OrderRequest -> dispatch via adapter   |
//+------------------------------------------------------------------+
void CoreEngine::RunExecutionPhase(const RiskDecision &decision)
{
    OrderRequest req;
    if(!m_execution_engine.BuildOrderRequest(decision, m_last_market_state, req))
    {
        Print("[Core] BuildOrderRequest failed for decision ", decision.decision_id);
        return;
    }

    EmitSimpleEvent(EV_ORDER_REQUESTED, "ExecutionEngine", decision.snapshot_id);

    bool sent = m_mt5_adapter.SendOrder(req);
    m_context.total_orders_sent++;

    if(sent)
        EmitSimpleEvent(EV_ORDER_DISPATCHED, "MT5Adapter", decision.snapshot_id);

    //--- reconcile positions immediately after a send attempt
    PositionSnapshotEvent snap = m_mt5_adapter.QueryBrokerPositions();
    m_trade_manager.ReconcilePositions(snap);
}

//+------------------------------------------------------------------+
//| OnTrade - broker trade event -> reconcile + emit                 |
//+------------------------------------------------------------------+
void CoreEngine::OnTrade(void)
{
    if(!m_initialized) return;
    m_mt5_adapter.CaptureTrade();
    PositionSnapshotEvent snap = m_mt5_adapter.QueryBrokerPositions();
    m_trade_manager.ReconcilePositions(snap);
}

//+------------------------------------------------------------------+
//| OnTimer - heartbeat + snapshot + queue drain                     |
//+------------------------------------------------------------------+
void CoreEngine::OnTimer(void)
{
    if(!m_initialized) return;
    datetime now = TimeCurrent();

    //--- heartbeat
    if((long)(now - m_last_heartbeat_time) >= m_config.heartbeat_interval_sec)
    {
        m_last_heartbeat_time = now;
        m_trade_manager.UpdatePricesOnHeartbeat(m_last_market_state);
        m_risk_engine.UpdateExposure();
        EmitSimpleEvent(EV_HEARTBEAT, "CoreEngine", m_current_snapshot_id);
    }

    //--- periodic snapshot
    if((long)(now - m_last_snapshot_time) >= m_config.snapshot_interval_sec)
    {
        TriggerSnapshot();
        m_last_snapshot_time = now;
    }

    //--- drain queue (timer has more budget than a tick)
    ProcessQueueBudget(500, 100);
}

//+------------------------------------------------------------------+
void CoreEngine::TriggerSnapshot(void)
{
    long id = AssignSnapshotId();
    if(m_persistence.WriteSnapshot(m_context, id))
        EmitSimpleEvent(EV_STATE_PERSISTED, "PersistenceManager", id);
}

//+------------------------------------------------------------------+
//| ProcessQueueBudget - drain events within time/count budget       |
//+------------------------------------------------------------------+
int CoreEngine::ProcessQueueBudget(ulong max_ms, int max_events)
{
    ulong start    = GetTickCount64();
    int    processed = 0;

    //--- priority queue first
    while(!m_priority_queue.IsEmpty() && processed < max_events)
    {
        AtlasEvent ev;
        if(!m_priority_queue.Dequeue(ev)) break;
        ProcessEvent(ev);
        processed++;
        if(GetTickCount64() - start >= max_ms) break;
    }

    //--- normal queue
    while(!m_event_queue.IsEmpty() && processed < max_events)
    {
        AtlasEvent ev;
        if(!m_event_queue.Dequeue(ev)) break;
        ProcessEvent(ev);
        processed++;
        if(GetTickCount64() - start >= max_ms) break;
    }
    return processed;
}

//+------------------------------------------------------------------+
//| ProcessEvent - dispatch a single event to its handler             |
//+------------------------------------------------------------------+
void CoreEngine::ProcessEvent(const AtlasEvent &event)
{
    switch(event.type)
    {
        case EV_TICK_RECEIVED:
        case EV_MARKET_STATE_UPDATED:
        case EV_STRATEGY_VOTE_SUBMITTED:
        case EV_VOTES_AGGREGATED:
        case EV_RISK_DECISION_RENDERED:
        case EV_ORDER_REQUESTED:
        case EV_ORDER_DISPATCHED:
            //--- these are flow signals; no side effect beyond logging
            m_persistence.AppendEvent(event);
            break;

        case EV_TRADE_EXECUTED:
        {
            PositionSnapshotEvent snap = m_mt5_adapter.QueryBrokerPositions();
            m_trade_manager.ReconcilePositions(snap);
            m_persistence.AppendEvent(event);
            break;
        }

        case EV_ERROR_OCCURRED:
            Print("[Core] ERROR event from ", event.source_module,
                  " snapshot=", event.snapshot_id);
            break;

        case EV_HEARTBEAT:
            m_persistence.AppendEvent(event);
            break;

        case EV_STATE_PERSISTED:
            break;

        case EV_SYSTEM_SHUTDOWN:
            Print("[Core] Shutdown event propagated.");
            break;

        case EV_KILL_SWITCH_ACTIVATED:
            Print("[Core] *** KILL SWITCH ACTIVE *** - trading halted.");
            m_persistence.AppendEvent(event);
            break;
    }
}

#endif // ATLAS_CORE_ENGINE_MQH
//+------------------------------------------------------------------+
