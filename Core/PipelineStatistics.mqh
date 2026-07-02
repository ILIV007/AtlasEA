//+------------------------------------------------------------------+
//|                                      Core/PipelineStatistics.mqh
//|             AtlasEA v2.0 - Pipeline & Latency Statistics           |
//+------------------------------------------------------------------+
#ifndef ATLAS_PIPELINE_STATISTICS_MQH
#define ATLAS_PIPELINE_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class PipelineStatistics
 * @brief Tracks per-phase latency and pipeline execution metrics.
 *
 * Maintains a rolling window of latency samples per phase for p50/p95/p99
 * computation, plus aggregate counters (total ticks, total phases executed,
 * budget overruns).
 *
 * Memory: fixed-size ring buffer per phase (ATLAS_LATENCY_SAMPLES).
 * No dynamic allocation.
 *
 * Phases tracked: Market, Strategy, Risk, Execution, Dispatch, Total.
 */
class PipelineStatistics
{
public:
    /// Phase identifiers
    enum ENUM_PHASE
    {
        PHASE_MARKET     = 0,
        PHASE_STRATEGY   = 1,
        PHASE_RISK       = 2,
        PHASE_EXECUTION  = 3,
        PHASE_DISPATCH   = 4,
        PHASE_TOTAL      = 5,
        PHASE_COUNT      = 6
    };

private:
    /// Per-phase rolling latency samples (milliseconds)
    double m_samples[PHASE_COUNT][ATLAS_LATENCY_SAMPLES];
    int    m_sample_count[PHASE_COUNT];
    int    m_sample_head[PHASE_COUNT];

    /// Per-phase aggregate stats
    double m_phase_total_ms[PHASE_COUNT];
    double m_phase_peak_ms[PHASE_COUNT];
    ulong  m_phase_executions[PHASE_COUNT];

    /// Pipeline-level stats
    ulong  m_total_ticks;
    ulong  m_budget_overruns;     ///< Ticks that exceeded max_ms_per_tick
    double m_tick_total_ms;
    double m_tick_peak_ms;

    ILogger *m_logger;

    /// @brief Compute percentile from the rolling window.
    double Percentile(const ENUM_PHASE phase, const double p) const;

public:
    /**
     * @brief Constructor — initializes all counters to zero.
     */
    PipelineStatistics(void);

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Record the latency of a single phase execution.
     * @param phase The phase that completed.
     * @param ms    Elapsed milliseconds.
     */
    void RecordPhase(const ENUM_PHASE phase, const double ms);

    /**
     * @brief Record a complete tick (all phases done).
     * @param total_ms Total tick elapsed time.
     * @param budget_overrun true if total_ms exceeded the budget.
     */
    void RecordTick(const double total_ms, const bool budget_overrun);

    /**
     * @brief Get the average latency for a phase.
     */
    double AverageLatency(const ENUM_PHASE phase) const;

    /**
     * @brief Get the peak latency for a phase.
     */
    double PeakLatency(const ENUM_PHASE phase) const;

    /**
     * @brief Get the p95 latency for a phase.
     */
    double P95Latency(const ENUM_PHASE phase) const;

    /**
     * @brief Get the p99 latency for a phase.
     */
    double P99Latency(const ENUM_PHASE phase) const;

    /**
     * @brief Get the number of executions for a phase.
     */
    ulong  Executions(const ENUM_PHASE phase) const { return m_phase_executions[phase]; }

    /// @brief Total ticks processed.
    ulong  TotalTicks(void) const { return m_total_ticks; }

    /// @brief Total ticks that exceeded the budget.
    ulong  BudgetOverruns(void) const { return m_budget_overruns; }

    /// @brief Average tick latency (ms).
    double AverageTickLatency(void) const;

    /// @brief Peak tick latency (ms).
    double PeakTickLatency(void) const { return m_tick_peak_ms; }

    /**
     * @brief Reset all statistics to zero.
     */
    void Reset(void);

    /**
     * @brief Log a summary of all statistics.
     */
    void LogSummary(void) const;
};

//+------------------------------------------------------------------+
//| PipelineStatistics implementation                                 |
//+------------------------------------------------------------------+

PipelineStatistics::PipelineStatistics(void)
{
    m_logger = NULL;
    for(int p = 0; p < PHASE_COUNT; p++)
    {
        m_sample_count[p]     = 0;
        m_sample_head[p]      = 0;
        m_phase_total_ms[p]   = 0.0;
        m_phase_peak_ms[p]    = 0.0;
        m_phase_executions[p] = 0;
        for(int i = 0; i < ATLAS_LATENCY_SAMPLES; i++)
            m_samples[p][i] = 0.0;
    }
    m_total_ticks      = 0;
    m_budget_overruns  = 0;
    m_tick_total_ms    = 0.0;
    m_tick_peak_ms     = 0.0;
}

