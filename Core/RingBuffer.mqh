//+------------------------------------------------------------------+
//|                                            Core/RingBuffer.mqh   |
//|                  AtlasEA v1.0 - Lock-free Ring Buffer (events)   |
//+------------------------------------------------------------------+
#ifndef ATLAS_RING_BUFFER_MQH
#define ATLAS_RING_BUFFER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

//+------------------------------------------------------------------+
//| EventRingBuffer - fixed-capacity FIFO ring buffer for AtlasEvent |
//| MQL5 EAs are single-threaded per chart, so no atomics needed.    |
//+------------------------------------------------------------------+
class EventRingBuffer
{
private:
    AtlasEvent m_buffer[ATLAS_EVENT_QUEUE_SIZE];
    int        m_head;     // next write slot
    int        m_tail;     // next read slot
    int        m_count;
    int        m_capacity;
    ulong      m_dropped;  // dropped event counter

public:
    EventRingBuffer(void) { Clear(ATLAS_EVENT_QUEUE_SIZE); }

    void Clear(int capacity)
    {
        m_capacity = capacity;
        if(m_capacity > ATLAS_EVENT_QUEUE_SIZE) m_capacity = ATLAS_EVENT_QUEUE_SIZE;
        if(m_capacity < 1) m_capacity = 1;
        m_head    = 0;
        m_tail    = 0;
        m_count   = 0;
        m_dropped = 0;
    }

    int    Count(void)    const { return m_count; }
    bool   IsEmpty(void)  const { return m_count == 0; }
    bool   IsFull(void)   const { return m_count >= m_capacity; }
    ulong  Dropped(void)  const { return m_dropped; }

    //+--------------------------------------------------------------+
    bool Enqueue(const AtlasEvent &event)
    {
        if(IsFull())
        {
            m_dropped++;
            return false;
        }
        m_buffer[m_head] = event;
        m_head = (m_head + 1) % m_capacity;
        m_count++;
        return true;
    }

    //+--------------------------------------------------------------+
    bool Dequeue(AtlasEvent &event)
    {
        if(IsEmpty()) return false;
        event = m_buffer[m_tail];
        m_tail = (m_tail + 1) % m_capacity;
        m_count--;
        return true;
    }

    //+--------------------------------------------------------------+
    bool Peek(AtlasEvent &event) const
    {
        if(IsEmpty()) return false;
        event = m_buffer[m_tail];
        return true;
    }
};

#endif // ATLAS_RING_BUFFER_MQH
//+------------------------------------------------------------------+
