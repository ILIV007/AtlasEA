//+------------------------------------------------------------------+
//|                                             Core/RingBuffer.mqh
//|               AtlasEA v2.0 - Lock-Free Ring Buffer (single-thread)|
//+------------------------------------------------------------------+
#ifndef ATLAS_RING_BUFFER_MQH
#define ATLAS_RING_BUFFER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class RingBuffer
 * @brief Fixed-capacity FIFO ring buffer for AtlasEvent.
 *
 * Lock-free by design: MQL5 EAs are single-threaded per chart, so no
 * atomics or memory barriers are needed.
 *
 * Memory: the buffer is a fixed-size stack array — zero dynamic allocation.
 * Overflow policy: on Enqueue when full, the event is dropped and the
 * dropped counter is incremented. The caller (EventQueue) decides whether
 * to escalate.
 *
 * Cache-friendly: contiguous array, sequential access pattern.
 */
class RingBuffer
{
private:
    AtlasEvent m_buffer[ATLAS_EVENT_QUEUE_SIZE];  ///< Fixed storage
    int        m_head;                              ///< Next write slot
    int        m_tail;                              ///< Next read slot
    int        m_count;                             ///< Current element count
    int        m_capacity;                          ///< Usable capacity
    ulong      m_total_enqueued;                    ///< Lifetime enqueue count
    ulong      m_total_dequeued;                    ///< Lifetime dequeue count
    ulong      m_total_dropped;                     ///< Lifetime drop count
    ulong      m_peak_depth;                        ///< Peak occupancy
    ILogger   *m_logger;                            ///< Logger (may be NULL)

public:
    /**
     * @brief Constructor — initializes an empty buffer with default capacity.
     */
    RingBuffer(void);

    /**
     * @brief Reset the buffer to empty state with a given capacity.
     * @param capacity Maximum elements (clamped to ATLAS_EVENT_QUEUE_SIZE).
     * @param logger   Optional logger for overflow warnings (may be NULL).
     */
    void Reset(const int capacity, ILogger *logger = NULL);

    /**
     * @brief Enqueue an event. If full, the event is dropped.
     * @param event Const reference to the event to enqueue.
     * @return true if enqueued, false if dropped (buffer full).
     */
    bool Enqueue(const AtlasEvent &event);

    /**
     * @brief Dequeue the oldest event.
     * @param event Output: the dequeued event.
     * @return true if an event was dequeued, false if empty.
     */
    bool Dequeue(AtlasEvent &event);

    /**
     * @brief Peek at the oldest event without removing it.
     * @param event Output: a copy of the oldest event.
     * @return true if an event was available, false if empty.
     */
    bool Peek(AtlasEvent &event) const;

    /// @brief Current number of elements in the buffer.
    int    Count(void)        const { return m_count; }

    /// @brief true if the buffer is empty.
    bool   IsEmpty(void)      const { return m_count == 0; }

    /// @brief true if the buffer is at capacity.
    bool   IsFull(void)       const { return m_count >= m_capacity; }

    /// @brief Remaining free slots.
    int    FreeSlots(void)    const { return m_capacity - m_count; }

    /// @brief Lifetime total events enqueued.
    ulong  TotalEnqueued(void) const { return m_total_enqueued; }

    /// @brief Lifetime total events dequeued.
    ulong  TotalDequeued(void) const { return m_total_dequeued; }

    /// @brief Lifetime total events dropped due to overflow.
    ulong  TotalDropped(void)  const { return m_total_dropped; }

    /// @brief Peak occupancy ever observed.
    ulong  PeakDepth(void)     const { return m_peak_depth; }

    /// @brief Current utilization as a fraction [0.0, 1.0].
    double Utilization(void)   const { return (m_capacity > 0) ? (double)m_count / (double)m_capacity : 0.0; }
};

//+------------------------------------------------------------------+
//| RingBuffer implementation                                        |
//+------------------------------------------------------------------+

RingBuffer::RingBuffer(void)
{
    m_head           = 0;
    m_tail           = 0;
    m_count          = 0;
    m_capacity       = ATLAS_EVENT_QUEUE_SIZE;
    m_total_enqueued = 0;
    m_total_dequeued = 0;
    m_total_dropped  = 0;
    m_peak_depth     = 0;
    m_logger         = NULL;
}

//+------------------------------------------------------------------+
void RingBuffer::Reset(const int capacity, ILogger *logger)
{
    m_capacity = capacity;
    if(m_capacity > ATLAS_EVENT_QUEUE_SIZE) m_capacity = ATLAS_EVENT_QUEUE_SIZE;
    if(m_capacity < 1) m_capacity = 1;

    m_head           = 0;
    m_tail           = 0;
    m_count          = 0;
    m_total_enqueued = 0;
    m_total_dequeued = 0;
    m_total_dropped  = 0;
    m_peak_depth     = 0;
    m_logger         = logger;
}

//+------------------------------------------------------------------+
bool RingBuffer::Enqueue(const AtlasEvent &event)
{
    if(IsFull())
    {
        m_total_dropped++;
        if(m_logger != NULL)
            m_logger.Warn("RingBuffer", "Overflow: event dropped. total_dropped=" + IntegerToString((long)m_total_dropped));
        return false;
    }

    m_buffer[m_head] = event;
    m_head = (m_head + 1) % m_capacity;
    m_count++;
    m_total_enqueued++;

    if((ulong)m_count > m_peak_depth)
        m_peak_depth = (ulong)m_count;

    return true;
}

//+------------------------------------------------------------------+
bool RingBuffer::Dequeue(AtlasEvent &event)
{
    if(IsEmpty())
        return false;

    event = m_buffer[m_tail];
    m_tail = (m_tail + 1) % m_capacity;
    m_count--;
    m_total_dequeued++;
    return true;
}

//+------------------------------------------------------------------+
bool RingBuffer::Peek(AtlasEvent &event) const
{
    if(IsEmpty())
        return false;
    event = m_buffer[m_tail];
    return true;
}

#endif // ATLAS_RING_BUFFER_MQH
//+------------------------------------------------------------------+
