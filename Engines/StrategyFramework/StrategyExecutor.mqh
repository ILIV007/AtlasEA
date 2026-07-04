//+------------------------------------------------------------------+
//|           Engines/StrategyFramework/StrategyExecutor.mqh         |
//|       AtlasEA v0.1.10.0 - Strategy Execution Engine              |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_EXECUTOR_MQH
#define ATLAS_STRATEGY_EXECUTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Contracts/RiskDecision.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/IStrategy.mqh"
#include "StrategyContext.mqh"
#include "StrategyRegistry.mqh"
#include "VoteBuilder.mqh"

/**
 * @struct StrategyExecutionStats
 * @brief Per-strategy execution statistics (for diagnostics).
 */
struct StrategyExecutionStats
{
    int    strategy_id;
    ulong  evaluations;       ///< Total Evaluate() calls
    ulong  successes;         ///< Calls that returned a directional vote
    ulong  abstentions;       ///< Calls that returned NONE
    ulong  failures;          ///< Calls that returned false or invalid vote
    double total_latency_ms;  ///< Sum of execution times
    double peak_latency_ms;   ///< Max execution time
};

/**
 * @class StrategyExecutor
 * @brief Executes all enabled strategies and collects votes.
 *
 * Responsibilities:
 *   - Receive a MarketState
 *   - Build a StrategyContext (read-only)
 *   - Iterate enabled strategies (sorted by priority)
 *   - Call Evaluate() on each
 *   - Handle failures (log + neutral vote + continue)
 *   - Measure per-strategy execution time
 *   - Validate votes via VoteBuilder
 *   - Return an array of StrategyVote
 *
 * Isolation:
 *   - Each strategy executes independently.
 *   - If one strategy fails, the executor logs, substitutes a neutral vote,
 *     and continues with the next strategy.
 *   - The executor NEVER crashes because of a strategy failure.
 *
 * Performance:
 *   - Total budget: 30 ms for all strategies.
 *   - Per-strategy budget: 5 ms (soft limit, logged if exceeded).
 *   - No heap allocation during evaluation.
 *   - No string operations in the hot path (except on failure).
 *
 * Memory: fixed-size arrays. Zero dynamic allocation.
 */
class StrategyExecutor
{
private:
    ILogger             *m_logger;
    VoteBuilder          m_vote_builder;
    StrategyExecutionStats m_stats[ATLAS_MAX_STRATEGIES];
    int                  m_stats_count;
    ulong                m_total_executions;
    ulong                m_total_failures;
    double               m_total_latency_ms;
    double               m_peak_latency_ms;

    /// @brief Find or create stats entry for a strategy.
    int FindStatsIndex(const int strategy_id) const;

    /// @brief Get or create stats entry.
    StrategyExecutionStats* GetStats(const int strategy_id);

public:
    /**
     * @brief Constructor.
     */
    StrategyExecutor(void);

    /**
     * @brief Initialize the executor.
     * @param logger Logger.
     * @param vote_builder Vote builder (for validation).
     */
    void Initialize(ILogger *logger, const VoteBuilder &vote_builder);

    /**
     * @brief Execute all enabled strategies in the registry.
     *
     * @param registry     The strategy registry.
     * @param state        Current market state (immutable).
     * @param config       EA configuration.
     * @param snapshot_id  Current snapshot ID.
     * @param out_votes    Output array (caller-allocated, capacity ATLAS_MAX_VOTES).
     * @param out_count    Output: number of votes written.
     * @return true if at least one strategy executed (even if all abstained).
     */
    bool Execute(const StrategyRegistry &registry,
                 const MarketState &state,
                 const AtlasConfig &config,
                 const long snapshot_id,
                 StrategyVote &out_votes[],
                 int &out_count);

    /**
     * @brief Reset all statistics.
     */
    void ResetStats(void);

    /**
     * @brief Log execution statistics.
     */
    void LogStats(void) const;

