//+------------------------------------------------------------------+
//|                   Events/EventJournal.mqh                       |
//|       AtlasEA v0.1.19.0 - Event Journal (Ring Buffer)           |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_JOURNAL_MQH
#define ATLAS_EVENT_JOURNAL_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "EventMetadata.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Core/ValidationResult.mqh"

/**
 * @brief Journal capacity (ring buffer size).
 */
#define ATLAS_JOURNAL_CAPACITY 1024

/**
 * @class EventJournal
 * @brief In-memory ring buffer for sourced events.
 *
 * Fixed-capacity ring buffer. When full, oldest events are evicted (FIFO).
 * No dynamic allocation. O(1) append, O(N) scan.
 *
 * The journal is the backing store for the EventStore.
 */
class EventJournal
{
private:
    SourcedEvent m_entries[ATLAS_JOURNAL_CAPACITY];
    int          m_head;       ///< Next write slot
    int          m_tail;       ///< Oldest read slot
    int          m_count;      ///< Current count
    long         m_next_seq;   ///< Next sequence number
    ILogger     *m_logger;

public:
    /**
     * @brief Constructor.
     */
    EventJournal(void)
    {
        m_logger  = NULL;
        m_head    = 0;
        m_tail    = 0;
        m_count   = 0;
        m_next_seq = 1;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Append a sourced event. O(1).
     * Assigns the sequence number. If full, evicts oldest.
     * @return The assigned sequence number, or 0 on failure.
     */
    long Append(SourcedEvent &entry)
    {
        //--- Assign sequence number
        entry.metadata.sequence = m_next_seq;

        //--- Write to ring
        m_entries[m_head] = entry;
        m_head = (m_head + 1) % ATLAS_JOURNAL_CAPACITY;

        if(m_count < ATLAS_JOURNAL_CAPACITY)
        {
            m_count++;
        }
        else
        {
            //--- Evict oldest
            m_tail = (m_tail + 1) % ATLAS_JOURNAL_CAPACITY;
        }

        m_next_seq++;
        return entry.metadata.sequence;
    }

    /**
     * @brief Read by absolute sequence number. O(N) scan.
     * @return true if found.
     */
    bool Read(const long sequence, SourcedEvent &out) const
    {
        for(int i = 0; i < m_count; i++)
        {
            int idx = (m_tail + i) % ATLAS_JOURNAL_CAPACITY;
            if(m_entries[idx].metadata.sequence == sequence)
            {
                out = m_entries[idx];
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Read by index (0 = oldest, count-1 = newest). O(1).
     */
    bool ReadByIndex(const int index, SourcedEvent &out) const
    {
        if(index < 0 || index >= m_count) return false;
        int idx = (m_tail + index) % ATLAS_JOURNAL_CAPACITY;
        out = m_entries[idx];
        return true;
    }

    /**
     * @brief Read a range [from_seq, to_seq]. O(N).
     * @return Number of events read.
     */
    int ReadRange(const long from_seq, const long to_seq,
                   SourcedEvent out_events[], const int max_count) const
    {
        int found = 0;
        for(int i = 0; i < m_count && found < max_count; i++)
        {
            int idx = (m_tail + i) % ATLAS_JOURNAL_CAPACITY;
            long seq = m_entries[idx].metadata.sequence;
            if(seq >= from_seq && seq <= to_seq)
            {
                out_events[found] = m_entries[idx];
                found++;
            }
        }
        return found;
    }

    /**
     * @brief Count total entries.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Get next sequence number.
     */
    long GetNextSequence(void) const { return m_next_seq; }

    /**
     * @brief Clear the journal.
     */
    void Clear(void)
    {
        m_head    = 0;
        m_tail    = 0;
        m_count   = 0;
        m_next_seq = 1;
    }

    /**
     * @brief Check if the journal is full.
     */
    bool IsFull(void) const { return m_count >= ATLAS_JOURNAL_CAPACITY; }

    /**
     * @brief Get the oldest sequence number in the journal.
     */
    long GetOldestSequence(void) const
    {
        if(m_count == 0) return 0;
        return m_entries[m_tail].metadata.sequence;
    }

    /**
     * @brief Get the newest sequence number.
     */
    long GetNewestSequence(void) const
    {
        if(m_count == 0) return 0;
        int idx = (m_head - 1 + ATLAS_JOURNAL_CAPACITY) % ATLAS_JOURNAL_CAPACITY;
        return m_entries[idx].metadata.sequence;
    }

    /**
     * @brief Validate journal structural invariants.
     * @return ValidationResult.
     *
     * Invariants:
     *   - ATLAS_JOURNAL_CAPACITY > 0
     *   - m_count in [0, ATLAS_JOURNAL_CAPACITY]
     *   - m_head in [0, ATLAS_JOURNAL_CAPACITY)
     *   - m_tail in [0, ATLAS_JOURNAL_CAPACITY)
     *   - m_next_seq > 0 (monotonic, starts at 1)
     *   - count == 0 implies head == tail (empty invariant)
     *   - count == capacity implies head == tail (full invariant)
     *   - (head - tail + capacity) % capacity == count when 0 < count < capacity
     */
    ValidationResult Validate(void) const
    {
        if(ATLAS_JOURNAL_CAPACITY <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "ATLAS_JOURNAL_CAPACITY must be > 0", "ATLAS_JOURNAL_CAPACITY");
        if(m_count < 0 || m_count > ATLAS_JOURNAL_CAPACITY)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "m_count out of range: " + IntegerToString(m_count), "m_count");
        if(m_head < 0 || m_head >= ATLAS_JOURNAL_CAPACITY)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "m_head out of range: " + IntegerToString(m_head), "m_head");
        if(m_tail < 0 || m_tail >= ATLAS_JOURNAL_CAPACITY)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "m_tail out of range: " + IntegerToString(m_tail), "m_tail");
        if(m_next_seq <= 0)
            return ValidationResult::Fail(ATLAS_V_MONOTONICITY,
                "m_next_seq must be > 0: " + IntegerToString(m_next_seq),
                "m_next_seq");
        //--- Empty invariant: head must equal tail
        if(m_count == 0 && m_head != m_tail)
            return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                "empty buffer must have head == tail", "m_head/m_tail");
        //--- Full invariant: head must equal tail
        if(m_count == ATLAS_JOURNAL_CAPACITY && m_head != m_tail)
            return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                "full buffer must have head == tail", "m_head/m_tail");
        //--- Count consistency (only meaningful for non-empty, non-full)
        if(m_count > 0 && m_count < ATLAS_JOURNAL_CAPACITY)
        {
            int expected = (m_head - m_tail + ATLAS_JOURNAL_CAPACITY)
                           % ATLAS_JOURNAL_CAPACITY;
            if(expected != m_count)
                return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                    "ring count mismatch: expected=" + IntegerToString(expected) +
                    " actual=" + IntegerToString(m_count), "m_count");
        }
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_EVENT_JOURNAL_MQH
//+------------------------------------------------------------------+
