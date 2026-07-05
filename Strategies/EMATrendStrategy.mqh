//+------------------------------------------------------------------+
//|                  Strategies/EMATrendStrategy.mqh                 |
//|       AtlasEA v1.0 Step 3 - EMA Trend Strategy                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_EMA_TREND_STRATEGY_MQH
#define ATLAS_EMA_TREND_STRATEGY_MQH

#include "BaseStrategy.mqh"

/**
 * @struct EMATrendConfig
 * @brief Configuration for the EMA Trend strategy.
 */
struct EMATrendConfig
{
    double min_separation_atr;   ///< Min EMA separation in ATR units
    double min_slope_atr;        ///< Min EMA slope in ATR units
    int    trend_strength_min;   ///< Min trend strength [0, 100]
    double base_confidence;      ///< Base confidence when all conditions met
    double max_confidence;       ///< Max confidence (scaled by strength)

    EMATrendConfig(void)
    {
        min_separation_atr = 0.1;    // EMA fast/slow must be 0.1 ATR apart
        min_slope_atr      = 0.01;   // EMA fast slope must be > 0.01 ATR
        trend_strength_min = 30;
        base_confidence    = 0.50;
        max_confidence     = 0.85;
    }
};

/**
 * @class EMATrendStrategy
 * @brief Detects trend using EMA pairs (fast/slow).
 *
 * Signal logic:
 *   BUY when:
 *     - EMA fast > EMA slow (uptrend)
 *     - Separation >= min_separation_atr
 *     - EMA fast slope is positive (rising)
 *     - Slope >= min_slope_atr
 *     - Trend strength >= trend_strength_min
 *
 *   SELL when:
 *     - EMA fast < EMA slow (downtrend)
 *     - Separation >= min_separation_atr
 *     - EMA fast slope is negative (falling)
 *     - |Slope| >= min_slope_atr
 *     - Trend strength >= trend_strength_min
 *
 *   NONE when conditions not met.
 *
 * Uses MarketState features:
 *   features[0] = (price - EMA_fast) / ATR
 *   features[1] = (price - EMA_slow) / ATR
 *   features[2] = EMA_fast_slope / ATR
 *   features[3] = EMA_slow_slope / ATR
 *   features[4] = EMA_separation / ATR
 *
 * Performance: O(1), no allocation.
 */
class EMATrendStrategy : public BaseStrategy
{
private:
    EMATrendConfig m_ema_config;

public:
    /**
     * @brief Constructor.
     * @param id Strategy ID.
     */
    EMATrendStrategy(const int id)
        : BaseStrategy(id, "1.0.0")
    {
    }

    /**
     * @brief Set EMA-specific configuration.
     */
    void SetEMAConfig(const EMATrendConfig &config) { m_ema_config = config; }

    /**
     * @brief Get EMA-specific configuration.
     */
    EMATrendConfig GetEMAConfig(void) const { return m_ema_config; }

    virtual string Name(void) const override { return "EMATrendStrategy"; }

    virtual void Warmup(void) override
    {
        m_warmed_up = true;
    }

    /**
     * @brief Main evaluation logic.
     */
    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();

        //--- Get EMA values from features
        double f0 = ctx.GetFeature(0); // (price - EMA_fast) / ATR
        double f1 = ctx.GetFeature(1); // (price - EMA_slow) / ATR
        double f2 = ctx.GetFeature(2); // EMA_fast slope / ATR
        double f3 = ctx.GetFeature(3); // EMA_slow slope / ATR
        double f4 = ctx.GetFeature(4); // EMA separation / ATR

        //--- Separation = |f0 - f1| (normalized by ATR)
        double separation = MathAbs(f0 - f1);
        if(separation < m_ema_config.min_separation_atr)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Slope check
        double fast_slope = f2;

        //--- Trend strength check
        if(market.trend_strength < m_ema_config.trend_strength_min)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Determine direction
        int direction = ATLAS_ORDER_NONE;

        //--- BUY: EMA fast above EMA slow, positive slope, price above both
        if(f0 > 0.0 && f1 > 0.0 && f0 > f1 && fast_slope > m_ema_config.min_slope_atr)
        {
            direction = ATLAS_ORDER_BUY;
        }
        //--- SELL: EMA fast below EMA slow, negative slope, price below both
        else if(f0 < 0.0 && f1 < 0.0 && f0 < f1 && fast_slope < -m_ema_config.min_slope_atr)
        {
            direction = ATLAS_ORDER_SELL;
        }

        if(direction == ATLAS_ORDER_NONE)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Compute confidence based on trend strength and separation
        double strength_factor = (double)market.trend_strength / 100.0;
        double sep_factor = MathMin(1.0, separation / 1.0); // Cap at 1.0
        double confidence = m_ema_config.base_confidence +
                           (m_ema_config.max_confidence - m_ema_config.base_confidence) *
                           strength_factor * sep_factor;
        confidence = ClampConfidence(confidence);

        if(direction == ATLAS_ORDER_BUY)
            return BuildBuyVote(ctx, confidence, ATLAS_STRAT_REASON_TREND_UP);
        else
            return BuildSellVote(ctx, confidence, ATLAS_STRAT_REASON_TREND_DOWN);
    }
};

#endif // ATLAS_EMA_TREND_STRATEGY_MQH
//+------------------------------------------------------------------+
