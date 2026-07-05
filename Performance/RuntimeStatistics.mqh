//+------------------------------------------------------------------+
//|                    Performance/RuntimeStatistics.mqh             |
//|       AtlasEA v1.0 Step 8 - Runtime Statistics Tracker            |
//+------------------------------------------------------------------+
#ifndef ATLAS_RUNTIME_STATISTICS_MQH
#define ATLAS_RUNTIME_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum samples for tick duration ring.
 */
#define ATLAS_RT_TICK_SAMPLES 256

/**
 * @struct RuntimeStats
 * @brief Aggregated runtime statistics.
 */
struct RuntimeStats
{
    //--- Tick duration ---
    ulong  total_ticks;
    double avg_tick_ms;         ///< Average tick duration
    double peak_tick_ms;        ///< Peak tick duration
    double p95_tick_ms;         ///< 95th percentile
    double p99_tick_ms;         ///< 99th percentile
    ulong  ticks_over_5ms;      ///< Ticks exceeding 5 ms
    ulong  ticks_over_20ms;     ///< Ticks exceeding 20 ms

    //--- Throughput ---
    ulong  total_events;        ///< Total events processed
    ulong  total_orders;        ///< Total orders sent
    double events_per_sec;      ///< Events/second (rolling)
    double orders_per_min;      ///< Orders/minute (rolling)

    //--- Memory ---
    ulong  current_memory_mb;   ///< Current MQL memory (MB)
    ulong  peak_memory_mb;      ///< Peak MQL memory (MB)
    ulong  initial_memory_mb;   ///< Memory at start
    double memory_growth_pct;   ///< Growth since start

    //--- Timers ---
    datetime start_time;        ///< EA start time
    ulong  uptime_sec;          ///< Total uptime
    ulong  last_tick_time_sec;  ///< Seconds since last tick
    double timer_drift_ms;      ///< Timer drift (observed - expected interval)

    //--- File I/O ---
    ulong  file_opens;          ///< Total FileOpen calls
    ulong  file_writes;         ///< Total FileWriteString calls
    ulong  file_closes;         ///< Total FileClose calls
    ulong  file_errors;         ///< File operation errors

    //--- Queue ---
    int    event_queue_depth;   ///< Current event queue depth
    int    priority_queue_depth;
    int    max_queue_depth;     ///< Peak queue depth

    RuntimeStats(void)
    {
        total_ticks       = 0;
        avg_tick_ms       = 0.0;
        peak_tick_ms      = 0.0;
        p95_tick_ms       = 0.0;
        p99_tick_ms       = 0.0;
        ticks_over_5ms    = 0;
        ticks_over_20ms   = 0;
        total_events      = 0;
        total_orders      = 0;
        events_per_sec    = 0.0;
        orders_per_min    = 0.0;
        current_memory_mb = 0;
        peak_memory_mb    = 0;
        initial_memory_mb = 0;
        memory_growth_pct = 0.0;
        start_time        = 0;
        uptime_sec        = 0;
        last_tick_time_sec = 0;
        timer_drift_ms    = 0.0;
        file_opens        = 0;
        file_writes       = 0;
        file_closes       = 0;
        file_errors       = 0;
        event_queue_depth = 0;
        priority_queue_depth = 0;
        max_queue_depth   = 0;
    }
};

/**
 * @class RuntimeStatistics
 * @brief Tracks runtime statistics for performance monitoring.
 *
 * SOLE RESPONSIBILITY: collect and aggregate runtime stats.
 * Does NOT modify any system behavior.
 *
 * Tracks:
 *   - Tick duration (avg, peak, p95, p99, over-threshold counts)
 *   - Event/order throughput
 *   - Memory usage (current, peak, growth)
 *   - Timer drift
 *   - File I/O counts
 *   - Queue depths
 *
 * Performance: O(1) per RecordTick(). No allocation.
 * Memory: ~4 KB (256-sample ring + stats struct).
 */
class RuntimeStatistics
{
private:
    ILogger *m_logger;

    //--- Tick duration ring (for percentile calculation)
    double m_tick_samples[ATLAS_RT_TICK_SAMPLES];
    int    m_tick_sample_count;
    int    m_tick_sample_next;
    double m_tick_sum;          ///< Running sum for average
    double m_tick_peak;         ///< Peak tick duration

    //--- Rolling throughput (1-minute window)
    datetime m_throughput_minute_start;
    ulong    m_events_this_minute;
    ulong    m_orders_this_minute;

    //--- Memory tracking
    ulong m_initial_memory_mb;
    ulong m_peak_memory_mb;
    datetime m_start_time;
    datetime m_last_tick_time;

