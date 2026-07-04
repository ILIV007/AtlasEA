//+------------------------------------------------------------------+
//|                 Strategy/StrategyScheduler.mqh                  |
//|       AtlasEA v0.1.20.0 - Strategy Execution Scheduler           |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_SCHEDULER_V2_MQH
#define ATLAS_STRATEGY_SCHEDULER_V2_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Interfaces/ILogger.mqh"
#include "StrategyContext.mqh"
#include "StrategyRegistry.mqh"
#include "StrategyHealth.mqh"
#include "StrategyStatistics.mqh"

/**
 * @class StrategyScheduler
 * @brief Executes enabled strategies in priority order with budget enforcement.
 *
 * Responsibilities:
 *   - Execute strategies in priority order (lower = first)
 *   - Enforce per-strategy time budget (5ms soft limit)
 *   - Skip disabled strategies
 *   - Skip strategies in cooldown
 *   - Check health before execution
 *   - Measure execution latency
 *   - Update statistics
 *
 * The scheduler does NOT collect votes — that's VoteCollector's job.
 * The scheduler calls Evaluate() and passes the result to the collector.
 */
class StrategyScheduler
{
private:
    ILogger             *m_logger;
    StrategyRegistry    *m_registry;
    StrategyStatistics  *m_stats;
    ulong                m_total_executions;
    ulong                m_total_failures;
    double               m_total_latency_ms;
    double               m_peak_latency_ms;
    double               m_max_strategy_ms;  ///< Soft per-strategy limit

public:
    /**
     * @brief Constructor.
     */
    StrategyScheduler(void)
    {
        m_logger            = NULL;
        m_registry          = NULL;
        m_stats             = NULL;
        m_total_executions  = 0;
        m_total_failures    = 0;
        m_total_latency_ms  = 0.0;
        m_peak_latency_ms   = 0.0;
        m_max_strategy_ms   = 5.0;  ///< 5ms soft limit
    }

    /**
     * @brief Set dependencies.
     */
    void SetDependencies(ILogger *logger, StrategyRegistry *registry,
                          StrategyStatistics *stats)
    {
        m_logger   = logger;
        m_registry = registry;
        m_stats    = stats;
    }

    /**
     * @brief Set the per-strategy time budget (soft limit).
     */
    void SetMaxStrategyMs(const double ms) { m_max_strategy_ms = ms; }

