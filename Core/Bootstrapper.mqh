//+------------------------------------------------------------------+
//|                      Core/Bootstrapper.mqh                      |
//|       AtlasEA v0.1.21.0 - Production Bootstrapper                |
//+------------------------------------------------------------------+
#ifndef ATLAS_BOOTSTRAPPER_MQH
#define ATLAS_BOOTSTRAPPER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

//--- Interfaces
#include "../Interfaces/IDependencyContainer.mqh"
#include "../Interfaces/IBootstrapper.mqh"
#include "../Interfaces/IModuleRegistry.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IMarketDataSource.mqh"
#include "../Interfaces/IStrategySet.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "../Interfaces/IPositionStore.mqh"
#include "../Interfaces/IStateStore.mqh"
#include "../Interfaces/IHealthMonitor.mqh"
#include "../Interfaces/IRecoveryManager.mqh"

//--- Core
#include "DependencyContainer.mqh"
#include "DependencyValidator.mqh"
#include "ModuleRegistry.mqh"
#include "ApplicationLifecycle.mqh"
#include "CoreEngine.mqh"
#include "NullLogger.mqh"
#include "ValidationResult.mqh"

//--- Concrete implementations
#include "../Infrastructure/Logging/Logger.mqh"
#include "../Diagnostics/HealthMonitor.mqh"
#include "../Diagnostics/MetricsCollector.mqh"
#include "../Diagnostics/MetricsExporter.mqh"
#include "../Engines/MarketEngine.mqh"
#include "../Engines/StrategyEngine.mqh"
#include "../Engines/RiskEngine.mqh"
#include "../Engines/ExecutionEngine.mqh"
#include "../Engines/MoneyManagementEngine.mqh"
#include "../Infrastructure/MT5Adapter.mqh"
#include "../Infrastructure/TradeManager.mqh"
#include "../Infrastructure/TradeLifecycleManager.mqh"
#include "../Infrastructure/PersistenceManager.mqh"
#include "../Recovery/RecoveryManager.mqh"

/**
 * @class Bootstrapper
 * @brief Production bootstrapper — builds the entire application graph.
 *
 * This is the ONLY object that calls `new` for application modules.
 * It constructs, injects, validates, and owns all instances.
 *
 * Initialization order (strict):
 *   1. Logger
 *   2. Metrics
 *   3. HealthMonitor
 *   4. Persistence
 *   5. BrokerAdapter
 *   6. TradeManager
 *   7. RecoveryManager
 *   8. MarketEngine
 *   9. StrategyEngine
 *  10. RiskEngine
 *  11. ExecutionEngine
 *  12. CoreEngine
 *
 * Shutdown order (reverse):
 *  12. CoreEngine → 11. ExecutionEngine → ... → 1. Logger
 *
 * The Bootstrapper implements IBootstrapper for interface-driven usage.
 */
class Bootstrapper : public IBootstrapper
{
private:
    //=== DI + Lifecycle ===
    DependencyContainer  m_container;
    ModuleRegistry       m_modules;
    DependencyValidator  m_validator;
    ApplicationLifecycle m_lifecycle;

    //=== Owned instances (deleted on shutdown) ===
    Logger             *m_logger;
    MetricsCollector   *m_metrics;
    HealthMonitor      *m_health;
    MT5Adapter         *m_broker;
    TradeManager       *m_trade;
    PersistenceManager *m_persistence;
    RecoveryManager    *m_recovery;
    MarketEngine       *m_market;
    StrategyEngine     *m_strategy;
    RiskEngine         *m_risk;
    ExecutionEngine    *m_execution;
    MoneyManagementEngine *m_money_mgmt;
    TradeLifecycleManager *m_trade_lifecycle;
    CoreEngine         *m_core;

    //=== State ===
    AtlasConfig m_config;
    int         m_last_result;
    string      m_failure_reason;

