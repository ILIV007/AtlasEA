//+------------------------------------------------------------------+
//|                   Interfaces/IMetricsSnapshot.mqh               |
//|       AtlasEA v0.1.14.0 - Immutable Metrics Snapshot            |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMETRICS_SNAPSHOT_MQH
#define ATLAS_IMETRICS_SNAPSHOT_MQH

#include "../Config/Settings.mqh"
#include "IPerformanceProfiler.mqh"
#include "ILatencyMonitor.mqh"
#include "IMemoryStatistics.mqh"
#include "IEventStatistics.mqh"
#include "IQueueStatistics.mqh"

/**
 * @struct MetricsSnapshot
 * @brief Immutable point-in-time snapshot of ALL system metrics.
 *
 * The MetricsExporter receives this struct and does NOT know about
 * the individual monitoring interfaces. This decouples the exporter
 * from the monitoring implementation.
 *
 * Memory: ~4 KB (fixed). No dynamic allocation.
 */
struct MetricsSnapshot
{
    datetime timestamp;

    //--- Performance Profiler (8 phases) ---
    PhaseProfile phases[ATLAS_PHASE_COUNT];

    //--- Latency Monitor (7 types) ---
    LatencyStats latencies[ATLAS_LATENCY_COUNT];

    //--- Memory Statistics ---
    MemorySnapshot memory;

    //--- Event Statistics ---
    EventStats events;

    //--- Queue Statistics (2 queues) ---
    QueueStats queues[ATLAS_QUEUE_COUNT];
};

/**
 * @class IMetricsSnapshotProvider
 * @brief Interface for capturing a MetricsSnapshot.
 *
 * Implemented by MetricsCollector. The exporter calls Capture() to
 * get an immutable snapshot, then formats it.
 */
class IMetricsSnapshotProvider
{
public:
    /**
     * @brief Capture a point-in-time snapshot of all metrics.
     * @return A populated MetricsSnapshot struct.
     */
    virtual MetricsSnapshot CaptureSnapshot(void) const = 0;

    virtual ~IMetricsSnapshotProvider(void) {}
};

#endif // ATLAS_IMETRICS_SNAPSHOT_MQH
//+------------------------------------------------------------------+
