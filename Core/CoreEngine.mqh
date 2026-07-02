//+------------------------------------------------------------------+
//|                                          Core/CoreEngine.mqh
//|            AtlasEA v2.0 - Core Orchestrator & Event Bus           |
//+------------------------------------------------------------------+
#ifndef ATLAS_CORE_ENGINE_MQH
#define ATLAS_CORE_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/IMarketDataSource.mqh"
#include "../Interfaces/IStrategySet.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IPositionStore.mqh"
#include "../Interfaces/IStateStore.mqh"
#include "AtlasContext.mqh"
#include "NullLogger.mqh"
#include "ContextGuardian.mqh"
#include "ContextFactory.mqh"
#include "PermissionMatrix.mqh"
#include "RingBuffer.mqh"
#include "EventQueue.mqh"
#include "EventDispatcher.mqh"
#include "SnapshotManager.mqh"
#include "PhaseScheduler.mqh"
#include "TimeBudgetRunner.mqh"
#include "KillSwitchPropagator.mqh"
#include "PipelineStatistics.mqh"
#include "ModuleRegistry.mqh"

/**
 * @class CoreEngine
 * @brief Central orchestrator implementing IEventBus.
 *
 * Owns all Core infrastructure (context, queues, guardian, scheduler, etc.)
 * and wires injected engine/infra implementations via their interfaces.
 *
 * Responsibilities:
 *   - IEventBus implementation (Enqueue into EventQueue)
 *   - Lifecycle: Initialize / Shutdown
 *   - Tick pipeline: OnTick → PhaseScheduler.RunPipeline → EventDispatcher.ProcessBatch
 *   - Heartbeat: OnTimer → periodic snapshots, position reconciliation, exposure updates
 *   - Trade events: OnTrade → broker position reconciliation
 *   - Kill switch propagation
 *   - Daily reset detection
 *   - Module registration and discovery
 *
 * Memory: all Core components are stack-allocated. Engine/infra implementations
 * are injected as pointers (owned by the caller — typically AtlasEA.mq5).
 * No dynamic allocation in OnTick/OnTimer/OnTrade.
 *
 * Thread model: MQL5 single-threaded. No locks.
 */
class CoreEngine : public IEventBus
{
private:
    //=== Configuration ===
    AtlasConfig m_config;

    //=== Logger ===
    ILogger     *m_logger;          ///< Injected logger (or NullLogger)
    NullLogger   m_null_logger;     ///< Default no-op logger
    bool         m_owns_logger;     ///< true if we created the logger

    //=== Core infrastructure (stack-allocated, owned) ===
    AtlasContext        m_context;
    PermissionMatrix    m_permission_matrix;
    ContextGuardian     m_guardian;
    ContextFactory      m_context_factory;
    EventQueue          m_event_queue;
    EventDispatcher     m_dispatcher;
    SnapshotManager     m_snapshot_mgr;
    PhaseScheduler      m_scheduler;
    TimeBudgetRunner    m_budget;
    KillSwitchPropagator m_kill_switch;
    PipelineStatistics  m_stats;
    ModuleRegistry      m_registry;

    //=== Injected engine/infra (NOT owned — caller manages lifetime) ===
    IMarketDataSource *m_market_engine;
    IStrategySet      *m_strategy_engine;
    IRiskEvaluator    *m_risk_engine;
    IOrderBuilder     *m_execution_engine;
    IBrokerAdapter    *m_broker_adapter;
    IPositionStore    *m_trade_manager;
    IStateStore       *m_persistence;

    //=== State ===
    bool m_initialized;
    bool m_shutdown_requested;
    datetime m_last_heartbeat_time;
    datetime m_last_daily_check;

    /// @brief Register all default permissions in the matrix.
    void RegisterDefaultPermissions(void);

    /// @brief Register all Core modules in the registry.
    void RegisterCoreModules(void);

    /// @brief Check and perform daily reset if needed.
    void CheckDailyReset(void);

    /// @brief Emit a simple flow event.
    void EmitSimpleEvent(const ENUM_ATLAS_EVENT_TYPE type, const string source, const long snapshot_id);

public:
    /**
     * @brief Constructor — initializes all members to safe defaults.
     */
    CoreEngine(void);

