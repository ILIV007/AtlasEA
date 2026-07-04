//+------------------------------------------------------------------+
//|                Diagnostics/MetricsCollector.mqh                 |
//|       AtlasEA v0.1.14.0 - System Metrics Collector               |
//+------------------------------------------------------------------+
#ifndef ATLAS_METRICS_COLLECTOR_MQH
#define ATLAS_METRICS_COLLECTOR_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ISystemMetrics.mqh"
#include "../Interfaces/IMetricsSnapshot.mqh"
#include "../Interfaces/IPerformanceProfiler.mqh"
#include "../Interfaces/ILatencyMonitor.mqh"
#include "../Interfaces/IMemoryStatistics.mqh"
#include "../Interfaces/IEventStatistics.mqh"
#include "../Interfaces/IQueueStatistics.mqh"
#include "PerformanceProfiler.mqh"
#include "LatencyMonitor.mqh"
#include "MemoryStatistics.mqh"
#include "EventStatistics.mqh"
#include "QueueStatistics.mqh"
//--- Note: PipelineStatistics is owned by Core (Core/PipelineStatistics.mqh).
//--- The Diagnostics version was removed as dead code.

/**
 * @class MetricsCollector
 * @brief Concrete implementation of ISystemMetrics + IMetricsSnapshotProvider.
 *
 * Owns the 6 monitoring component instances and exposes them through
 * the ISystemMetrics interface. This is the single point of access
 * for all system metrics.
 *
 * Also implements IMetricsSnapshotProvider::CaptureSnapshot() to produce
 * an immutable point-in-time MetricsSnapshot for the MetricsExporter.
 *
 * Memory: all 6 components are stack-allocated (~20 KB total).
 * No dynamic allocation.
 */
class MetricsCollector : public ISystemMetrics, public IMetricsSnapshotProvider
{
private:
    PerformanceProfiler   m_profiler;
    LatencyMonitor        m_latency;
    MemoryStatistics      m_memory;
    EventStatistics       m_events;
    QueueStatistics       m_queues;

public:
    /**
     * @brief Constructor.
     */
    MetricsCollector(void) {}

    //=== ISystemMetrics implementation ===

    virtual IPerformanceProfiler* GetProfiler(void) override { return &m_profiler; }
    virtual ILatencyMonitor*      GetLatencyMonitor(void) override { return &m_latency; }
    virtual IMemoryStatistics*    GetMemoryStats(void) override { return &m_memory; }
    virtual IEventStatistics*     GetEventStats(void) override { return &m_events; }
    virtual IQueueStatistics*     GetQueueStats(void) override { return &m_queues; }
    //--- GetPipelineStats() removed — PipelineStatistics is owned by Core

    virtual void ResetAll(void) override
    {
        m_profiler.ResetAll();
        m_latency.ResetAll();
        m_memory.Reset();
        m_events.Reset();
        m_queues.ResetAll();
    }

    virtual void UpdateAll(void) override
    {
        m_memory.UpdateMqlMemory();
    }

    //=== IMetricsSnapshotProvider implementation ===

    /**
     * @brief Capture a point-in-time snapshot of all metrics.
     *
     * Aggregates data from all 5 monitoring components into a single
     * immutable MetricsSnapshot struct. Used by MetricsExporter to
     * produce a final snapshot before shutdown.
     */
    virtual MetricsSnapshot CaptureSnapshot(void) const override
    {
        MetricsSnapshot snap;
        snap.timestamp = TimeCurrent();

        //--- Performance profiler (8 phases)
        for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
            m_profiler.GetProfile(i, snap.phases[i]);

        //--- Latency monitor (7 types)
        for(int i = 0; i < ATLAS_LATENCY_COUNT; i++)
            m_latency.GetStats(i, snap.latencies[i]);

        //--- Memory statistics
        snap.memory = m_memory.GetSnapshot();

        //--- Event statistics
        m_events.GetStats(snap.events);

        //--- Queue statistics (2 queues)
        for(int i = 0; i < ATLAS_QUEUE_COUNT; i++)
            m_queues.GetStats(i, snap.queues[i]);

        return snap;
    }

    //=== Direct access (for Bootstrap DI) ===

    /**
     * @brief Set the logger on all components.
     */
    void SetLogger(ILogger *logger)
    {
        m_profiler.SetLogger(logger);
        m_latency.SetLogger(logger);
        m_memory.SetLogger(logger);
        m_events.SetLogger(logger);
        m_queues.SetLogger(logger);
    }

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate structural invariants of the metrics collector.
     *
     * Delegates to each owned sub-component that exposes Validate().
     * Currently only PerformanceProfiler and LatencyMonitor have
     * Validate(); MemoryStatistics / EventStatistics / QueueStatistics
     * do not (yet) expose it and are silently treated as Ok() — they are
     * pure-statistics structs with no invariants beyond their Reset().
     *
     * Returns the first sub-component failure encountered, or Ok() if
     * all sub-components validate cleanly.
     *
     * @return ValidationResult::Ok() if all invariants hold,
     *         ValidationResult::Fail(code, reason, field) otherwise.
     */
    ValidationResult Validate(void) const
    {
        ValidationResult r;

        r = m_profiler.Validate();
        if(!r.valid) return r;

        r = m_latency.Validate();
        if(!r.valid) return r;

        //--- m_memory / m_events / m_queues have no Validate() yet — skip.
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_METRICS_COLLECTOR_MQH
//+------------------------------------------------------------------+