    /// @brief Register all modules in the module registry.
    void RegisterModules(void)
    {
        m_modules.Register(ATLAS_MODULE_CORE,        "CoreEngine",       ATLAS_VERSION_STRING, 12, 1);
        m_modules.Register(ATLAS_MODULE_MARKET,      "MarketEngine",     "1.0",                8, 5);
        m_modules.Register(ATLAS_MODULE_STRATEGY,    "StrategyEngine",   "1.0",                9, 4);
        m_modules.Register(ATLAS_MODULE_RISK,        "RiskEngine",       "1.0",               10, 3);
        m_modules.Register(ATLAS_MODULE_EXECUTION,   "ExecutionEngine",  "1.0",               11, 2);
        m_modules.Register(ATLAS_MODULE_MT5,         "MT5Adapter",       "1.0",                5, 8);
        m_modules.Register(ATLAS_MODULE_TRADE,       "TradeManager",     "1.0",                6, 7);
        m_modules.Register(ATLAS_MODULE_PERSISTENCE, "PersistenceManager","1.0",               4, 9);
    }

    /// @brief Create and register the Logger.
    bool CreateLogger(void)
    {
        m_logger = new Logger(m_config.log_level);
        if(m_logger == NULL) return false;
        m_container.SetLogger(m_logger);
        m_modules.SetLogger(m_logger);
        m_validator.SetLogger(m_logger);
        m_container.RegisterSingleton(ATLAS_DEP_LOGGER, "Logger", m_logger);
        return true;
    }

    /// @brief Create and register Metrics + Health.
    bool CreateDiagnostics(void)
    {
        m_metrics = new MetricsCollector();
        if(m_metrics == NULL) return false;
        m_metrics.SetLogger(m_logger);
        m_container.RegisterSingleton(ATLAS_DEP_METRICS, "MetricsCollector", m_metrics);

        m_health = new HealthMonitor();
        if(m_health == NULL) return false;
        m_health.SetSources(m_logger, m_broker,
                            m_metrics.GetProfiler(), m_metrics.GetLatencyMonitor(),
                            m_metrics.GetMemoryStats(), m_metrics.GetEventStats(),
                            m_metrics.GetQueueStats());
        m_container.RegisterSingleton(ATLAS_DEP_HEALTH, "HealthMonitor", m_health);
        return true;
    }

    /// @brief Create infrastructure (persistence, broker, trade).
    bool CreateInfrastructure(void)
    {
        m_persistence = new PersistenceManager();
        if(m_persistence == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_PERSISTENCE, "PersistenceManager", m_persistence);

        m_broker = new MT5Adapter(NULL);
        if(m_broker == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_BROKER, "MT5Adapter", m_broker);

        m_trade = new TradeManager(NULL);
        if(m_trade == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_TRADE_MANAGER, "TradeManager", m_trade);

        m_trade_lifecycle = new TradeLifecycleManager();
        if(m_trade_lifecycle == NULL) return false;
        m_trade_lifecycle.SetLogger(m_logger);
        m_trade_lifecycle.SetConfig(m_config);

        return true;
    }

    /// @brief Create RecoveryManager.
    bool CreateRecovery(void)
    {
        m_recovery = new RecoveryManager();
        if(m_recovery == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_RECOVERY, "RecoveryManager", m_recovery);
        return true;
    }

    /// @brief Create all engines.
    bool CreateEngines(void)
    {
        m_market = new MarketEngine();
        if(m_market == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_MARKET_ENGINE, "MarketEngine", m_market);

        m_strategy = new StrategyEngine();
        if(m_strategy == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_STRATEGY_ENGINE, "StrategyEngine", m_strategy);

        m_risk = new RiskEngine();
        if(m_risk == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_RISK_ENGINE, "RiskEngine", m_risk);

        m_execution = new ExecutionEngine();
        if(m_execution == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_EXECUTION_ENGINE, "ExecutionEngine", m_execution);

        m_money_mgmt = new MoneyManagementEngine();
        if(m_money_mgmt == NULL) return false;
        m_money_mgmt.SetLogger(m_logger);
        m_money_mgmt.SetConfig(m_config);

        return true;
    }

