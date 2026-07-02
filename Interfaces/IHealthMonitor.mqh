//+------------------------------------------------------------------+
//|                                   Interfaces/IHealthMonitor.mqh  |
//|                AtlasEA v0.1.8.0 - Health Monitor Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_IHEALTH_MONITOR_MQH
#define ATLAS_IHEALTH_MONITOR_MQH

#include "../Config/Settings.mqh"

/**
 * @struct HealthSnapshot
 * @brief Immutable snapshot of system health metrics.
 *
 * Populated by IHealthMonitor.GetSnapshot() on demand.
 * All values are point-in-time readings (no history).
 */
struct HealthSnapshot
{
    //--- Queue health
    int    queue_depth;           ///< Total events in both queues
    int    priority_queue_depth;  ///< Events in priority queue
    ulong  total_dropped_events;  ///< Lifetime dropped events

    //--- Latency
    double avg_pipeline_latency_ms;  ///< Average tick pipeline latency
    double peak_pipeline_latency_ms; ///< Peak tick pipeline latency
    double avg_tick_latency_ms;      ///< Average OnTick latency
    double peak_tick_latency_ms;     ///< Peak OnTick latency

    //--- Broker connectivity
    bool   broker_connected;      ///< Terminal connected to server
    bool   trading_enabled;       ///< Auto-trading allowed
    bool   market_open;           ///< Symbol trade mode enabled

    //--- Memory
    ulong  memory_used_mb;        ///< MQL5 memory in use (MB)

    //--- Errors
    string last_fatal_error;      ///< Last FATAL-level error message
    datetime last_fatal_time;     ///< When the last fatal occurred
    ulong  total_errors;          ///< Lifetime ERROR+ events

    //--- Overall
    bool   system_healthy;        ///< Composite health flag
    string health_reason;         ///< If unhealthy, the reason
};

/**
 * @class IHealthMonitor
 * @brief Interface for system health monitoring.
 *
 * Implemented by the Diagnostics module. Consumed by CoreEngine
 * (for heartbeat logging) and by Bootstrap (for startup validation).
 *
 * The HealthMonitor aggregates metrics from multiple sources
 * (EventQueue, PipelineStatistics, TimeBudgetRunner, broker adapter).
 * It does NOT own those sources — it queries them on demand.
 */
class IHealthMonitor
{
public:
    /**
     * @brief Capture a point-in-time health snapshot.
     * @return A populated HealthSnapshot struct.
     */
    virtual HealthSnapshot GetSnapshot(void) const = 0;

    /**
     * @brief Report a fatal error (stored as last_fatal_error).
     * @param message The fatal error message.
     */
    virtual void ReportFatal(const string message) = 0;

    /**
     * @brief Report a non-fatal error (increments total_errors).
     */
    virtual void ReportError(void) = 0;

    /**
     * @brief Check if the system is currently healthy.
     */
    virtual bool IsHealthy(void) const = 0;

    virtual ~IHealthMonitor(void) {}
};

#endif // ATLAS_IHEALTH_MONITOR_MQH
//+------------------------------------------------------------------+
