//+------------------------------------------------------------------+
//|                   Trading/Signal/SignalScoring.mqh               |
//|       AtlasEA v0.2.1 - Signal Scoring (Deterministic)            |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_SCORING_MQH
#define ATLAS_SIGNAL_SCORING_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"

/**
 * @brief Maximum strategy priority weight.
 * Strategy priorities are in [0, ATLAS_MAX_STRATEGY_PRIORITY].
 */
#define ATLAS_MAX_STRATEGY_PRIORITY 10

/**
 * @struct StrategyPriority
 * @brief Priority configuration for a single strategy.
 *
 * Higher priority strategies get a higher score bonus. This allows
 * the system to prefer signals from more trusted or higher-priority
 * strategies when multiple signals compete.
 */
struct StrategyPriority
{
    int  strategy_id;     ///< Strategy ID this priority applies to
    int  priority;        ///< Priority [0, ATLAS_MAX_STRATEGY_PRIORITY]
    bool enabled;         ///< Is this strategy enabled?

    StrategyPriority(void)
    {
        strategy_id = 0;
        priority    = 5;  // Default medium priority
        enabled     = true;
    }
};

/**
 * @struct ScoringConfig
 * @brief Configuration for the signal scoring algorithm.
 *
 * All weights are in points. The final score is the weighted sum,
 * clamped to [0, 100].
 *
 * Scoring components:
 *   - Confidence:   [0, 40] points (confidence * 40)
 *   - Freshness:    [0, 25] points (newer = more points)
 *   - Strategy priority: [0, 20] points (priority / max * 20)
 *   - Market quality: [0, 15] points (spread + volatility + trend)
 *   Total: [0, 100]
 */
struct ScoringConfig
{
    double confidence_weight;    ///< Max points for confidence (default 40)
    double freshness_weight;     ///< Max points for freshness (default 25)
    double priority_weight;      ///< Max points for strategy priority (default 20)
    double market_quality_weight; ///< Max points for market quality (default 15)

    int    freshness_halflife_sec; ///< Seconds for freshness to halve
    double max_spread_points;    ///< Spread above this = 0 market quality
    double min_volatility_index; ///< Volatility below this = reduced quality
    double max_volatility_index; ///< Volatility above this = reduced quality (fast market)
    int    min_trend_strength;   ///< Trend strength below this = reduced quality

    ScoringConfig(void)
    {
        confidence_weight      = 40.0;
        freshness_weight       = 25.0;
        priority_weight        = 20.0;
        market_quality_weight  = 15.0;
        freshness_halflife_sec = 120;   // 2 minutes
        max_spread_points      = 50.0;
        min_volatility_index   = 0.5;
        max_volatility_index   = 10.0;
        min_trend_strength     = 20;
    }
};

/**
 * @struct SignalScore
 * @brief The score breakdown for a signal.
 */
struct SignalScore
{
    double total;              ///< Total score [0, 100]
    double confidence_score;   ///< Confidence component [0, confidence_weight]
    double freshness_score;    ///< Freshness component [0, freshness_weight]
    double priority_score;     ///< Strategy priority component [0, priority_weight]
    double market_quality_score; ///< Market quality component [0, market_quality_weight]

    SignalScore(void)
    {
        total                = 0.0;
        confidence_score     = 0.0;
        freshness_score      = 0.0;
        priority_score       = 0.0;
        market_quality_score = 0.0;
    }
};

/**
 * @class SignalScoring
 * @brief Scores signals deterministically.
 *
 * SOLE RESPONSIBILITY: compute a deterministic score [0, 100] for a
 * signal based on:
 *   1. Confidence (strategy's self-reported confidence)
 *   2. Freshness (how recent the signal is)
 *   3. Strategy priority (configurable per-strategy weight)
 *   4. Market quality (spread, volatility, trend strength)
 *
 * The scoring is PURELY deterministic — no AI, no ML, no randomness.
 * The same signal + market state + config always produces the same score.
 *
 * Scoring formula:
 *   confidence_score  = confidence * confidence_weight
 *   freshness_score   = freshness_weight * exp(-age / halflife * ln(2))
 *   priority_score    = (priority / max_priority) * priority_weight
 *   market_quality    = f(spread, volatility, trend) * market_quality_weight
 *   total             = sum, clamped to [0, 100]
 *
 * Memory: ~300 bytes (config + priority table + logger).
 */
