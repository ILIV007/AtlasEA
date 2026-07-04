//+------------------------------------------------------------------+
//|                       Interfaces/IEventStatistics.mqh           |
//|       AtlasEA v0.1.12.0 - Event Statistics Interface            |
//+------------------------------------------------------------------+
#ifndef ATLAS_IEVENT_STATISTICS_MQH
#define ATLAS_IEVENT_STATISTICS_MQH

#include "../Config/Settings.mqh"

/**
 * @struct EventStats
 * @brief Aggregate event statistics (expanded v0.1.14.0).
 */
struct EventStats
{
    ulong events_generated;     ///< Total events emitted
    ulong events_processed;     ///< Total events dispatched
    ulong events_dropped;       ///< Events dropped (queue overflow)
    ulong priority_events;      ///< Priority queue events
    ulong rejected_events;      ///< Events rejected by dispatcher
    ulong duplicate_events;     ///< Duplicate events detected
    double avg_queue_depth;     ///< Average queue depth
    ulong max_queue_depth;      ///< Maximum queue depth
    ulong per_type_count[13];   ///< Count per ENUM_ATLAS_EVENT_TYPE

    //--- NEW in v0.1.14.0 ---
    double avg_event_size;      ///< Average event size (bytes)
    ulong  largest_event;       ///< Largest event size (bytes)
    ulong  dropped_by_reason[8];///< Dropped events by reason code
    double duplicate_ratio;     ///< duplicate / generated
    double priority_ratio;      ///< priority / generated
    double events_per_second;   ///< Events per second (rolling)
    double peak_events_per_second; ///< Peak EPS
};

/**
 * @class IEventStatistics
 * @brief Interface for tracking event statistics (expanded v0.1.14.0).
 */
class IEventStatistics
{
public:
    virtual void RecordGenerated(const int event_type) = 0;
    virtual void RecordProcessed(const int event_type) = 0;
    virtual void RecordDropped(void) = 0;
    virtual void RecordPriority(void) = 0;
    virtual void RecordRejected(void) = 0;
    virtual void RecordDuplicate(void) = 0;
    virtual void RecordQueueDepth(const int depth) = 0;
    virtual void GetStats(EventStats &out) const = 0;
    virtual void Reset(void) = 0;

    //--- NEW in v0.1.14.0 ---
    virtual void RecordEventSize(const ulong bytes) = 0;
    virtual void RecordDroppedByReason(const int reason_code) = 0;
    virtual void UpdateEventsPerSecond(void) = 0;

    virtual ~IEventStatistics(void) {}
};

#endif // ATLAS_IEVENT_STATISTICS_MQH
//+------------------------------------------------------------------+
