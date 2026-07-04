//+------------------------------------------------------------------+
//|            Infrastructure/Logging/MemoryRingSink.mqh            |
//|       AtlasEA v0.1.14.0 - In-Memory Ring Buffer Sink             |
//+------------------------------------------------------------------+
#ifndef ATLAS_MEMORY_RING_SINK_MQH
#define ATLAS_MEMORY_RING_SINK_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogSink.mqh"

/**
 * @brief Maximum entries in the in-memory ring buffer.
 */
#define ATLAS_LOG_RING_SIZE 256

/**
 * @class MemoryRingSink
 * @brief Stores log entries in a fixed-size in-memory ring buffer.
 *
 * Used for diagnostics — the last N log entries can be retrieved
 * for inspection without reading a file.
 *
 * Memory: 256 × ~128 bytes = ~32 KB (fixed, pre-allocated).
 */
class MemoryRingSink : public ILogSink
{
private:
    LogEntry m_entries[ATLAS_LOG_RING_SIZE];
    int      m_head;
    int      m_count;
    string   m_name;

public:
    /**
     * @brief Constructor.
     */
    MemoryRingSink(void)
    {
        m_head  = 0;
        m_count = 0;
        m_name  = "MemoryRingSink";
    }

    virtual void Write(const LogEntry &entry) override
    {
        m_entries[m_head] = entry;
        m_head = (m_head + 1) % ATLAS_LOG_RING_SIZE;
        if(m_count < ATLAS_LOG_RING_SIZE)
            m_count++;
    }

    virtual void Flush(void) override { /* In-memory — nothing to flush */ }

    virtual string GetName(void) const override { return m_name; }

    /**
     * @brief Get the number of entries in the ring.
     */
    int EntryCount(void) const { return m_count; }

    /**
     * @brief Get a log entry by index (0 = oldest, count-1 = newest).
     */
    bool GetEntry(const int index, LogEntry &out) const
    {
        if(index < 0 || index >= m_count) return false;
        int actual;
        if(m_count < ATLAS_LOG_RING_SIZE)
            actual = index;
        else
            actual = (m_head + index) % ATLAS_LOG_RING_SIZE;
        out = m_entries[actual];
        return true;
    }

    /**
     * @brief Clear the ring buffer.
     */
    void Clear(void)
    {
        m_head  = 0;
        m_count = 0;
    }
};

#endif // ATLAS_MEMORY_RING_SINK_MQH
//+------------------------------------------------------------------+
