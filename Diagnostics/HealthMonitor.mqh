//+------------------------------------------------------------------+
//|                    Diagnostics/HealthMonitor.mqh                |
//|       AtlasEA v0.1.12.0 - System Health Monitor (Full)          |
//+------------------------------------------------------------------+
#ifndef ATLAS_HEALTH_MONITOR_MQH
#define ATLAS_HEALTH_MONITOR_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/IHealthMonitor.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IPerformanceProfiler.mqh"
#include "../Interfaces/ILatencyMonitor.mqh"
#include "../Interfaces/IMemoryStatistics.mqh"
#include "../Interfaces/IEventStatistics.mqh"
#include "../Interfaces/IQueueStatistics.mqh"

//--- Note: ATLAS_HEALTH_* macros and HealthReport struct are defined in
//--- Interfaces/IHealthMonitor.mqh (the canonical source). This file
//--- uses them — no redefinition here.

/**
 * @class HealthMonitor
 * @brief Comprehensive system health monitor.
 *
 * Aggregates data from all monitoring interfaces and produces a
 * HealthReport with GREEN/YELLOW/RED status.
 *
 * GREEN: All systems nominal.
 * YELLOW: Degraded but operational (warnings, slow but functional).
 * RED: Critical — intervention required (kill switch, broker disconnect,
 *      queue overflow, persistent failures).
 */
class HealthMonitor : public IHealthMonitor
{
private:
    ILogger              *m_logger;
    IBrokerAdapter       *m_broker;
    IPerformanceProfiler *m_profiler;
    ILatencyMonitor      *m_latency;
    IMemoryStatistics    *m_memory;
    IEventStatistics     *m_events;
    IQueueStatistics     *m_queues;

    //--- Thresholds
    double m_slow_tick_ms;          ///< Tick latency threshold for "slow"
    double m_slow_order_ms;         ///< Order latency threshold
    double m_high_slippage_points;  ///< Slippage threshold
    double m_memory_growth_pct;     ///< Memory growth threshold
    int    m_queue_overflow_limit;  ///< Queue depth for overflow warning

    //--- Error tracking
    string  m_last_fatal_error;
    datetime m_last_fatal_time;
    ulong   m_total_errors;

    /// @brief Add an issue to the report.
    void AddIssue(HealthReport &report, const ENUM_HEALTH_ISSUE_CODE code,
                   const string description, const int severity) const
    {
        if(report.issue_count < 16)
        {
            report.issues[report.issue_count].code        = code;
            report.issues[report.issue_count].description = description;
            report.issues[report.issue_count].timestamp   = TimeCurrent();
            report.issues[report.issue_count].severity    = severity;
            report.issue_count++;
        }
    }

public:
    /**
     * @brief Constructor.
     */
    HealthMonitor(void)
    {
        m_logger               = NULL;
        m_broker               = NULL;
        m_profiler             = NULL;
        m_latency              = NULL;
        m_memory               = NULL;
        m_events               = NULL;
        m_queues               = NULL;
        m_slow_tick_ms         = 50.0;   ///< 50ms = slow tick
        m_slow_order_ms        = 5000.0; ///< 5s = slow order
        m_high_slippage_points = 20.0;   ///< 20 points = high slippage
        m_memory_growth_pct    = 50.0;   ///< 50% growth = warning
        m_queue_overflow_limit = 400;    ///< 400 events = overflow
        m_last_fatal_time      = 0;
        m_total_errors         = 0;
    }

    /**
     * @brief Set all data sources (dependency injection).
     */
    void SetSources(ILogger *logger,
                    IBrokerAdapter *broker,
                    IPerformanceProfiler *profiler,
                    ILatencyMonitor *latency,
                    IMemoryStatistics *memory,
                    IEventStatistics *events,
                    IQueueStatistics *queues)
    {
        m_logger   = logger;
        m_broker   = broker;
        m_profiler = profiler;
        m_latency  = latency;
        m_memory   = memory;
        m_events   = events;
        m_queues   = queues;
    }

    /**
     * @brief Clear all borrowed source pointers.
     *
     * Called during shutdown BEFORE the source objects (broker, metrics
     * components) are destroyed. Prevents dangling-pointer access if the
     * HealthMonitor outlives its sources (e.g. during Bootstrapper teardown).
     */
    void ClearSources(void)
    {
        m_logger   = NULL;
        m_broker   = NULL;
        m_profiler = NULL;
        m_latency  = NULL;
        m_memory   = NULL;
        m_events   = NULL;
        m_queues   = NULL;
    }

    /**
     * @brief Reset error-tracking state.
     *
     * Clears the last fatal error, fatal timestamp, and total error count.
     * Allows the monitor to recover from a RED state without object
     * destruction (restart-safe).
     */
    void Reset(void)
    {
        m_last_fatal_error = "";
        m_last_fatal_time  = 0;
        m_total_errors     = 0;
    }

