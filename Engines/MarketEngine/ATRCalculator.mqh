//+------------------------------------------------------------------+
//|                     Engines/MarketEngine/ATRCalculator.mqh       |
//|          AtlasEA v0.1.9.0 - ATR(14) with Wilder Smoothing        |
//+------------------------------------------------------------------+
#ifndef ATLAS_ATR_CALCULATOR_MQH
#define ATLAS_ATR_CALCULATOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "BarBuffer.mqh"

/**
 * @class ATRCalculator
 * @brief ATR(14) calculator using Wilder's smoothing method.
 *
 * Wilder's smoothing formula:
 *   ATR_today = (ATR_yesterday × (period - 1) + TR_today) / period
 *
 * For the first 'period' bars, a simple average of True Range is used
 * as the seed value (Wilder's original method).
 *
 * True Range (TR) = max(
 *   high - low,
 *   |high - prev_close|,
 *   |low  - prev_close|
 * )
 *
 * Requirements met:
 *   - No dynamic allocation (fixed-size ring for TR history)
 *   - Incremental update (O(1) per new bar)
 *   - Cached calculation (ATR value stored, only recomputed on bar close)
 *   - Wilder smoothing (industry standard, non-repainting)
 *
 * Memory: ~130 bytes (14 doubles for TR ring + scalars)
 * Performance: O(1) per update, O(1) per read
 */
class ATRCalculator
{
private:
    int    m_period;           ///< ATR period (default 14)
    double m_tr_ring[];        ///< True Range history ring (size = period)
    int    m_tr_count;         ///< Number of TR values collected (0..period)
    int    m_tr_head;          ///< Next write slot in the ring
    double m_atr;              ///< Current ATR value (cached)
    double m_atr_prev;         ///< Previous ATR value (for slope calculation)
    bool   m_initialized;      ///< true after first ATR computation
    bool   m_cache_valid;      ///< true if ATR is up-to-date for current bars

    /// @brief Compute True Range for a bar.
    /// @param high  Current bar high
    /// @param low   Current bar low
    /// @param prev_close Previous bar close (0 if no previous bar)
    /// @return True Range value
    double ComputeTrueRange(const double high, const double low, const double prev_close) const;

    /// @brief Compute the seed ATR (simple average of TR ring).
    double ComputeSeedATR(void) const;

public:
    /**
     * @brief Constructor — initializes with default period 14.
     */
    ATRCalculator(void);

    /**
     * @brief Initialize the calculator with a specific period.
     * @param period ATR period (must be > 0, default 14).
     */
    void Initialize(const int period);

    /**
     * @brief Add a new closed bar and update ATR incrementally.
     *
     * Uses Wilder's smoothing:
     *   - If fewer than 'period' bars collected: accumulate TR, compute seed when full.
     *   - If 'period' or more bars: apply Wilder's formula.
     *
     * @param high       Current bar high
     * @param low        Current bar low
     * @param close      Current bar close (stored as prev_close for next bar)
     * @param prev_close Previous bar close (0 if first bar)
     */
    void OnBarClose(const double high, const double low, const double close, const double prev_close);

    /**
     * @brief Get the current ATR value.
     * @return ATR value, or 0.0 if not yet initialized.
     */
    double GetATR(void) const { return m_atr; }

    /**
     * @brief Get the previous ATR value (for slope calculation).
     * @return Previous ATR, or 0.0 if not available.
     */
    double GetPrevATR(void) const { return m_atr_prev; }

    /**
     * @brief Check if ATR has been initialized (enough bars collected).
     * @return true if ATR value is valid.
     */
    bool IsInitialized(void) const { return m_initialized; }

    /**
     * @brief Check if the cache is valid (no recompute needed).
     * @return true if ATR is up-to-date.
     */
    bool IsCacheValid(void) const { return m_cache_valid; }

    /**
     * @brief Invalidate the cache (forces recompute on next OnBarClose).
     * Called automatically when a new bar closes.
     */
    void Invalidate(void) { m_cache_valid = false; }

