//+------------------------------------------------------------------+
//|                  Strategies/PullbackStrategy.mqh                 |
//|       AtlasEA v1.0 Step 3 - Pullback Strategy                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_PULLBACK_STRATEGY_MQH
#define ATLAS_PULLBACK_STRATEGY_MQH

#include "BaseStrategy.mqh"

/**
 * @struct PullbackConfig
 * @brief Configuration for the Pullback strategy.
 */
struct PullbackConfig
{
    double pullback_min_atr;     ///< Min pullback depth in ATR units
    double pullback_max_atr;     ///< Max pullback depth (don't buy too deep)
    double rejection_min_atr;    ///< Min rejection candle in ATR units
    double momentum_min_atr;     ///< Min momentum continuation in ATR units
    int    trend_strength_min;   ///< Min trend strength required
    double base_confidence;
    double max_confidence;

    PullbackConfig(void)
    {
        pullback_min_atr    = 0.3;
        pullback_max_atr    = 1.5;
        rejection_min_atr   = 0.2;
        momentum_min_atr    = 0.1;
        trend_strength_min  = 30;
        base_confidence     = 0.45;
        max_confidence      = 0.80;
    }
};

/**
 * @class PullbackStrategy
 * @brief Trades pullbacks within an established trend.
 *
 * Signal logic (BUY example):
 *   1. Trend is UP (trend_direction == 1, trend_strength >= min)
 *   2. Price pulled back toward EMA fast (pullback depth in [min, max] ATR)
 *   3. Rejection candle formed (price bounced back from pullback)
 *   4. Momentum continuation (price moving back in trend direction)
 *
 * Uses MarketState features:
 *   features[0] = (price - EMA_fast) / ATR  → pullback depth
 *   features[2] = EMA_fast_slope / ATR       → momentum
 *   features[4] = EMA_separation / ATR       → trend intact
 *
 * Performance: O(1), no allocation.
 */
class PullbackStrategy : public BaseStrategy
{
private:
    PullbackConfig m_pb_config;

public:
    PullbackStrategy(const int id)
        : BaseStrategy(id, "1.0.0")
    {
    }

    void SetPullbackConfig(const PullbackConfig &config) { m_pb_config = config; }
    PullbackConfig GetPullbackConfig(void) const { return m_pb_config; }

    virtual string Name(void) const override { return "PullbackStrategy"; }

    virtual void Warmup(void) override { m_warmed_up = true; }

    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();

        //--- Require trend
        if(market.trend_direction == 0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);
        if(market.trend_strength < m_pb_config.trend_strength_min)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Get features
        double f0 = ctx.GetFeature(0); // (price - EMA_fast) / ATR
        double f2 = ctx.GetFeature(2); // EMA_fast slope / ATR
        double f4 = ctx.GetFeature(4); // EMA separation / ATR

        double atr = ctx.GetATR();
        if(atr <= 0.0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        int direction = ATLAS_ORDER_NONE;
        double confidence = 0.0;

        if(market.trend_direction == 1) // Uptrend → look for BUY pullback
        {
            //--- Pullback: price moved below EMA fast (f0 < 0) but not too far
            double pullback_depth = MathAbs(f0); // depth in ATR units
            if(pullback_depth < m_pb_config.pullback_min_atr ||
               pullback_depth > m_pb_config.pullback_max_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            //--- Rejection: price is now back near or above EMA fast (f0 >= -rejection_min)
            if(f0 < -m_pb_config.rejection_min_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            //--- Momentum continuation: EMA fast slope is still positive
            if(f2 < m_pb_config.momentum_min_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            direction = ATLAS_ORDER_BUY;

            //--- Confidence: deeper pullback + stronger trend = higher confidence
            double depth_factor = MathMin(1.0, pullback_depth / m_pb_config.pullback_max_atr);
            double strength_factor = (double)market.trend_strength / 100.0;
            confidence = m_pb_config.base_confidence +
                        (m_pb_config.max_confidence - m_pb_config.base_confidence) *
                        depth_factor * strength_factor;
        }
        else if(market.trend_direction == -1) // Downtrend → look for SELL pullback
        {
            //--- Pullback: price moved above EMA fast (f0 > 0) but not too far
            double pullback_depth = MathAbs(f0);
            if(pullback_depth < m_pb_config.pullback_min_atr ||
               pullback_depth > m_pb_config.pullback_max_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            //--- Rejection: price is now back near or below EMA fast
            if(f0 > m_pb_config.rejection_min_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            //--- Momentum continuation: EMA fast slope is still negative
            if(f2 > -m_pb_config.momentum_min_atr)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

            direction = ATLAS_ORDER_SELL;

            double depth_factor = MathMin(1.0, pullback_depth / m_pb_config.pullback_max_atr);
            double strength_factor = (double)market.trend_strength / 100.0;
            confidence = m_pb_config.base_confidence +
                        (m_pb_config.max_confidence - m_pb_config.base_confidence) *
                        depth_factor * strength_factor;
        }

        if(direction == ATLAS_ORDER_NONE)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        confidence = ClampConfidence(confidence);

        if(direction == ATLAS_ORDER_BUY)
            return BuildBuyVote(ctx, confidence, ATLAS_STRAT_REASON_PULLBACK_BUY);
        else
            return BuildSellVote(ctx, confidence, ATLAS_STRAT_REASON_PULLBACK_SELL);
    }
};

#endif // ATLAS_PULLBACK_STRATEGY_MQH
//+------------------------------------------------------------------+
