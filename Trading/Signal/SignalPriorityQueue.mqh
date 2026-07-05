//+------------------------------------------------------------------+
//|                Trading/Signal/SignalPriorityQueue.mqh            |
//|       AtlasEA v0.2.1 - Fixed-Size Priority Queue                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_PRIORITY_QUEUE_MQH
#define ATLAS_SIGNAL_PRIORITY_QUEUE_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"

/**
 * @brief Maximum signals in the priority queue.
 * Fixed-size — no dynamic allocation.
 */
#define ATLAS_SIGNAL_QUEUE_CAPACITY 32

/**
 * @struct ScoredSignal
 * @brief A signal paired with its score for priority queue ordering.
 */
struct ScoredSignal
{
    TradeSignal signal;   ///< The signal
    double      score;    ///< Total score [0, 100]
    long        sequence; ///< Insertion sequence (for stable ordering)

    ScoredSignal(void)
    {
        score    = 0.0;
        sequence = 0;
    }
};

/**
 * @class SignalPriorityQueue
 * @brief Fixed-size priority queue for scored signals.
 *
 * SOLE RESPONSIBILITY: maintain signals ordered by score (highest first),
 * with stable ordering (ties broken by insertion sequence).
 *
 * Properties:
 *   - Fixed-size: ATLAS_SIGNAL_QUEUE_CAPACITY (32) slots. No dynamic alloc.
 *   - Highest score first: Peek() always returns the highest-scored signal.
 *   - Stable: if two signals have the same score, the one inserted first
 *     comes first (FIFO within same score).
 *   - Bounded overflow: if full, the lowest-scored signal is evicted.
 *
 * Implementation: a simple sorted array. Insert is O(n) (shift), Peek
 * is O(1), Pop is O(n) (shift). With capacity 32, this is fast enough
 * for the signal pipeline (which runs once per tick).
 *
 * Memory: ~32 * 250 bytes = ~8 KB (fixed).
 */
class SignalPriorityQueue
{
private:
    ScoredSignal m_items[ATLAS_SIGNAL_QUEUE_CAPACITY];
    int          m_count;
    long         m_next_sequence;
    ILogger     *m_logger;

