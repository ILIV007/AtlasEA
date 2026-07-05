//+------------------------------------------------------------------+
//|                    Performance/ResourceMonitor.mqh               |
//|       AtlasEA v1.0 Step 8 - Resource Monitor                      |
//+------------------------------------------------------------------+
#ifndef ATLAS_RESOURCE_MONITOR_MQH
#define ATLAS_RESOURCE_MONITOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/ICacheManager.mqh"
#include "RuntimeStatistics.mqh"
#include "CacheManager.mqh"

/**
 * @brief Resource health status codes.
 */
#define ATLAS_RES_OK            0
#define ATLAS_RES_WARNING       1   ///< Approaching limits
#define ATLAS_RES_CRITICAL      2   ///< Exceeding limits
#define ATLAS_RES_UNKNOWN       3

/**
 * @struct ResourceSnapshot
 * @brief Point-in-time resource snapshot.
 */
struct ResourceSnapshot
{
    int    status;              ///< ATLAS_RES_*
    string status_name;         ///< Human-readable

    //--- CPU / tick performance ---
    double avg_tick_ms;         ///< Average tick duration
    double peak_tick_ms;        ///< Peak tick duration
    double p95_tick_ms;         ///< 95th percentile
    ulong  ticks_over_5ms;      ///< Ticks over 5 ms
    ulong  ticks_over_20ms;     ///< Ticks over 20 ms

    //--- Memory ---
    ulong  current_memory_mb;   ///< Current MQL memory
    ulong  peak_memory_mb;      ///< Peak memory
    double memory_growth_pct;   ///< Growth since start

    //--- Cache ---
    double cache_hit_ratio;     ///< Overall cache hit ratio
    int    cache_valid_count;   ///< Valid cache entries
    int    cache_total_count;   ///< Total cache entries

    //--- Queues ---
    int    event_queue_depth;   ///< Current event queue depth
    int    max_queue_depth;     ///< Peak queue depth

    //--- File I/O ---
    ulong  file_opens;          ///< Total file opens
    ulong  file_errors;         ///< File errors

    //--- Throughput ---
    double events_per_sec;      ///< Events per second
    double orders_per_min;      ///< Orders per minute

    //--- Uptime ---
    ulong  uptime_sec;          ///< Total uptime
    double timer_drift_ms;      ///< Timer drift

    datetime timestamp;         ///< Snapshot time

    ResourceSnapshot(void)
    {
        status            = ATLAS_RES_OK;
        status_name       = "OK";
        avg_tick_ms       = 0.0;
        peak_tick_ms      = 0.0;
        p95_tick_ms       = 0.0;
        ticks_over_5ms    = 0;
        ticks_over_20ms   = 0;
        current_memory_mb = 0;
        peak_memory_mb    = 0;
        memory_growth_pct = 0.0;
        cache_hit_ratio   = 0.0;
        cache_valid_count = 0;
        cache_total_count = 0;
        event_queue_depth = 0;
        max_queue_depth   = 0;
        file_opens        = 0;
        file_errors       = 0;
        events_per_sec    = 0.0;
        orders_per_min    = 0.0;
        uptime_sec        = 0;
        timer_drift_ms    = 0.0;
        timestamp         = 0;
    }
};

/**
 * @class ResourceMonitor
 * @brief Continuously monitors CPU, memory, cache, queues, and file I/O.
 *
 * SOLE RESPONSIBILITY: collect resource metrics and assess health.
 * Does NOT modify any system behavior.
 *
 * Monitors:
 *   - CPU: tick duration (avg, peak, p95, over-threshold counts)
 *   - Memory: current, peak, growth %
 *   - Cache: hit ratio, valid count
 *   - Queues: depth, peak
 *   - File I/O: opens, writes, errors
 *   - Throughput: events/sec, orders/min
 *   - Timer drift
 *
 * Status assessment:
 *   OK: all metrics within targets
 *   WARNING: any metric approaching limits
 *   CRITICAL: any metric exceeding limits
 *
 * Targets:
 *   Avg tick < 5 ms, Peak < 20 ms
 *   Memory growth < 50%
 *   Cache hit ratio > 50%
 *   No file errors
 *   Queue depth < 400 (of 512)
 *   Timer drift < 5000 ms
 *
 * Performance: O(1) per snapshot. No allocation.
 */
class ResourceMonitor
{
private:
    ILogger            *m_logger;
    RuntimeStatistics  *m_runtime_stats;
    CacheManager       *m_cache;

    //--- Targets
    double m_target_avg_tick_ms;
    double m_target_peak_tick_ms;
    double m_target_memory_growth_pct;
    double m_target_cache_hit_ratio;
    int    m_target_max_queue_depth;
    double m_target_timer_drift_ms;

public:
    ResourceMonitor(void)
    {
        m_logger                   = NULL;
        m_runtime_stats            = NULL;
        m_cache                    = NULL;
        m_target_avg_tick_ms       = 5.0;
        m_target_peak_tick_ms      = 20.0;
        m_target_memory_growth_pct = 50.0;
        m_target_cache_hit_ratio   = 0.50;
        m_target_max_queue_depth   = 400;
        m_target_timer_drift_ms    = 5000.0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }
    void SetRuntimeStats(RuntimeStatistics *stats) { m_runtime_stats = stats; }
    void SetCacheManager(CacheManager *cache) { m_cache = cache; }

