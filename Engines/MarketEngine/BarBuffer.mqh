//+------------------------------------------------------------------+
//|                                  Engines/MarketEngine/BarBuffer.mqh
//|                AtlasEA v0.1.1.0 - OHLC Ring Buffer (100 bars)     |
//+------------------------------------------------------------------+
#ifndef ATLAS_BAR_BUFFER_MQH
#define ATLAS_BAR_BUFFER_MQH

#include "../../Config/Settings.mqh"

/**
 * @def ATLAS_BAR_BUFFER_CAPACITY
 * @brief Fixed capacity of the OHLC ring buffer (100 bars).
 */
#define ATLAS_BAR_BUFFER_CAPACITY 100

/**
 * @struct BarData
 * @brief One OHLCV bar held in the internal ring buffer.
 */
struct BarData
{
    datetime time;          ///< Bar open time
    double   open;          ///< Open price
    double   high;          ///< High price
    double   low;           ///< Low price
    double   close;         ///< Close price
    long     tick_volume;   ///< Tick volume
    long     real_volume;   ///< Real volume
};

/**
 * @class BarBuffer
 * @brief Fixed-capacity FIFO ring buffer for OHLCV bars.
 *
 * Capacity: 100 bars (ATLAS_BAR_BUFFER_CAPACITY).
 * Memory: stack-allocated fixed array — zero dynamic allocation.
 * Access: O(1) for all operations (ring index arithmetic).
 *
 * Bars are stored in chronological order. Index 0 = oldest bar in buffer,
 * index (Count-1) = newest (most recently closed) bar.
 *
 * The forming (current, unclosed) bar is NOT stored in the ring buffer —
 * it is tracked separately by MarketEngine to ensure all indicator
 * calculations use only CLOSED bars (non-repainting guarantee).
 */
class BarBuffer
{
private:
    BarData m_bars[ATLAS_BAR_BUFFER_CAPACITY];  ///< Fixed storage
    int     m_count;                              ///< Current number of bars
    int     m_head;                               ///< Next write slot (ring)

public:
    /**
     * @brief Constructor — initializes an empty buffer.
     */
    BarBuffer(void);

    /**
     * @brief Reset the buffer to empty state.
     */
    void Reset(void);

    /**
     * @brief Add a closed bar to the buffer.
     * If the buffer is full, the oldest bar is evicted (FIFO).
     * @param bar The closed bar to add.
     */
    void AddBar(const BarData &bar);

    /**
     * @brief Get a bar by index (0 = oldest, Count-1 = newest).
     * @param index Bar index (0-based, oldest first).
     * @param out   Output: copy of the bar.
     * @return true if index is valid, false otherwise.
     */
    bool GetBar(const int index, BarData &out) const;

    /**
     * @brief Get the close price of a bar by index.
     * @param index Bar index (0 = oldest, Count-1 = newest).
     * @return Close price, or 0.0 if index invalid.
     */
    double GetClose(const int index) const;

    /**
     * @brief Get the high price of a bar by index.
     */
    double GetHigh(const int index) const;

    /**
     * @brief Get the low price of a bar by index.
     */
    double GetLow(const int index) const;

    /**
     * @brief Get the tick volume of a bar by index.
     */
    long GetTickVolume(const int index) const;

    /**
     * @brief Number of bars currently in the buffer.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief true if the buffer is empty.
     */
    bool IsEmpty(void) const { return m_count == 0; }

    /**
     * @brief true if the buffer is at capacity.
     */
    bool IsFull(void) const { return m_count >= ATLAS_BAR_BUFFER_CAPACITY; }

    /**
     * @brief Get the newest (most recently closed) bar.
     * @param out Output: copy of the newest bar.
     * @return true if buffer is not empty.
     */
    bool GetNewest(BarData &out) const;

    /**
     * @brief Get the oldest bar in the buffer.
     * @param out Output: copy of the oldest bar.
     * @return true if buffer is not empty.
     */
    bool GetOldest(BarData &out) const;

    /**
     * @brief Compute the highest high over the last N bars.
     * @param n Number of bars to look back (from newest).
     * @return Highest high, or 0.0 if buffer is empty.
     */
    double HighestHigh(const int n) const;

    /**
     * @brief Compute the lowest low over the last N bars.
     * @param n Number of bars to look back (from newest).
     * @return Lowest low, or 0.0 if buffer is empty.
     */
    double LowestLow(const int n) const;