    //--- File I/O counters
    ulong m_file_opens;
    ulong m_file_writes;
    ulong m_file_closes;
    ulong m_file_errors;

    //--- Queue tracking
    int m_max_queue_depth;

    //--- Timer drift
    datetime m_expected_timer_time;
    int m_timer_interval_sec;

    //--- Stats
    RuntimeStats m_stats;

public:
    RuntimeStatistics(void)
    {
        m_logger                = NULL;
        m_tick_sample_count     = 0;
        m_tick_sample_next      = 0;
        m_tick_sum              = 0.0;
        m_tick_peak             = 0.0;
        m_throughput_minute_start = 0;
        m_events_this_minute    = 0;
        m_orders_this_minute    = 0;
        m_initial_memory_mb     = 0;
        m_peak_memory_mb        = 0;
        m_start_time            = 0;
        m_last_tick_time        = 0;
        m_file_opens            = 0;
        m_file_writes           = 0;
        m_file_closes           = 0;
        m_file_errors           = 0;
        m_max_queue_depth       = 0;
        m_expected_timer_time   = 0;
        m_timer_interval_sec    = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Initialize runtime statistics.
     */
    void Initialize(const int timer_interval_sec)
    {
        m_start_time        = TimeCurrent();
        m_last_tick_time    = m_start_time;
        m_timer_interval_sec = timer_interval_sec;
        m_expected_timer_time = m_start_time + timer_interval_sec;
        m_initial_memory_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);
        m_peak_memory_mb    = m_initial_memory_mb;
        m_stats.initial_memory_mb = m_initial_memory_mb;
        m_stats.start_time  = m_start_time;
    }

    /**
     * @brief Record a tick's duration.
     * @param tick_ms Tick duration in milliseconds.
     */
    void RecordTick(const double tick_ms)
    {
        m_stats.total_ticks++;
        m_tick_sum += tick_ms;
        if(tick_ms > m_tick_peak) m_tick_peak = tick_ms;

        //--- Ring buffer
        m_tick_samples[m_tick_sample_next] = tick_ms;
        m_tick_sample_next = (m_tick_sample_next + 1) % ATLAS_RT_TICK_SAMPLES;
        if(m_tick_sample_count < ATLAS_RT_TICK_SAMPLES) m_tick_sample_count++;

        //--- Average
        m_stats.avg_tick_ms = m_tick_sum / (double)m_stats.total_ticks;
        m_stats.peak_tick_ms = m_tick_peak;

        //--- Over-threshold counts
        if(tick_ms > 5.0)  m_stats.ticks_over_5ms++;
        if(tick_ms > 20.0) m_stats.ticks_over_20ms++;

        m_last_tick_time = TimeCurrent();
    }

    /**
     * @brief Record events processed.
     */
    void RecordEvents(const int count)
    {
        m_stats.total_events += count;
        m_events_this_minute += count;
    }

    /**
     * @brief Record an order sent.
     */
    void RecordOrder(void)
    {
        m_stats.total_orders++;
        m_orders_this_minute++;
    }

    /**
     * @brief Record a file operation.
     */
    void RecordFileOpen(void)  { m_file_opens++;  m_stats.file_opens++; }
    void RecordFileWrite(void) { m_file_writes++; m_stats.file_writes++; }
    void RecordFileClose(void) { m_file_closes++; m_stats.file_closes++; }
    void RecordFileError(void) { m_file_errors++; m_stats.file_errors++; }

    /**
     * @brief Record queue depths.
     */
    void RecordQueueDepth(const int event_depth, const int priority_depth)
    {
        m_stats.event_queue_depth    = event_depth;
        m_stats.priority_queue_depth = priority_depth;
        int total = event_depth + priority_depth;
        if(total > m_max_queue_depth) m_max_queue_depth = total;
        m_stats.max_queue_depth = m_max_queue_depth;
    }

    /**
     * @brief Record timer fire (for drift calculation).
     */
    void RecordTimer(void)
    {
        if(m_expected_timer_time > 0 && m_timer_interval_sec > 0)
        {
            long drift = (long)TimeCurrent() - (long)m_expected_timer_time;
            m_stats.timer_drift_ms = (double)drift * 1000.0;
        }
        m_expected_timer_time = TimeCurrent() + m_timer_interval_sec;
    }

