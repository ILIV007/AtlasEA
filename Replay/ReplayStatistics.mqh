//+------------------------------------------------------------------+
//|                   Replay/ReplayStatistics.mqh                   |
//|       AtlasEA v0.1.23.0 - Replay Statistics Collector           |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_STATISTICS_MQH
#define ATLAS_REPLAY_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IReplayStatistics.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class ReplayStatistics
 * @brief Concrete implementation of IReplayStatistics.
 *
 * Collects:
 *   - Events replayed
 *   - Events skipped
 *   - Replay duration
 *   - Average replay speed (events/sec)
 *   - Maximum replay latency (ms)
 *   - Synchronization drift (ms)
 *   - Progress percentage
 */
class ReplayStatistics : public IReplayStatistics
{
private:
    ReplayStats m_stats;
    ulong       m_start_ms;
    ILogger    *m_logger;

public:
    /**
     * @brief Constructor.
     */
    ReplayStatistics(void)
    {
        m_logger   = NULL;
        m_start_ms = 0;
        Reset();
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Start the statistics timer.
     */
    void Start(void)
    {
        m_start_ms = GetTickCount64();
    }

    //=== IReplayStatistics implementation ===

    virtual void RecordEvent(const double latency_ms) override
    {
        m_stats.events_replayed++;
        if(latency_ms > m_stats.max_replay_latency_ms)
            m_stats.max_replay_latency_ms = latency_ms;
        UpdateProgress();
    }

    virtual void RecordSkip(void) override
    {
        m_stats.events_skipped++;
    }

    virtual void RecordDrift(const double drift_ms) override
    {
        m_stats.sync_drift_ms = drift_ms;
    }

    virtual void SetTotal(const long total) override
    {
        m_stats.total_loaded = total;
    }

    virtual void UpdateProgress(void) override
    {
        if(m_stats.total_loaded > 0)
        {
            m_stats.progress_pct = (double)m_stats.events_replayed /
                                   (double)m_stats.total_loaded * 100.0;
        }

        //--- Update duration
        if(m_start_ms > 0)
        {
            m_stats.replay_duration_ms = (double)(GetTickCount64() - m_start_ms);
        }

        //--- Update average speed
        if(m_stats.replay_duration_ms > 0.0)
        {
            m_stats.avg_replay_speed = (double)m_stats.events_replayed /
                                       (m_stats.replay_duration_ms / 1000.0);
        }
    }

    virtual ReplayStats GetStats(void) const override
    {
        return m_stats;
    }

    virtual void Reset(void) override
    {
        m_stats.events_replayed       = 0;
        m_stats.events_skipped        = 0;
        m_stats.replay_duration_ms    = 0.0;
        m_stats.avg_replay_speed      = 0.0;
        m_stats.max_replay_latency_ms = 0.0;
        m_stats.sync_drift_ms         = 0.0;
        m_stats.total_loaded          = 0;
        m_stats.progress_pct          = 0.0;
        m_start_ms                    = 0;
    }

    /**
     * @brief Log the statistics.
     */
    void LogStats(void) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("ReplayStatistics",
            "replayed=" + IntegerToString((long)m_stats.events_replayed) +
            " skipped=" + IntegerToString((long)m_stats.events_skipped) +
            " duration=" + DoubleToString(m_stats.replay_duration_ms, 1) + "ms" +
            " speed=" + DoubleToString(m_stats.avg_replay_speed, 1) + " ev/s" +
            " max_latency=" + DoubleToString(m_stats.max_replay_latency_ms, 3) + "ms" +
            " drift=" + DoubleToString(m_stats.sync_drift_ms, 1) + "ms" +
            " progress=" + DoubleToString(m_stats.progress_pct, 1) + "%");
    }
};

#endif // ATLAS_REPLAY_STATISTICS_MQH
//+------------------------------------------------------------------+
