//+------------------------------------------------------------------+
//|                    Trading/Filters/SpreadFilter.mqh              |
//|       AtlasEA v0.2.2 - Spread Filter                             |
//+------------------------------------------------------------------+
#ifndef ATLAS_SPREAD_FILTER_MQH
#define ATLAS_SPREAD_FILTER_MQH

#include "IFilter.mqh"

/**
 * @struct SpreadFilterConfig
 * @brief Configuration for the spread filter.
 */
struct SpreadFilterConfig
{
    FilterConfig base;              ///< Base config (enabled, priority, reason_code)
    double max_spread_points;       ///< Maximum allowed spread in points
    bool   use_market_state_spread; ///< Use MarketState.spread (true) or query broker (false)

    SpreadFilterConfig(void)
    {
        base.enabled       = true;
        base.priority      = 10;
        base.reason_code   = ATLAS_FR_SPREAD_TOO_HIGH;
        max_spread_points  = 50.0;       // 50 points
        use_market_state_spread = true;  // Use cached value (no broker call)
    }
};

/**
 * @class SpreadFilter
 * @brief Rejects signals when the spread exceeds the configured maximum.
 *
 * SOLE RESPONSIBILITY: check that the current spread is within limits.
 *
 * The spread is read from MarketState.spread (already computed by the
 * MarketEngine — no repeated SymbolInfo calls). If the market state's
 * spread is unavailable or invalid, the filter falls back to querying
 * the broker adapter (SymbolBid/Ask/Point).
 *
 * The filter compares spread in POINTS (spread / point) against the
 * configured max_spread_points.
 *
 * Memory: ~100 bytes (config + cached point value).
 */
class SpreadFilter : public IFilter
{
private:
    ILogger            *m_logger;
    SpreadFilterConfig  m_config;
    double              m_cached_point;  ///< Cached point value (avoids repeated SymbolPoint calls)
    bool                m_initialized;

public:
    /**
     * @brief Constructor.
     */
    SpreadFilter(void)
    {
        m_logger      = NULL;
        m_cached_point = 0.0;
        m_initialized  = false;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "SpreadFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    /**
     * @brief Set the spread-specific configuration.
     */
    void SetSpreadConfig(const SpreadFilterConfig &config) { m_config = config; }

    /**
     * @brief Get the spread-specific configuration.
     */
    SpreadFilterConfig GetSpreadConfig(void) const { return m_config; }

    virtual void SetLogger(ILogger *logger) override { m_logger = logger; }

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized  = false;
        m_cached_point = 0.0;
    }

    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) override
    {
        //--- Disabled filter → SKIP
        if(!m_config.base.enabled)
            return FilterResult::Skip(GetName(), ATLAS_FR_FILTER_DISABLED, "disabled");

        //--- Get the spread
        double spread = 0.0;
        double point  = 0.0;

        if(m_config.use_market_state_spread && MathIsValidNumber(market.spread))
        {
            spread = market.spread;
            point  = market.point;
        }
        else if(broker != NULL)
        {
            //--- Fallback: query broker (cached point)
            if(m_cached_point <= 0.0)
                m_cached_point = broker.SymbolPoint();
            point = m_cached_point;
            if(point > 0.0)
                spread = (broker.SymbolAsk() - broker.SymbolBid());
        }

        //--- Validate spread
        if(!MathIsValidNumber(spread) || spread < 0.0)
            return FilterResult::Block(GetName(), ATLAS_FR_SPREAD_INVALID,
                "spread is NaN or negative");

        //--- Convert to points
        if(point <= 0.0) point = 0.00001; // Fallback
        double spread_points = spread / point;

        //--- Check against max
        if(spread_points > m_config.max_spread_points)
            return FilterResult::Block(GetName(), ATLAS_FR_SPREAD_TOO_HIGH,
                "spread " + DoubleToString(spread_points, 1) + " > max " +
                DoubleToString(m_config.max_spread_points, 1));

        return FilterResult::Pass(GetName());
    }
};

#endif // ATLAS_SPREAD_FILTER_MQH
//+------------------------------------------------------------------+