//+------------------------------------------------------------------+
void PipelineStatistics::RecordPhase(const ENUM_PHASE phase, const double ms)
{
    if(phase < 0 || phase >= PHASE_COUNT) return;

    int idx = m_sample_head[phase];
    m_samples[phase][idx] = ms;
    m_sample_head[phase] = (m_sample_head[phase] + 1) % ATLAS_LATENCY_SAMPLES;
    if(m_sample_count[phase] < ATLAS_LATENCY_SAMPLES)
        m_sample_count[phase]++;

    m_phase_total_ms[phase]   += ms;
    m_phase_executions[phase]++;
    if(ms > m_phase_peak_ms[phase])
        m_phase_peak_ms[phase] = ms;
}

//+------------------------------------------------------------------+
void PipelineStatistics::RecordTick(const double total_ms, const bool budget_overrun)
{
    m_total_ticks++;
    m_tick_total_ms += total_ms;
    if(total_ms > m_tick_peak_ms)
        m_tick_peak_ms = total_ms;
    if(budget_overrun)
        m_budget_overruns++;

    RecordPhase(PHASE_TOTAL, total_ms);
}

//+------------------------------------------------------------------+
double PipelineStatistics::Percentile(const ENUM_PHASE phase, const double p) const
{
    if(phase < 0 || phase >= PHASE_COUNT) return 0.0;
    int n = m_sample_count[phase];
    if(n == 0) return 0.0;

    //--- Copy and sort (small fixed array — no heap alloc)
    double tmp[ATLAS_LATENCY_SAMPLES];
    for(int i = 0; i < n; i++)
        tmp[i] = m_samples[phase][i];

    //--- Simple insertion sort (n <= 256, no STL)
    for(int i = 1; i < n; i++)
    {
        double key = tmp[i];
        int j = i - 1;
        while(j >= 0 && tmp[j] > key)
        {
            tmp[j+1] = tmp[j];
            j--;
        }
        tmp[j+1] = key;
    }

    int idx = (int)(p * (double)(n - 1));
    if(idx < 0) idx = 0;
    if(idx >= n) idx = n - 1;
    return tmp[idx];
}

//+------------------------------------------------------------------+
double PipelineStatistics::AverageLatency(const ENUM_PHASE phase) const
{
    if(phase < 0 || phase >= PHASE_COUNT) return 0.0;
    if(m_phase_executions[phase] == 0) return 0.0;
    return m_phase_total_ms[phase] / (double)m_phase_executions[phase];
}

//+------------------------------------------------------------------+
double PipelineStatistics::PeakLatency(const ENUM_PHASE phase) const
{
    if(phase < 0 || phase >= PHASE_COUNT) return 0.0;
    return m_phase_peak_ms[phase];
}

//+------------------------------------------------------------------+
double PipelineStatistics::P95Latency(const ENUM_PHASE phase) const
{
    return Percentile(phase, 0.95);
}

//+------------------------------------------------------------------+
double PipelineStatistics::P99Latency(const ENUM_PHASE phase) const
{
    return Percentile(phase, 0.99);
}

//+------------------------------------------------------------------+
double PipelineStatistics::AverageTickLatency(void) const
{
    if(m_total_ticks == 0) return 0.0;
    return m_tick_total_ms / (double)m_total_ticks;
}

//+------------------------------------------------------------------+
void PipelineStatistics::Reset(void)
{
    for(int p = 0; p < PHASE_COUNT; p++)
    {
        m_sample_count[p]     = 0;
        m_sample_head[p]      = 0;
        m_phase_total_ms[p]   = 0.0;
        m_phase_peak_ms[p]    = 0.0;
        m_phase_executions[p] = 0;
    }
    m_total_ticks      = 0;
    m_budget_overruns  = 0;
    m_tick_total_ms    = 0.0;
    m_tick_peak_ms     = 0.0;
}

//+------------------------------------------------------------------+
void PipelineStatistics::LogSummary(void) const
{
    if(m_logger == NULL) return;

    string names[PHASE_COUNT] = {"Market", "Strategy", "Risk", "Execution", "Dispatch", "Total"};
    for(int p = 0; p < PHASE_COUNT; p++)
    {
        m_logger.Info("PipelineStats",
            names[p] + " avg=" + DoubleToString(AverageLatency((ENUM_PHASE)p), 3) +
            " p95=" + DoubleToString(P95Latency((ENUM_PHASE)p), 3) +
            " peak=" + DoubleToString(PeakLatency((ENUM_PHASE)p), 3) +
            " count=" + IntegerToString((long)m_phase_executions[p]));
    }
    m_logger.Info("PipelineStats",
        "Ticks=" + IntegerToString((long)m_total_ticks) +
        " avg_tick=" + DoubleToString(AverageTickLatency(), 3) +
        " peak_tick=" + DoubleToString(m_tick_peak_ms, 3) +
        " overruns=" + IntegerToString((long)m_budget_overruns));
}

#endif // ATLAS_PIPELINE_STATISTICS_MQH
//+------------------------------------------------------------------+
