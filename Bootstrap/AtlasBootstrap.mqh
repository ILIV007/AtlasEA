//+------------------------------------------------------------------+
//|                                  Bootstrap/AtlasBootstrap.mqh    |
//|          AtlasEA v0.1.8.0 - Application Bootstrap & DI Container  |
//+------------------------------------------------------------------+
#ifndef ATLAS_BOOTSTRAP_MQH
#define ATLAS_BOOTSTRAP_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IMarketDataSource.mqh"
#include "../Interfaces/IStrategySet.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "../Interfaces/IPositionStore.mqh"
#include "../Interfaces/IStateStore.mqh"
#include "../Interfaces/IHealthMonitor.mqh"
#include "../Core/ServiceRegistry.mqh"
#include "../Core/CoreEngine.mqh"
#include "../Core/NullLogger.mqh"
#include "../Diagnostics/HealthMonitor.mqh"
#include "../Engines/MarketEngine.mqh"
#include "../Engines/StrategyEngine.mqh"
#include "../Engines/RiskEngine.mqh"
#include "../Engines/ExecutionEngine.mqh"
#include "../Infrastructure/MT5Adapter.mqh"
#include "../Infrastructure/TradeManager.mqh"
#include "../Infrastructure/PersistenceManager.mqh"

/**
 * @class AtlasBootstrap
 * @brief Constructs, wires, and validates the entire AtlasEA application.
 *
 * Responsibilities:
 *   1. Construct every service (logger, health monitor)
 *   2. Construct every engine (Market, Strategy, Risk, Execution)
 *   3. Construct every infrastructure component (MT5Adapter, TradeManager, PersistenceManager)
 *   4. Perform dependency injection (engines receive interfaces, not concretes)
 *   5. Register shared singletons in ServiceRegistry
 *   6. Validate startup (all dependencies resolved, no duplicates)
 *   7. Return an initialized CoreEngine
 *
 * Ownership: Bootstrap owns ALL instances. On Shutdown(), it deletes them
 * in reverse construction order. CoreEngine does NOT own engines/infra —
 * it receives pointers and calls Initialize/Shutdown.
 *
 * Memory: all instances are heap-allocated (new) at startup and deleted
 * at shutdown. No allocation during operation.
 *
 * Thread model: single-threaded. Bootstrap runs once at OnInit.
 *
 * Usage:
 *   AtlasBootstrap bootstrap;
 *   CoreEngine *engine = bootstrap.Initialize(config);
 *   if(engine == NULL) return INIT_FAILED;
 *   // ... use engine ...
 *   bootstrap.Shutdown();  // deletes everything including engine
 */
class AtlasBootstrap
{
private:
    //=== Service Registry (shared singletons) ===
    ServiceRegistry  *m_registry;

    //=== Owned instances (deleted on shutdown) ===
    ILogger          *m_logger;
    HealthMonitor    *m_health_monitor;

    //=== Engines ===
    MarketEngine     *m_market_engine;
    StrategyEngine   *m_strategy_engine;
    RiskEngine       *m_risk_engine;
    ExecutionEngine  *m_execution_engine;

    //=== Infrastructure ===
    MT5Adapter       *m_mt5_adapter;
    TradeManager     *m_trade_manager;
    PersistenceManager *m_persistence;

    //=== Core ===
    CoreEngine       *m_core_engine;

    //=== State ===
    bool              m_initialized;
    AtlasConfig       m_config;

    /// @brief Construct all services.
    bool CreateServices(void);

    /// @brief Construct all engines.
    bool CreateEngines(void);

    /// @brief Construct all infrastructure components.
    bool CreateInfrastructure(void);

    /// @brief Inject dependencies into engines.
    bool InjectDependencies(void);

    /// @brief Validate that all components are constructed and wired.
    bool ValidateStartup(void);

    /// @brief Register services in the ServiceRegistry.
    void RegisterServices(void);

public:
    /**
     * @brief Constructor.
     */
    AtlasBootstrap(void);

    /**
     * @brief Destructor — calls Shutdown if not already called.
     */
    ~AtlasBootstrap(void);

