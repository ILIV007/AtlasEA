//+------------------------------------------------------------------+
//|                   Interfaces/IMarketClassifier.mqh               |
//|       AtlasEA v1.0 Step 4 - Market Classifier Interface          |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMARKET_CLASSIFIER_MQH
#define ATLAS_IMARKET_CLASSIFIER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Market regime codes (simplified for profile selection).
 * These are higher-level than the 8 RegimeDetector codes.
 */
#define ATLAS_REGIME_TRENDING        0   ///< Strong directional move
#define ATLAS_REGIME_RANGING         1   ///< Sideways, no clear direction
#define ATLAS_REGIME_HIGH_VOLATILITY 2   ///< Abnormal volatility (fast market)
#define ATLAS_REGIME_LOW_VOLATILITY  3   ///< Very low volatility (quiet)
#define ATLAS_REGIME_BREAKOUT        4   ///< Price breaking out of range
#define ATLAS_REGIME_NEWS_PROTECTION 5   ///< News event detected (protected)
#define ATLAS_REGIME_UNKNOWN         6   ///< Cannot classify

#define ATLAS_REGIME_PROFILE_COUNT   7   ///< Total regime codes

/**
 * @struct MarketClassification
 * @brief Result of market classification.
 */
struct MarketClassification
{
    int    regime;              ///< ATLAS_REGIME_* code
    string regime_name;         ///< Human-readable name
    int    confidence;          ///< Classification confidence [0, 100]
    int    trend_strength;      ///< Trend strength [0, 100]
    double volatility_index;    ///< Volatility index value
    bool   is_fast_market;      ///< Fast market flag
    bool   is_news_time;        ///< News event flag
    datetime timestamp;         ///< Classification time
    long   snapshot_id;         ///< Market snapshot ID

    MarketClassification(void)
    {
        regime           = ATLAS_REGIME_UNKNOWN;
        regime_name      = "UNKNOWN";
        confidence       = 0;
        trend_strength   = 0;
        volatility_index = 0.0;
        is_fast_market   = false;
        is_news_time     = false;
        timestamp        = 0;
        snapshot_id      = 0;
    }
};

/**
 * @class IMarketClassifier
 * @brief Interface for market regime classification.
 *
 * Implemented by MarketClassifier (Profiles/). Consumed by
 * ProfileSelector and ProfileManager.
 *
 * Contract:
 *   - Uses ONLY existing MarketState data (no indicator recalculation).
 *   - O(1) classification.
 *   - Deterministic (same input → same output).
 *   - No MT5 API calls.
 *   - No heap allocation.
 */
class IMarketClassifier
{
public:
    /**
     * @brief Classify the current market regime.
     * @param market Current market state (read-only).
     * @return MarketClassification result.
     */
    virtual MarketClassification Classify(const MarketState &market) = 0;

    /**
     * @brief Get the name of a regime code.
     */
    virtual string RegimeName(const int regime) const = 0;

    /**
     * @brief Check if a news event is currently active.
     * Override in subclasses if news detection is implemented.
     */
    virtual bool IsNewsTime(void) const = 0;

    /**
     * @brief Set the news time flag (called by CoreEngine if news calendar is available).
     */
    virtual void SetNewsTime(const bool active) = 0;

    virtual ~IMarketClassifier(void) {}
};

/**
 * @brief Get the name of a regime code (free function).
 */
string MarketRegimeName(const int regime)
{
    switch(regime)
    {
        case ATLAS_REGIME_TRENDING:        return "TRENDING";
        case ATLAS_REGIME_RANGING:         return "RANGING";
        case ATLAS_REGIME_HIGH_VOLATILITY: return "HIGH_VOLATILITY";
        case ATLAS_REGIME_LOW_VOLATILITY:  return "LOW_VOLATILITY";
        case ATLAS_REGIME_BREAKOUT:        return "BREAKOUT";
        case ATLAS_REGIME_NEWS_PROTECTION: return "NEWS_PROTECTION";
        case ATLAS_REGIME_UNKNOWN:         return "UNKNOWN";
    }
    return "UNKNOWN";
}

#endif // ATLAS_IMARKET_CLASSIFIER_MQH
//+------------------------------------------------------------------+