    /**
     * @brief Update memory stats (called on heartbeat).
     */
    void UpdateMemory(void)
    {
        m_stats.current_memory_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);
        if(m_stats.current_memory_mb > m_peak_memory_mb)
            m_peak_memory_mb = m_stats.current_memory_mb;
        m_stats.peak_memory_mb = m_peak_memory_mb;
        if(m_initial_memory_mb > 0)
            m_stats.memory_growth_pct =
                ((double)m_stats.current_memory_mb - (double)m_initial_memory_mb) /
                (double)m_initial_memory_mb * 100.0;
    }

    /**
     * @brief Update rolling throughput (called on heartbeat).
     */
    void UpdateThroughput(void)
    {
        datetime now = TimeCurrent();
        long minute_elapsed = (long)now - (long)m_throughput_minute_start;
        if(minute_elapsed >= 60)
        {
            m_stats.orders_per_min = (double)m_orders_this_minute;
            m_stats.events_per_sec = (double)m_events_this_minute / 60.0;
            m_throughput_minute_start = now;
            m_events_this_minute = 0;
            m_orders_this_minute = 0;
        }
    }

    /**
     * @brief Compute percentiles from the tick sample ring.
     */
    void ComputePercentiles(void)
    {
        if(m_tick_sample_count <= 0) return;

        //--- Copy and sort (simple insertion sort, sample size is small)
        double sorted[ATLAS_RT_TICK_SAMPLES];
        for(int i = 0; i < m_tick_sample_count; i++)
            sorted[i] = m_tick_samples[i];

        for(int i = 1; i < m_tick_sample_count; i++)
        {
            double key = sorted[i];
            int j = i - 1;
            while(j >= 0 && sorted[j] > key)
            {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = key;
        }

        int p95_idx = (int)(m_tick_sample_count * 0.95);
        int p99_idx = (int)(m_tick_sample_count * 0.99);
        if(p95_idx >= m_tick_sample_count) p95_idx = m_tick_sample_count - 1;
        if(p99_idx >= m_tick_sample_count) p99_idx = m_tick_sample_count - 1;

        m_stats.p95_tick_ms = sorted[p95_idx];
        m_stats.p99_tick_ms = sorted[p99_idx];
    }

    /**
     * @brief Get the current runtime stats.
     */
    RuntimeStats GetStats(void)
    {
        m_stats.uptime_sec = (m_start_time > 0)
            ? (ulong)((long)TimeCurrent() - (long)m_start_time) : 0;
        m_stats.last_tick_time_sec = (m_last_tick_time > 0)
            ? (ulong)((long)TimeCurrent() - (long)m_last_tick_time) : 0;
        ComputePercentiles();
        return m_stats;
    }

    /**
     * @brief Reset all statistics (daily reset).
     */
    void ResetDaily(void)
    {
        m_tick_sum          = 0.0;
        m_tick_peak         = 0.0;
        m_tick_sample_count = 0;
        m_tick_sample_next  = 0;
        m_stats.total_ticks = 0;
        m_stats.ticks_over_5ms  = 0;
        m_stats.ticks_over_20ms = 0;
        m_file_opens  = 0;
        m_file_writes = 0;
        m_file_closes = 0;
        m_file_errors = 0;
        m_max_queue_depth = 0;
    }

    /**
     * @brief Log the current statistics.
     */
    void LogStats(void)
    {
        if(m_logger == NULL) return;
        RuntimeStats s = GetStats();
        m_logger.Info("RuntimeStatistics",
            "Ticks=" + IntegerToString((long)s.total_ticks) +
            " Avg=" + DoubleToString(s.avg_tick_ms, 2) + "ms" +
            " Peak=" + DoubleToString(s.peak_tick_ms, 2) + "ms" +
            " P95=" + DoubleToString(s.p95_tick_ms, 2) + "ms" +
            " P99=" + DoubleToString(s.p99_tick_ms, 2) + "ms" +
            " >5ms=" + IntegerToString((long)s.ticks_over_5ms) +
            " >20ms=" + IntegerToString((long)s.ticks_over_20ms));
        m_logger.Info("RuntimeStatistics",
            "Memory: current=" + IntegerToString((long)s.current_memory_mb) + "MB" +
            " peak=" + IntegerToString((long)s.peak_memory_mb) + "MB" +
            " growth=" + DoubleToString(s.memory_growth_pct, 1) + "%" +
            " Uptime=" + IntegerToString((long)s.uptime_sec) + "s" +
            " Drift=" + DoubleToString(s.timer_drift_ms, 0) + "ms" +
            " QueueMax=" + IntegerToString(s.max_queue_depth) +
            " FileOps: O=" + IntegerToString((long)s.file_opens) +
            " W=" + IntegerToString((long)s.file_writes) +
            " C=" + IntegerToString((long)s.file_closes));
    }
};

#endif // ATLAS_RUNTIME_STATISTICS_MQH
//+------------------------------------------------------------------+
