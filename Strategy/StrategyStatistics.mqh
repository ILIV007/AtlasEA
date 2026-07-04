//+------------------------------------------------------------------+
//|                  Strategy/StrategyStatistics.mqh                 |
//|       AtlasEA v0.1.20.0 - Per-Strategy Statistics                |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_STATISTICS_V2_MQH
#define ATLAS_STRATEGY_STATISTICS_V2_MQH

#include "../Config/Settings.mqh"

/**
 * @struct StrategyStats
 * @brief Execution statistics for one strategy.
 */
struct StrategyStats
{
    ulong  execution_count;       ///< Total Evaluate() calls
    ulong  success_count;         ///< Produced a valid directional vote
    ulong  failure_count;         ///< Returned invalid or failed
    ulong  abstention_count;      ///< Returned ATLAS_ORDER_NONE
    ulong  invalid_vote_count;    ///< Votes that failed validation
    ulong  disabled_count;        ///< Times skipped due to disabled
    ulong  cooldown_count;        ///< Times skipped due to cooldown
    double total_latency_ms;      ///< Sum of execution times
    double peak_latency_ms;       ///< Maximum single execution time
    datetime last_execution_time; ///< When last executed

    /**
     * @brief Default constructor.
     */
    StrategyStats(void)
    {
        execution_count    = 0;
        success_count      = 0;
        failure_count      = 0;
        abstention_count   = 0;
        invalid_vote_count = 0;
        disabled_count     = 0;
        cooldown_count     = 0;
        total_latency_ms   = 0.0;
        peak_latency_ms    = 0.0;
        last_execution_time = 0;
    }

    /**
     * @brief Get average latency in milliseconds.
     */
    double AverageLatencyMs(void) const
    {
        if(execution_count == 0) return 0.0;
        return total_latency_ms / (double)execution_count;
    }

    /**
     * @brief Get success rate (0..1).
     */
    double SuccessRate(void) const
    {
        if(execution_count == 0) return 0.0;
        return (double)success_count / (double)execution_count;
    }

    /**
     * @brief Reset all statistics.
     */
    void Reset(void)
    {
        execution_count    = 0;
        success_count      = 0;
        failure_count      = 0;
        abstention_count   = 0;
        invalid_vote_count = 0;
        disabled_count     = 0;
        cooldown_count     = 0;
        total_latency_ms   = 0.0;
        peak_latency_ms    = 0.0;
        last_execution_time = 0;
    }
};

/**
 * @class StrategyStatistics
 * @brief Tracks per-strategy execution statistics.
 *
 * Fixed-size array of ATLAS_MAX_STRATEGIES (8) stats entries.
 * No dynamic allocation.
 */
class StrategyStatistics
{
private:
    StrategyStats m_stats[ATLAS_MAX_STRATEGIES];
    int           m_strategy_ids[ATLAS_MAX_STRATEGIES];
    int           m_count;

    int FindIndex(const int strategy_id) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategy_ids[i] == strategy_id)
                return i;
        }
        return -1;
    }

    int GetOrCreateIndex(const int strategy_id)
    {
        int idx = FindIndex(strategy_id);
        if(idx >= 0) return idx;

        if(m_count >= ATLAS_MAX_STRATEGIES)
            return 0;  //--- Defensive: reuse slot 0

        m_strategy_ids[m_count] = strategy_id;
        m_stats[m_count].Reset();
        m_count++;
        return m_count - 1;
    }

public:
    /**
     * @brief Constructor.
     */
    StrategyStatistics(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
            m_strategy_ids[i] = 0;
    }

    /**
     * @brief Record a successful execution.
     */
    void RecordSuccess(const int strategy_id, const double latency_ms)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].execution_count++;
        m_stats[idx].success_count++;
        m_stats[idx].total_latency_ms += latency_ms;
        if(latency_ms > m_stats[idx].peak_latency_ms)
            m_stats[idx].peak_latency_ms = latency_ms;
        m_stats[idx].last_execution_time = TimeCurrent();
    }

    /**
     * @brief Record a failure.
     */
    void RecordFailure(const int strategy_id, const double latency_ms)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].execution_count++;
        m_stats[idx].failure_count++;
        m_stats[idx].total_latency_ms += latency_ms;
        if(latency_ms > m_stats[idx].peak_latency_ms)
            m_stats[idx].peak_latency_ms = latency_ms;
        m_stats[idx].last_execution_time = TimeCurrent();
    }

    /**
     * @brief Record an abstention.
     */
    void RecordAbstention(const int strategy_id, const double latency_ms)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].execution_count++;
        m_stats[idx].abstention_count++;
        m_stats[idx].total_latency_ms += latency_ms;
        m_stats[idx].last_execution_time = TimeCurrent();
    }

    /**
     * @brief Record an invalid vote.
     */
    void RecordInvalidVote(const int strategy_id)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].invalid_vote_count++;
    }

    /**
     * @brief Record a skip due to disabled.
     */
    void RecordDisabled(const int strategy_id)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].disabled_count++;
    }

    /**
     * @brief Record a skip due to cooldown.
     */
    void RecordCooldown(const int strategy_id)
    {
        int idx = GetOrCreateIndex(strategy_id);
        m_stats[idx].cooldown_count++;
    }

    /**
     * @brief Get stats for a strategy.
     */
    bool GetStats(const int strategy_id, StrategyStats &out) const
    {
        int idx = FindIndex(strategy_id);
        if(idx < 0) return false;
        out = m_stats[idx];
        return true;
    }

    /**
     * @brief Reset all statistics.
     */
    void Reset(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        {
            m_strategy_ids[i] = 0;
            m_stats[i].Reset();
        }
    }

    /**
     * @brief Get the number of tracked strategies.
     */
    int Count(void) const { return m_count; }
};

#endif // ATLAS_STRATEGY_STATISTICS_V2_MQH
//+------------------------------------------------------------------+
