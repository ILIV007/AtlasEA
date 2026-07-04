//+------------------------------------------------------------------+
//|                     Replay/ReplayCursor.mqh                     |
//|       AtlasEA v0.1.23.0 - Replay Cursor (bi-directional)        |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_CURSOR_MQH
#define ATLAS_REPLAY_CURSOR_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Events/EventMetadata.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum events the cursor can hold.
 */
#define ATLAS_REPLAY_CURSOR_MAX 1024

/**
 * @class ReplayCursor
 * @brief Bi-directional cursor over a loaded event array.
 *
 * Supports:
 *   - Next() — advance to the next event
 *   - Previous() — go back one event
 *   - Seek(index) — jump to an arbitrary index
 *   - Peek() — look at the next event without advancing
 *   - Current() — get the current event
 *   - EOF() — check if at end
 *   - Reset() — go back to the beginning
 *
 * Fixed-size array. No dynamic allocation.
 */
class ReplayCursor
{
private:
    SourcedEvent m_events[ATLAS_REPLAY_CURSOR_MAX];
    int          m_count;
    int          m_position;  ///< Current index (0-based, -1 = before start)
    ILogger     *m_logger;

public:
    /**
     * @brief Constructor.
     */
    ReplayCursor(void)
    {
        m_count    = 0;
        m_position = -1;
        m_logger   = NULL;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Load events into the cursor.
     * @param events Array of sourced events.
     * @param count Number of events to load (max ATLAS_REPLAY_CURSOR_MAX).
     */
    void Load(const SourcedEvent &events[], const int count)
    {
        m_count = (count < ATLAS_REPLAY_CURSOR_MAX) ? count : ATLAS_REPLAY_CURSOR_MAX;
        for(int i = 0; i < m_count; i++)
            m_events[i] = events[i];
        m_position = -1;
    }

    /**
     * @brief Add a single event to the cursor.
     */
    bool Add(const SourcedEvent &event)
    {
        if(m_count >= ATLAS_REPLAY_CURSOR_MAX) return false;
        m_events[m_count] = event;
        m_count++;
        return true;
    }

    /**
     * @brief Advance to the next event.
     * @return true if advanced, false if at EOF.
     */
    bool Next(void)
    {
        if(m_position + 1 >= m_count) return false;
        m_position++;
        return true;
    }

    /**
     * @brief Go back one event.
     * @return true if moved back, false if at beginning.
     */
    bool Previous(void)
    {
        if(m_position <= 0) return false;
        m_position--;
        return true;
    }

    /**
     * @brief Seek to a specific index.
     * @param index Zero-based index (0..count-1), or -1 for before start.
     * @return true if index is valid.
     */
    bool Seek(const int index)
    {
        if(index < -1 || index >= m_count) return false;
        m_position = index;
        return true;
    }

    /**
     * @brief Seek to a specific sequence number.
     * @return true if found.
     */
    bool SeekBySequence(const long sequence)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_events[i].metadata.sequence == sequence)
            {
                m_position = i;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Peek at the next event without advancing.
     * @return true if there is a next event.
     */
    bool Peek(SourcedEvent &out) const
    {
        if(m_position + 1 >= m_count) return false;
        out = m_events[m_position + 1];
        return true;
    }

    /**
     * @brief Get the current event.
     * @return true if there is a current event.
     */
    bool Current(SourcedEvent &out) const
    {
        if(m_position < 0 || m_position >= m_count) return false;
        out = m_events[m_position];
        return true;
    }

    /**
     * @brief Get the current event's base AtlasEvent.
     */
    bool CurrentEvent(AtlasEvent &out) const
    {
        SourcedEvent sourced;
        if(!Current(sourced)) return false;
        out = sourced.event;
        return true;
    }

    /**
     * @brief Check if at end of cursor.
     */
    bool EOF(void) const
    {
        return (m_position + 1 >= m_count);
    }

    /**
     * @brief Reset cursor to before the start.
     */
    void Reset(void)
    {
        m_position = -1;
    }

    /**
     * @brief Clear all loaded events.
     */
    void Clear(void)
    {
        m_count    = 0;
        m_position = -1;
    }

    //=== Accessors ===
    int Count(void) const      { return m_count; }
    int Position(void) const   { return m_position; }
    long CurrentSequence(void) const
    {
        if(m_position < 0 || m_position >= m_count) return 0;
        return m_events[m_position].metadata.sequence;
    }

    /**
     * @brief Get the first sequence number in the cursor.
     */
    long FirstSequence(void) const
    {
        if(m_count == 0) return 0;
        return m_events[0].metadata.sequence;
    }

    /**
     * @brief Get the last sequence number.
     */
    long LastSequence(void) const
    {
        if(m_count == 0) return 0;
        return m_events[m_count - 1].metadata.sequence;
    }

    /**
     * @brief Get the first timestamp.
     */
    datetime FirstTimestamp(void) const
    {
        if(m_count == 0) return 0;
        return m_events[0].event.timestamp;
    }

    /**
     * @brief Get the last timestamp.
     */
    datetime LastTimestamp(void) const
    {
        if(m_count == 0) return 0;
        return m_events[m_count - 1].event.timestamp;
    }
};

#endif // ATLAS_REPLAY_CURSOR_MQH
//+------------------------------------------------------------------+