    /**
     * @brief Execute all enabled strategies and collect results.
     * @param ctx Read-only strategy context.
     * @param out_votes Output array (caller-allocated, capacity ATLAS_MAX_VOTES).
     * @param out_count Output: number of votes written.
     * @return true if at least one strategy executed.
     */
    bool Execute(const StrategyContext &ctx,
                  StrategyVote out_votes[],
                  int &out_count)
    {
        out_count = 0;

        if(m_registry == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("StrategyScheduler", "No registry");
            return false;
        }

        //--- Get enabled strategies sorted by priority
        IStrategy *strategies[ATLAS_MAX_STRATEGIES];
        int strat_count = 0;
        m_registry.GetEnabledSorted(strategies, strat_count);

        if(strat_count == 0) return false;

        //--- Execute each strategy
        for(int i = 0; i < strat_count && out_count < ATLAS_MAX_VOTES; i++)
        {
            IStrategy *strategy = strategies[i];
            if(strategy == NULL) continue;

            //--- Check symbol support
            if(!strategy.SupportsSymbol(ctx.GetSymbolInfo().symbol))
                continue;

            //--- Check timeframe support (simplified — uses current period string)
            //--- In production, the caller would provide the timeframe string
            //--- For now, all strategies support all timeframes ("*")

            //--- Check health
            if(!strategy.GetHealthState().CanExecute())
            {
                if(m_stats != NULL)
                    m_stats.RecordDisabled(strategy.GetId());
                continue;
            }

            //--- Check cooldown
            if(strategy.IsInCooldown())
            {
                if(m_stats != NULL)
                    m_stats.RecordCooldown(strategy.GetId());
                continue;
            }

            //--- Time the execution
            ulong start_ms = GetTickCount64();

            StrategyVote vote;
            vote = strategy.Evaluate(ctx);

            double elapsed_ms = (double)(GetTickCount64() - start_ms);

            //--- Update global counters
            m_total_executions++;
            m_total_latency_ms += elapsed_ms;
            if(elapsed_ms > m_peak_latency_ms)
                m_peak_latency_ms = elapsed_ms;

            //--- Record execution on the strategy
            strategy.RecordExecution();

            //--- Check for timeout
            if(elapsed_ms > m_max_strategy_ms)
            {
                StrategyHealth::RecordTimeout(strategy.GetHealthState());
                if(m_stats != NULL)
                    m_stats.RecordCooldown(strategy.GetId());
                if(m_logger != NULL)
                    m_logger.Warn("StrategyScheduler",
                        strategy.Name() + " exceeded " + DoubleToString(m_max_strategy_ms, 1) +
                        "ms: " + DoubleToString(elapsed_ms, 1) + "ms");
            }

            //--- Validate the vote
            if(!IsValidVote(vote, ctx))
            {
                StrategyHealth::RecordInvalidVote(strategy.GetHealthState());
                if(m_stats != NULL)
                    m_stats.RecordInvalidVote(strategy.GetId());

                //--- Record as failure
                StrategyHealth::RecordFailure(strategy.GetHealthState(), "Invalid vote");
                if(m_stats != NULL)
                    m_stats.RecordFailure(strategy.GetId(), elapsed_ms);
                m_total_failures++;
                continue;
            }

            //--- Categorize the result
            if(vote.direction == ATLAS_ORDER_NONE)
            {
                //--- Abstention
                if(m_stats != NULL)
                    m_stats.RecordAbstention(strategy.GetId(), elapsed_ms);
                StrategyHealth::RecordSuccess(strategy.GetHealthState());
            }
            else
            {
                //--- Directional vote — add to output
                if(m_stats != NULL)
                    m_stats.RecordSuccess(strategy.GetId(), elapsed_ms);
                StrategyHealth::RecordSuccess(strategy.GetHealthState());
                out_votes[out_count] = vote;
                out_count++;
            }
        }

        return (out_count > 0);
    }

    //=== Statistics ===
    ulong TotalExecutions(void) const { return m_total_executions; }
    ulong TotalFailures(void) const { return m_total_failures; }
    double AvgLatencyMs(void) const
    {
        if(m_total_executions == 0) return 0.0;
        return m_total_latency_ms / (double)m_total_executions;
    }
    double PeakLatencyMs(void) const { return m_peak_latency_ms; }

    void Reset(void)
    {
        m_total_executions = 0;
        m_total_failures   = 0;
        m_total_latency_ms = 0.0;
        m_peak_latency_ms  = 0.0;
    }

private:
    /// @brief Validate a vote produced by a strategy.
    bool IsValidVote(const StrategyVote &vote, const StrategyContext &ctx) const
    {
        //--- Direction must be valid
        if(vote.direction != ATLAS_ORDER_BUY &&
           vote.direction != ATLAS_ORDER_SELL &&
           vote.direction != ATLAS_ORDER_NONE)
            return false;

        //--- Confidence must be valid
        if(!MathIsValidNumber(vote.confidence)) return false;
        if(vote.confidence < 0.0 || vote.confidence > 1.0) return false;

        //--- Snapshot ID must match
        if(vote.snapshot_id != ctx.GetSnapshotId()) return false;

        //--- For directional votes, prices must be valid
        if(vote.direction != ATLAS_ORDER_NONE)
        {
            if(!MathIsValidNumber(vote.suggested_entry) || vote.suggested_entry <= 0.0) return false;
            if(!MathIsValidNumber(vote.suggested_sl) || vote.suggested_sl <= 0.0) return false;
            if(!MathIsValidNumber(vote.suggested_tp) || vote.suggested_tp <= 0.0) return false;
        }

        return true;
    }
};

#endif // ATLAS_STRATEGY_SCHEDULER_V2_MQH
//+------------------------------------------------------------------+
