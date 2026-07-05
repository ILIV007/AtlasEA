//+------------------------------------------------------------------+
//|                   Strategies/RangeStrategy.mqh                   |
//|       AtlasEA v1.0 Step 3 - Range Strategy                       |
//+------------------------------------------------------------------+
#ifndef ATLAS_RANGE_STRATEGY_MQH
#define ATLAS_RANGE_STRATEGY_MQH

#include "BaseStrategy.mqh"
#include "VolatilityFilter.mqh"

/**
 * @struct RangeConfig
 * @brief Configuration for the Range strategy.
 */
struct RangeConfig
{
    double range_min_width_atr;   ///< Min range width in ATR units (must be range)
    double range_max_width_atr;   ///< Max range width in ATR (if wider, not range)
    double fade_min_atr;          ///< Min distance from range edge to fade
    double fade_max_atr;          ///< Max distance (don't fade too far out)
    int    adx_max_for_range;     ///< Max ADX (trend strength) for range market
    double base_confidence;
    double max_confidence;
    bool   use_bollinger;         ///< Use Bollinger Bands for range edges

    RangeConfig(void)
    {
        range_min_width_atr = 0.3;
        range_max_width_atr = 2.0;
        fade_min_atr        = 0.1;
        fade_max_atr        = 0.5;
        adx_max_for_range   = 25;
        base_confidence     = 0.45;
        max_confidence      = 0.75;
        use_bollinger       = true;
    }
};

/**
 * @class RangeStrategy
 * @brief Trades range fade entries in ranging markets.
 *
 * Signal logic (BUY fade of range low):
 *   1. Market is ranging (trend_strength < adx_max_for_range)
 *   2. Price is near range low (within fade_min to fade_max ATR)
 *   3. Price is showing rejection (bouncing back up)
 *   4. Volatility is within acceptable bounds
 *
 * SELL is the mirror image (fade of range high).
 *
 * Uses MarketState fields:
 *   - bb_upper, bb_middle, bb_lower (Bollinger Bands for range edges)
 *   - trend_strength (to detect range: low strength = range)
 *   - atr_14 (for distance normalization)
 *   - bid, ask (current price)
 *
 * Rejects trend markets (trend_strength >= adx_max_for_range).
 *
 * Performance: O(1), no allocation.
 */
class RangeStrategy : public BaseStrategy
{
private:
    RangeConfig m_rng_config;
    VolatilityFilter m_vol_filter;

public:
    RangeStrategy(const int id)
        : BaseStrategy(id, "1.0.0")
    {
    }

    void SetRangeConfig(const RangeConfig &config) { m_rng_config = config; }
    RangeConfig GetRangeConfig(void) const { return m_rng_config; }

    /**
     * @brief Set the volatility filter configuration.
     */
    void SetVolatilityFilter(const VolatilityFilterConfig &config)
    {
        m_vol_filter.SetConfig(config);
    }

    virtual string Name(void) const override { return "RangeStrategy"; }

    virtual void Warmup(void) override { m_warmed_up = true; }

    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();
        double atr = ctx.GetATR();
        double price = ctx.GetMidPrice();

        if(atr <= 0.0 || price <= 0.0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Reject trend markets
        if(market.trend_strength >= m_rng_config.adx_max_for_range)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Volatility filter
        if(!m_vol_filter.Passes(market))
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_FILTER_REJECT);

        //--- Get Bollinger Band values from features or market state
        //--- Bollinger values are in IndicatorCache, but not directly in MarketState.
        //--- We use the OHLC + ATR to estimate range edges.
        //--- Range high = recent high, range low = recent low
        //--- For simplicity, use Bollinger if available via features:
        //--- features[20] = %B (position within bands, 0-1)
        //--- features[21] = BB width / ATR

        double bb_pct_b = ctx.GetFeature(20); // %B (0 = lower band, 1 = upper band)
        double bb_width_atr = ctx.GetFeature(21); // BB width / ATR

        //--- Range width check
        if(bb_width_atr < m_rng_config.range_min_width_atr ||
           bb_width_atr > m_rng_config.range_max_width_atr)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        int direction = ATLAS_ORDER_NONE;
        double confidence = 0.0;

        //--- Fade lower band (BUY)
        //--- %B < 0.2 means price is near lower band
        if(bb_pct_b < 0.2 && bb_pct_b >= -0.1)
        {
            //--- Distance from lower band in ATR units
            double dist_atr = (0.2 - bb_pct_b) * bb_width_atr;
            if(dist_atr >= m_rng_config.fade_min_atr &&
               dist_atr <= m_rng_config.fade_max_atr)
            {
                //--- Check rejection: close should be above low (bouncing)
                if(market.close > market.low)
                {
                    direction = ATLAS_ORDER_BUY;
                    double dist_factor = MathMin(1.0, dist_atr / m_rng_config.fade_max_atr);
                    confidence = m_rng_config.base_confidence +
                                (m_rng_config.max_confidence - m_rng_config.base_confidence) *
                                dist_factor;
                }
            }
        }
        //--- Fade upper band (SELL)
        //--- %B > 0.8 means price is near upper band
        else if(bb_pct_b > 0.8 && bb_pct_b <= 1.1)
        {
            double dist_atr = (bb_pct_b - 0.8) * bb_width_atr;
            if(dist_atr >= m_rng_config.fade_min_atr &&
               dist_atr <= m_rng_config.fade_max_atr)
            {
                //--- Check rejection: close should be below high (bouncing)
                if(market.close < market.high)
                {
                    direction = ATLAS_ORDER_SELL;
                    double dist_factor = MathMin(1.0, dist_atr / m_rng_config.fade_max_atr);
                    confidence = m_rng_config.base_confidence +
                                (m_rng_config.max_confidence - m_rng_config.base_confidence) *
                                dist_factor;
                }
            }
        }

        if(direction == ATLAS_ORDER_NONE)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        confidence = ClampConfidence(confidence);

        if(direction == ATLAS_ORDER_BUY)
            return BuildBuyVote(ctx, confidence, ATLAS_STRAT_REASON_RANGE_FADE_BUY);
        else
            return BuildSellVote(ctx, confidence, ATLAS_STRAT_REASON_RANGE_FADE_SELL);
    }
};

#endif // ATLAS_RANGE_STRATEGY_MQH
//+------------------------------------------------------------------+
