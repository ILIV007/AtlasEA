//+------------------------------------------------------------------+
//|                  Strategies/MomentumStrategy.mqh                 |
//|       AtlasEA v1.0 Step 3 - Momentum Strategy                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_MOMENTUM_STRATEGY_MQH
#define ATLAS_MOMENTUM_STRATEGY_MQH

#include "BaseStrategy.mqh"

/**
 * @struct MomentumConfig
 * @brief Configuration for the Momentum strategy.
 */
struct MomentumConfig
{
    double impulse_min_atr;        ///< Min impulse candle size in ATR units
    double atr_expansion_min;      ///< Min ATR expansion ratio (current/avg)
    double volume_increase_min;    ///< Min volume increase ratio
    double momentum_cont_min_atr;  ///< Min momentum continuation in ATR
    double base_confidence;
    double max_confidence;
    bool   require_trend_alignment; ///< Require trend_direction alignment

    MomentumConfig(void)
    {
        impulse_min_atr       = 0.5;
        atr_expansion_min     = 1.2;
        volume_increase_min   = 1.5;
        momentum_cont_min_atr = 0.1;
        base_confidence       = 0.50;
        max_confidence        = 0.85;
        require_trend_alignment = false;
    }
};

/**
 * @class MomentumStrategy
 * @brief Detects strong momentum impulses with ATR and volume confirmation.
 *
 * Signal logic (BUY):
 *   1. Strong impulse candle: |close - open| >= impulse_min_atr × ATR
 *   2. Direction: close > open (bullish candle)
 *   3. ATR expansion: current ATR >= atr_expansion_min × recent average
 *      (simplified: volatility_index check)
 *   4. Volume increase: tick_volume above average (simplified: threshold)
 *   5. Momentum continuation: price continues in direction (bar body)
 *
 * SELL is the mirror image.
 *
 * Uses MarketState fields:
 *   - open, close (current bar — impulse detection)
 *   - atr_14 (impulse normalization)
 *   - volatility_index (ATR expansion proxy)
 *   - tick_volume (volume increase)
 *   - trend_direction (optional alignment)
 *
 * Performance: O(1), no allocation.
 */
class MomentumStrategy : public BaseStrategy
{
private:
    MomentumConfig m_mom_config;

public:
    MomentumStrategy(const int id)
        : BaseStrategy(id, "1.0.0")
    {
    }

    void SetMomentumConfig(const MomentumConfig &config) { m_mom_config = config; }
    MomentumConfig GetMomentumConfig(void) const { return m_mom_config; }

    virtual string Name(void) const override { return "MomentumStrategy"; }

    virtual void Warmup(void) override { m_warmed_up = true; }

    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();
        double atr = ctx.GetATR();
        double price = ctx.GetMidPrice();

        if(atr <= 0.0 || price <= 0.0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Impulse candle detection
        double body = market.close - market.open;
        double body_atr = MathAbs(body) / atr;

        if(body_atr < m_mom_config.impulse_min_atr)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Direction from candle body
        int candle_dir = (body > 0.0) ? ATLAS_ORDER_BUY : ATLAS_ORDER_SELL;

        //--- ATR expansion check (use volatility_index as proxy)
        //--- volatility_index > threshold indicates ATR expansion
        if(market.volatility_index < m_mom_config.atr_expansion_min)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Volume increase check
        //--- tick_volume is cumulative; we use a minimum threshold as proxy
        if(market.tick_volume < 100)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Trend alignment (optional)
        if(m_mom_config.require_trend_alignment)
        {
            if(candle_dir == ATLAS_ORDER_BUY && market.trend_direction != 1)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);
            if(candle_dir == ATLAS_ORDER_SELL && market.trend_direction != -1)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);
        }

        //--- Momentum continuation: check if close is in the direction of the body
        //--- (already satisfied by body > 0 for BUY, body < 0 for SELL)

        //--- Confidence: stronger impulse + higher volatility = higher confidence
        double impulse_factor = MathMin(1.0, body_atr / 2.0);
        double vol_factor = MathMin(1.0, market.volatility_index / 5.0);
        double confidence = m_mom_config.base_confidence +
                           (m_mom_config.max_confidence - m_mom_config.base_confidence) *
                           impulse_factor * vol_factor;
        confidence = ClampConfidence(confidence);

        if(candle_dir == ATLAS_ORDER_BUY)
            return BuildBuyVote(ctx, confidence, ATLAS_STRAT_REASON_MOMENTUM_BUY);
        else
            return BuildSellVote(ctx, confidence, ATLAS_STRAT_REASON_MOMENTUM_SELL);
    }
};

#endif // ATLAS_MOMENTUM_STRATEGY_MQH
//+------------------------------------------------------------------+
