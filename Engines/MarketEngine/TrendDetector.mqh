//+------------------------------------------------------------------+
//|                       Engines/MarketEngine/TrendDetector.mqh      |
//|          AtlasEA v0.1.1.0 - Non-Repainting Trend Detection      |
//+------------------------------------------------------------------+
#ifndef ATLAS_TREND_DETECTOR_MQH
#define ATLAS_TREND_DETECTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "IndicatorCache.mqh"

/**
 * @class TrendDetector
 * @brief Non-repainting trend detection using EMA crossover on CLOSED bars.
 *
 * Trend direction: based on EMA(fast) vs EMA(slow) separation.
 *   - If EMA_fast > EMA_slow + threshold → uptrend (+1)
 *   - If EMA_fast < EMA_slow - threshold → downtrend (-1)
 *   - Otherwise → no trend (0)
 *
 * Threshold = 0.25 * ATR (avoids whipsaws in low-volatility periods).
 *
 * Trend strength: |EMA_fast - EMA_slow| / ATR, scaled 0..100.
 *   - 0 = EMAs are equal
 *   - 100 = separation >= 2 * ATR
 *
 * Trend duration: number of bars since the last direction change.
 * Incremented on each bar where direction stays the same.
 * Reset to 1 when direction changes.
 *
 * NON-REPAINTING GUARANTEE:
 *   All inputs come from IndicatorCache which reads at shift=1 (last
 *   closed bar). The forming bar is never consulted. Therefore the
 *   trend output for a given bar never changes once that bar closes.
 *
 * Performance: O(1) — all values are pre-cached.
 */
class TrendDetector
{
private:
    ILogger *m_logger;
    double   m_separation_threshold_mult; ///< ATR multiplier for trend threshold

    int      m_direction;     ///< Current trend direction (-1, 0, +1)
    int      m_strength;      ///< Current trend strength (0..100)
    int      m_duration;      ///< Bars since last direction change

    /// @brief Compute the direction from EMA separation.
    int ComputeDirection(const double ema_fast, const double ema_slow,
                         const double atr, const double threshold) const;

    /// @brief Compute the strength from EMA separation.
    int ComputeStrength(const double ema_fast, const double ema_slow,
                        const double atr) const;

public:
    /**
     * @brief Constructor.
     */
    TrendDetector(void);

    /**
     * @brief Initialize the trend detector.
     * @param logger       Logger.
     * @param threshold_mult  ATR multiplier for trend threshold (default 0.25).
     */
    void Initialize(ILogger *logger, const double threshold_mult);

    /**
     * @brief Update trend state from the indicator cache.
     * Called once per closed bar (when a new bar opens).
     * @param cache Indicator cache (must be refreshed first).
     */
    void Update(const IndicatorCache &cache);

    /// @brief Current trend direction (-1, 0, +1).
    int Direction(void) const { return m_direction; }

    /// @brief Current trend strength (0..100).
    int Strength(void) const { return m_strength; }

    /// @brief Bars since last direction change.
    int Duration(void) const { return m_duration; }

    /// @brief Reset to initial state.
    void Reset(void);
};

//+------------------------------------------------------------------+
//| TrendDetector implementation                                      |
//+------------------------------------------------------------------+

TrendDetector::TrendDetector(void)
{
    m_logger                     = NULL;
    m_separation_threshold_mult  = 0.25;
    m_direction                  = 0;
    m_strength                   = 0;
    m_duration                   = 0;
}

//+------------------------------------------------------------------+
void TrendDetector::Initialize(ILogger *logger, const double threshold_mult)
{
    m_logger                    = logger;
    m_separation_threshold_mult = (threshold_mult > 0.0) ? threshold_mult : 0.25;
    Reset();
}

//+------------------------------------------------------------------+
void TrendDetector::Reset(void)
{
    m_direction = 0;
    m_strength  = 0;
    m_duration  = 0;
}

//+------------------------------------------------------------------+
int TrendDetector::ComputeDirection(const double ema_fast, const double ema_slow,
                                     const double atr, const double threshold) const
{
    double separation = ema_fast - ema_slow;
    if(separation > threshold)  return 1;   //--- Uptrend
    if(separation < -threshold) return -1;  //--- Downtrend
    return 0;                                //--- No clear trend
}

//+------------------------------------------------------------------+
int TrendDetector::ComputeStrength(const double ema_fast, const double ema_slow,
                                   const double atr) const
{
    if(atr <= 0.0) return 0;
    double separation = MathAbs(ema_fast - ema_slow);
    double ratio = separation / atr;
    //--- Scale: ratio of 0 = strength 0, ratio of 2.0+ = strength 100
    double strength = ratio / 2.0 * 100.0;
    if(strength < 0.0)   strength = 0.0;
    if(strength > 100.0) strength = 100.0;
    return (int)strength;
}

//+------------------------------------------------------------------+
void TrendDetector::Update(const IndicatorCache &cache)
{
    if(!cache.IsValid())
    {
        if(m_logger != NULL)
            m_logger.Warn("TrendDetector", "Update: indicator cache not valid");
        return;
    }

    double atr = cache.ATR();
    if(atr <= 0.0)
    {
        if(m_logger != NULL)
            m_logger.Warn("TrendDetector", "Update: ATR is zero");
        return;
    }

    double threshold = atr * m_separation_threshold_mult;

    int new_dir = ComputeDirection(cache.EMAFast(), cache.EMASlow(), atr, threshold);

    //--- Duration tracking
    if(new_dir == m_direction && new_dir != 0)
    {
        //--- Same direction — increment duration
        m_duration++;
    }
    else if(new_dir != m_direction)
    {
        //--- Direction changed — reset duration
        m_duration = (new_dir != 0) ? 1 : 0;
    }

    m_direction = new_dir;
    m_strength  = ComputeStrength(cache.EMAFast(), cache.EMASlow(), atr);
}

#endif // ATLAS_TREND_DETECTOR_MQH
//+------------------------------------------------------------------+
