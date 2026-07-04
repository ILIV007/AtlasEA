//+------------------------------------------------------------------+
//|                                       Engines/StrategyEngine.mqh |
//|          AtlasEA v0.1.20.0 - Strategy Engine (Plugin Framework)  |
//|                                                                  |
//|  v0.1.20.0: Completely redesigned as a modular plugin framework. |
//|  StrategyEngine now contains NO trading logic. It is only:       |
//|    - strategy registry (ownership)                               |
//|    - lifecycle manager (init/shutdown/reset)                     |
//|    - execution scheduler (delegates to StrategyScheduler)        |
//|    - vote collector (delegates to VoteCollector)                 |
//|                                                                  |
//|  Implements IStrategySet for backward compatibility with         |
//|  CoreEngine (PhaseScheduler calls EvaluateStrategies()).         |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_ENGINE_MQH
#define ATLAS_STRATEGY_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/IStrategySet.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Strategy/StrategyContext.mqh"
#include "../Strategy/StrategyRegistry.mqh"
#include "../Strategy/StrategyScheduler.mqh"
#include "../Strategy/VoteCollector.mqh"
#include "../Strategy/StrategyStatistics.mqh"
#include "../Strategy/StrategyHealth.mqh"
#include "../Strategy/BaseStrategy.mqh"

/**
 * @class StrategyEngine
 * @brief Implements IStrategySet using the modular Strategy Plugin Framework.
 *
 * This class contains NO trading logic. It is a thin orchestrator that:
 *   1. Holds the StrategyRegistry (strategy ownership)
 *   2. Manages lifecycle (Initialize/Shutdown/Reset)
 *   3. Delegates execution to StrategyScheduler
 *   4. Delegates vote collection to VoteCollector
 *   5. Returns votes to CoreEngine via IStrategySet.EvaluateStrategies()
 *
 * Strategies register via RegisterStrategy(). The engine does NOT
 * know what strategies do — it only calls their interface methods.
 */
class StrategyEngine : public IStrategySet
{
private:
    //=== Dependencies (injected) ===
    ILogger        *m_logger;
    IContextStore  *m_context;
    AtlasConfig     m_config;

    //=== Framework components (stack-allocated, owned) ===
    StrategyRegistry   m_registry;
    StrategyScheduler  m_scheduler;
    VoteCollector      m_collector;
    StrategyStatistics m_stats;

    //=== Context snapshots (updated each tick) ===
    AccountSnapshot  m_account;
    SymbolInfo       m_symbol;
    SessionInfo      m_session;
    ClockSnapshot    m_clock;

    //=== State ===
    bool m_initialized;

    /// @brief Build the read-only StrategyContext from current state.
    StrategyContext BuildContext(const MarketState &state, const long snapshot_id)
    {
        //--- Update account snapshot from context
        if(m_context != NULL)
        {
            //--- Account info comes from the broker adapter via CoreEngine
            //--- For now, use placeholder values (CoreEngine would inject these)
            m_account.equity      = 0.0;  //--- Would be filled from broker
            m_account.balance     = 0.0;
            m_account.free_margin = 0.0;
        }

        //--- Update symbol info from market state
        m_symbol.symbol = state.symbol;
        m_symbol.point  = state.point;
        m_symbol.digits = state.digits;
        m_symbol.bid    = state.bid;
        m_symbol.ask    = state.ask;

        //--- Update session info
        m_session.session_state = state.session_state;
        m_session.market_open   = (state.session_state != ATLAS_SESSION_OFF);
        m_session.weekend       = (state.session_state == ATLAS_SESSION_OFF);

        //--- Update clock
        m_clock.current_time = TimeCurrent();
        m_clock.bar_time     = state.bar_time;
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        m_clock.day_of_week = dt.day_of_week;
        m_clock.hour        = dt.hour;
        m_clock.minute      = dt.min;

        return StrategyContext(&state, &m_account, &m_symbol,
                               &m_session, &m_clock, m_logger, snapshot_id);
    }

public:
    /**
     * @brief Constructor.
     */
    StrategyEngine(void)
    {
        m_logger      = NULL;
        m_context     = NULL;
        m_initialized = false;
        ZeroMemory(m_config);
    }