    /// @brief Inject dependencies into all modules.
    bool InjectDependencies(void)
    {
        //--- MT5Adapter: config + logger
        m_broker.SetLogger(m_logger);
        m_broker.Initialize(m_config);

        //--- MarketEngine: broker, logger, config
        m_market.SetDependencies(m_broker, m_logger, m_config);

        //--- StrategyEngine: logger, context (set by Core), config
        m_strategy.SetDependencies(m_logger, NULL, m_config);

        //--- RiskEngine: logger, context, broker, config
        m_risk.SetDependencies(m_logger, NULL, m_broker, m_config);

        //--- ExecutionEngine: logger, context, broker, config
        m_execution.SetDependencies(m_logger, NULL, m_broker, m_config);

        //--- TradeManager: event_bus, logger, context (set by Core), broker, config
        //--- (context is NULL here — will be re-set after CoreEngine creates AtlasContext)

        //--- Persistence: logger, context (set by Core), config
        m_persistence.SetDependencies(m_logger, NULL, m_config);

        //--- Recovery: logger, persistence, broker, event_bus (set by Core), config
        m_recovery.SetDependencies(m_logger, m_persistence, m_broker, NULL, m_config);

        return true;
    }

    /// @brief Create CoreEngine and wire everything.
    bool CreateCoreEngine(void)
    {
        m_core = new CoreEngine();
        if(m_core == NULL) return false;
        m_container.RegisterSingleton(ATLAS_DEP_CORE_ENGINE, "CoreEngine", m_core);
        m_container.RegisterSingleton(ATLAS_DEP_EVENT_BUS, "CoreEngine(EventBus)", m_core);

        bool ok = m_core.Initialize(
            m_config,
            m_logger,
            m_market,
            m_strategy,
            m_risk,
            m_execution,
            m_broker,
            m_trade,
            m_persistence
        );

        if(!ok)
        {
            m_failure_reason = "CoreEngine.Initialize() failed";
            return false;
        }

        //--- Inject context + event bus into modules that need them
        IContextStore *context = m_core.GetContext();

        //--- Re-inject with real context now that CoreEngine created it
        m_strategy.SetDependencies(m_logger, context, m_config);
        m_risk.SetDependencies(m_logger, context, m_broker, m_config);
        m_execution.SetDependencies(m_logger, context, m_broker, m_config);
        m_execution.SetMoneyManagement(m_money_mgmt);

        //--- TradeManager: needs event_bus, logger, context, broker, config
        m_trade.SetDependencies(m_core, m_logger, context, m_broker, m_config);

        //--- PersistenceManager: needs logger, context, config
        m_persistence.SetDependencies(m_logger, context, m_config);

        //--- RecoveryManager: logger, persistence, broker, event_bus, config
        m_recovery.SetDependencies(m_logger, m_persistence, m_broker, m_core, m_config);

        return true;
    }

    /// @brief Validate the entire dependency graph.
    bool ValidateGraph(void)
    {
        ValidationResult result = m_validator.ValidateAll(m_container, m_modules);
        if(!result.valid)
        {
            m_failure_reason = "Dependency graph validation failed: " +
                              IntegerToString(result.error_count) + " errors";
            return false;
        }
        return true;
    }

    /// @brief Mark all modules as initialized.
    void MarkAllInitialized(void)
    {
        m_modules.MarkInitialized(ATLAS_MODULE_PERSISTENCE);
        m_modules.MarkInitialized(ATLAS_MODULE_MT5);
        m_modules.MarkInitialized(ATLAS_MODULE_TRADE);
        m_modules.MarkInitialized(ATLAS_MODULE_MARKET);
        m_modules.MarkInitialized(ATLAS_MODULE_STRATEGY);
        m_modules.MarkInitialized(ATLAS_MODULE_RISK);
        m_modules.MarkInitialized(ATLAS_MODULE_EXECUTION);
        m_modules.MarkInitialized(ATLAS_MODULE_CORE);
    }

public:
    /**
     * @brief Constructor.
     */
    Bootstrapper(void)
    {
        m_logger       = NULL;
        m_metrics      = NULL;
        m_health       = NULL;
        m_broker       = NULL;
        m_trade        = NULL;
        m_persistence  = NULL;
        m_recovery     = NULL;
        m_market       = NULL;
        m_strategy     = NULL;
        m_risk         = NULL;
        m_execution    = NULL;
        m_money_mgmt   = NULL;
        m_trade_lifecycle = NULL;
        m_core         = NULL;
        m_last_result  = ATLAS_BOOTSTRAP_FAILED;
        m_failure_reason = "";
    }