    /**
     * @brief Get the number of bars collected so far.
     * @return Count (0..period).
     */
    int BarsCollected(void) const { return m_tr_count; }

    /**
     * @brief Get the configured period.
     */
    int Period(void) const { return m_period; }

    /**
     * @brief Reset the calculator to initial state.
     */
    void Reset(void);

    /**
     * @brief Get the last True Range value (for diagnostics).
     * @return Last TR, or 0.0 if none collected.
     */
    double GetLastTR(void) const;
};

//+------------------------------------------------------------------+
//| ATRCalculator implementation                                      |
//+------------------------------------------------------------------+

ATRCalculator::ATRCalculator(void)
{
    m_period       = 14;
    ArrayResize(m_tr_ring, 14);
    ArrayInitialize(m_tr_ring, 0.0);
    m_tr_count     = 0;
    m_tr_head      = 0;
    m_atr          = 0.0;
    m_atr_prev     = 0.0;
    m_initialized  = false;
    m_cache_valid  = false;
}

//+------------------------------------------------------------------+
void ATRCalculator::Initialize(const int period)
{
    m_period = (period > 0) ? period : 14;
    ArrayResize(m_tr_ring, m_period);
    ArrayInitialize(m_tr_ring, 0.0);
    Reset();
}

//+------------------------------------------------------------------+
void ATRCalculator::Reset(void)
{
    m_tr_count     = 0;
    m_tr_head      = 0;
    m_atr          = 0.0;
    m_atr_prev     = 0.0;
    m_initialized  = false;
    m_cache_valid  = false;
    for(int i = 0; i < ArraySize(m_tr_ring); i++)
        m_tr_ring[i] = 0.0;
}

//+------------------------------------------------------------------+
double ATRCalculator::ComputeTrueRange(const double high, const double low, const double prev_close) const
{
    if(prev_close <= 0.0)
        return high - low;

    double tr1 = high - low;
    double tr2 = MathAbs(high - prev_close);
    double tr3 = MathAbs(low  - prev_close);

    double tr = tr1;
    if(tr2 > tr) tr = tr2;
    if(tr3 > tr) tr = tr3;
    return tr;
}

//+------------------------------------------------------------------+
double ATRCalculator::ComputeSeedATR(void) const
{
    if(m_tr_count == 0) return 0.0;
    double sum = 0.0;
    for(int i = 0; i < m_tr_count; i++)
        sum += m_tr_ring[i];
    return sum / (double)m_tr_count;
}

//+------------------------------------------------------------------+
void ATRCalculator::OnBarClose(const double high, const double low, const double close, const double prev_close)
{
    //--- Compute True Range for this bar
    double tr = ComputeTrueRange(high, low, prev_close);

    //--- Store TR in ring buffer
    if(m_tr_count < m_period)
    {
        m_tr_ring[m_tr_head] = tr;
        m_tr_head = (m_tr_head + 1) % m_period;
        m_tr_count++;
    }
    else
    {
        m_tr_ring[m_tr_head] = tr;
        m_tr_head = (m_tr_head + 1) % m_period;
    }

    //--- Save previous ATR
    m_atr_prev = m_atr;

    //--- Compute ATR
    if(m_tr_count < m_period)
    {
        //--- Not enough bars yet — use running average as preliminary ATR
        m_atr = ComputeSeedATR();
        m_initialized = false;
    }
    else if(!m_initialized)
    {
        //--- First full computation — seed with simple average
        m_atr = ComputeSeedATR();
        m_initialized = true;
    }
    else
    {
        //--- Wilder's smoothing: ATR_today = (ATR_yesterday × (period-1) + TR_today) / period
        m_atr = (m_atr_prev * (double)(m_period - 1) + tr) / (double)m_period;
    }

    m_cache_valid = true;
}

//+------------------------------------------------------------------+
double ATRCalculator::GetLastTR(void) const
{
    if(m_tr_count == 0) return 0.0;
    int last_idx = (m_tr_head - 1 + m_period) % m_period;
    return m_tr_ring[last_idx];
}

#endif // ATLAS_ATR_CALCULATOR_MQH
//+------------------------------------------------------------------+
