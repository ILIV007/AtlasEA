//+------------------------------------------------------------------+
//|                      Interfaces/IPipelineStatistics.mqh         |
//|       AtlasEA v0.1.12.0 - Pipeline Statistics Interface         |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPIPELINE_STATISTICS_MQH
#define ATLAS_IPIPELINE_STATISTICS_MQH

#include "../Config/Settings.mqh"

/**
 * @struct PipelinePhaseStats
 * @brief Statistics for one pipeline phase.
 */
struct PipelinePhaseStats
{
    ulong  execution_count;     ///< Number of executions
    double avg_time_ms;         ///< Average execution time
    double max_time_ms;         ///< Maximum execution time
    ulong  timeout_count;       ///< Number of timeouts
    ulong  failure_count;       ///< Number of failures
};

/**
 * @class IPipelineStatistics
 * @brief Interface for tracking pipeline phase statistics.
 */
class IPipelineStatistics
{
public:
    virtual void RecordPhase(const int phase, const double time_ms,
                             const bool timeout, const bool failure) = 0;
    virtual void GetPhaseStats(const int phase, PipelinePhaseStats &out) const = 0;
    virtual void Reset(const int phase) = 0;
    virtual void ResetAll(void) = 0;
    virtual void LogSummary(void) const = 0;

    virtual ~IPipelineStatistics(void) {}
};

#endif // ATLAS_IPIPELINE_STATISTICS_MQH
//+------------------------------------------------------------------+