    /**
     * @brief Destructor — calls Shutdown if not already called.
     */
    ~CoreEngine(void);

    //=== Lifecycle ===

    /**
     * @brief Initialize the CoreEngine with config and injected dependencies.
     * @param config    EA configuration.
     * @param logger    Logger (may be NULL — NullLogger used as default).
     * @param market    Market data source (may be NULL — pipeline skips market phase).
     * @param strategy  Strategy set (may be NULL — pipeline skips strategy phase).
     * @param risk      Risk evaluator (may be NULL — pipeline skips risk phase).
     * @param execution Order builder (may be NULL — pipeline skips execution phase).
     * @param broker    Broker adapter (REQUIRED — tick capture needs this).
     * @param trade     Position store (may be NULL — no position tracking).
     * @param persistence State store (may be NULL — no persistence).
     * @return true if initialization succeeded.
     */
    bool Initialize(const AtlasConfig &config,
                    ILogger *logger,
                    IMarketDataSource *market,
                    IStrategySet *strategy,
                    IRiskEvaluator *risk,
                    IOrderBuilder *execution,
                    IBrokerAdapter *broker,
                    IPositionStore *trade,
                    IStateStore *persistence);

    /**
     * @brief Shutdown the engine. Flushes state, releases resources.
     * @param reason Shutdown reason code.
     */
    void Shutdown(const int reason);

    //=== MT5 Event Handlers ===

    /**
     * @brief Called on every tick. Runs the pipeline + drains events.
     */
    void OnTick(void);

    /**
     * @brief Called on trade events. Reconciles positions.
     */
    void OnTrade(void);

    /**
     * @brief Called on timer. Heartbeat + snapshot + queue drain.
     */
    void OnTimer(void);

    //=== IEventBus implementation ===

    virtual void EmitEvent(const AtlasEvent &event) override;
    virtual void EmitPriorityEvent(const AtlasEvent &event) override;

    //=== Accessors ===

    /// @brief Get the context store (read+write interface).
    IContextStore* GetContext(void) { return &m_context; }

    /// @brief Get the pipeline statistics.
    const PipelineStatistics& GetStats(void) const { return m_stats; }

    /// @brief Get the module registry.
    const ModuleRegistry& GetRegistry(void) const { return m_registry; }

    /// @brief Get the event queue.
    const EventQueue& GetQueue(void) const { return m_event_queue; }

    /// @brief Get the kill switch propagator.
    KillSwitchPropagator& GetKillSwitch(void) { return m_kill_switch; }

    /// @brief Is the engine initialized?
    bool IsInitialized(void) const { return m_initialized; }

    /// @brief Is the kill switch active?
    bool IsKillSwitchActive(void) const { return m_context.IsKillSwitchActive(); }
};

//+------------------------------------------------------------------+
//| CoreEngine implementation                                         |
//+------------------------------------------------------------------+

CoreEngine::CoreEngine(void)
{
    m_logger           = NULL;
    m_owns_logger      = false;

    m_market_engine    = NULL;
    m_strategy_engine  = NULL;
    m_risk_engine      = NULL;
    m_execution_engine = NULL;
    m_broker_adapter   = NULL;
    m_trade_manager    = NULL;
    m_persistence      = NULL;

    m_initialized       = false;
    m_shutdown_requested = false;
    m_last_heartbeat_time = 0;
    m_last_daily_check   = 0;
}

//+------------------------------------------------------------------+
CoreEngine::~CoreEngine(void)
{
    if(m_initialized)
        Shutdown(0);
}

//+------------------------------------------------------------------+
void CoreEngine::RegisterDefaultPermissions(void)
{
    //--- Each module gets write access to the context contract
    m_permission_matrix.GrantPermission(ATLAS_MODULE_CORE,      ATLAS_CONTRACT_CONTEXT);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_MARKET,    ATLAS_CONTRACT_MARKET_STATE);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_STRATEGY,  ATLAS_CONTRACT_RISK_DECISION);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_RISK,      ATLAS_CONTRACT_CONTEXT);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_RISK,      ATLAS_CONTRACT_RISK_DECISION);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_EXECUTION, ATLAS_CONTRACT_ORDER_REQUEST);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_MT5,       ATLAS_CONTRACT_EVENT);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_TRADE,     ATLAS_CONTRACT_CONTEXT);
    m_permission_matrix.GrantPermission(ATLAS_MODULE_PERSISTENCE, ATLAS_CONTRACT_CONTEXT);
}