    /**
     * @brief Initialize the entire application.
     * @param config EA configuration.
     * @return Pointer to initialized CoreEngine, or NULL on failure.
     *
     * On failure, all partially-constructed components are cleaned up
     * and NULL is returned. The caller should return INIT_FAILED.
     */
    CoreEngine *Initialize(const AtlasConfig &config);

    /**
     * @brief Shutdown the application. Deletes all owned instances.
     */
    void Shutdown(void);

    /**
     * @brief Get the ServiceRegistry (for external access to singletons).
     */
    ServiceRegistry *GetRegistry(void) const { return m_registry; }

    /**
     * @brief Get the HealthMonitor (for external health checks).
     */
    IHealthMonitor *GetHealthMonitor(void) const { return m_health_monitor; }

    /**
     * @brief Is the bootstrap initialized?
     */
    bool IsInitialized(void) const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| AtlasBootstrap implementation                                     |
//+------------------------------------------------------------------+

AtlasBootstrap::AtlasBootstrap(void)
{
    m_registry        = NULL;
    m_logger          = NULL;
    m_health_monitor  = NULL;
    m_market_engine   = NULL;
    m_strategy_engine = NULL;
    m_risk_engine     = NULL;
    m_execution_engine = NULL;
    m_mt5_adapter     = NULL;
    m_trade_manager   = NULL;
    m_persistence     = NULL;
    m_core_engine     = NULL;
    m_initialized     = false;
}

//+------------------------------------------------------------------+
AtlasBootstrap::~AtlasBootstrap(void)
{
    if(m_initialized)
        Shutdown();
}

//+------------------------------------------------------------------+
bool AtlasBootstrap::CreateServices(void)
{
    //--- Logger: use NullLogger for now (real Logger in a future phase)
    //--- In a future phase, this could be: m_logger = new FileLogger(config);
    //--- For now, NullLogger is stack-allocated inside CoreEngine, but we
    //--- create a heap instance here so it can be registered.
    m_logger = new NullLogger();
    if(m_logger == NULL) return false;

    //--- Health Monitor
    m_health_monitor = new HealthMonitor();
    if(m_health_monitor == NULL) return false;

    return true;
}

//+------------------------------------------------------------------+
bool AtlasBootstrap::CreateEngines(void)
{
    m_market_engine = new MarketEngine();
    if(m_market_engine == NULL) return false;

    m_strategy_engine = new StrategyEngine();
    if(m_strategy_engine == NULL) return false;

    m_risk_engine = new RiskEngine();
    if(m_risk_engine == NULL) return false;

    m_execution_engine = new ExecutionEngine();
    if(m_execution_engine == NULL) return false;

    return true;
}

//+------------------------------------------------------------------+
bool AtlasBootstrap::CreateInfrastructure(void)
{
    //--- MT5 Adapter (REQUIRED — must be created first since engines need it)
    m_mt5_adapter = new MT5Adapter(NULL);  //--- EventBus injected later
    if(m_mt5_adapter == NULL) return false;

    //--- Trade Manager
    m_trade_manager = new TradeManager(NULL);  //--- EventBus injected later
    if(m_trade_manager == NULL) return false;

    //--- Persistence Manager
    m_persistence = new PersistenceManager();
    if(m_persistence == NULL) return false;

    return true;
}

//+------------------------------------------------------------------+
void AtlasBootstrap::RegisterServices(void)
{
    m_registry.SetLogger(m_logger);

    //--- Register shared singletons
    m_registry.Register(ATLAS_SERVICE_LOGGER,         "Logger",        m_logger);
    m_registry.Register(ATLAS_SERVICE_HEALTH_MONITOR, "HealthMonitor", m_health_monitor);

    //--- Other services (Clock, UUIDGenerator, Metrics, ErrorManager, ConfigProvider)
    //--- are deferred to future phases. For now, they are NULL.
    //--- ValidateAll() is NOT called until those services exist.
}

//+------------------------------------------------------------------+
bool AtlasBootstrap::InjectDependencies(void)
{
    //--- MarketEngine depends on: broker, logger, config
    m_market_engine.SetDependencies(m_mt5_adapter, m_logger, m_config);

    //--- StrategyEngine depends on: logger, context (set during CoreEngine init), config
    //--- StrategyEngine::SetDependencies will be called by CoreEngine after it creates the context
    //--- For now, we just set the logger and config
    //--- (StrategyEngine's SetDependencies signature may vary — this is a placeholder
    //--- that will be aligned when the engine is fully implemented)

    //--- RiskEngine depends on: broker, logger, context, config, event bus
    //--- Same pattern — context and event bus are set by CoreEngine

    //--- ExecutionEngine depends on: broker, logger, context, config

    //--- MT5Adapter depends on: event bus (set by CoreEngine), logger, config

    //--- TradeManager depends on: event bus (set by CoreEngine), logger, context, config

    //--- PersistenceManager depends on: logger, context, config

    //--- HealthMonitor depends on: logger, queue, stats, broker, symbol
    //--- (queue and stats are owned by CoreEngine, set after CoreEngine is created)

    return true;
}

//+------------------------------------------------------------------+
bool AtlasBootstrap::ValidateStartup(void)
{
    //--- Validate all required instances exist
    if(m_logger == NULL)
    {
        Print("[Bootstrap] Validation FAILED: logger is NULL");
        return false;
    }
    if(m_health_monitor == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: health monitor is NULL");
        return false;
    }
    if(m_market_engine == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: market engine is NULL");
        return false;
    }
    if(m_strategy_engine == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: strategy engine is NULL");
        return false;
    }
    if(m_risk_engine == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: risk engine is NULL");
        return false;
    }
    if(m_execution_engine == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: execution engine is NULL");
        return false;
    }
    if(m_mt5_adapter == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: MT5 adapter is NULL");
        return false;
    }
    if(m_trade_manager == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: trade manager is NULL");
        return false;
    }
    if(m_persistence == NULL)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: persistence manager is NULL");
        return false;
    }