    /**
     * @brief Destructor — calls Shutdown if running.
     */
    ~Bootstrapper(void)
    {
        if(m_lifecycle.IsRunning() || m_lifecycle.IsFailed())
            Shutdown();
    }

    /**
     * @brief Validate runtime invariants of the Bootstrapper.
     *
     * Contract:
     *   - If Bootstrap has been called and the system is RUNNING
     *     (m_lifecycle.IsRunning()), every owned module pointer MUST be
     *     non-NULL:
     *       m_logger, m_core, m_broker, m_market, m_risk, m_execution,
     *       m_persistence, m_trade, m_recovery, m_metrics, m_health.
     *   - In the CREATED state (before Bootstrap), all pointers are NULL
     *     and that is explicitly valid.
     *
     * This method catches partially-constructed application graphs that
     * could result from a failed Bootstrap call that returned NULL before
     * every module was created.
     *
     * @return ValidationResult::Ok() on success, Fail() on first violation.
     */
    ValidationResult Validate(void) const
    {
        //--- Pre-bootstrap state: all pointers NULL is valid.
        if(!m_lifecycle.IsRunning())
            return ValidationResult::Ok();

        //--- Post-bootstrap: every owned module must be present.
        if(m_logger      == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "Logger not created", "m_logger");
        if(m_core        == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "CoreEngine not created", "m_core");
        if(m_broker      == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "Broker adapter not created", "m_broker");
        if(m_market      == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "MarketEngine not created", "m_market");
        if(m_risk        == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "RiskEngine not created", "m_risk");
        if(m_execution   == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "ExecutionEngine not created", "m_execution");
        if(m_money_mgmt  == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "MoneyManagementEngine not created", "m_money_mgmt");
        if(m_trade_lifecycle == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "TradeLifecycleManager not created", "m_trade_lifecycle");
        if(m_persistence == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "PersistenceManager not created", "m_persistence");
        if(m_trade       == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "TradeManager not created", "m_trade");
        if(m_recovery    == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "RecoveryManager not created", "m_recovery");
        if(m_metrics     == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "MetricsCollector not created", "m_metrics");
        if(m_health      == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "HealthMonitor not created", "m_health");

        return ValidationResult::Ok();
    }

    //=== IBootstrapper implementation ===

