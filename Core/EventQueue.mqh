//+------------------------------------------------------------------+
//|                                            Core/EventQueue.mqh
//|              AtlasEA v2.0 - Dual-Queue Event Queue                |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_QUEUE_MQH
#define ATLAS_EVENT_QUEUE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"
#include "RingBuffer.mqh"

/**
 * @class EventQueue
 * @brief Composes a normal ring buffer and a priority ring buffer.
 *
 * Priority events (fills, kill-switch, errors) are always drained before
 * normal events. This ensures risk-critical updates are processed first.
 *
 * Overflow handling:
 *   - If the priority buffer overflows, the event falls back to the normal buffer.
 *   - If the normal buffer overflows, the event is dropped and counted.
 *
 * Statistics: tracks enqueue/dequeue/drop counts for both queues,
 * plus peak depth and current utilization.
 *
 * Memory: two fixed-size RingBuffer instances (stack-allocated). Zero
 * dynamic allocation on the hot path.
 */
class EventQueue
{
private:
    RingBuffer m_normal;     ///< Normal-priority queue
    RingBuffer m_priority;   ///< High-priority queue
    ILogger   *m_logger;     ///< Logger (may be NULL)

    /// Lifetime total events dropped (both queues combined)
    ulong m_total_dropped;

public:
    /**
     * @brief Constructor — initializes both ring buffers.
     */
    EventQueue(void);

    /**
     * @brief Initialize the queue with a logger and capacities.
     * @param logger          Logger for overflow warnings.
     * @param normal_cap      Capacity for the normal queue.
     * @param priority_cap    Capacity for the priority queue.
     */
    void Initialize(ILogger *logger, const int normal_cap, const int priority_cap);

    /**
     * @brief Enqueue a normal-priority event.
     * @param event The event to enqueue.
     * @return true if enqueued, false if dropped.
     */
    bool Enqueue(const AtlasEvent &event);

    /**
     * @brief Enqueue a high-priority event.
     * If the priority buffer is full, falls back to the normal buffer.
     * @param event The event to enqueue.
     * @return true if enqueued (in either queue), false if both full.
     */
    bool EnqueuePriority(const AtlasEvent &event);

    /**
     * @brief Dequeue the next event (priority first, then normal).
     * @param event Output: the dequeued event.
     * @return true if an event was dequeued, false if both empty.
     */
    bool Dequeue(AtlasEvent &event);

    /**
     * @brief Peek at the next event without removing it.
     * @param event Output: a copy of the next event.
     * @return true if an event was available, false if both empty.
     */
    bool Peek(AtlasEvent &event) const;

    /// @brief Total events currently in both queues.
    int  TotalCount(void) const { return m_normal.Count() + m_priority.Count(); }

    /// @brief Events in the normal queue.
    int  NormalCount(void) const { return m_normal.Count(); }

    /// @brief Events in the priority queue.
    int  PriorityCount(void) const { return m_priority.Count(); }

    /// @brief true if both queues are empty.
    bool IsEmpty(void) const { return m_normal.IsEmpty() && m_priority.IsEmpty(); }

    /// @brief Lifetime total events dropped.
    ulong TotalDropped(void) const { return m_total_dropped; }

    /// @brief Normal queue lifetime enqueued count.
    ulong NormalEnqueued(void) const { return m_normal.TotalEnqueued(); }

    /// @brief Priority queue lifetime enqueued count.
    ulong PriorityEnqueued(void) const { return m_priority.TotalEnqueued(); }

    /// @brief Normal queue peak depth.
    ulong NormalPeakDepth(void) const { return m_normal.PeakDepth(); }

    /// @brief Priority queue peak depth.
    ulong PriorityPeakDepth(void) const { return m_priority.PeakDepth(); }

    /// @brief Normal queue current utilization [0.0, 1.0].
    double NormalUtilization(void) const { return m_normal.Utilization(); }

    /// @brief Priority queue current utilization [0.0, 1.0].
    double PriorityUtilization(void) const { return m_priority.Utilization(); }

    /// @brief Reset all statistics (not the buffers themselves).
    void ResetStats(void);
};

//+------------------------------------------------------------------+
//| EventQueue implementation                                        |
//+------------------------------------------------------------------+

EventQueue::EventQueue(void)
{
    m_logger       = NULL;
    m_total_dropped = 0;
}

//+------------------------------------------------------------------+
void EventQueue::Initialize(ILogger *logger, const int normal_cap, const int priority_cap)
{
    m_logger = logger;
    m_normal.Reset(normal_cap, logger);
    m_priority.Reset(priority_cap, logger);
    m_total_dropped = 0;
}

//+------------------------------------------------------------------+
bool EventQueue::Enqueue(const AtlasEvent &event)
{
    bool ok = m_normal.Enqueue(event);
    if(!ok)
    {
        m_total_dropped++;
        if(m_logger != NULL)
            m_logger.Error("EventQueue", "Normal queue overflow. event_type=" + IntegerToString((int)event.type));
    }
    return ok;
}

//+------------------------------------------------------------------+
bool EventQueue::EnqueuePriority(const AtlasEvent &event)
{
    //--- Try priority buffer first
    if(!m_priority.IsFull())
        return m_priority.Enqueue(event);

    //--- Fallback to normal buffer
    if(m_logger != NULL)
        m_logger.Warn("EventQueue", "Priority buffer full, falling back to normal queue");
    bool ok = m_normal.Enqueue(event);
    if(!ok)
    {
        m_total_dropped++;
        if(m_logger != NULL)
            m_logger.Error("EventQueue", "Both queues full! Event dropped. type=" + IntegerToString((int)event.type));
    }
    return ok;
}

//+------------------------------------------------------------------+
bool EventQueue::Dequeue(AtlasEvent &event)
{
    //--- Priority first
    if(!m_priority.IsEmpty())
        return m_priority.Dequeue(event);

    //--- Then normal
    return m_normal.Dequeue(event);
}

//+------------------------------------------------------------------+
bool EventQueue::Peek(AtlasEvent &event) const
{
    if(!m_priority.IsEmpty())
        return m_priority.Peek(event);
    return m_normal.Peek(event);
}

//+------------------------------------------------------------------+
void EventQueue::ResetStats(void)
{
    m_total_dropped = 0;
}

#endif // ATLAS_EVENT_QUEUE_MQH
//+------------------------------------------------------------------+
