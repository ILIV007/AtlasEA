//+------------------------------------------------------------------+
//|                  Trading/Filters/MarketStateFilter.mqh           |
//|       AtlasEA v0.2.2 - Market State / Regime Filter              |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_STATE_FILTER_MQH
#define ATLAS_MARKET_STATE_FILTER_MQH

#include "IFilter.mqh"
#include "../../Engines/MarketEngine/RegimeDetector.mqh"

/**
 * @brief Market state category codes (simplified from 8 regimes to 4 categories).
 * Used by the MarketStateFilter for allow/deny configuration.
 */
#define ATLAS_MSC_TRENDING    0   ///< Regimes: TRENDING, PULLBACK
#define ATLAS_MSC_RANGING     1   ///< Regimes: RANGING, ACCUMULATION, DISTRIBUTION
#define ATLAS_MSC_FAST_MARKET 2   ///< Regimes: VOLATILE, BREAKOUT
#define ATLAS_MSC_SLOW_MARKET 3   ///< Regime: QUIET
#define ATLAS_MSC_COUNT       4

/**
 * @struct MarketStateFilterConfig
 * @brief Configuration for the market state filter.
 */
struct MarketStateFilterConfig
{
    FilterConfig base;                  ///< Base config
    bool allow_trending;                ///< Allow trending markets
    bool allow_ranging;                 ///< Allow ranging markets
    bool allow_fast_market;             ///< Allow fast/volatile markets
    bool allow_slow_market;             ///< Allow slow/quiet markets

    MarketStateFilterConfig(void)
    {
        base.enabled         = true;
        base.priority        = 40;
        base.reason_code     = ATLAS_FR_REGIME_NOT_ALLOWED;
        allow_trending       = true;
        allow_ranging        = true;
        allow_fast_market    = false;  // Block fast market by default (risky)
        allow_slow_market    = true;
    }
};

/**
 * @class MarketStateFilter
 * @brief Allows or blocks signals based on the current market regime.
 *
 * SOLE RESPONSIBILITY: check that the current market regime is in the
 * allowed list.
 *
 * The RegimeDetector classifies the market into 8 regimes (TRENDING,
 * RANGING, VOLATILE, QUIET, BREAKOUT, PULLBACK, ACCUMULATION,
 * DISTRIBUTION). This filter maps those 8 regimes into 4 simplified
 * categories:
 *
 *   TRENDING:    TRENDING, PULLBACK
 *   RANGING:     RANGING, ACCUMULATION, DISTRIBUTION
 *   FAST_MARKET: VOLATILE, BREAKOUT
 *   SLOW_MARKET: QUIET
 *
 * The regime is read from MarketState.features[30], which is stored
 * as a normalized value [0, 1] (regime_code / 7.0). This filter
 * reconstructs the regime code and maps it to a category.
 *
 * The filter does NOT calculate indicators — it reads the pre-computed
 * regime from the MarketState.
 *
 * Memory: ~80 bytes (config only).
 */
class MarketStateFilter : public IFilter
{
private:
    ILogger                   *m_logger;
    MarketStateFilterConfig    m_config;
    bool                       m_initialized;

public:
    /**
     * @brief Constructor.
     */
    MarketStateFilter(void)
    {
        m_logger      = NULL;
        m_initialized = false;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "MarketStateFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetMarketStateConfig(const MarketStateFilterConfig &config) { m_config = config; }
    MarketStateFilterConfig GetMarketStateConfig(void) const { return m_config; }

    virtual void SetLogger(ILogger *logger) override { m_logger = logger; }

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized = false;
    }

    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) override
    {
        if(!m_config.base.enabled)
            return FilterResult::Skip(GetName(), ATLAS_FR_FILTER_DISABLED, "disabled");

        //--- Extract the regime code from MarketState.features[30]
        //--- features[30] = regime_code / 7.0 (normalized [0, 1])
        int regime_code = ATLAS_REGIME_QUIET; // Default
        if(market.feature_count > 30)
        {
            double norm = market.features[30];
            if(MathIsValidNumber(norm) && norm >= 0.0 && norm <= 1.0)
                regime_code = (int)(norm * 7.0 + 0.5);
            else
                return FilterResult::Block(GetName(), ATLAS_FR_REGIME_UNKNOWN,
                    "regime feature is invalid: " + DoubleToString(norm, 3));
        }
        else
        {
            //--- Fallback: use is_fast_market + trend_strength to classify
            if(market.is_fast_market)
                regime_code = ATLAS_REGIME_VOLATILE;
            else if(market.trend_strength > 30 && market.trend_direction != 0)
                regime_code = ATLAS_REGIME_TRENDING;
            else if(market.trend_strength < 20)
                regime_code = ATLAS_REGIME_QUIET;
            else
                regime_code = ATLAS_REGIME_RANGING;
        }

        //--- Map regime to category
        int category = MapRegimeToCategory(regime_code);

        //--- Check if the category is allowed
        bool allowed = false;
        string category_name = CategoryName(category);

        switch(category)
        {
            case ATLAS_MSC_TRENDING:    allowed = m_config.allow_trending;    break;
            case ATLAS_MSC_RANGING:     allowed = m_config.allow_ranging;     break;
            case ATLAS_MSC_FAST_MARKET: allowed = m_config.allow_fast_market; break;
            case ATLAS_MSC_SLOW_MARKET: allowed = m_config.allow_slow_market; break;
            default:
                return FilterResult::Block(GetName(), ATLAS_FR_REGIME_UNKNOWN,
                    "unknown regime category");
        }

        if(!allowed)
            return FilterResult::Block(GetName(), ATLAS_FR_REGIME_NOT_ALLOWED,
                category_name + " not allowed (regime=" +
                IntegerToString(regime_code) + ")");

        return FilterResult::Pass(GetName());
    }

    /**
     * @brief Get the current market category name (for diagnostics).
     */
    static string CategoryName(const int category)
    {
        switch(category)
        {
            case ATLAS_MSC_TRENDING:    return "TRENDING";
            case ATLAS_MSC_RANGING:     return "RANGING";
            case ATLAS_MSC_FAST_MARKET: return "FAST_MARKET";
            case ATLAS_MSC_SLOW_MARKET: return "SLOW_MARKET";
        }
        return "UNKNOWN";
    }

private:
    /**
     * @brief Map an 8-regime code to a 4-category code.
     */
    int MapRegimeToCategory(const int regime) const
    {
        switch(regime)
        {
            case ATLAS_REGIME_TRENDING:
            case ATLAS_REGIME_PULLBACK:
                return ATLAS_MSC_TRENDING;

            case ATLAS_REGIME_RANGING:
            case ATLAS_REGIME_ACCUMULATION:
            case ATLAS_REGIME_DISTRIBUTION:
                return ATLAS_MSC_RANGING;

            case ATLAS_REGIME_VOLATILE:
            case ATLAS_REGIME_BREAKOUT:
                return ATLAS_MSC_FAST_MARKET;

            case ATLAS_REGIME_QUIET:
                return ATLAS_MSC_SLOW_MARKET;
        }
        return ATLAS_MSC_SLOW_MARKET; // Default to slow
    }
};

#endif // ATLAS_MARKET_STATE_FILTER_MQH
//+------------------------------------------------------------------+