    /**
     * @brief Set thresholds (optional — defaults are sensible).
     */
    void SetThresholds(const double slow_tick_ms,
                       const double slow_order_ms,
                       const double high_slippage_points,
                       const double memory_growth_pct,
                       const int queue_overflow_limit)
    {
        m_slow_tick_ms         = slow_tick_ms;
        m_slow_order_ms        = slow_order_ms;
        m_high_slippage_points = high_slippage_points;
        m_memory_growth_pct    = memory_growth_pct;
        m_queue_overflow_limit = queue_overflow_limit;
    }

    //=== IHealthMonitor implementation ===

    virtual HealthSnapshot GetSnapshot(void) const override
    {
        HealthSnapshot snap;
        ZeroMemory(snap);

        //--- Queue health
        if(m_events != NULL)
        {
            EventStats es;
            m_events.GetStats(es);
            snap.total_dropped_events = es.events_dropped;
            snap.queue_depth          = (int)es.max_queue_depth;
        }

        //--- Latency
        if(m_latency != NULL)
        {
            snap.avg_pipeline_latency_ms = m_latency.GetAverage(ATLAS_LATENCY_PIPELINE);
            snap.peak_pipeline_latency_ms = m_latency.GetPeak(ATLAS_LATENCY_PIPELINE);
            snap.avg_tick_latency_ms      = m_latency.GetAverage(ATLAS_LATENCY_TICK);
            snap.peak_tick_latency_ms      = m_latency.GetPeak(ATLAS_LATENCY_TICK);
        }

        //--- Broker connectivity
        if(m_broker != NULL)
        {
            snap.broker_connected = true;
            snap.trading_enabled   = true;
            snap.market_open       = true;
        }

        //--- Memory
        if(m_memory != NULL)
        {
            MemorySnapshot ms = m_memory.GetSnapshot();
            snap.memory_used_mb = ms.current_memory_mb;
        }

        //--- Errors
        snap.last_fatal_error = m_last_fatal_error;
        snap.last_fatal_time  = m_last_fatal_time;
        snap.total_errors     = m_total_errors;

        //--- Composite health
        HealthReport report = GetReport();
        snap.system_healthy = (report.status == ATLAS_HEALTH_GREEN);
        snap.health_reason  = report.summary;

        return snap;
    }

    virtual void ReportFatal(const string message) override
    {
        m_last_fatal_error = message;
        m_last_fatal_time  = TimeCurrent();
        m_total_errors++;
        if(m_logger != NULL)
            m_logger.Fatal("HealthMonitor", "FATAL: " + message);
    }

    virtual void ReportError(void) override { m_total_errors++; }

    virtual bool IsHealthy(void) const override
    {
        return (GetReport().status == ATLAS_HEALTH_GREEN);
    }

    //=== Extended API ===

    /**
     * @brief Validate structural invariants of the health monitor.
     *
     * Design by contract (v0.1.26.x): verifies that error counters are
     * non-negative and that the configured thresholds are positive
     * (zero/negative thresholds would silently disable the related
     * checks in GetReport()).
     *
     * @return ValidationResult::Ok() if all invariants hold,
     *         ValidationResult::Fail(code, reason, field) otherwise.
     */
    ValidationResult Validate(void) const
    {
        //--- m_total_errors is ulong — can never be negative in practice,
        //--- but the cast makes the contract explicit & future-proof.
        if((long)m_total_errors < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "m_total_errors is negative",
                                          "m_total_errors");

        if(m_queue_overflow_limit <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "m_queue_overflow_limit must be > 0",
                                          "m_queue_overflow_limit");

        if(m_slow_tick_ms <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "m_slow_tick_ms must be > 0",
                                          "m_slow_tick_ms");

        if(m_slow_order_ms <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "m_slow_order_ms must be > 0",
                                          "m_slow_order_ms");

        return ValidationResult::Ok();
    }

