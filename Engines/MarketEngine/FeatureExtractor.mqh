//+------------------------------------------------------------------+
//|                     Engines/MarketEngine/FeatureExtractor.mqh     |
//|          AtlasEA v0.1.1.0 - 32-Feature Extraction Engine        |
//+------------------------------------------------------------------+
#ifndef ATLAS_FEATURE_EXTRACTOR_MQH
#define ATLAS_FEATURE_EXTRACTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "IndicatorCache.mqh"
#include "TrendDetector.mqh"
#include "RegimeDetector.mqh"
#include "BarBuffer.mqh"

/**
 * @class FeatureExtractor
 * @brief Generates exactly 32 normalized features for the strategy layer.
 *
 * ALL features are:
 *   - DETERMINISTIC: same inputs → same output (no MathRand, no time-of-call variance)
 *   - NON-REPAINTING: derived from CLOSED bars only (shift >= 1)
 *   - NORMALIZED: bounded to [-1, 1] or [0, 1]
 *
 * Feature vector layout (indices 0..31):
 *
 *   PRICE / MA FEATURES:
 *     0: Price vs EMA20 (z-score, [-1,1])
 *     1: Price vs EMA50 (z-score, [-1,1])
 *     2: EMA20 slope / ATR ([-1,1])
 *     3: EMA50 slope / ATR ([-1,1])
 *     4: EMA20 vs EMA50 separation / ATR ([-1,1])
 *
 *   VOLATILITY FEATURES:
 *     5: ATR / price ([0,1])
 *     6: ATR vs prev ATR ratio ([0,1])
 *     7: BB width / middle ([0,1])
 *     8: BB %B ([0,1])
 *
 *   MOMENTUM FEATURES:
 *     9: RSI / 100 ([0,1])
 *    10: RSI delta ([-1,1])
 *    11: MACD histogram / ATR ([-1,1])
 *    12: MACD signal cross direction (-1, 0, 1)
 *    13: CCI / 200 ([-1,1])
 *    14: Stochastic %K / 100 ([0,1])
 *    15: Stochastic %D / 100 ([0,1])
 *
 *   TREND FEATURES:
 *    16: Trend direction (-1, 0, 1)
 *    17: Trend strength / 100 ([0,1])
 *    18: Trend duration / 50 ([0,1])
 *    19: ADX / 100 ([0,1])
 *    20: DI+ / (DI+ + DI-) ([0,1])
 *    21: DI- / (DI+ + DI-) ([0,1])
 *
 *   PRICE ACTION FEATURES (from last closed bar):
 *    22: Body ratio ([0,1])
 *    23: Upper shadow ratio ([0,1])
 *    24: Lower shadow ratio ([0,1])
 *    25: Bar range / ATR ([0,1])
 *
 *   VOLUME FEATURES:
 *    26: Tick volume change rate ([-1,1])
 *    27: Tick volume / 20-bar avg ([0,1])
 *
 *   SPREAD / MARKET QUALITY:
 *    28: Spread / max spread ([0,1])
 *
 *   CONTEXT FEATURES:
 *    29: Session state / 4 ([0,1])
 *    30: Market regime / 7 ([0,1])
 *    31: Bar progress (current bar time elapsed / period) ([0,1])
 *
 * Performance: O(1) per feature. Total: O(1).
 * No allocation. No recursion.
 */
class FeatureExtractor
{
private:
    ILogger *m_logger;

    /// @brief Clamp a value to [lo, hi].
    double Clamp(const double v, const double lo, const double hi) const;

    /// @brief Safe division: a / b, returns 0.0 if b <= 0.
    double SafeDiv(const double a, const double b) const;

public:
    /**
     * @brief Constructor.
     */
    FeatureExtractor(void);

    /**
     * @brief Initialize the feature extractor.
     * @param logger Logger.
     */
    void Initialize(ILogger *logger);

    /**
     * @brief Extract all 32 features into the output array.
     * @param features  Output array (must be ATLAS_FEATURE_SIZE = 32 elements).
     * @param count     Output: number of features written (always 32).
     * @param cache     Indicator cache (refreshed, from closed bars).
     * @param trend     Trend detector (updated).
     * @param regime    Regime detector (updated).
     * @param bars      Bar buffer (for price action + volume).
     * @param price     Current mid price (bid+ask)/2.
     * @param spread    Current spread in price units.
     * @param max_spread Maximum allowed spread in price units.
     * @param session   Session code (ATLAS_SESSION_*).
     * @param bar_progress Bar progress 0.0..1.0 (elapsed / period).
     */
    void Extract(double &features[], int &count,
                 const IndicatorCache &cache,
                 const TrendDetector &trend,
                 const RegimeDetector &regime,
                 const BarBuffer &bars,
                 const double price,
                 const double spread,
                 const double max_spread,
                 const int session,
                 const double bar_progress) const;
};

