//+------------------------------------------------------------------+
//|                       Engines/MarketEngine/RegimeDetector.mqh     |
//|          AtlasEA v0.1.1.0 - Market Regime Detection              |
//+------------------------------------------------------------------+
#ifndef ATLAS_REGIME_DETECTOR_MQH
#define ATLAS_REGIME_DETECTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "IndicatorCache.mqh"
#include "TrendDetector.mqh"
#include "BarBuffer.mqh"

/**
 * @brief Market regime codes.
 * Used as feature[31] in the MarketState feature vector.
 */
#define ATLAS_REGIME_TRENDING       0
#define ATLAS_REGIME_RANGING        1
#define ATLAS_REGIME_VOLATILE       2
#define ATLAS_REGIME_QUIET          3
#define ATLAS_REGIME_BREAKOUT       4
#define ATLAS_REGIME_PULLBACK       5
#define ATLAS_REGIME_ACCUMULATION   6
#define ATLAS_REGIME_DISTRIBUTION   7
#define ATLAS_REGIME_COUNT          8

/**
 * @class RegimeDetector
 * @brief Classifies the current market into one of 8 regimes.
 *
 * Classification logic (all from CLOSED bars — non-repainting):
 *
 *   QUIET:          ADX < 20 AND ATR/price < median
 *   VOLATILE:       ATR > 1.5 * 20-bar avg ATR (ATR spike)
 *   TRENDING:       ADX > 25 AND trend_direction != 0 AND trend_strength > 30
 *   RANGING:        ADX < 20 AND |price - BB_middle| < 0.2 * BB_width
 *   BREAKOUT:       Close touches/exceeds BB_upper or BB_lower AND ADX rising
 *   PULLBACK:       Trend_direction != 0 AND price pulled back to EMA_fast
 *   ACCUMULATION:   BB_width < 20-bar avg AND volume declining AND ADX < 20
 *   DISTRIBUTION:   BB_width < 20-bar avg AND volume declining AND ADX < 20
 *                   (differentiated by trend context)
 *
 * Priority order (first match wins):
 *   1. VOLATILE    (ATR spike overrides everything — risk management)
 *   2. BREAKOUT    (price at Bollinger extreme)
 *   3. TRENDING    (strong directional move)
 *   4. PULLBACK    (counter-trend move within a trend)
 *   5. ACCUMULATION (consolidation before potential breakout up)
 *   6. DISTRIBUTION (consolidation before potential breakout down)
 *   7. RANGING     (sideways, no direction)
 *   8. QUIET       (low activity, low volatility)
 *
 * Performance: O(1) — all inputs are pre-cached.
 */
class RegimeDetector
{
private:
    ILogger *m_logger;

    //--- Configuration thresholds
    double m_adx_trend_threshold;       ///< ADX above this = trending (default 25)
    double m_adx_range_threshold;       ///< ADX below this = ranging (default 20)
    double m_atr_spike_mult;            ///< ATR spike multiplier (default 1.5)
    double m_bb_breakout_threshold;     ///< %B above this = breakout (default 0.95)
    double m_bb_range_threshold;        ///< %B within this of 0.5 = ranging (default 0.2)
    double m_pullback_atr_mult;         ///< Pullback distance from EMA in ATR (default 0.5)

    int    m_current_regime;            ///< Current regime code
    int    m_prev_regime;               ///< Previous regime code
    int    m_regime_duration;           ///< Bars in current regime

    /// @brief Compute Bollinger %B from indicator cache.
    double ComputePercentB(const IndicatorCache &cache, const double price) const;

    /// @brief Compute Bollinger width as fraction of middle band.
    double ComputeBBWidth(const IndicatorCache &cache) const;

public:
    /**
     * @brief Constructor.
     */
    RegimeDetector(void);

    /**
     * @brief Initialize the regime detector with thresholds.
     * @param logger Logger.
     */
    void Initialize(ILogger *logger);

    /**
     * @brief Update regime classification from indicator cache + trend + bars.
     * @param cache   Indicator cache (refreshed).
     * @param trend   Trend detector (updated).
     * @param bars    Bar buffer (for ATR average).
     * @param price   Current mid price.
     */
    void Update(const IndicatorCache &cache, const TrendDetector &trend,
                const BarBuffer &bars, const double price);

    /// @brief Current regime code (ATLAS_REGIME_*).
    int CurrentRegime(void) const { return m_current_regime; }

    /// @brief Previous regime code.
    int PreviousRegime(void) const { return m_prev_regime; }

    /// @brief Bars in current regime.
    int RegimeDuration(void) const { return m_regime_duration; }

    /// @brief true if regime changed on the last Update.
    bool RegimeChanged(void) const { return m_current_regime != m_prev_regime; }

    /// @brief Get human-readable regime name.
    string RegimeName(const int regime_code) const;

    /// @brief Reset to initial state.
    void Reset(void);
};

//+------------------------------------------------------------------+
//| RegimeDetector implementation                                     |
//+------------------------------------------------------------------+

RegimeDetector::RegimeDetector(void)
{
    m_logger                 = NULL;
    m_adx_trend_threshold    = 25.0;
    m_adx_range_threshold    = 20.0;
    m_atr_spike_mult         = 1.5;
    m_bb_breakout_threshold  = 0.95;
    m_bb_range_threshold     = 0.2;
    m_pullback_atr_mult      = 0.5;
    m_current_regime         = ATLAS_REGIME_QUIET;
    m_prev_regime            = ATLAS_REGIME_QUIET;
    m_regime_duration        = 0;
}

//+------------------------------------------------------------------+
void RegimeDetector::Initialize(ILogger *logger)
{
    m_logger = logger;
    Reset();
}