    /**
     * @brief Set monitoring targets.
     */
    void SetTargets(const double avg_tick, const double peak_tick,
                    const double mem_growth, const double cache_ratio,
                    const int max_queue, const double drift)
    {
        m_target_avg_tick_ms       = avg_tick;
        m_target_peak_tick_ms      = peak_tick;
        m_target_memory_growth_pct = mem_growth;
        m_target_cache_hit_ratio   = cache_ratio;
        m_target_max_queue_depth   = max_queue;
        m_target_timer_drift_ms    = drift;
    }

    /**
     * @brief Take a resource snapshot.
     * Called on heartbeat (timer).
     * @return ResourceSnapshot with current metrics and status.
     */
    ResourceSnapshot Snapshot(void)
    {
        ResourceSnapshot snap;
        snap.timestamp = TimeCurrent();

        if(m_runtime_stats != NULL)
        {
            RuntimeStats rs = m_runtime_stats.GetStats();
            snap.avg_tick_ms       = rs.avg_tick_ms;
            snap.peak_tick_ms      = rs.peak_tick_ms;
            snap.p95_tick_ms       = rs.p95_tick_ms;
            snap.ticks_over_5ms    = rs.ticks_over_5ms;
            snap.ticks_over_20ms   = rs.ticks_over_20ms;
            snap.current_memory_mb = rs.current_memory_mb;
            snap.peak_memory_mb    = rs.peak_memory_mb;
            snap.memory_growth_pct = rs.memory_growth_pct;
            snap.event_queue_depth = rs.event_queue_depth;
            snap.max_queue_depth   = rs.max_queue_depth;
            snap.file_opens        = rs.file_opens;
            snap.file_errors       = rs.file_errors;
            snap.events_per_sec    = rs.events_per_sec;
            snap.orders_per_min    = rs.orders_per_min;
            snap.uptime_sec        = rs.uptime_sec;
            snap.timer_drift_ms    = rs.timer_drift_ms;
        }

        if(m_cache != NULL)
        {
            CacheStats cs = m_cache.GetStats();
            snap.cache_hit_ratio   = cs.OverallHitRatio();
            snap.cache_valid_count = cs.valid_count;
            snap.cache_total_count = ATLAS_CACHE_COUNT;
        }

        //--- Assess status
        snap.status = AssessStatus(snap);
        snap.status_name = ResourceStatusName(snap.status);

        return snap;
    }

    /**
     * @brief Log the resource snapshot.
     */
    void LogSnapshot(const ResourceSnapshot &snap) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("ResourceMonitor",
            "Status: " + snap.status_name +
            " Tick: avg=" + DoubleToString(snap.avg_tick_ms, 2) + "ms" +
            " peak=" + DoubleToString(snap.peak_tick_ms, 2) + "ms" +
            " p95=" + DoubleToString(snap.p95_tick_ms, 2) + "ms" +
            " Mem: " + IntegerToString((long)snap.current_memory_mb) + "MB" +
            " growth=" + DoubleToString(snap.memory_growth_pct, 1) + "%" +
            " Cache: " + DoubleToString(snap.cache_hit_ratio * 100.0, 1) + "%" +
            " Queue: " + IntegerToString(snap.event_queue_depth) +
            " Drift: " + DoubleToString(snap.timer_drift_ms, 0) + "ms");
    }

private:
    int AssessStatus(const ResourceSnapshot &snap) const
    {
        bool warning  = false;
        bool critical = false;

        //--- Tick duration
        if(snap.avg_tick_ms > m_target_avg_tick_ms) warning = true;
        if(snap.peak_tick_ms > m_target_peak_tick_ms) warning = true;
        if(snap.peak_tick_ms > m_target_peak_tick_ms * 2.0) critical = true;

        //--- Memory growth
        if(snap.memory_growth_pct > m_target_memory_growth_pct) warning = true;
        if(snap.memory_growth_pct > m_target_memory_growth_pct * 2.0) critical = true;

        //--- Cache hit ratio
        if(snap.cache_hit_ratio < m_target_cache_hit_ratio &&
           snap.cache_total_count > 0) warning = true;

        //--- Queue depth
        if(snap.event_queue_depth > m_target_max_queue_depth) warning = true;
        if(snap.event_queue_depth > m_target_max_queue_depth * 2) critical = true;

        //--- File errors
        if(snap.file_errors > 0) warning = true;
        if(snap.file_errors > 10) critical = true;

        //--- Timer drift
        if(snap.timer_drift_ms > m_target_timer_drift_ms) warning = true;

        if(critical) return ATLAS_RES_CRITICAL;
        if(warning)  return ATLAS_RES_WARNING;
        return ATLAS_RES_OK;
    }

    static string ResourceStatusName(const int status)
    {
        switch(status)
        {
            case ATLAS_RES_OK:        return "OK";
            case ATLAS_RES_WARNING:   return "WARNING";
            case ATLAS_RES_CRITICAL:  return "CRITICAL";
            case ATLAS_RES_UNKNOWN:   return "UNKNOWN";
        }
        return "UNKNOWN";
    }
};

#endif // ATLAS_RESOURCE_MONITOR_MQH
//+------------------------------------------------------------------+