//+------------------------------------------------------------------+
void CoreEngine::RegisterCoreModules(void)
{
    m_registry.Register(ATLAS_MODULE_CORE,        "CoreEngine",       ATLAS_VERSION_STRING);
    m_registry.Register(ATLAS_MODULE_MARKET,      "MarketEngine",     "pending");
    m_registry.Register(ATLAS_MODULE_STRATEGY,    "StrategyEngine",   "pending");
    m_registry.Register(ATLAS_MODULE_RISK,        "RiskEngine",       "pending");
    m_registry.Register(ATLAS_MODULE_EXECUTION,   "ExecutionEngine",  "pending");
    m_registry.Register(ATLAS_MODULE_MT5,         "MT5Adapter",       "pending");
    m_registry.Register(ATLAS_MODULE_TRADE,       "TradeManager",     "pending");
    m_registry.Register(ATLAS_MODULE_PERSISTENCE, "PersistenceManager","pending");
}

//+------------------------------------------------------------------+
void CoreEngine::CheckDailyReset(void)
{
    if(m_context_factory.IsNewTradingDay(m_context))
    {
        double equity = (m_broker_adapter != NULL) ? m_broker_adapter.AccountEquity() : 0.0;
        m_context_factory.ResetDaily(m_context, equity);
        m_kill_switch.Deactivate(m_snapshot_mgr.CurrentId());

        if(m_logger != NULL)
            m_logger.Info("CoreEngine", "New trading day — daily limits reset, kill switch cleared");
    }
}