class SignalScoring
{
private:
    ILogger           *m_logger;
    ScoringConfig      m_config;
    StrategyPriority   m_priorities[ATLAS_MAX_STRATEGIES];
    int                m_priority_count;

public:
    /**
     * @brief Constructor.
     */
    SignalScoring(void)
    {
        m_logger         = NULL;
        m_priority_count = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the scoring configuration.
     */
    void SetConfig(const ScoringConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const ScoringConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Set the priority for a strategy.
     */
    void SetStrategyPriority(const int strategy_id, const int priority,
                              const bool enabled)
    {
        //--- Find existing entry
        for(int i = 0; i < m_priority_count; i++)
        {
            if(m_priorities[i].strategy_id == strategy_id)
            {
                m_priorities[i].priority = priority;
                m_priorities[i].enabled  = enabled;
                return;
            }
        }
        //--- Add new entry
        if(m_priority_count < ATLAS_MAX_STRATEGIES)
        {
            m_priorities[m_priority_count].strategy_id = strategy_id;
            m_priorities[m_priority_count].priority    = priority;
            m_priorities[m_priority_count].enabled     = enabled;
            m_priority_count++;
        }
    }

    /**
     * @brief Get the priority for a strategy.
     * @return Priority [0, ATLAS_MAX_STRATEGY_PRIORITY], or 5 (default) if not set.
     */
    int GetStrategyPriority(const int strategy_id) const
    {
        for(int i = 0; i < m_priority_count; i++)
        {
            if(m_priorities[i].strategy_id == strategy_id)
            {
                if(!m_priorities[i].enabled) return 0;
                return m_priorities[i].priority;
            }
        }
        return 5; // Default medium priority
    }

    /**
     * @brief Score a signal.
     *
     * @param signal The signal to score (should be normalized + validated).
     * @param market Current market state (for quality assessment).
     * @return SignalScore with breakdown.
     */
    SignalScore Score(const TradeSignal &signal, const MarketState &market)
    {
        SignalScore score;

        //=== 1. Confidence score ===
        score.confidence_score = ScoreConfidence(signal.confidence);

        //=== 2. Freshness score ===
        score.freshness_score = ScoreFreshness(signal.timestamp);

        //=== 3. Strategy priority score ===
        score.priority_score = ScorePriority(signal.strategy_id);

        //=== 4. Market quality score ===
        score.market_quality_score = ScoreMarketQuality(market);

        //=== Total ===
        score.total = score.confidence_score + score.freshness_score +
                      score.priority_score + score.market_quality_score;

        //--- Clamp to [0, 100]
        if(score.total < 0.0)   score.total = 0.0;
        if(score.total > 100.0) score.total = 100.0;

        if(m_logger != NULL)
            m_logger.Debug("SignalScoring",
                "Scored " + signal.signal_id +
                " total=" + DoubleToString(score.total, 1) +
                " (conf=" + DoubleToString(score.confidence_score, 1) +
                " fresh=" + DoubleToString(score.freshness_score, 1) +
                " prio=" + DoubleToString(score.priority_score, 1) +
                " qual=" + DoubleToString(score.market_quality_score, 1) + ")");

        return score;
    }

    /**
     * @brief Get just the total score (convenience).
     */
    double ScoreTotal(const TradeSignal &signal, const MarketState &market)
    {
        return Score(signal, market).total;
    }

private:
    /**
     * @brief Score confidence: [0, confidence_weight].
     * confidence in [0, 1] → [0, confidence_weight].
     */
    double ScoreConfidence(const double confidence) const
    {
        if(!MathIsValidNumber(confidence)) return 0.0;
        double c = confidence;
        if(c < 0.0) c = 0.0;
        if(c > 1.0) c = 1.0;
        return c * m_config.confidence_weight;
    }

    /**
     * @brief Score freshness: [0, freshness_weight].
     * Uses exponential decay: score = weight * 0.5^(age / halflife).
     * A signal 0 seconds old gets full weight.
     * A signal `halflife` seconds old gets half weight.
     * A signal 3*halflife seconds old gets 1/8 weight.
     */
    double ScoreFreshness(const datetime timestamp) const
    {
        if(timestamp <= 0) return 0.0;
        long age_sec = (long)TimeCurrent() - (long)timestamp;
        if(age_sec < 0) age_sec = 0;
        if(m_config.freshness_halflife_sec <= 0) return m_config.freshness_weight;

        //--- Exponential decay: 0.5^(age / halflife)
        double half_lives = (double)age_sec / (double)m_config.freshness_halflife_sec;
        double decay = MathPow(0.5, half_lives);
        return m_config.freshness_weight * decay;
    }

    /**
     * @brief Score strategy priority: [0, priority_weight].
     * priority in [0, ATLAS_MAX_STRATEGY_PRIORITY] → [0, priority_weight].
     */
    double ScorePriority(const int strategy_id) const
    {
        int prio = GetStrategyPriority(strategy_id);
        if(prio <= 0) return 0.0;
        if(prio > ATLAS_MAX_STRATEGY_PRIORITY) prio = ATLAS_MAX_STRATEGY_PRIORITY;
        return ((double)prio / (double)ATLAS_MAX_STRATEGY_PRIORITY) * m_config.priority_weight;
    }

    /**
     * @brief Score market quality: [0, market_quality_weight].
     *
     * Market quality is a combination of:
     *   - Spread (lower is better)
     *   - Volatility index (moderate is better)
     *   - Trend strength (stronger is better)
     *   - Fast market penalty (is_fast_market reduces quality)
     *
     * Each sub-factor produces a [0, 1] multiplier, and the final
     * quality score is the geometric mean of the multipliers times
     * the weight.
     */
    double ScoreMarketQuality(const MarketState &market) const
    {
        //--- Spread quality: 0 (wide) to 1 (tight)
        double spread_quality = 1.0;
        if(m_config.max_spread_points > 0.0 && market.spread >= 0.0)
        {
            double spread_points = market.spread;
            if(market.point > 0.0)
                spread_points = market.spread / market.point;
            if(spread_points >= m_config.max_spread_points)
                spread_quality = 0.0;
            else
                spread_quality = 1.0 - (spread_points / m_config.max_spread_points);
        }

        //--- Volatility quality: 1 (moderate) to 0 (too low or too high)
        double vol_quality = 1.0;
        if(market.volatility_index > 0.0)
        {
            if(market.volatility_index < m_config.min_volatility_index)
                vol_quality = market.volatility_index / m_config.min_volatility_index;
            else if(market.volatility_index > m_config.max_volatility_index)
                vol_quality = m_config.max_volatility_index / market.volatility_index;
            //--- else: moderate → 1.0
        }

        //--- Trend quality: 0 (weak) to 1 (strong)
        double trend_quality = 0.0;
        if(market.trend_strength >= m_config.min_trend_strength)
            trend_quality = 1.0;
        else if(m_config.min_trend_strength > 0)
            trend_quality = (double)market.trend_strength / (double)m_config.min_trend_strength;

        //--- Fast market penalty
        double fast_penalty = market.is_fast_market ? 0.5 : 1.0;

        //--- Geometric mean of the multipliers
        double geo_mean = MathPow(spread_quality * vol_quality * trend_quality * fast_penalty, 0.25);
        if(!MathIsValidNumber(geo_mean)) geo_mean = 0.0;
        if(geo_mean < 0.0) geo_mean = 0.0;
        if(geo_mean > 1.0) geo_mean = 1.0;

        return geo_mean * m_config.market_quality_weight;
    }
};

#endif // ATLAS_SIGNAL_SCORING_MQH
//+------------------------------------------------------------------+
