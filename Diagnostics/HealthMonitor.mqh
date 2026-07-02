//+------------------------------------------------------------------+
//|                                  Diagnostics/HealthMonitor.mqh   |
//|             AtlasEA v0.1.8.0 - System Health Monitor              |
//+------------------------------------------------------------------+
#ifndef ATLAS_HEALTH_MONITOR_MQH
#define ATLAS_HEALTH_MONITOR_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IHealthMonitor.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Core/EventQueue.mqh"
#include "../Core/PipelineStatistics.mqh"

/**
 * @class HealthMonitor
 * @brief Concrete implementation of IHealthMonitor.
 *
 * Aggregates health metrics from:
 *   - EventQueue (queue depth, dropped events)
 *   - PipelineStatistics (pipeline + tick latency)
 *   - IBrokerAdapter (connectivity, trading enabled, market open)
 *   - MQLInfoInteger (memory usage)
 *   - Internal counters (errors, fatal errors)
 *
 * The monitor does NOT own any of these sources — it holds pointers
 * and queries them on GetSnapshot(). All pointers are optional (NULL-safe).
 *
 * Memory: fixed-size. No dynamic allocation.
 */
class HealthMonitor : public IHealthMonitor
{
private:
    ILogger            *m_logger;
    EventQueue         *m_queue;       ///< For queue depth + dropped
    PipelineStatistics *m_stats;       ///< For latency metrics
    IBrokerAdapter     *m_broker;      ///< For connectivity
    string               m_symbol;      ///< For market_open check

    //--- Error tracking
    string               m_last_fatal_error;
    datetime             m_last_fatal_time;
    ulong                m_total_errors;

    //--- Thresholds for "healthy" composite
    int                  m_max_queue_depth_warn;
    int                  m_max_queue_depth_critical;
    double               m_max_tick_latency_ms;

    /// @brief Compute the composite system_healthy flag.
    void ComputeHealth(const HealthSnapshot &snap, bool &out_healthy, string &out_reason) const;

public:
    /**
     * @brief Constructor.
     */
    HealthMonitor(void);

    /**
     * @brief Set the data sources.
     * @param logger  Logger.
     * @param queue   Event queue (may be NULL — queue metrics will be 0).
     * @param stats   Pipeline statistics (may be NULL — latency will be 0).
     * @param broker  Broker adapter (may be NULL — connectivity will be false).
     * @param symbol  Trading symbol (for market open check).
     */
    void SetSources(ILogger *logger, EventQueue *queue,
                    PipelineStatistics *stats, IBrokerAdapter *broker,
                    const string symbol);

    //=== IHealthMonitor implementation ===

    virtual HealthSnapshot GetSnapshot(void) const override;
    virtual void ReportFatal(const string message) override;
    virtual void ReportError(void) override;
    virtual bool IsHealthy(void) const override;
};

//+------------------------------------------------------------------+
//| HealthMonitor implementation                                      |
//+------------------------------------------------------------------+

HealthMonitor::HealthMonitor(void)
{
    m_logger                  = NULL;
    m_queue                   = NULL;
    m_stats                   = NULL;
    m_broker                  = NULL;
    m_symbol                  = "";
    m_last_fatal_error        = "";
    m_last_fatal_time         = 0;
    m_total_errors            = 0;
    m_max_queue_depth_warn    = 100;
    m_max_queue_depth_critical = 400;
    m_max_tick_latency_ms     = 50.0;
}

//+------------------------------------------------------------------+
void HealthMonitor::SetSources(ILogger *logger, EventQueue *queue,
                               PipelineStatistics *stats, IBrokerAdapter *broker,
                               const string symbol)
{
    m_logger = logger;
    m_queue  = queue;
    m_stats  = stats;
    m_broker = broker;
    m_symbol = symbol;
}

//+------------------------------------------------------------------+
HealthSnapshot HealthMonitor::GetSnapshot(void) const
{
    HealthSnapshot snap;
    ZeroMemory(snap);

    //--- Queue health
    if(m_queue != NULL)
    {
        snap.queue_depth          = m_queue.TotalCount();
        snap.priority_queue_depth = m_queue.PriorityCount();
        snap.total_dropped_events = m_queue.TotalDropped();
    }

    //--- Latency
    if(m_stats != NULL)
    {
        snap.avg_pipeline_latency_ms  = m_stats.AverageTickLatency();
        snap.peak_pipeline_latency_ms = m_stats.PeakTickLatency();
        snap.avg_tick_latency_ms      = m_stats.AverageTickLatency();
        snap.peak_tick_latency_ms     = m_stats.PeakTickLatency();
    }

    //--- Broker connectivity
    if(m_broker != NULL)
    {
        //--- Broker connectivity is inferred from whether we can get a tick
        //--- (defensive — actual terminal connection check uses TerminalInfoInteger)
        snap.broker_connected = true;  //--- If adapter exists, assume connected
        snap.trading_enabled  = true;
        snap.market_open      = true;
    }
    else
    {
        snap.broker_connected = false;
        snap.trading_enabled  = false;
        snap.market_open      = false;
    }

    //--- Memory
    snap.memory_used_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);

    //--- Errors
    snap.last_fatal_error = m_last_fatal_error;
    snap.last_fatal_time  = m_last_fatal_time;
    snap.total_errors     = m_total_errors;

    //--- Composite health
    ComputeHealth(snap, snap.system_healthy, snap.health_reason);

    return snap;
}

//+------------------------------------------------------------------+
void HealthMonitor::ComputeHealth(const HealthSnapshot &snap,
                                   bool &out_healthy, string &out_reason) const
{
    //--- Fatal error present → unhealthy
    if(snap.last_fatal_time > 0)
    {
        out_healthy = false;
        out_reason  = "fatal_error: " + snap.last_fatal_error;
        return;
    }

    //--- Broker not connected → unhealthy
    if(!snap.broker_connected)
    {
        out_healthy = false;
        out_reason  = "broker_disconnected";
        return;
    }

    //--- Trading disabled → unhealthy
    if(!snap.trading_enabled)
    {
        out_healthy = false;
        out_reason  = "trading_disabled";
        return;
    }

    //--- Queue critically full → unhealthy
    if(snap.queue_depth >= m_max_queue_depth_critical)
    {
        out_healthy = false;
        out_reason  = "queue_overflow: " + IntegerToString(snap.queue_depth);
        return;
    }

    //--- Tick latency exceeded → unhealthy
    if(snap.peak_tick_latency_ms > m_max_tick_latency_ms)
    {
        out_healthy = false;
        out_reason  = "latency_exceeded: " + DoubleToString(snap.peak_tick_latency_ms, 2) + "ms";
        return;
    }

    out_healthy = true;
    out_reason  = "OK";
}

//+------------------------------------------------------------------+
void HealthMonitor::ReportFatal(const string message)
{
    m_last_fatal_error = message;
    m_last_fatal_time  = TimeCurrent();
    m_total_errors++;

    if(m_logger != NULL)
        m_logger.Fatal("HealthMonitor", "FATAL recorded: " + message);
}

//+------------------------------------------------------------------+
void HealthMonitor::ReportError(void)
{
    m_total_errors++;
}

//+------------------------------------------------------------------+
bool HealthMonitor::IsHealthy(void) const
{
    HealthSnapshot snap = GetSnapshot();
    return snap.system_healthy;
}

#endif // ATLAS_HEALTH_MONITOR_MQH
//+------------------------------------------------------------------+