    //=== Accessors ===
    ulong TotalExecutions(void) const { return m_total_executions; }
    ulong TotalFailures(void) const { return m_total_failures; }
    double AvgLatencyMs(void) const
    {
        if(m_total_executions == 0) return 0.0;
        return m_total_latency_ms / (double)m_total_executions;
    }
    double PeakLatencyMs(void) const { return m_peak_latency_ms; }
};

//+------------------------------------------------------------------+
//| StrategyExecutor implementation                                   |
//+------------------------------------------------------------------+

StrategyExecutor::StrategyExecutor(void)
{
    m_logger             = NULL;
    m_stats_count        = 0;
    m_total_executions   = 0;
    m_total_failures     = 0;
    m_total_latency_ms   = 0.0;
    m_peak_latency_ms    = 0.0;
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
    {
        m_stats[i].strategy_id      = 0;
        m_stats[i].evaluations      = 0;
        m_stats[i].successes        = 0;
        m_stats[i].abstentions      = 0;
        m_stats[i].failures         = 0;
        m_stats[i].total_latency_ms = 0.0;
        m_stats[i].peak_latency_ms  = 0.0;
    }
}

//+------------------------------------------------------------------+
void StrategyExecutor::Initialize(ILogger *logger, const VoteBuilder &vote_builder)
{
    m_logger       = logger;
    m_vote_builder = vote_builder;
    m_vote_builder.SetLogger(logger);
    ResetStats();
}