    virtual CoreEngine *Bootstrap(const AtlasConfig &config) override
    {
        if(!m_lifecycle.IsCreated())
        {
            m_failure_reason = "Bootstrapper not in CREATED state (current: " +
                              m_lifecycle.GetStateName() + ")";
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            return NULL;
        }

        m_config = config;
        m_lifecycle.Transition(ATLAS_LIFECYCLE_BOOTSTRAPPING);

        //==============================================================
        // STEP 1: Create Logger (always first)
        //==============================================================
        if(!CreateLogger())
        {
            m_failure_reason = "Failed to create Logger";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            return NULL;
        }
        m_logger.Info("Bootstrapper", "=== AtlasEA v" + ATLAS_VERSION_STRING + " bootstrap ===");

        //==============================================================
        // STEP 2: Register modules
        //==============================================================
        RegisterModules();

        //==============================================================
        // STEP 3: Create Infrastructure (persistence, broker, trade)
        //==============================================================
        m_logger.Info("Bootstrapper", "Creating infrastructure...");
        if(!CreateInfrastructure())
        {
            m_failure_reason = "Failed to create infrastructure";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 4: Create Recovery
        //==============================================================
        m_logger.Info("Bootstrapper", "Creating recovery...");
        if(!CreateRecovery())
        {
            m_failure_reason = "Failed to create RecoveryManager";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 5: Create Engines
        //==============================================================
        m_logger.Info("Bootstrapper", "Creating engines...");
        if(!CreateEngines())
        {
            m_failure_reason = "Failed to create engines";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 6: Create Diagnostics
        //==============================================================
        m_logger.Info("Bootstrapper", "Creating diagnostics...");
        if(!CreateDiagnostics())
        {
            m_failure_reason = "Failed to create diagnostics";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 7: Inject Dependencies
        //==============================================================
        m_logger.Info("Bootstrapper", "Injecting dependencies...");
        if(!InjectDependencies())
        {
            m_failure_reason = "Failed to inject dependencies";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 8: Validate Dependency Graph
        //==============================================================
        m_logger.Info("Bootstrapper", "Validating dependency graph...");
        if(!ValidateGraph())
        {
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 9: Transition to INITIALIZING
        //==============================================================
        m_lifecycle.Transition(ATLAS_LIFECYCLE_INITIALIZING);

        //==============================================================
        // STEP 10: Create CoreEngine (initializes everything)
        //==============================================================
        m_logger.Info("Bootstrapper", "Creating CoreEngine...");
        if(!CreateCoreEngine())
        {
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 11: Mark all modules as initialized
        //==============================================================
        //--- v1.0: Initialize MoneyManagementEngine
        if(!m_money_mgmt.Initialize())
        {
            m_failure_reason = "MoneyManagementEngine.Initialize() failed";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }
        //--- v1.0 Step 2: Initialize TradeLifecycleManager
        if(!m_trade_lifecycle.Initialize())
        {
            m_failure_reason = "TradeLifecycleManager.Initialize() failed";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }
        MarkAllInitialized();

        //==============================================================
        // STEP 12: Validate module health
        //==============================================================
        if(!m_modules.AllInitialized())
        {
            m_failure_reason = "Not all modules initialized";
            m_lifecycle.Fail(m_failure_reason);
            m_last_result = ATLAS_BOOTSTRAP_FAILED;
            Shutdown();
            return NULL;
        }

        //==============================================================
        // STEP 13: Transition to RUNNING
        //==============================================================
        m_lifecycle.Transition(ATLAS_LIFECYCLE_RUNNING);

        //==============================================================
        // STEP 14: Log status
        //==============================================================
        m_container.LogStatus();
        m_modules.LogStatus();
        m_logger.Info("Bootstrapper", "=== Bootstrap complete ===");

        m_last_result = ATLAS_BOOTSTRAP_SUCCESS;
        return m_core;
    }

    virtual void Shutdown(void) override
    {
        if(m_lifecycle.IsStopped() || m_lifecycle.IsCreated()) return;

        m_lifecycle.Transition(ATLAS_LIFECYCLE_STOPPING);

        if(m_logger != NULL)
            m_logger.Info("Bootstrapper", "=== Shutdown initiated ===");

        //==============================================================
        // Shutdown order (reverse of initialization):
        //
        //   12. CoreEngine       — stops timer, flushes persistence,
        //                          drains event queue, resets guardian
        //   11. RecoveryManager   — clears recovery state + safe-mode
        //   10. ExecutionEngine   — releases order state
        //    9. RiskEngine        — clears cached market state
        //    8. StrategyEngine    — clears strategy registry
        //    7. MarketEngine      — releases indicator handles
        //   >> HealthMonitor.ClearSources() HERE — before ANY borrowed
        //      source (broker, metrics components) is deleted.
        //    6. PersistenceManager— flushes event buffer, closes files
        //    5. TradeManager      — clears broker/context refs
        //    4. MT5Adapter        — clears event bus ref
        //    3. HealthMonitor     — sources already cleared, safe to delete
        //    2. MetricsCollector  — final snapshot exported above, then deleted
        //    1. Logger            — flushes all sinks, then deleted
        //
        // CRITICAL: HealthMonitor holds borrowed pointers to m_broker and
        // the 5 metrics components (which live inside m_metrics). We clear
        // those pointers BEFORE any source object is deleted so there is
        // never a window of dangling pointers.
        //
        // CRITICAL: The final metrics snapshot is exported BEFORE m_metrics
        // is deleted (task requirement: "Metrics export final snapshot
        // before shutdown").
        //==============================================================

        //--- 12. CoreEngine
        if(m_core != NULL)
        {
            m_core.Shutdown(0);
            delete m_core;
            m_core = NULL;
        }

        //--- 11. RecoveryManager (explicit Shutdown before delete)
        if(m_recovery != NULL)
        {
            m_recovery.Shutdown();
            delete m_recovery;
            m_recovery = NULL;
        }

        //--- 10-7. Engines (reverse order)
        if(m_execution != NULL)   { m_execution.Shutdown(); delete m_execution; m_execution = NULL; }
        if(m_money_mgmt != NULL)  { m_money_mgmt.Shutdown(); delete m_money_mgmt; m_money_mgmt = NULL; }
        if(m_trade_lifecycle != NULL) { m_trade_lifecycle.Shutdown(); delete m_trade_lifecycle; m_trade_lifecycle = NULL; }
        if(m_risk != NULL)        { m_risk.Shutdown();     delete m_risk;       m_risk = NULL; }
        if(m_strategy != NULL)    { m_strategy.Shutdown(); delete m_strategy;   m_strategy = NULL; }
        if(m_market != NULL)      { m_market.Shutdown();   delete m_market;     m_market = NULL; }

        //--- >> HealthMonitor: clear borrowed source pointers NOW, before
        //    any source object (broker, metrics components) is deleted.
        //    This eliminates any window of dangling pointers.
        if(m_health != NULL)
            m_health.ClearSources();

        //--- 6-4. Infrastructure (reverse order)
        if(m_persistence != NULL) { m_persistence.Shutdown(); delete m_persistence; m_persistence = NULL; }
        if(m_trade != NULL)       { m_trade.Shutdown();    delete m_trade;      m_trade = NULL; }
        if(m_broker != NULL)      { m_broker.Shutdown();   delete m_broker;     m_broker = NULL; }

        //--- 3. HealthMonitor — sources already cleared, safe to delete
        if(m_health != NULL)
        {
            delete m_health;
            m_health = NULL;
        }

        //--- 2. MetricsCollector — export final snapshot, then delete.
        //    The snapshot is written to a timestamped file so the operator
        //    can inspect final telemetry after shutdown.
        if(m_metrics != NULL)
        {
            if(m_logger != NULL)
            {
                MetricsExporter exporter;
                exporter.SetLogger(m_logger);
                MetricsSnapshot snap = m_metrics.CaptureSnapshot();
                string fn = "AtlasEA_metrics_" +
                            IntegerToString((long)snap.timestamp) + ".log";
                if(exporter.ExportSnapshotToFile(snap, ATLAS_EXPORT_CSV, fn))
                    m_logger.Info("Bootstrapper", "Final metrics snapshot exported to " + fn);
                else
                    m_logger.Warn("Bootstrapper", "Final metrics snapshot export FAILED");
            }
            delete m_metrics;
            m_metrics = NULL;
        }

        //--- 1. Logger — flush all sinks, then delete (Logger destructor
        //    also calls FlushAll, but we do it explicitly first so the
        //    "Shutdown complete" message is flushed too).
        if(m_logger != NULL)
        {
            m_logger.Info("Bootstrapper", "=== Shutdown complete ===");
            m_logger.FlushAll();
            delete m_logger;
            m_logger = NULL;
        }

        m_container.Clear();
        m_modules.Clear();
        m_lifecycle.Transition(ATLAS_LIFECYCLE_STOPPED);
    }

    //=== Accessors ===

    virtual IDependencyContainer* GetContainer(void) override { return &m_container; }
    virtual int GetLastResult(void) const override { return m_last_result; }
    virtual string GetFailureReason(void) const override { return m_failure_reason; }
    virtual bool IsRunning(void) const override { return m_lifecycle.IsRunning(); }

    /// @brief Get the module registry.
    ModuleRegistry& GetModuleRegistry(void) { return m_modules; }

    /// @brief Get the lifecycle.
    ApplicationLifecycle& GetLifecycle(void) { return m_lifecycle; }

    /// @brief Get the logger.
    Logger *GetLogger(void) const { return m_logger; }

    /// @brief Get the health monitor.
    HealthMonitor *GetHealthMonitor(void) const { return m_health; }

    /// @brief Get the metrics.
    MetricsCollector *GetMetrics(void) const { return m_metrics; }

    /// @brief Get the recovery manager.
    RecoveryManager *GetRecovery(void) const { return m_recovery; }
};

#endif // ATLAS_BOOTSTRAPPER_MQH
//+------------------------------------------------------------------+