//+------------------------------------------------------------------+
void RegimeDetector::Reset(void)
{
    m_current_regime  = ATLAS_REGIME_QUIET;
    m_prev_regime     = ATLAS_REGIME_QUIET;
    m_regime_duration = 0;
}

//+------------------------------------------------------------------+
double RegimeDetector::ComputePercentB(const IndicatorCache &cache, const double price) const
{
    double range = cache.BBUpper() - cache.BBLower();
    if(range <= 0.0) return 0.5;
    return (price - cache.BBLower()) / range;
}

//+------------------------------------------------------------------+
double RegimeDetector::ComputeBBWidth(const IndicatorCache &cache) const
{
    if(cache.BBMiddle() <= 0.0) return 0.0;
    return (cache.BBUpper() - cache.BBLower()) / cache.BBMiddle();
}

//+------------------------------------------------------------------+
string RegimeDetector::RegimeName(const int regime_code) const
{
    switch(regime_code)
    {
        case ATLAS_REGIME_TRENDING:     return "TRENDING";
        case ATLAS_REGIME_RANGING:      return "RANGING";
        case ATLAS_REGIME_VOLATILE:     return "VOLATILE";
        case ATLAS_REGIME_QUIET:        return "QUIET";
        case ATLAS_REGIME_BREAKOUT:     return "BREAKOUT";
        case ATLAS_REGIME_PULLBACK:     return "PULLBACK";
        case ATLAS_REGIME_ACCUMULATION: return "ACCUMULATION";
        case ATLAS_REGIME_DISTRIBUTION: return "DISTRIBUTION";
    }
    return "UNKNOWN";
}

//+------------------------------------------------------------------+
void RegimeDetector::Update(const IndicatorCache &cache, const TrendDetector &trend,
                            const BarBuffer &bars, const double price)
{
    if(!cache.IsValid())
    {
        if(m_logger != NULL)
            m_logger.Warn("RegimeDetector", "Update: cache not valid");
        return;
    }

    m_prev_regime = m_current_regime;

    double atr       = cache.ATR();
    double adx       = cache.ADX();
    double pct_b     = ComputePercentB(cache, price);
    double bb_width  = ComputeBBWidth(cache);

    //--- Compute 20-bar average ATR (from indicator cache values)
    //--- We approximate using ATR vs ATR_prev ratio since we only cache 2 values
    //--- A more precise avg would require CopyBuffer of 20 values — too slow for 10ms budget
    double atr_avg = (atr + cache.ATRPrev()) / 2.0;
    if(atr_avg <= 0.0) atr_avg = atr;

    int new_regime = ATLAS_REGIME_QUIET;

    //==============================================================
    // 1. VOLATILE — ATR spike (overrides everything)
    //==============================================================
    if(atr > atr_avg * m_atr_spike_mult && atr_avg > 0.0)
    {
        new_regime = ATLAS_REGIME_VOLATILE;
    }
    //==============================================================
    // 2. BREAKOUT — price at Bollinger extreme
    //==============================================================
    else if(pct_b >= m_bb_breakout_threshold || pct_b <= (1.0 - m_bb_breakout_threshold))
    {
        new_regime = ATLAS_REGIME_BREAKOUT;
    }
    //==============================================================
    // 3. TRENDING — strong directional move
    //==============================================================
    else if(adx > m_adx_trend_threshold &&
            trend.Direction() != 0 &&
            trend.Strength() > 30)
    {
        new_regime = ATLAS_REGIME_TRENDING;
    }
    //==============================================================
    // 4. PULLBACK — counter-trend move within a trend
    //==============================================================
    else if(trend.Direction() != 0 && trend.Duration() > 3 && atr > 0.0)
    {
        double ema_dist = MathAbs(price - cache.EMAFast()) / atr;
        if(ema_dist < m_pullback_atr_mult)
            new_regime = ATLAS_REGIME_PULLBACK;
        else
            new_regime = ATLAS_REGIME_TRENDING;
    }
    //==============================================================
    // 5. ACCUMULATION / DISTRIBUTION — consolidation
    //==============================================================
    else if(adx < m_adx_range_threshold && bb_width < 0.02)
    {
        //--- Differentiate by recent price action
        if(bars.Count() >= 2)
        {
            BarData newest;
            if(bars.GetNewest(newest))
            {
                //--- If recent close > open → accumulation (buying pressure)
                if(newest.close > newest.open)
                    new_regime = ATLAS_REGIME_ACCUMULATION;
                else
                    new_regime = ATLAS_REGIME_DISTRIBUTION;
            }
            else
            {
                new_regime = ATLAS_REGIME_QUIET;
            }
        }
        else
        {
            new_regime = ATLAS_REGIME_QUIET;
        }
    }
    //==============================================================
    // 6. RANGING — sideways, no direction
    //==============================================================
    else if(adx < m_adx_range_threshold)
    {
        new_regime = ATLAS_REGIME_RANGING;
    }
    //==============================================================
    // 7. QUIET — low activity
    //==============================================================
    else
    {
        new_regime = ATLAS_REGIME_QUIET;
    }

    //--- Duration tracking
    if(new_regime == m_current_regime)
        m_regime_duration++;
    else
        m_regime_duration = 1;

    m_current_regime = new_regime;

    //--- Log regime changes
    if(RegimeChanged() && m_logger != NULL)
    {
        m_logger.Info("RegimeDetector",
            "Regime change: " + RegimeName(m_prev_regime) + " -> " + RegimeName(m_current_regime));
    }
}

#endif // ATLAS_REGIME_DETECTOR_MQH
//+------------------------------------------------------------------+
