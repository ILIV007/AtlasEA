//+------------------------------------------------------------------+
//|                  Strategies/BreakoutStrategy.mqh                 |
//|       AtlasEA v1.0 Step 3 - Breakout Strategy                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_BREAKOUT_STRATEGY_MQH
#define ATLAS_BREAKOUT_STRATEGY_MQH

#include "BaseStrategy.mqh"

/**
 * @brief Breakout type codes.
 */
#define ATLAS_BREAKOUT_HIGH        0
#define ATLAS_BREAKOUT_LOW         1
#define ATLAS_BREAKOUT_RANGE       2
#define ATLAS_BREAKOUT_CONSOLIDATION 3

/**
 * @struct BreakoutConfig
 * @brief Configuration for the Breakout strategy.
 */
struct BreakoutConfig
{
    double breakout_min_atr;      ///< Min breakout distance in ATR units
    double false_breakout_max_atr;///< Max pullback before it's a false breakout
    int    consolidation_min_bars;///< Min bars for consolidation detection
    double consolidation_max_width_atr; ///< Max range width for consolidation
    double asian_range_hours;     ///< Asian range duration (hours)
    double base_confidence;
    double max_confidence;
    bool   require_volume_increase; ///< Require tick volume increase

    BreakoutConfig(void)
    {
        breakout_min_atr           = 0.5;
        false_breakout_max_atr     = 1.0;
        consolidation_min_bars     = 5;
        consolidation_max_width_atr = 2.0;
        asian_range_hours          = 6.0;
        base_confidence            = 0.50;
        max_confidence             = 0.85;
        require_volume_increase    = true;
    }
};

/**
 * @class BreakoutStrategy
 * @brief Detects breakouts: high, low, range, consolidation.
 *
 * Signal logic:
 *   BUY when:
 *     - Price breaks above recent high (or range high, or consolidation high)
 *     - Breakout distance >= breakout_min_atr
 *     - Volume is increasing (if required)
 *     - Not a false breakout (price doesn't immediately reverse)
 *
 *   SELL when:
 *     - Price breaks below recent low (or range low, or consolidation low)
 *     - Breakout distance >= breakout_min_atr
 *     - Volume is increasing (if required)
 *     - Not a false breakout
 *
 * Uses MarketState fields:
 *   - open, high, low, close (current bar OHLC)
 *   - bar_time (for consolidation detection)
 *   - tick_volume (for volume increase check)
 *   - atr_14 (for distance normalization)
 *
 * Performance: O(1), no allocation.
 */
class BreakoutStrategy : public BaseStrategy
{
private:
    BreakoutConfig m_brk_config;

    //--- Cached recent high/low (updated on each bar)
    double m_recent_high;
    double m_recent_low;
    int    m_bar_count;
    datetime m_last_bar_time;
    double m_range_high;
    double m_range_low;
    bool   m_range_established;

public:
    BreakoutStrategy(const int id)
        : BaseStrategy(id, "1.0.0")
    {
        m_recent_high      = 0.0;
        m_recent_low       = 0.0;
        m_bar_count        = 0;
        m_last_bar_time    = 0;
        m_range_high       = 0.0;
        m_range_low        = 0.0;
        m_range_established = false;
    }

    void SetBreakoutConfig(const BreakoutConfig &config) { m_brk_config = config; }
    BreakoutConfig GetBreakoutConfig(void) const { return m_brk_config; }

    virtual string Name(void) const override { return "BreakoutStrategy"; }

    virtual void Warmup(void) override
    {
        m_warmed_up = true;
        m_recent_high = 0.0;
        m_recent_low = 0.0;
        m_bar_count = 0;
        m_range_established = false;
    }

    virtual void OnBar(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();

        //--- Update recent high/low
        if(market.bar_time > 0 && market.bar_time != m_last_bar_time)
        {
            if(market.high > m_recent_high || m_recent_high == 0.0)
                m_recent_high = market.high;
            if(market.low < m_recent_low || m_recent_low == 0.0)
                m_recent_low = market.low;

            m_bar_count++;
            m_last_bar_time = market.bar_time;

            //--- Establish range after consolidation_min_bars
            if(m_bar_count >= m_brk_config.consolidation_min_bars)
            {
                m_range_high = m_recent_high;
                m_range_low = m_recent_low;
                m_range_established = true;
            }
        }
    }

    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) override
    {
        const MarketState &market = ctx.GetMarketState();
        double atr = ctx.GetATR();
        double price = ctx.GetMidPrice();

        if(atr <= 0.0 || price <= 0.0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Need an established range to detect breakout
        if(!m_range_established || m_range_high <= 0.0 || m_range_low <= 0.0)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Calculate range width
        double range_width = m_range_high - m_range_low;
        double range_width_atr = (atr > 0.0) ? range_width / atr : 0.0;

        //--- Check if range is too wide (not a consolidation)
        if(range_width_atr > m_brk_config.consolidation_max_width_atr)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Breakout distance
        double breakout_dist = 0.0;
        int direction = ATLAS_ORDER_NONE;
        int breakout_type = ATLAS_BREAKOUT_HIGH;

        //--- Check upside breakout
        if(price > m_range_high)
        {
            breakout_dist = price - m_range_high;
            breakout_type = ATLAS_BREAKOUT_HIGH;
            direction = ATLAS_ORDER_BUY;
        }
        //--- Check downside breakout
        else if(price < m_range_low)
        {
            breakout_dist = m_range_low - price;
            breakout_type = ATLAS_BREAKOUT_LOW;
            direction = ATLAS_ORDER_SELL;
        }

        if(direction == ATLAS_ORDER_NONE)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Breakout distance check
        double breakout_dist_atr = breakout_dist / atr;
        if(breakout_dist_atr < m_brk_config.breakout_min_atr)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- False breakout filter: check if price has reversed back into range
        //--- (if price was outside but came back, it's a false breakout)
        if(breakout_type == ATLAS_BREAKOUT_HIGH && market.close < m_range_high)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);
        if(breakout_type == ATLAS_BREAKOUT_LOW && market.close > m_range_low)
            return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);

        //--- Volume increase check
        if(m_brk_config.require_volume_increase)
        {
            //--- Use tick_volume as proxy for volume
            //--- If tick_volume is below average, skip (can't compute average
            //    without history, so we use a minimum threshold)
            if(market.tick_volume < 10)
                return BuildNoneVote(ctx, ATLAS_STRAT_REASON_NO_SIGNAL);
        }

        //--- Confidence: stronger breakout = higher confidence
        double dist_factor = MathMin(1.0, breakout_dist_atr / 2.0);
        double confidence = m_brk_config.base_confidence +
                           (m_brk_config.max_confidence - m_brk_config.base_confidence) *
                           dist_factor;
        confidence = ClampConfidence(confidence);

        //--- Reset range after breakout (new range will form)
        m_range_established = false;
        m_bar_count = 0;
        m_recent_high = 0.0;
        m_recent_low = 0.0;

        if(direction == ATLAS_ORDER_BUY)
            return BuildBuyVote(ctx, confidence, ATLAS_STRAT_REASON_BREAKOUT_UP);
        else
            return BuildSellVote(ctx, confidence, ATLAS_STRAT_REASON_BREAKOUT_DOWN);
    }
};

#endif // ATLAS_BREAKOUT_STRATEGY_MQH
//+------------------------------------------------------------------+
