//+------------------------------------------------------------------+
//|                   Profiles/MarketClassifier.mqh                  |
//|       AtlasEA v1.0 Step 4 - Market Regime Classifier             |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_CLASSIFIER_MQH
#define ATLAS_MARKET_CLASSIFIER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IMarketClassifier.mqh"

/**
 * @struct ClassifierConfig
 * @brief Configuration for the market classifier.
 */
struct ClassifierConfig
{
    int    trend_strength_threshold;  ///< Min trend strength for TRENDING
    int    trend_strength_range_max;  ///< Max trend strength for RANGING
    double volatility_high_threshold; ///< Vol index above this = HIGH_VOLATILITY
    double volatility_low_threshold;  ///< Vol index below this = LOW_VOLATILITY
    double atr_price_ratio_high;      ///< ATR/price above this = HIGH_VOLATILITY
    double atr_price_ratio_low;       ///< ATR/price below this = LOW_VOLATILITY
    int    breakout_lookback_bars;    ///< Bars to look back for breakout detection

    ClassifierConfig(void)
    {
        trend_strength_threshold  = 40;
        trend_strength_range_max  = 20;
        volatility_high_threshold = 8.0;
        volatility_low_threshold  = 0.5;
        atr_price_ratio_high      = 0.005;  // 0.5%
        atr_price_ratio_low       = 0.0005; // 0.05%
        breakout_lookback_bars    = 20;
    }
};

/**
 * @class MarketClassifier
 * @brief Classifies the current market regime using existing MarketState data.
 *
 * SOLE RESPONSIBILITY: determine the current market regime from
 * pre-computed MarketState fields. Does NOT recalculate any indicators.
 *
 * Classification priority (first match wins):
 *   1. NEWS_PROTECTION — if news time flag is set
 *   2. HIGH_VOLATILITY — if is_fast_market OR volatility_index very high
 *   3. BREAKOUT — if price is at Bollinger extreme (features[20] %B > 0.95 or < 0.05)
 *   4. TRENDING — if trend_strength >= threshold AND trend_direction != 0
 *   5. RANGING — if trend_strength <= range_max
 *   6. LOW_VOLATILITY — if volatility_index very low
 *   7. UNKNOWN — cannot classify
 *
 * Uses ONLY existing MarketState fields:
 *   - is_fast_market (pre-computed by MarketEngine)
 *   - volatility_index (pre-computed)
 *   - trend_direction (pre-computed by TrendDetector)
 *   - trend_strength (pre-computed)
 *   - atr_14 (pre-computed by ATRCalculator)
 *   - features[20] = Bollinger %B (pre-computed by FeatureExtractor)
 *   - bid, ask (for price reference)
 *
 * Performance: O(1), no allocation, no indicator calculation.
 */
class MarketClassifier : public IMarketClassifier
{
private:
    ILogger         *m_logger;
    ClassifierConfig m_config;
    bool             m_news_time;
    bool             m_initialized;

public:
    /**
     * @brief Constructor.
     */
    MarketClassifier(void)
    {
        m_logger      = NULL;
        m_news_time   = false;
        m_initialized = false;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const ClassifierConfig &config) { m_config = config; }

    /**
     * @brief Get the configuration.
     */
    const ClassifierConfig& GetConfig(void) const { return m_config; }

    //=== IMarketClassifier implementation ===

    virtual MarketClassification Classify(const MarketState &market) override
    {
        MarketClassification result;
        result.timestamp        = market.timestamp;
        result.snapshot_id      = market.snapshot_id;
        result.trend_strength   = market.trend_strength;
        result.volatility_index = market.volatility_index;
        result.is_fast_market   = market.is_fast_market;
        result.is_news_time     = m_news_time;

        //=== 1. NEWS_PROTECTION (highest priority) ===
        if(m_news_time)
        {
            result.regime      = ATLAS_REGIME_NEWS_PROTECTION;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 100;
            return result;
        }

        //=== 2. HIGH_VOLATILITY ===
        if(market.is_fast_market ||
           (MathIsValidNumber(market.volatility_index) &&
            market.volatility_index > m_config.volatility_high_threshold))
        {
            result.regime      = ATLAS_REGIME_HIGH_VOLATILITY;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 90;
            return result;
        }

        //--- Compute ATR/price ratio for additional volatility check
        double price = (market.bid + market.ask) / 2.0;
        double atr_ratio = 0.0;
        if(price > 0.0 && MathIsValidNumber(market.atr_14) && market.atr_14 > 0.0)
            atr_ratio = market.atr_14 / price;

        if(atr_ratio > m_config.atr_price_ratio_high)
        {
            result.regime      = ATLAS_REGIME_HIGH_VOLATILITY;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 85;
            return result;
        }

        //=== 3. BREAKOUT (Bollinger %B extreme) ===
        double pct_b = 0.5;
        if(market.feature_count > 20)
            pct_b = market.features[20];

        if(pct_b > 0.95 || pct_b < 0.05)
        {
            result.regime      = ATLAS_REGIME_BREAKOUT;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 75;
            return result;
        }

        //=== 4. TRENDING ===
        if(market.trend_direction != 0 &&
           market.trend_strength >= m_config.trend_strength_threshold)
        {
            result.regime      = ATLAS_REGIME_TRENDING;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 60 + (market.trend_strength - m_config.trend_strength_threshold);
            if(result.confidence > 100) result.confidence = 100;
            return result;
        }

        //=== 5. LOW_VOLATILITY ===
        if(MathIsValidNumber(market.volatility_index) &&
           market.volatility_index < m_config.volatility_low_threshold)
        {
            result.regime      = ATLAS_REGIME_LOW_VOLATILITY;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 70;
            return result;
        }

        if(atr_ratio > 0.0 && atr_ratio < m_config.atr_price_ratio_low)
        {
            result.regime      = ATLAS_REGIME_LOW_VOLATILITY;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 65;
            return result;
        }

        //=== 6. RANGING ===
        if(market.trend_strength <= m_config.trend_strength_range_max)
        {
            result.regime      = ATLAS_REGIME_RANGING;
            result.regime_name = MarketRegimeName(result.regime);
            result.confidence  = 55;
            return result;
        }

        //=== 7. UNKNOWN ===
        result.regime      = ATLAS_REGIME_UNKNOWN;
        result.regime_name = MarketRegimeName(result.regime);
        result.confidence  = 0;
        return result;
    }

    virtual string RegimeName(const int regime) const override
    {
        return MarketRegimeName(regime);
    }

    virtual bool IsNewsTime(void) const override
    {
        return m_news_time;
    }

    virtual void SetNewsTime(const bool active) override
    {
        m_news_time = active;
    }

    /**
     * @brief Initialize the classifier.
     */
    bool Initialize(void)
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("MarketClassifier", "Initialized");
        return true;
    }

    /**
     * @brief Shutdown the classifier.
     */
    void Shutdown(void)
    {
        m_initialized = false;
        m_news_time   = false;
    }

    bool IsInitialized(void) const { return m_initialized; }
};

#endif // ATLAS_MARKET_CLASSIFIER_MQH
//+------------------------------------------------------------------+