//+------------------------------------------------------------------+
void CoreEngine::EmitSimpleEvent(const ENUM_ATLAS_EVENT_TYPE type, const string source, const long snapshot_id)
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
bool CoreEngine::Initialize(const AtlasConfig &config,
                            ILogger *logger,
                            IMarketDataSource *market,
                            IStrategySet *strategy,
                            IRiskEvaluator *risk,
                            IOrderBuilder *execution,
                            IBrokerAdapter *broker,
                            IPositionStore *trade,
                            IStateStore *persistence)
{
    if(m_initialized)
    {
        if(logger != NULL)
            logger.Warn("CoreEngine", "Initialize: already initialized");
        return true;
    }

    m_config = config;

    //--- Logger
    if(logger != NULL)
    {
        m_logger      = logger;
        m_owns_logger = false;
    }
    else
    {
        m_logger      = &m_null_logger;
        m_owns_logger = false;  // NullLogger is a member, not dynamically allocated
    }

    //--- Store injected dependencies
    m_market_engine    = market;
    m_strategy_engine  = strategy;
    m_risk_engine      = risk;
    m_execution_engine = execution;
    m_broker_adapter   = broker;
    m_trade_manager    = trade;
    m_persistence      = persistence;

    //--- Validate required dependencies
    if(m_broker_adapter == NULL)
    {
        m_logger.Error("CoreEngine", "Initialize: broker adapter is REQUIRED");
        return false;
    }

    //--- Initialize Core infrastructure
    m_permission_matrix.SetLogger(m_logger);
    RegisterDefaultPermissions();
    m_logger.Info("CoreEngine", "Permission matrix configured");

    m_guardian.Attach(&m_permission_matrix, m_logger);
    m_logger.Info("CoreEngine", "Context guardian attached");

    m_context_factory.SetLogger(m_logger);

    //--- Context: recover state if persistence is available
    if(m_persistence != NULL)
    {
        if(m_persistence.RecoverState(m_context))
            m_logger.Info("CoreEngine", "Context state recovered from persistence");
        else
            m_logger.Info("CoreEngine", "No previous state found — starting fresh");
    }

    //--- If no recovery, initialize fresh
    if(m_context.GetTradingDayStart() == 0)
    {
        m_context_factory.InitializeFresh(m_context);
        double equity = m_broker_adapter.AccountEquity();
        m_context_factory.ResetDaily(m_context, equity);
    }

    //--- Event queue
    m_event_queue.Initialize(m_logger, ATLAS_EVENT_QUEUE_SIZE, ATLAS_PRIORITY_QUEUE_SIZE);
    m_logger.Info("CoreEngine", "Event queue initialized");

    //--- Snapshot manager
    m_snapshot_mgr.Initialize(&m_context, m_logger, m_config.snapshot_interval_sec);

    //--- Kill switch propagator
    m_kill_switch.Initialize(this, &m_context, m_logger);

    //--- Pipeline statistics
    m_stats.SetLogger(m_logger);

    //--- Time budget runner
    m_budget.Initialize(m_logger, m_config.max_ms_per_tick, m_config.max_events_per_tick);

    //--- Event dispatcher
    m_dispatcher.Initialize(&m_event_queue, &m_context, m_logger);

    //--- Phase scheduler
    m_scheduler.Initialize(this, &m_context, m_logger,
                           m_market_engine, m_strategy_engine,
                           m_risk_engine, m_execution_engine,
                           m_broker_adapter,
                           &m_snapshot_mgr, &m_stats, &m_budget,
                           m_config);

    //--- Module registry
    m_registry.SetLogger(m_logger);
    RegisterCoreModules();
    m_registry.MarkInitialized(ATLAS_MODULE_CORE);

    //--- Mark injected modules as initialized
    if(m_market_engine    != NULL) m_registry.MarkInitialized(ATLAS_MODULE_MARKET);
    if(m_strategy_engine  != NULL) m_registry.MarkInitialized(ATLAS_MODULE_STRATEGY);
    if(m_risk_engine      != NULL) m_registry.MarkInitialized(ATLAS_MODULE_RISK);
    if(m_execution_engine != NULL) m_registry.MarkInitialized(ATLAS_MODULE_EXECUTION);
    if(m_broker_adapter   != NULL) m_registry.MarkInitialized(ATLAS_MODULE_MT5);
    if(m_trade_manager    != NULL) m_registry.MarkInitialized(ATLAS_MODULE_TRADE);
    if(m_persistence      != NULL) m_registry.MarkInitialized(ATLAS_MODULE_PERSISTENCE);

    //--- Set up timer for heartbeat
    EventSetTimer(m_config.heartbeat_interval_sec);

    m_last_daily_check    = TimeCurrent();
    m_last_heartbeat_time = TimeCurrent();

    m_initialized = true;

    m_logger.Info("CoreEngine",
        "AtlasEA v" + ATLAS_VERSION_STRING + " initialized. " +
        "Symbol=" + m_config.symbol + " " +
        "Magic=" + IntegerToString(m_config.magic_number) + " " +
        "KillSwitch=" + (m_context.IsKillSwitchActive() ? "ACTIVE" : "inactive"));

    m_registry.LogStatus();

    return true;
}

//+------------------------------------------------------------------+
void CoreEngine::Shutdown(const int reason)
{
    if(!m_initialized) return;

    m_shutdown_requested = true;

    m_logger.Info("CoreEngine", "Shutdown initiated (reason=" + IntegerToString(reason) + ")");

    //--- Emit shutdown event
    EmitSimpleEvent(EV_SYSTEM_SHUTDOWN, "CoreEngine", m_snapshot_mgr.CurrentId());

    //--- Drain remaining events (generous budget for shutdown)
    m_budget.StartTick();
    m_dispatcher.ProcessBatch(NULL, &m_stats);

    //--- Final snapshot
    if(m_persistence != NULL)
    {
        m_persistence.WriteSnapshot(m_context, m_snapshot_mgr.CurrentId());
        m_persistence.FlushEventBuffer();
    }

    //--- Kill timer
    EventKillTimer();

    //--- Reset guardian ownerships
    m_guardian.ResetAll();

    //--- Log final statistics
    m_stats.LogSummary();

    m_logger.Info("CoreEngine", "Shutdown complete");

    m_initialized = false;
}