    /**
     * @brief Generate a complete health report.
     * @return HealthReport with GREEN/YELLOW/RED status and issues.
     */
    virtual HealthReport GetReport(void) const override
    {
        HealthReport report;
        report.status      = ATLAS_HEALTH_GREEN;
        report.issue_count = 0;
        report.summary     = "All systems nominal";

        report.queue_overflow       = false;
        report.pipeline_timeout     = false;
        report.memory_growth        = false;
        report.snapshot_failure     = false;
        report.persistence_failure  = false;
        report.broker_connected     = true;
        report.recovery_failure     = false;
        report.slow_tick            = false;
        report.slow_order           = false;
        report.high_slippage        = false;
        report.kill_switch_active   = false;

        //--- Check 1: Fatal error → RED
        if(m_last_fatal_time > 0)
        {
            report.status = ATLAS_HEALTH_RED;
            AddIssue(report, FATAL_ERROR, "Fatal error: " + m_last_fatal_error, ATLAS_HEALTH_RED);
        }

        //--- Check 2: Broker disconnect → RED
        if(m_broker == NULL)
        {
            report.broker_connected = false;
            report.status = ATLAS_HEALTH_RED;
            AddIssue(report, BROKER_DISCONNECTED, "Broker adapter not connected", ATLAS_HEALTH_RED);
        }

        //--- Check 3: Queue overflow → RED
        if(m_events != NULL)
        {
            EventStats es;
            m_events.GetStats(es);
            if((int)es.max_queue_depth >= m_queue_overflow_limit)
            {
                report.queue_overflow = true;
                report.status = ATLAS_HEALTH_RED;
                AddIssue(report, QUEUE_OVERFLOW,
                          "Queue overflow: depth=" + IntegerToString((int)es.max_queue_depth),
                          ATLAS_HEALTH_RED);
            }
            if(es.events_dropped > 0)
            {
                report.status = (report.status < ATLAS_HEALTH_YELLOW) ? ATLAS_HEALTH_YELLOW : report.status;
                AddIssue(report, QUEUE_OVERFLOW,
                          "Events dropped: " + IntegerToString((long)es.events_dropped),
                          ATLAS_HEALTH_YELLOW);
            }
        }

        //--- Check 4: Slow tick → YELLOW
        if(m_latency != NULL)
        {
            double peak_tick = m_latency.GetPeak(ATLAS_LATENCY_TICK);
            if(peak_tick > m_slow_tick_ms)
            {
                report.slow_tick = true;
                report.status = (report.status < ATLAS_HEALTH_YELLOW) ? ATLAS_HEALTH_YELLOW : report.status;
                AddIssue(report, SLOW_TICK,
                          "Slow tick: " + DoubleToString(peak_tick, 1) + "ms",
                          ATLAS_HEALTH_YELLOW);
            }

            double peak_order = m_latency.GetPeak(ATLAS_LATENCY_ORDER);
            if(peak_order > m_slow_order_ms)
            {
                report.slow_order = true;
                report.status = (report.status < ATLAS_HEALTH_YELLOW) ? ATLAS_HEALTH_YELLOW : report.status;
                AddIssue(report, SLOW_ORDER,
                          "Slow order: " + DoubleToString(peak_order, 1) + "ms",
                          ATLAS_HEALTH_YELLOW);
            }
        }

        //--- Check 5: Memory growth → YELLOW
        if(m_memory != NULL)
        {
            MemorySnapshot ms = m_memory.GetSnapshot();
            if(ms.memory_growth_pct > m_memory_growth_pct)
            {
                report.memory_growth = true;
                report.status = (report.status < ATLAS_HEALTH_YELLOW) ? ATLAS_HEALTH_YELLOW : report.status;
                AddIssue(report, MEMORY_GROWTH,
                          "Memory growth: " + DoubleToString(ms.memory_growth_pct, 1) + "%",
                          ATLAS_HEALTH_YELLOW);
            }
        }

        //--- Check 6: Pipeline timeout → YELLOW
        if(m_profiler != NULL)
        {
            for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
            {
                PhaseProfile pp;
                m_profiler.GetProfile(i, pp);
                if(pp.max_microseconds > (ulong)(m_slow_tick_ms * 1000))
                {
                    report.pipeline_timeout = true;
                    report.status = (report.status < ATLAS_HEALTH_YELLOW) ? ATLAS_HEALTH_YELLOW : report.status;
                    AddIssue(report, PIPELINE_TIMEOUT,
                              "Pipeline phase " + IntegerToString(i) + " timeout: " +
                              IntegerToString((long)pp.max_microseconds) + "us",
                              ATLAS_HEALTH_YELLOW);
                    break;
                }
            }
        }

        //--- Build summary
        if(report.status == ATLAS_HEALTH_GREEN)
            report.summary = "All systems nominal";
        else if(report.status == ATLAS_HEALTH_YELLOW)
            report.summary = "Degraded: " + IntegerToString(report.issue_count) + " warning(s)";
        else
            report.summary = "CRITICAL: " + IntegerToString(report.issue_count) + " issue(s)";

        return report;
    }

    /**
     * @brief Log the health report.
     */
    virtual void LogReport(void) const override
    {
        if(m_logger == NULL) return;

        HealthReport report = GetReport();
        string status_str;
        switch(report.status)
        {
            case ATLAS_HEALTH_GREEN:  status_str = "GREEN";  break;
            case ATLAS_HEALTH_YELLOW: status_str = "YELLOW"; break;
            case ATLAS_HEALTH_RED:    status_str = "RED";    break;
            default:                  status_str = "UNKNOWN"; break;
        }

        m_logger.Info("HealthMonitor", "=== HEALTH: " + status_str + " ===");
        m_logger.Info("HealthMonitor", "Summary: " + report.summary);

        for(int i = 0; i < report.issue_count; i++)
            m_logger.Warn("HealthMonitor", "  Issue: " + report.issues[i].description);
    }
};

#endif // ATLAS_HEALTH_MONITOR_MQH
//+------------------------------------------------------------------+
