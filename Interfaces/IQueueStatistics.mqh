//+------------------------------------------------------------------+
//|                       Interfaces/IQueueStatistics.mqh           |
//|       AtlasEA v0.1.12.0 - Queue Statistics Interface             |
//+------------------------------------------------------------------+
#ifndef ATLAS_IQUEUE_STATISTICS_MQH
#define ATLAS_IQUEUE_STATISTICS_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Queue identifiers.
 */
#define ATLAS_QUEUE_NORMAL    0
#define ATLAS_QUEUE_PRIORITY  1
#define ATLAS_QUEUE_COUNT     2

/**
 * @struct QueueStats
 * @brief Statistics for one queue.
 */
struct QueueStats
{
    int    current_count;       ///< Current items in queue
    int    peak_count;          ///< Peak items observed
    ulong  drop_count;          ///< Total dropped (overflow)
    ulong  overflow_count;      ///< Total overflow events
    double avg_wait_time_ms;    ///< Average time in queue
    ulong  total_enqueued;      ///< Lifetime enqueued
    ulong  total_dequeued;      ///< Lifetime dequeued
};

/**
 * @class IQueueStatistics
 * @brief Interface for tracking queue statistics.
 */
class IQueueStatistics
{
public:
    virtual void RecordEnqueue(const int queue_id) = 0;
    virtual void RecordDequeue(const int queue_id, const double wait_ms) = 0;
    virtual void RecordDrop(const int queue_id) = 0;
    virtual void RecordOverflow(const int queue_id) = 0;
    virtual void UpdateDepth(const int queue_id, const int depth) = 0;
    virtual void GetStats(const int queue_id, QueueStats &out) const = 0;
    virtual void Reset(const int queue_id) = 0;
    virtual void ResetAll(void) = 0;

    virtual ~IQueueStatistics(void) {}
};

#endif // ATLAS_IQUEUE_STATISTICS_MQH
//+------------------------------------------------------------------+