    //--- Statistics
    int m_total_pushed;
    int m_total_popped;
    int m_total_evicted;

public:
    /**
     * @brief Constructor.
     */
    SignalPriorityQueue(void)
    {
        m_count        = 0;
        m_next_sequence = 0;
        m_logger       = NULL;
        m_total_pushed   = 0;
        m_total_popped   = 0;
        m_total_evicted  = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Push a scored signal into the queue.
     *
     * Inserts in sorted position (highest score first). If the queue is
     * full, the new signal is only accepted if its score is higher than
     * the lowest score in the queue; in that case the lowest is evicted.
     *
     * @param signal The signal to push.
     * @param score  The signal's score.
     * @return true if accepted, false if rejected (queue full and score too low).
     */
    bool Push(const TradeSignal &signal, const double score)
    {
        m_total_pushed++;

        //--- Check if we need to evict
        if(m_count >= ATLAS_SIGNAL_QUEUE_CAPACITY)
        {
            //--- Find the lowest score (last item, since sorted descending)
            double lowest = m_items[m_count - 1].score;
            if(score <= lowest)
            {
                //--- New signal is not better than the worst — reject
                if(m_logger != NULL)
                    m_logger.Debug("SignalPriorityQueue",
                        "Rejected " + signal.signal_id +
                        " score=" + DoubleToString(score, 1) +
                        " <= lowest=" + DoubleToString(lowest, 1));
                return false;
            }

            //--- Evict the lowest
            m_count--;
            m_total_evicted++;
            if(m_logger != NULL)
                m_logger.Debug("SignalPriorityQueue",
                    "Evicted " + m_items[m_count].signal.signal_id +
                    " score=" + DoubleToString(m_items[m_count].score, 1));
        }

        //--- Create the scored signal
        ScoredSignal item;
        item.signal   = signal;
        item.score    = score;
        item.sequence = m_next_sequence++;

        //--- Find insertion position (binary search for efficiency)
        int pos = FindInsertionPos(score, item.sequence);

        //--- Shift items right to make room
        for(int i = m_count; i > pos; i--)
            m_items[i] = m_items[i - 1];

        //--- Insert
        m_items[pos] = item;
        m_count++;

        if(m_logger != NULL)
            m_logger.Debug("SignalPriorityQueue",
                "Pushed " + signal.signal_id +
                " score=" + DoubleToString(score, 1) +
                " at pos " + IntegerToString(pos) +
                " count=" + IntegerToString(m_count));

        return true;
    }

    /**
     * @brief Peek at the highest-priority signal without removing it.
     * @param out Output: the highest-priority scored signal.
     * @return true if the queue is non-empty.
     */
    bool Peek(ScoredSignal &out) const
    {
        if(m_count == 0) return false;
        out = m_items[0];
        return true;
    }

    /**
     * @brief Pop the highest-priority signal.
     * @param out Output: the highest-priority scored signal.
     * @return true if a signal was popped.
     */
    bool Pop(ScoredSignal &out)
    {
        if(m_count == 0) return false;

        out = m_items[0];
        m_total_popped++;

        //--- Shift left
        for(int i = 1; i < m_count; i++)
            m_items[i - 1] = m_items[i];
        m_count--;

        return true;
    }

    /**
     * @brief Remove a specific signal by ID.
     * @param signal_id The signal ID to remove.
     * @return true if found and removed.
     */
    bool Remove(const string signal_id)
    {
        if(StringLen(signal_id) == 0) return false;
        for(int i = 0; i < m_count; i++)
        {
            if(m_items[i].signal.signal_id == signal_id)
            {
                //--- Shift left
                for(int j = i + 1; j < m_count; j++)
                    m_items[j - 1] = m_items[j];
                m_count--;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Clear all signals from the queue.
     */
    void Clear(void)
    {
        m_count = 0;
    }

    /**
     * @brief Get the number of signals in the queue.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Check if the queue is empty.
     */
    bool IsEmpty(void) const { return m_count == 0; }

    /**
     * @brief Check if the queue is full.
     */
    bool IsFull(void) const { return m_count >= ATLAS_SIGNAL_QUEUE_CAPACITY; }

    /**
     * @brief Get the signal at a specific index (0 = highest priority).
     */
    bool GetAt(const int index, ScoredSignal &out) const
    {
        if(index < 0 || index >= m_count) return false;
        out = m_items[index];
        return true;
    }

    //=== Statistics ===
    int TotalPushed(void)   const { return m_total_pushed; }
    int TotalPopped(void)   const { return m_total_popped; }
    int TotalEvicted(void)  const { return m_total_evicted; }

    /**
     * @brief Reset statistics (does not clear the queue).
     */
    void ResetStats(void)
    {
        m_total_pushed  = 0;
        m_total_popped  = 0;
        m_total_evicted = 0;
    }

private:
    /**
     * @brief Find the insertion position for a new scored signal.
     *
     * The queue is sorted descending by score. For stable ordering,
     * ties are broken by sequence (lower sequence = higher priority,
     * i.e., inserted first = comes first).
     *
     * @param score The new signal's score.
     * @param sequence The new signal's insertion sequence.
     * @return The index at which to insert (0 = front).
     */
    int FindInsertionPos(const double score, const long sequence) const
    {
        //--- Linear search (capacity is small, binary search overhead not worth it)
        for(int i = 0; i < m_count; i++)
        {
            if(score > m_items[i].score)
                return i;
            //--- Tie: lower sequence (inserted earlier) comes first
            if(score == m_items[i].score && sequence < m_items[i].sequence)
                return i;
        }
        return m_count; // Insert at end
    }
};

#endif // ATLAS_SIGNAL_PRIORITY_QUEUE_MQH
//+------------------------------------------------------------------+
