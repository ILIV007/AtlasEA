//+------------------------------------------------------------------+
//|                 Trading/Filters/VolatilityFilter.mqh             |
//|       AtlasEA v0.2.2 - Volatility Filter                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_VOLATILITY_FILTER_MQH
#define ATLAS_VOLATILITY_FILTER_MQH

#include "IFilter.mqh"

/**
 * @struct VolatilityFilterConfig
 * @brief Configuration for the volatility filter.
 */
struct VolatilityFilterConfig
{
    FilterConfig base;                  ///< Base config
    double min_volatility_index;        ///< Reject if volatility_index < this
    double max_volatility_index;        ///< Reject if volatility_index > this
    double min_atr_fraction;            ///< Reject if ATR/price < this
    double max_atr_fraction;            ///< Reject if ATR/price > this (abnormal spike)
    bool   block_fast_market;           ///< Reject if is_fast_market is true

    VolatilityFilterConfig(void)
    {
        base.enabled               = true;
        base.priority              = 30;
        base.reason_code           = ATLAS_FR_VOLATILITY_TOO_LOW;
        min_volatility_index       = 0.5;   // Reject extremely low vol
        max_volatility_index       = 15.0;  // Reject abnormal spikes
        min_atr_fraction           = 0.0001; // ATR/price min (0.01%)
        max_atr_fraction           = 0.05;   // ATR/price max (5% — abnormal)
        block_fast_market          = true;
    }
};

/**
 * @class VolatilityFilter
 * @brief Rejects signals when volatility is too low or abnormally high.
 *
 * SOLE RESPONSIBILITY: check that the current market volatility is
 * within acceptable bounds.
 *
 * Uses ONLY already-available market data from MarketState:
 *   - volatility_index: composite volatility metric (pre-computed)
 *   - atr_14: ATR(14) value (pre-computed, non-repainting)
 *   - is_fast_market: flag for abnormal volatility spikes
 *
 * This filter does NOT calculate any indicators. It reads the
 * pre-computed values from the MarketState that the MarketEngine
 * already produced.
 *
 * Rejection criteria:
 *   1. volatility_index < min_volatility_index → VOLATILITY_TOO_LOW
 *   2. volatility_index > max_volatility_index → VOLATILITY_TOO_HIGH
 *   3. ATR/price < min_atr_fraction → VOLATILITY_TOO_LOW
 *   4. ATR/price > max_atr_fraction → VOLATILITY_TOO_HIGH
 *   5. is_fast_market == true (if block_fast_market) → VOLATILITY_TOO_HIGH
 *
 * Memory: ~100 bytes (config only).
 */
class VolatilityFilter : public IFilter
{
private:
    ILogger                 *m_logger;
    VolatilityFilterConfig   m_config;
    bool                     m_initialized;

public:
    /**
     * @brief Constructor.
     */
    VolatilityFilter(void)
    {
        m_logger      = NULL;
        m_initialized = false;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "VolatilityFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetVolatilityConfig(const VolatilityFilterConfig &config) { m_config = config; }
    VolatilityFilterConfig GetVolatilityConfig(void) const { return m_config; }

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

        //--- Check fast market flag (abnormal volatility spike)
        if(m_config.block_fast_market && market.is_fast_market)
            return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_TOO_HIGH,
                "fast market detected");

        //--- Validate volatility_index
        if(!MathIsValidNumber(market.volatility_index))
            return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_INVALID,
                "volatility_index is NaN/INF");

        //--- Check volatility_index range
        if(market.volatility_index < m_config.min_volatility_index)
            return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_TOO_LOW,
                "volatility_index " + DoubleToString(market.volatility_index, 2) +
                " < min " + DoubleToString(m_config.min_volatility_index, 2));

        if(market.volatility_index > m_config.max_volatility_index)
            return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_TOO_HIGH,
                "volatility_index " + DoubleToString(market.volatility_index, 2) +
                " > max " + DoubleToString(m_config.max_volatility_index, 2));

        //--- Validate ATR
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0)
            return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_INVALID,
                "atr_14 is NaN/INF or <= 0");

        //--- Check ATR/price fraction (need a reference price)
        double ref_price = (market.bid + market.ask) / 2.0;
        if(ref_price <= 0.0) ref_price = market.bid;
        if(ref_price <= 0.0) ref_price = market.ask;

        if(ref_price > 0.0)
        {
            double atr_fraction = market.atr_14 / ref_price;

            if(atr_fraction < m_config.min_atr_fraction)
                return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_TOO_LOW,
                    "ATR/price " + DoubleToString(atr_fraction * 100.0, 4) +
                    "% < min " + DoubleToString(m_config.min_atr_fraction * 100.0, 4) + "%");

            if(atr_fraction > m_config.max_atr_fraction)
                return FilterResult::Block(GetName(), ATLAS_FR_VOLATILITY_TOO_HIGH,
                    "ATR/price " + DoubleToString(atr_fraction * 100.0, 4) +
                    "% > max " + DoubleToString(m_config.max_atr_fraction * 100.0, 4) + "%");
        }

        return FilterResult::Pass(GetName());
    }
};

#endif // ATLAS_VOLATILITY_FILTER_MQH
//+------------------------------------------------------------------+