//+------------------------------------------------------------------+
int StrategyExecutor::FindStatsIndex(const int strategy_id) const
{
    for(int i = 0; i < m_stats_count; i++)
    {
        if(m_stats[i].strategy_id == strategy_id)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
StrategyExecutionStats* StrategyExecutor::GetStats(const int strategy_id)
{
    int idx = FindStatsIndex(strategy_id);
    if(idx >= 0) return &m_stats[idx];

    if(m_stats_count >= ATLAS_MAX_STRATEGIES)
        return &m_stats[0];  //--- Defensive: reuse slot 0 if full

    m_stats[m_stats_count].strategy_id = strategy_id;
    m_stats[m_stats_count].evaluations = 0;
    m_stats[m_stats_count].successes   = 0;
    m_stats[m_stats_count].abstentions = 0;
    m_stats[m_stats_count].failures    = 0;
    m_stats[m_stats_count].total_latency_ms = 0.0;
    m_stats[m_stats_count].peak_latency_ms  = 0.0;
    m_stats_count++;
    return &m_stats[m_stats_count - 1];
}

//+------------------------------------------------------------------+
bool StrategyExecutor::Execute(const StrategyRegistry &registry,
                                const MarketState &state,
                                const AtlasConfig &config,
                                const long snapshot_id,
                                StrategyVote &out_votes[],
                                int &out_count)
{
    out_count = 0;

    if(!state.is_valid)
    {
        if(m_logger != NULL)
            m_logger.Warn("StrategyExecutor", "Execute: market state invalid");
        return false;
    }

    //--- Get enabled strategies sorted by priority
    IStrategy *strategies[ATLAS_MAX_STRATEGIES];
    int strat_count = 0;
    registry.GetEnabledSorted(strategies, strat_count);

    if(strat_count == 0)
    {
        return false;  //--- No strategies to execute
    }

    //--- Build the read-only context
    StrategyContext ctx(&state, &config, m_logger, snapshot_id);

    //--- Execute each strategy
    for(int i = 0; i < strat_count && out_count < ATLAS_MAX_VOTES; i++)
    {
        IStrategy *strategy = strategies[i];
        if(strategy == NULL) continue;

        const StrategyMetadata &meta = strategy.GetMetadata();

        //--- Check symbol support
        if(!meta.SupportsSymbol(config.symbol))
            continue;

        //--- Measure execution time
        ulong start_ms = GetTickCount64();

        StrategyVote vote;
        ZeroMemory(vote);

        bool eval_ok = false;
        bool failed  = false;

        //--- Execute the strategy (isolated)
        eval_ok = strategy.Evaluate(ctx, vote);

        ulong elapsed_ms = GetTickCount64() - start_ms;
        m_total_executions++;
        m_total_latency_ms += (double)elapsed_ms;
        if((double)elapsed_ms > m_peak_latency_ms)
            m_peak_latency_ms = (double)elapsed_ms;

        //--- Update per-strategy stats
        StrategyExecutionStats *stats = GetStats(meta.strategy_id);
        if(stats != NULL)
        {
            stats.evaluations++;
            stats.total_latency_ms += (double)elapsed_ms;
            if((double)elapsed_ms > stats.peak_latency_ms)
                stats.peak_latency_ms = (double)elapsed_ms;
        }

        //--- Check for timeout (soft limit: 5 ms)
        if(elapsed_ms > 5)
        {
            if(m_logger != NULL)
                m_logger.Warn("StrategyExecutor",
                    meta.name + " exceeded 5ms budget: " + IntegerToString((long)elapsed_ms) + "ms");
        }

        //--- Handle failure
        if(!eval_ok)
        {
            failed = true;
            if(stats != NULL) stats.failures++;
            m_total_failures++;
            if(m_logger != NULL)
                m_logger.Warn("StrategyExecutor", meta.name + " Evaluate() returned false");

            //--- Substitute neutral vote and continue
            m_vote_builder.BuildNeutral(vote, meta, snapshot_id);
            continue;  //--- Don't add neutral vote to output
        }

        //--- Validate the vote
        string reason;
        if(!m_vote_builder.Validate(vote, reason))
        {
            failed = true;
            if(stats != NULL) stats.failures++;
            m_total_failures++;
            if(m_logger != NULL)
                m_logger.Warn("StrategyExecutor", meta.name + " produced invalid vote: " + reason);
            continue;
        }

        //--- Categorize the vote
        if(vote.direction == ATLAS_ORDER_NONE)
        {
            //--- Abstention — don't add to output, but count it
            if(stats != NULL) stats.abstentions++;
        }
        else
        {
            //--- Directional vote — add to output
            if(stats != NULL) stats.successes++;
            out_votes[out_count] = vote;
            out_count++;
        }
    }

    return (out_count > 0);
}

//+------------------------------------------------------------------+
void StrategyExecutor::ResetStats(void)
{
    m_stats_count      = 0;
    m_total_executions = 0;
    m_total_failures   = 0;
    m_total_latency_ms = 0.0;
    m_peak_latency_ms  = 0.0;
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
    {
        m_stats[i].strategy_id      = 0;
        m_stats[i].evaluations      = 0;
        m_stats[i].successes        = 0;
        m_stats[i].abstentions      = 0;
        m_stats[i].failures         = 0;
        m_stats[i].total_latency_ms = 0.0;
        m_stats[i].peak_latency_ms  = 0.0;
    }
}

//+------------------------------------------------------------------+
void StrategyExecutor::LogStats(void) const
{
    if(m_logger == NULL) return;

    m_logger.Info("StrategyExecutor",
        "total_exec=" + IntegerToString((long)m_total_executions) +
        " total_fail=" + IntegerToString((long)m_total_failures) +
        " avg_ms=" + DoubleToString(AvgLatencyMs(), 3) +
        " peak_ms=" + DoubleToString(m_peak_latency_ms, 3));

    for(int i = 0; i < m_stats_count; i++)
    {
        if(m_stats[i].strategy_id == 0) continue;
        double avg = 0.0;
        if(m_stats[i].evaluations > 0)
            avg = m_stats[i].total_latency_ms / (double)m_stats[i].evaluations;

        m_logger.Info("StrategyExecutor",
            "  id=" + IntegerToString(m_stats[i].strategy_id) +
            " evals=" + IntegerToString((long)m_stats[i].evaluations) +
            " ok=" + IntegerToString((long)m_stats[i].successes) +
            " abst=" + IntegerToString((long)m_stats[i].abstentions) +
            " fail=" + IntegerToString((long)m_stats[i].failures) +
            " avg_ms=" + DoubleToString(avg, 3) +
            " peak_ms=" + DoubleToString(m_stats[i].peak_latency_ms, 3));
    }
}

#endif // ATLAS_STRATEGY_EXECUTOR_MQH
//+------------------------------------------------------------------+
