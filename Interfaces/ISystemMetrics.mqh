//+------------------------------------------------------------------+
//|                    Interfaces/ISystemMetrics.mqh                |
//|       AtlasEA v0.1.14.0 - Aggregated System Metrics Interface   |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISYSTEM_METRICS_MQH
#define ATLAS_ISYSTEM_METRICS_MQH

#include "../Config/Settings.mqh"
#include "IPerformanceProfiler.mqh"
#include "ILatencyMonitor.mqh"
#include "IMemoryStatistics.mqh"
#include "IEventStatistics.mqh"
#include "IQueueStatistics.mqh"

/**
 * @class ISystemMetrics
 * @brief Aggregated interface for all system monitoring.
 *
 * HealthMonitor and MetricsExporter depend ONLY on this interface,
 * reducing coupling from 6 dependencies to 1.
 *
 * Implemented by MetricsCollector, which holds pointers to all 6
 * monitoring interfaces and delegates calls.
 */
class ISystemMetrics
{
public:
    //--- Sub-interface accessors ---
    virtual IPerformanceProfiler* GetProfiler(void) = 0;
    virtual ILatencyMonitor*      GetLatencyMonitor(void) = 0;
    virtual IMemoryStatistics*    GetMemoryStats(void) = 0;
    virtual IEventStatistics*     GetEventStats(void) = 0;
    virtual IQueueStatistics*     GetQueueStats(void) = 0;

    //--- Aggregate operations ---
    virtual void ResetAll(void) = 0;
    virtual void UpdateAll(void) = 0;

    virtual ~ISystemMetrics(void) {}
};

#endif // ATLAS_ISYSTEM_METRICS_MQH
//+------------------------------------------------------------------+
