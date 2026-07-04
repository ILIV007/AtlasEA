//+------------------------------------------------------------------+
//|                     Strategy/BaseStrategy.mqh                    |
//|       AtlasEA v0.1.20.0 - Abstract Strategy Base Class           |
//+------------------------------------------------------------------+
#ifndef ATLAS_BASE_STRATEGY_MQH
#define ATLAS_BASE_STRATEGY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "StrategyContext.mqh"
#include "StrategyHealth.mqh"
#include "StrategyStatistics.mqh"

/**
 * @class BaseStrategy
 * @brief Abstract base class for all strategy plugins.
 *
 * Provides:
 *   - Common validation (NaN checks, price checks)
 *   - Logger access (via context)
 *   - Config storage
 *   - Execution counter
 *   - Last execution time
 *   - Cooldown support
 *   - Health state tracking
 *   - Default no-op implementations for OnTick/OnBar
 *
 * Subclasses MUST override:
 *   - Evaluate() — produce a StrategyVote
 *
 * Subclasses MAY override:
 *   - Initialize() — custom init
 *   - Shutdown() — custom cleanup
 *   - Reset() — reset internal state
 *   - OnTick() — tick-level processing
 *   - OnBar() — bar-close processing
 *
 * Usage:
 *   class MyStrategy : public BaseStrategy
 *   {
 *   public:
 *       MyStrategy(void)
 *       {
 *           m_name     = "MyStrategy";
 *           m_version  = "1.0.0";
 *           m_priority = 50;
 *           m_weight   = 1.0;
 *       }
 *       virtual StrategyVote Evaluate(const StrategyContext &ctx) override
 *       {
 *           //--- Strategy logic
 *           return BuildAbstention(ctx);
 *       }
 *   };
 */
class BaseStrategy : public IStrategy
{
protected:
    //=== Identity ===
    string  m_name;
    string  m_version;
    int     m_priority;
    double  m_weight;
    bool    m_enabled;
    int     m_strategy_id;

    //=== Runtime state ===
    AtlasConfig          m_config;
    StrategyHealthState  m_health;
    datetime             m_last_execution;
    ulong                m_execution_count;
    datetime             m_cooldown_until;

    //=== Supported symbols/timeframes ===
    string  m_supported_symbols;     ///< "*" or comma-separated
    string  m_supported_timeframes;  ///< "*" or comma-separated

    //=== Helpers ===

    /// @brief Build a BUY vote.
    StrategyVote BuildBuyVote(const StrategyContext &ctx,
                               const double confidence,
                               const double entry, const double sl, const double tp,
                               const double volume = 0.0) const
    {
        StrategyVote vote;
        vote.strategy_id      = m_strategy_id;
        vote.strategy_version = m_version;
        vote.direction        = ATLAS_ORDER_BUY;
        vote.confidence       = ClampD(confidence, 0.0, 1.0);
        vote.suggested_volume = volume;
        vote.suggested_entry  = entry;
        vote.suggested_sl     = sl;
        vote.suggested_tp     = tp;
        vote.snapshot_id      = ctx.GetSnapshotId();
        vote.vote_time        = TimeCurrent();
        return vote;
    }

    /// @brief Build a SELL vote.
    StrategyVote BuildSellVote(const StrategyContext &ctx,
                                const double confidence,
                                const double entry, const double sl, const double tp,
                                const double volume = 0.0) const
    {
        StrategyVote vote;
        vote.strategy_id      = m_strategy_id;
        vote.strategy_version = m_version;
        vote.direction        = ATLAS_ORDER_SELL;
        vote.confidence       = ClampD(confidence, 0.0, 1.0);
        vote.suggested_volume = volume;
        vote.suggested_entry  = entry;
        vote.suggested_sl     = sl;
        vote.suggested_tp     = tp;
        vote.snapshot_id      = ctx.GetSnapshotId();
        vote.vote_time        = TimeCurrent();
        return vote;
    }

    /// @brief Build an abstention (no signal).
    StrategyVote BuildAbstention(const StrategyContext &ctx) const
    {
        StrategyVote vote;
        vote.strategy_id      = m_strategy_id;
        vote.strategy_version = m_version;
        vote.direction        = ATLAS_ORDER_NONE;
        vote.confidence       = 0.0;
        vote.suggested_volume = 0.0;
        vote.suggested_entry  = 0.0;
        vote.suggested_sl     = 0.0;
        vote.suggested_tp     = 0.0;
        vote.snapshot_id      = ctx.GetSnapshotId();
        vote.vote_time        = TimeCurrent();
        return vote;
    }