    /**
     * @brief Compute the average tick volume over the last N bars.
     * @param n Number of bars to look back.
     * @return Average volume, or 0.0 if buffer is empty.
     */
    double AverageVolume(const int n) const;
};

//+------------------------------------------------------------------+
//| BarBuffer implementation                                          |
//+------------------------------------------------------------------+

BarBuffer::BarBuffer(void)
{
    Reset();
}

//+------------------------------------------------------------------+
void BarBuffer::Reset(void)
{
    m_count = 0;
    m_head  = 0;
}

//+------------------------------------------------------------------+
void BarBuffer::AddBar(const BarData &bar)
{
    if(m_count < ATLAS_BAR_BUFFER_CAPACITY)
    {
        //--- Buffer not yet full — append at head
        m_bars[m_head] = bar;
        m_head++;
        m_count++;
    }
    else
    {
        //--- Buffer full — shift all bars left by one, append at end
        for(int i = 1; i < ATLAS_BAR_BUFFER_CAPACITY; i++)
            m_bars[i-1] = m_bars[i];
        m_bars[ATLAS_BAR_BUFFER_CAPACITY - 1] = bar;
    }
}

//+------------------------------------------------------------------+
bool BarBuffer::GetBar(const int index, BarData &out) const
{
    if(index < 0 || index >= m_count)
    {
        ZeroMemory(out);
        return false;
    }
    out = m_bars[index];
    return true;
}

//+------------------------------------------------------------------+
double BarBuffer::GetClose(const int index) const
{
    if(index < 0 || index >= m_count) return 0.0;
    return m_bars[index].close;
}

//+------------------------------------------------------------------+
double BarBuffer::GetHigh(const int index) const
{
    if(index < 0 || index >= m_count) return 0.0;
    return m_bars[index].high;
}

//+------------------------------------------------------------------+
double BarBuffer::GetLow(const int index) const
{
    if(index < 0 || index >= m_count) return 0.0;
    return m_bars[index].low;
}

//+------------------------------------------------------------------+
long BarBuffer::GetTickVolume(const int index) const
{
    if(index < 0 || index >= m_count) return 0;
    return m_bars[index].tick_volume;
}

//+------------------------------------------------------------------+
bool BarBuffer::GetNewest(BarData &out) const
{
    if(m_count == 0)
    {
        ZeroMemory(out);
        return false;
    }
    out = m_bars[m_count - 1];
    return true;
}

//+------------------------------------------------------------------+
bool BarBuffer::GetOldest(BarData &out) const
{
    if(m_count == 0)
    {
        ZeroMemory(out);
        return false;
    }
    out = m_bars[0];
    return true;
}

//+------------------------------------------------------------------+
double BarBuffer::HighestHigh(const int n) const
{
    if(m_count == 0) return 0.0;
    int lookback = (n < m_count) ? n : m_count;
    if(lookback <= 0) return 0.0;

    double highest = m_bars[m_count - 1].high;
    for(int i = 1; i < lookback; i++)
    {
        int idx = m_count - 1 - i;
        if(idx < 0) break;
        if(m_bars[idx].high > highest)
            highest = m_bars[idx].high;
    }
    return highest;
}

//+------------------------------------------------------------------+
double BarBuffer::LowestLow(const int n) const
{
    if(m_count == 0) return 0.0;
    int lookback = (n < m_count) ? n : m_count;
    if(lookback <= 0) return 0.0;

    double lowest = m_bars[m_count - 1].low;
    for(int i = 1; i < lookback; i++)
    {
        int idx = m_count - 1 - i;
        if(idx < 0) break;
        if(m_bars[idx].low < lowest)
            lowest = m_bars[idx].low;
    }
    return lowest;
}

//+------------------------------------------------------------------+
double BarBuffer::AverageVolume(const int n) const
{
    if(m_count == 0) return 0.0;
    int lookback = (n < m_count) ? n : m_count;
    if(lookback <= 0) return 0.0;

    double sum = 0.0;
    for(int i = 0; i < lookback; i++)
    {
        int idx = m_count - 1 - i;
        if(idx < 0) break;
        sum += (double)m_bars[idx].tick_volume;
    }
    return sum / (double)lookback;
}

#endif // ATLAS_BAR_BUFFER_MQH
//+------------------------------------------------------------------+