    /**
     * @brief Destructor — calls Shutdown.
     */
    ~StrategyEngine(void) { Shutdown(); }

    /**
     * @brief Set dependencies. Must be called before Initialize().
     */
    void SetDependencies(ILogger *logger, IContextStore *context, const AtlasConfig &config)
    {
        m_logger  = logger;
        m_context = context;
        m_config  = config;
    }

    /**
     * @brief Register a strategy with the framework.
     * @param strategy Pointer to the strategy (caller owns lifetime).
     * @param id Unique strategy ID (> 0).
     * @return true if registered, false on duplicate/invalid/full.
     */
    bool RegisterStrategy(IStrategy *strategy, const int id)
    {
        if(!m_registry.Register(strategy, id))
            return false;

        //--- Set the config on the strategy
        strategy.SetConfig(m_config);

        //--- Initialize the strategy
        if(!strategy.Initialize())
        {
            if(m_logger != NULL)
                m_logger.Error("StrategyEngine",
                    "Strategy " + strategy.Name() + " Initialize() failed");
            m_registry.Unregister(id);
            return false;
        }

        return true;
    }

    /**
     * @brief Unregister a strategy by ID.
     */
    bool UnregisterStrategy(const int id)
    {
        IStrategy *s = m_registry.FindById(id);
        if(s == NULL) return false;
        s.Shutdown();
        return m_registry.Unregister(id);
    }

    //=== IStrategySet implementation ===

    /**
     * @brief Evaluate all enabled strategies and return votes.
     *
     * This is the MAIN entry point, called by CoreEngine PhaseScheduler.
     *
     * Pipeline:
     *   1. Check kill switch
     *   2. Validate market state
     *   3. Build StrategyContext
     *   4. Delegate to StrategyScheduler.Execute()
     *   5. Delegate to VoteCollector.CollectBatch()
     *   6. Return votes
     *
     * @param state  Validated market state.
     * @param votes  Output array (caller-allocated, capacity ATLAS_MAX_VOTES).
     * @return Number of directional votes written (0..ATLAS_MAX_VOTES).
     */
    virtual int EvaluateStrategies(const MarketState &state, StrategyVote &votes[]) override
    {
        if(!m_initialized)
        {
            if(m_logger != NULL)
                m_logger.Error("StrategyEngine", "Not initialized");
            return 0;
        }

        //--- Kill switch check
        if(m_context != NULL && m_context.IsKillSwitchActive())
            return 0;

        //--- Market state validation
        if(!state.is_valid)
        {
            if(m_logger != NULL)
                m_logger.Warn("StrategyEngine", "Invalid market state");
            return 0;
        }

        if(state.snapshot_id <= 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("StrategyEngine", "Invalid snapshot_id");
            return 0;
        }

        if(state.feature_count != ATLAS_FEATURE_SIZE)
        {
            if(m_logger != NULL)
                m_logger.Error("StrategyEngine",
                    "Feature count mismatch: " + IntegerToString(state.feature_count));
            return 0;
        }

        if(state.atr_14 <= 0.0)
        {
            if(m_logger != NULL)
                m_logger.Warn("StrategyEngine", "ATR <= 0");
            return 0;
        }

        //--- Build the read-only context
        StrategyContext ctx = BuildContext(state, state.snapshot_id);

        //--- Execute strategies via scheduler
        StrategyVote raw_votes[ATLAS_MAX_VOTES];
        int raw_count = 0;

        m_scheduler.Execute(ctx, raw_votes, raw_count);

        //--- Collect and normalize votes
        int vote_count = 0;
        m_collector.CollectBatch(raw_votes, raw_count, votes, vote_count);

        return vote_count;
    }