//+------------------------------------------------------------------+
//| FeatureExtractor implementation                                   |
//+------------------------------------------------------------------+

FeatureExtractor::FeatureExtractor(void)
{
    m_logger = NULL;
}

//+------------------------------------------------------------------+
void FeatureExtractor::Initialize(ILogger *logger)
{
    m_logger = logger;
}

//+------------------------------------------------------------------+
double FeatureExtractor::Clamp(const double v, const double lo, const double hi) const
{
    if(v < lo) return lo;
    if(v > hi) return hi;
    return v;
}

//+------------------------------------------------------------------+
double FeatureExtractor::SafeDiv(const double a, const double b) const
{
    if(b <= 0.0) return 0.0;
    return a / b;
}

//+------------------------------------------------------------------+
void FeatureExtractor::Extract(double &features[], int &count,
                               const IndicatorCache &cache,
                               const TrendDetector &trend,
                               const RegimeDetector &regime,
                               const BarBuffer &bars,
                               const double price,
                               const double spread,
                               const double max_spread,
                               const int session,
                               const double bar_progress) const
{
    //--- Initialize all features to 0.0
    for(int i = 0; i < ATLAS_FEATURE_SIZE; i++)
        features[i] = 0.0;

    double atr = cache.ATR();
    if(atr <= 0.0) atr = price * 0.001;  //--- Fallback to avoid div-by-zero

    //==============================================================
    // PRICE / MA FEATURES (0-4)
    //==============================================================
    //--- 0: Price vs EMA20 (z-score, [-1,1])
    features[0] = Clamp(SafeDiv(price - cache.EMAFast(), atr), -1.0, 1.0);

    //--- 1: Price vs EMA50 (z-score, [-1,1])
    features[1] = Clamp(SafeDiv(price - cache.EMASlow(), atr), -1.0, 1.0);

    //--- 2: EMA20 slope / ATR ([-1,1])
    double ema_fast_slope = cache.EMAFast() - cache.EMAFastPrev();
    features[2] = Clamp(SafeDiv(ema_fast_slope, atr), -1.0, 1.0);

    //--- 3: EMA50 slope / ATR ([-1,1])
    double ema_slow_slope = cache.EMASlow() - cache.EMASlowPrev();
    features[3] = Clamp(SafeDiv(ema_slow_slope, atr), -1.0, 1.0);

    //--- 4: EMA20 vs EMA50 separation / ATR ([-1,1])
    double ema_separation = cache.EMAFast() - cache.EMASlow();
    features[4] = Clamp(SafeDiv(ema_separation, atr), -1.0, 1.0);

    //==============================================================
    // VOLATILITY FEATURES (5-8)
    //==============================================================
    //--- 5: ATR / price ([0,1])
    features[5] = Clamp(SafeDiv(atr, price) * 100.0, 0.0, 1.0);

    //--- 6: ATR vs prev ATR ratio ([0,1])
    double atr_ratio = SafeDiv(atr, cache.ATRPrev());
    features[6] = Clamp(atr_ratio / 3.0, 0.0, 1.0);

    //--- 7: BB width / middle ([0,1])
    double bb_width = (cache.BBUpper() - cache.BBLower());
    features[7] = Clamp(SafeDiv(bb_width, cache.BBMiddle()) * 100.0, 0.0, 1.0);

    //--- 8: BB %B ([0,1])
    double bb_range = cache.BBUpper() - cache.BBLower();
    double pct_b = (bb_range > 0.0) ? (price - cache.BBLower()) / bb_range : 0.5;
    features[8] = Clamp(pct_b, 0.0, 1.0);

    //==============================================================
    // MOMENTUM FEATURES (9-15)
    //==============================================================
    //--- 9: RSI / 100 ([0,1])
    features[9] = Clamp(cache.RSI() / 100.0, 0.0, 1.0);

    //--- 10: RSI delta ([-1,1])
    double rsi_delta = cache.RSI() - cache.RSIPrev();
    features[10] = Clamp(rsi_delta / 50.0, -1.0, 1.0);

    //--- 11: MACD histogram / ATR ([-1,1])
    double macd_hist = cache.MACDMain() - cache.MACDSignal();
    features[11] = Clamp(SafeDiv(macd_hist, atr), -1.0, 1.0);

    //--- 12: MACD signal cross direction (-1, 0, 1)
    double d_now  = cache.MACDMain() - cache.MACDSignal();
    double d_prev = cache.MACDMainPrev() - cache.MACDSignalPrev();
    if(d_now > 0 && d_prev <= 0)       features[12] = 1.0;   //--- Bullish cross
    else if(d_now < 0 && d_prev >= 0)  features[12] = -1.0;  //--- Bearish cross
    else                                features[12] = 0.0;

    //--- 13: CCI / 200 ([-1,1])
    features[13] = Clamp(cache.CCI() / 200.0, -1.0, 1.0);

    //--- 14: Stochastic %K / 100 ([0,1])
    features[14] = Clamp(cache.StochK() / 100.0, 0.0, 1.0);

    //--- 15: Stochastic %D / 100 ([0,1])
    features[15] = Clamp(cache.StochD() / 100.0, 0.0, 1.0);

    //==============================================================
    // TREND FEATURES (16-21)
    //==============================================================
    //--- 16: Trend direction (-1, 0, 1)
    features[16] = (double)trend.Direction();

    //--- 17: Trend strength / 100 ([0,1])
    features[17] = Clamp((double)trend.Strength() / 100.0, 0.0, 1.0);

    //--- 18: Trend duration / 50 ([0,1])
    features[18] = Clamp((double)trend.Duration() / 50.0, 0.0, 1.0);

    //--- 19: ADX / 100 ([0,1])
    features[19] = Clamp(cache.ADX() / 100.0, 0.0, 1.0);

    //--- 20: DI+ / (DI+ + DI-) ([0,1])
    double di_sum = cache.DIPlus() + cache.DIMinus();
    features[20] = (di_sum > 0.0) ? Clamp(cache.DIPlus() / di_sum, 0.0, 1.0) : 0.5;

    //--- 21: DI- / (DI+ + DI-) ([0,1])
    features[21] = (di_sum > 0.0) ? Clamp(cache.DIMinus() / di_sum, 0.0, 1.0) : 0.5;

    //==============================================================
    // PRICE ACTION FEATURES (22-25) — from last closed bar
    //==============================================================
    BarData last_bar;
    if(bars.GetNewest(last_bar))
    {
        double bar_range = last_bar.high - last_bar.low;
        if(bar_range > 0.0)
        {
            //--- 22: Body ratio ([0,1])
            double body = MathAbs(last_bar.close - last_bar.open);
            features[22] = Clamp(body / bar_range, 0.0, 1.0);

            //--- 23: Upper shadow ratio ([0,1])
            double upper_shadow = last_bar.high - MathMax(last_bar.close, last_bar.open);
            features[23] = Clamp(upper_shadow / bar_range, 0.0, 1.0);

            //--- 24: Lower shadow ratio ([0,1])
            double lower_shadow = MathMin(last_bar.close, last_bar.open) - last_bar.low;
            features[24] = Clamp(lower_shadow / bar_range, 0.0, 1.0);

            //--- 25: Bar range / ATR ([0,1])
            features[25] = Clamp(SafeDiv(bar_range, atr) / 2.0, 0.0, 1.0);
        }
    }

    //==============================================================
    // VOLUME FEATURES (26-27)
    //==============================================================
    if(bars.Count() >= 2)
    {
        long vol_curr = bars.GetTickVolume(bars.Count() - 1);
        long vol_prev = bars.GetTickVolume(bars.Count() - 2);

        //--- 26: Tick volume change rate ([-1,1])
        if(vol_prev > 0)
        {
            double vol_change = (double)(vol_curr - vol_prev) / (double)vol_prev;
            features[26] = Clamp(vol_change, -1.0, 1.0);
        }

        //--- 27: Tick volume / 20-bar avg ([0,1])
        double avg_vol = bars.AverageVolume(20);
        if(avg_vol > 0.0)
            features[27] = Clamp((double)vol_curr / avg_vol / 2.0, 0.0, 1.0);
    }

    //==============================================================
    // SPREAD / MARKET QUALITY (28)
    //==============================================================
    //--- 28: Spread / max spread ([0,1])
    if(max_spread > 0.0)
        features[28] = Clamp(spread / max_spread, 0.0, 1.0);

    //==============================================================
    // CONTEXT FEATURES (29-31)
    //==============================================================
    //--- 29: Session state / 4 ([0,1])
    features[29] = Clamp((double)session / 4.0, 0.0, 1.0);

    //--- 30: Market regime / 7 ([0,1])
    features[30] = Clamp((double)regime.CurrentRegime() / 7.0, 0.0, 1.0);

    //--- 31: Bar progress ([0,1])
    features[31] = Clamp(bar_progress, 0.0, 1.0);

    count = ATLAS_FEATURE_SIZE;
}

#endif // ATLAS_FEATURE_EXTRACTOR_MQH
//+------------------------------------------------------------------+
