//+------------------------------------------------------------------+
//|                   Strategies/VolatilityFilter.mqh                |
//|       AtlasEA v1.0 Step 3 - Reusable Volatility Filter           |
//+------------------------------------------------------------------+
#ifndef ATLAS_VOLATILITY_FILTER_STRAT_MQH
#define ATLAS_VOLATILITY_FILTER_STRAT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @struct VolatilityFilterConfig
 * @brief Configuration for the volatility filter.
 */
struct VolatilityFilterConfig
{
    double min_atr_points;         ///< Min ATR in points (0 = no limit)
    double max_atr_points;         ///< Max ATR in points (0 = no limit)
    double min_volatility_index;   ///< Min volatility index (0 = no limit)
    double max_volatility_index;   ///< Max volatility index (0 = no limit)
    bool   block_fast_market;      ///< Block when is_fast_market is true
    double min_atr_price_ratio;    ///< Min ATR/price ratio (0 = no limit)
    double max_atr_price_ratio;    ///< Max ATR/price ratio (0 = no limit)

    VolatilityFilterConfig(void)
    {
        min_atr_points       = 0.0;
        max_atr_points       = 0.0;
        min_volatility_index = 0.0;
        max_volatility_index = 0.0;
        block_fast_market    = true;
        min_atr_price_ratio  = 0.0;
        max_atr_price_ratio  = 0.0;
    }
};

/**
 * @class VolatilityFilter
 * @brief Reusable volatility filter for strategies.
 *
 * Rejects:
 *   - Low liquidity (ATR too low)
 *   - Extreme spread (via ATR/price ratio)
 *   - Extreme ATR (too volatile)
 *   - Abnormal volatility (volatility index out of range)
 *   - Fast market (is_fast_market flag)
 *
 * Usage:
 *   VolatilityFilter vf;
 *   vf.SetConfig(config);
 *   if(vf.Passes(market)) { ... proceed ... }
 *
 * Performance: O(1), no allocation, no recursion.
 */
class VolatilityFilter
{
private:
    VolatilityFilterConfig m_config;

public:
    /**
     * @brief Set the configuration.
     */
    void SetConfig(const VolatilityFilterConfig &config) { m_config = config; }

    /**
     * @brief Get the configuration.
     */
    const VolatilityFilterConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Check if the market passes the volatility filter.
     * @param market Current market state.
     * @return true if the market passes all volatility checks.
     */
    bool Passes(const MarketState &market) const
    {
        //--- Fast market check
        if(m_config.block_fast_market && market.is_fast_market)
            return false;

        //--- Volatility index range
        if(!MathIsValidNumber(market.volatility_index))
            return false;
        if(m_config.min_volatility_index > 0.0 &&
           market.volatility_index < m_config.min_volatility_index)
            return false;
        if(m_config.max_volatility_index > 0.0 &&
           market.volatility_index > m_config.max_volatility_index)
            return false;

        //--- ATR checks (need point for conversion)
        if(market.point <= 0.0) return true; // Can't check, allow
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0)
            return false;

        double atr_pts = market.atr_14 / market.point;
        if(m_config.min_atr_points > 0.0 && atr_pts < m_config.min_atr_points)
            return false;
        if(m_config.max_atr_points > 0.0 && atr_pts > m_config.max_atr_points)
            return false;

        //--- ATR/price ratio
        double price = (market.bid + market.ask) / 2.0;
        if(price > 0.0)
        {
            double ratio = market.atr_14 / price;
            if(m_config.min_atr_price_ratio > 0.0 &&
               ratio < m_config.min_atr_price_ratio)
                return false;
            if(m_config.max_atr_price_ratio > 0.0 &&
               ratio > m_config.max_atr_price_ratio)
                return false;
        }

        return true;
    }

    /**
     * @brief Get the reason the filter rejected (for diagnostics).
     * @return Reason string, or "OK" if passes.
     */
    string RejectReason(const MarketState &market) const
    {
        if(m_config.block_fast_market && market.is_fast_market)
            return "fast_market";
        if(!MathIsValidNumber(market.volatility_index))
            return "volatility_index_NaN";
        if(m_config.min_volatility_index > 0.0 &&
           market.volatility_index < m_config.min_volatility_index)
            return "volatility_index_too_low";
        if(m_config.max_volatility_index > 0.0 &&
           market.volatility_index > m_config.max_volatility_index)
            return "volatility_index_too_high";
        if(market.point > 0.0 && MathIsValidNumber(market.atr_14) && market.atr_14 > 0.0)
        {
            double atr_pts = market.atr_14 / market.point;
            if(m_config.min_atr_points > 0.0 && atr_pts < m_config.min_atr_points)
                return "atr_too_low";
            if(m_config.max_atr_points > 0.0 && atr_pts > m_config.max_atr_points)
                return "atr_too_high";
        }
        return "OK";
    }
};

#endif // ATLAS_VOLATILITY_FILTER_STRAT_MQH
//+------------------------------------------------------------------+