    /**
     * @brief Initialize the strategy engine.
     */
    virtual bool Initialize(void) override
    {
        if(m_logger == NULL)
            return false;

        //--- Wire framework components
        m_registry.SetLogger(m_logger);
        m_scheduler.SetDependencies(m_logger, &m_registry, &m_stats);
        m_collector.SetLogger(m_logger);

        m_initialized = true;
        m_logger.Info("StrategyEngine",
            "Initialized (plugin framework). Registered=" +
            IntegerToString(m_registry.Count()) + "/" + IntegerToString(ATLAS_MAX_STRATEGIES));
        return true;
    }

    /**
     * @brief Shutdown the strategy engine.
     */
    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;

        //--- Shutdown all strategies
        IStrategy *strategies[ATLAS_MAX_STRATEGIES];
        int count = 0;
        m_registry.GetAll(strategies, count);

        for(int i = 0; i < count; i++)
        {
            if(strategies[i] != NULL)
                strategies[i].Shutdown();
        }

        //--- Log stats
        if(m_logger != NULL)
        {
            m_logger.Info("StrategyEngine",
                "Scheduler: execs=" + IntegerToString((long)m_scheduler.TotalExecutions()) +
                " fails=" + IntegerToString((long)m_scheduler.TotalFailures()) +
                " avg_ms=" + DoubleToString(m_scheduler.AvgLatencyMs(), 3) +
                " peak_ms=" + DoubleToString(m_scheduler.PeakLatencyMs(), 3));
        }

        m_registry.Clear();
        m_stats.Reset();
        m_scheduler.Reset();

        m_logger.Info("StrategyEngine", "Shutdown");
        m_initialized = false;
    }

    //=== Extended API ===

    /**
     * @brief Get the registry (for external queries).
     */
    const StrategyRegistry& GetRegistry(void) const { return m_registry; }

    /**
     * @brief Get the scheduler statistics.
     */
    const StrategyScheduler& GetScheduler(void) const { return m_scheduler; }

    /**
     * @brief Get per-strategy statistics.
     */
    const StrategyStatistics& GetStatistics(void) const { return m_stats; }

    /**
     * @brief Reset all strategies (daily reset).
     */
    void ResetAll(void)
    {
        IStrategy *strategies[ATLAS_MAX_STRATEGIES];
        int count = 0;
        m_registry.GetAll(strategies, count);

        for(int i = 0; i < count; i++)
        {
            if(strategies[i] != NULL)
                strategies[i].Reset();
        }

        m_stats.Reset();
        m_scheduler.Reset();
    }

    /**
     * @brief Log diagnostics.
     */
    void LogDiagnostics(void) const
    {
        if(m_logger == NULL) return;

        m_logger.Info("StrategyEngine",
            "Registered: " + IntegerToString(m_registry.Count()) +
            " Enabled: " + IntegerToString(m_registry.EnabledCount()));

        m_logger.Info("StrategyEngine",
            "Scheduler: total=" + IntegerToString((long)m_scheduler.TotalExecutions()) +
            " fails=" + IntegerToString((long)m_scheduler.TotalFailures()) +
            " avg=" + DoubleToString(m_scheduler.AvgLatencyMs(), 3) + "ms" +
            " peak=" + DoubleToString(m_scheduler.PeakLatencyMs(), 3) + "ms");
    }

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate internal state for consistency.
     * @return ValidationResult — Ok() if all invariants hold, Fail() otherwise.
     *
     * Invariants checked:
     *   - m_logger != NULL (required dependency)
     *   - m_initialized is true
     *   - m_registry.Count() >= 0 (defensive — should always hold)
     *
     * Non-throwing (MQL5 has no exceptions).
     */
    ValidationResult Validate(void) const
    {
        if(m_logger == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "logger is NULL", "m_logger");
        if(!m_initialized)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "engine not initialized", "m_initialized");
        if(m_registry.Count() < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "registry count is negative", "m_registry");
        return ValidationResult::Ok();
    }

    /// @brief Convenience wrapper — true if Validate() passes.
    bool IsValid(void) const { return Validate().valid; }
};

#endif // ATLAS_STRATEGY_ENGINE_MQH
//+------------------------------------------------------------------+