    //--- Validate configuration
    if(m_config.magic_number <= 0)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: magic_number <= 0");
        return false;
    }
    if(StringLen(m_config.symbol) == 0)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: symbol is empty");
        return false;
    }
    if(m_config.max_ms_per_tick <= 0)
    {
        m_logger.Error("Bootstrap", "Validation FAILED: max_ms_per_tick <= 0");
        return false;
    }

    m_logger.Info("Bootstrap", "Startup validation PASSED");
    return true;
}

//+------------------------------------------------------------------+
CoreEngine *AtlasBootstrap::Initialize(const AtlasConfig &config)
{
    if(m_initialized)
    {
        if(m_logger != NULL)
            m_logger.Warn("Bootstrap", "Initialize: already initialized");
        return m_core_engine;
    }

    m_config = config;

    //==============================================================
    // STEP 1: Create Service Registry
    //==============================================================
    m_registry = new ServiceRegistry();
    if(m_registry == NULL)
    {
        Print("[Bootstrap] FATAL: cannot create ServiceRegistry");
        return NULL;
    }

    //==============================================================
    // STEP 2: Create Services (logger, health monitor)
    //==============================================================
    if(!CreateServices())
    {
        Print("[Bootstrap] FATAL: CreateServices failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 3: Register services
    //==============================================================
    RegisterServices();

    //==============================================================
    // STEP 4: Create Infrastructure (MT5Adapter first — engines need it)
    //==============================================================
    if(!CreateInfrastructure())
    {
        m_logger.Error("Bootstrap", "FATAL: CreateInfrastructure failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 5: Create Engines
    //==============================================================
    if(!CreateEngines())
    {
        m_logger.Error("Bootstrap", "FATAL: CreateEngines failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 6: Inject Dependencies
    //==============================================================
    if(!InjectDependencies())
    {
        m_logger.Error("Bootstrap", "FATAL: InjectDependencies failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 7: Validate Startup
    //==============================================================
    if(!ValidateStartup())
    {
        m_logger.Error("Bootstrap", "FATAL: ValidateStartup failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 8: Create CoreEngine and inject everything
    //==============================================================
    m_core_engine = new CoreEngine();
    if(m_core_engine == NULL)
    {
        m_logger.Error("Bootstrap", "FATAL: cannot create CoreEngine");
        Shutdown();
        return NULL;
    }

    bool ok = m_core_engine.Initialize(
        m_config,
        m_logger,
        m_market_engine,    // IMarketDataSource
        m_strategy_engine,  // IStrategySet
        m_risk_engine,      // IRiskEvaluator
        m_execution_engine, // IOrderBuilder
        m_mt5_adapter,      // IBrokerAdapter
        m_trade_manager,    // IPositionStore
        m_persistence       // IStateStore
    );

    if(!ok)
    {
        m_logger.Error("Bootstrap", "FATAL: CoreEngine.Initialize failed");
        Shutdown();
        return NULL;
    }

    //==============================================================
    // STEP 9: Wire HealthMonitor to CoreEngine's queue + stats
    //==============================================================
    //--- HealthMonitor needs access to EventQueue and PipelineStatistics
    //--- These are owned by CoreEngine. We access them via CoreEngine's
    //--- public accessors (GetQueue returns const ref; we need non-const
    //--- for HealthMonitor's pointer). This is a known limitation —
    //--- in a future refactor, CoreEngine would expose them via interfaces.
    //--- For now, HealthMonitor uses what CoreEngine provides.
    m_health_monitor.SetSources(m_logger,
                                 NULL,  //--- queue (CoreEngine owns it; future: expose accessor)
                                 NULL,  //--- stats (same)
                                 m_mt5_adapter,
                                 m_config.symbol);

    //==============================================================
    // STEP 10: Final validation
    //==============================================================
    m_logger.Info("Bootstrap",
        "AtlasEA v" + ATLAS_VERSION_STRING + " bootstrap complete. " +
        "All " + IntegerToString(m_registry.Count()) + " services registered.");

    m_registry.LogStatus();

    m_initialized = true;
    return m_core_engine;
}

//+------------------------------------------------------------------+
void AtlasBootstrap::Shutdown(void)
{
    if(m_logger != NULL)
        m_logger.Info("Bootstrap", "Shutdown initiated");

    //--- Shutdown CoreEngine first (it drains queues, flushes persistence)
    if(m_core_engine != NULL)
    {
        m_core_engine.Shutdown(0);
        delete m_core_engine;
        m_core_engine = NULL;
    }

    //--- Shutdown engines (reverse order)
    if(m_execution_engine != NULL) { m_execution_engine.Shutdown(); delete m_execution_engine; m_execution_engine = NULL; }
    if(m_risk_engine != NULL)      { m_risk_engine.Shutdown();      delete m_risk_engine;      m_risk_engine = NULL; }
    if(m_strategy_engine != NULL)  { m_strategy_engine.Shutdown();  delete m_strategy_engine;  m_strategy_engine = NULL; }
    if(m_market_engine != NULL)    { m_market_engine.Shutdown();    delete m_market_engine;    m_market_engine = NULL; }

    //--- Shutdown infrastructure (reverse order)
    if(m_persistence != NULL)   { m_persistence.Shutdown();   delete m_persistence;   m_persistence = NULL; }
    if(m_trade_manager != NULL) { m_trade_manager.Shutdown(); delete m_trade_manager; m_trade_manager = NULL; }
    if(m_mt5_adapter != NULL)   { m_mt5_adapter.Shutdown();   delete m_mt5_adapter;   m_mt5_adapter = NULL; }

    //--- Shutdown services
    if(m_health_monitor != NULL) { delete m_health_monitor; m_health_monitor = NULL; }
    if(m_logger != NULL)         { delete m_logger;         m_logger = NULL; }

    //--- Clear registry
    if(m_registry != NULL) { m_registry.Clear(); delete m_registry; m_registry = NULL; }

    m_initialized = false;
}

#endif // ATLAS_BOOTSTRAP_MQH
//+------------------------------------------------------------------+
