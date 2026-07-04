//+------------------------------------------------------------------+
//|                 Interfaces/IReplayStatistics.mqh                |
//|       AtlasEA v0.1.23.0 - Replay Statistics Interface           |
//+------------------------------------------------------------------+
#ifndef ATLAS_IREPLAY_STATISTICS_MQH
#define ATLAS_IREPLAY_STATISTICS_MQH

#include "../Config/Settings.mqh"

/**
 * @struct ReplayStats
 * @brief Collected statistics from a replay session.
 */
struct ReplayStats
{
    long   events_replayed;       ///< Total events replayed
    long   events_skipped;        ///< Events skipped (filtered)
    double replay_duration_ms;    ///< Wall-clock duration of replay
    double avg_replay_speed;      ///< Average replay speed (events/sec)
    double max_replay_latency_ms; ///< Maximum single-event latency
    double sync_drift_ms;         ///< Synchronization drift (virtual vs real time)
    long   total_loaded;          ///< Total events loaded
    double progress_pct;          ///< Progress percentage (0..100)
};

/**
 * @class IReplayStatistics
 * @brief Interface for collecting replay statistics.
 */
class IReplayStatistics
{
public:
    virtual void RecordEvent(const double latency_ms) = 0;
    virtual void RecordSkip(void) = 0;
    virtual void RecordDrift(const double drift_ms) = 0;
    virtual void SetTotal(const long total) = 0;
    virtual void UpdateProgress(void) = 0;
    virtual ReplayStats GetStats(void) const = 0;
    virtual void Reset(void) = 0;

    virtual ~IReplayStatistics(void) {}
};

#endif // ATLAS_IREPLAY_STATISTICS_MQH
//+------------------------------------------------------------------+