//+------------------------------------------------------------------+
void CoreEngine::OnTick(void)
{
    if(!m_initialized || m_shutdown_requested) return;

    //--- Start budget tracking
    m_budget.StartTick();
    ulong tick_start = GetTickCount64();

    m_context.SetTickTime(TimeCurrent());
    m_context.IncrementTicksProcessed();

    //--- Daily reset check (cheap — only check every 60 seconds)
    if(TimeCurrent() - m_last_daily_check > 60)
    {
        CheckDailyReset();
        m_last_daily_check = TimeCurrent();
    }

    //--- Run the 4-phase pipeline (Market → Strategy → Risk → Execution)
    m_scheduler.RunPipeline();

    //--- Drain queued events within remaining budget
    m_dispatcher.ProcessBatch(&m_budget, &m_stats);

    //--- Record tick statistics
    double total_ms = (double)(GetTickCount64() - tick_start);
    m_stats.RecordTick(total_ms, m_budget.LastTickOverrun());

    //--- Increment context events counter
    m_context.IncrementEventsEmitted();
}

//+------------------------------------------------------------------+
void CoreEngine::OnTrade(void)
{
    if(!m_initialized) return;

    //--- Reconcile positions via broker adapter
    if(m_broker_adapter != NULL && m_trade_manager != NULL)
    {
        PositionSnapshotEvent snap = m_broker_adapter.QueryBrokerPositions();
        m_trade_manager.ReconcilePositions(snap);
    }

    //--- Emit trade event
    EmitSimpleEvent(EV_TRADE_EXECUTED, "CoreEngine", m_snapshot_mgr.CurrentId());
}

//+------------------------------------------------------------------+
void CoreEngine::OnTimer(void)
{
    if(!m_initialized) return;

    datetime now = TimeCurrent();

    //--- Heartbeat
    if((long)(now - m_last_heartbeat_time) >= m_config.heartbeat_interval_sec)
    {
        m_last_heartbeat_time = now;

        //--- Update floating PnL
        if(m_trade_manager != NULL)
        {
            MarketState state = m_scheduler.LastMarketState();
            if(state.is_valid)
                m_trade_manager.UpdatePricesOnHeartbeat(state);
        }

        //--- Update exposure
        if(m_risk_engine != NULL)
            m_risk_engine.UpdateExposure();

        EmitSimpleEvent(EV_HEARTBEAT, "CoreEngine", m_snapshot_mgr.CurrentId());
    }

    //--- Periodic snapshot
    if(m_snapshot_mgr.IsSnapshotDue(now) && m_persistence != NULL)
    {
        if(m_persistence.WriteSnapshot(m_context, m_snapshot_mgr.CurrentId()))
        {
            m_snapshot_mgr.MarkSnapshotPersisted(now);
            EmitSimpleEvent(EV_STATE_PERSISTED, "CoreEngine", m_snapshot_mgr.CurrentId());
        }
    }

    //--- Drain queue with a generous budget (timer is not as time-critical as tick)
    m_budget.StartTick();
    m_dispatcher.ProcessBatch(&m_budget, &m_stats);
}

//+------------------------------------------------------------------+
//| IEventBus implementation                                          |
//+------------------------------------------------------------------+
void CoreEngine::EmitEvent(const AtlasEvent &event)
{
    if(!m_initialized) return;

    if(!m_event_queue.Enqueue(event))
    {
        //--- Queue full — emit an error event to priority queue
        AtlasEvent err;
        err.type          = EV_ERROR_OCCURRED;
        err.source_module = "CoreEngine";
        err.timestamp     = TimeCurrent();
        err.snapshot_id   = event.snapshot_id;
        err.payload_size  = 0;
        m_event_queue.EnqueuePriority(err);
    }
    m_context.IncrementEventsEmitted();
}

//+------------------------------------------------------------------+
void CoreEngine::EmitPriorityEvent(const AtlasEvent &event)
{
    if(!m_initialized) return;
    m_event_queue.EnqueuePriority(event);
    m_context.IncrementEventsEmitted();
}

#endif // ATLAS_CORE_ENGINE_MQH
//+------------------------------------------------------------------+