    /// @brief Clamp a double to [lo, hi].
    double ClampD(const double v, const double lo, const double hi) const
    {
        if(!MathIsValidNumber(v)) return lo;
        if(v < lo) return lo;
        if(v > hi) return hi;
        return v;
    }

    /// @brief Check if a price is valid.
    bool IsValidPrice(const double price) const
    {
        return (MathIsValidNumber(price) && price > 0.0);
    }

public:
    /**
     * @brief Constructor — sets sensible defaults.
     */
    BaseStrategy(void)
    {
        m_name               = "Unnamed";
        m_version            = "1.0.0";
        m_priority           = 100;
        m_weight             = 1.0;
        m_enabled            = true;
        m_strategy_id        = 0;
        m_last_execution     = 0;
        m_execution_count    = 0;
        m_cooldown_until     = 0;
        m_supported_symbols  = "*";
        m_supported_timeframes = "*";
        ZeroMemory(m_config);
    }

    virtual ~BaseStrategy(void) {}

    //=== IStrategy implementation (defaults) ===

    virtual bool Initialize(void) override { return true; }
    virtual void Shutdown(void) override {}
    virtual void Reset(void) override
    {
        m_execution_count = 0;
        m_last_execution  = 0;
        m_cooldown_until   = 0;
        m_health.Reset();
    }

    virtual void OnTick(const StrategyContext &ctx) override { /* Default: no-op */ }
    virtual void OnBar(const StrategyContext &ctx) override { /* Default: no-op */ }

    virtual StrategyVote Evaluate(const StrategyContext &ctx) override
    {
        //--- Default: abstain. Subclasses MUST override.
        return BuildAbstention(ctx);
    }

    //=== Metadata ===

    virtual string Name(void) const override     { return m_name; }
    virtual string Version(void) const override   { return m_version; }
    virtual int    Priority(void) const override  { return m_priority; }
    virtual double Weight(void) const override    { return m_weight; }
    virtual bool   Enabled(void) const override   { return m_enabled; }

    virtual int Health(void) const override
    {
        return m_health.status;
    }

    virtual bool SupportsSymbol(const string symbol) const override
    {
        if(m_supported_symbols == "*") return true;
        return (StringFind(m_supported_symbols, symbol) >= 0);
    }

    virtual bool SupportsTimeframe(const string timeframe) const override
    {
        if(m_supported_timeframes == "*") return true;
        return (StringFind(m_supported_timeframes, timeframe) >= 0);
    }

    //=== Extended API (for registry/scheduler use) ===

    /// @brief Get the strategy ID.
    int GetId(void) const { return m_strategy_id; }

    /// @brief Set the strategy ID (called by registry during registration).
    void SetId(const int id) { m_strategy_id = id; }

    /// @brief Set the config (called during initialization).
    void SetConfig(const AtlasConfig &config) { m_config = config; }

    /// @brief Enable/disable the strategy.
    void SetEnabled(const bool enabled)
    {
        m_enabled = enabled;
        if(!enabled)
        {
            m_health.status      = ATLAS_STRAT_HEALTH_YELLOW;
            m_health.reason_code = ATLAS_HEALTH_REASON_DISABLED;
            m_health.reason_text = "Strategy disabled";
        }
    }

    /// @brief Check if the strategy is in cooldown.
    bool IsInCooldown(void) const
    {
        return (TimeCurrent() < m_cooldown_until);
    }

    /// @brief Set cooldown until a specific time.
    void SetCooldown(const datetime until) { m_cooldown_until = until; }

    /// @brief Get the health state (mutable, for scheduler).
    StrategyHealthState& GetHealthState(void) { return m_health; }

    /// @brief Get execution count.
    ulong ExecutionCount(void) const { return m_execution_count; }

    /// @brief Get last execution time.
    datetime LastExecution(void) const { return m_last_execution; }

    /// @brief Record an execution (called by scheduler).
    void RecordExecution(void)
    {
        m_execution_count++;
        m_last_execution = TimeCurrent();
    }
};

#endif // ATLAS_BASE_STRATEGY_MQH
//+------------------------------------------------------------------+
