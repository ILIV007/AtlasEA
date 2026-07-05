//+------------------------------------------------------------------+
//|                    Strategies/BaseStrategy.mqh                   |
//|       AtlasEA v1.0 Step 3 - Base Strategy (Strategy Pack V1)     |
//+------------------------------------------------------------------+
#ifndef ATLAS_BASE_STRATEGY_V2_MQH
#define ATLAS_BASE_STRATEGY_V2_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Strategy/StrategyContext.mqh"

/**
 * @brief Strategy reason codes (why a vote was produced or not).
 */
#define ATLAS_STRAT_REASON_NONE              0
#define ATLAS_STRAT_REASON_NO_SIGNAL         1
#define ATLAS_STRAT_REASON_TREND_UP          2
#define ATLAS_STRAT_REASON_TREND_DOWN        3
#define ATLAS_STRAT_REASON_PULLBACK_BUY      4
#define ATLAS_STRAT_REASON_PULLBACK_SELL     5
#define ATLAS_STRAT_REASON_BREAKOUT_UP       6
#define ATLAS_STRAT_REASON_BREAKOUT_DOWN     7
#define ATLAS_STRAT_REASON_MOMENTUM_BUY      8
#define ATLAS_STRAT_REASON_MOMENTUM_SELL     9
#define ATLAS_STRAT_REASON_RANGE_FADE_BUY   10
#define ATLAS_STRAT_REASON_RANGE_FADE_SELL  11
#define ATLAS_STRAT_REASON_FILTER_REJECT    12
#define ATLAS_STRAT_REASON_COOLDOWN         13
#define ATLAS_STRAT_REASON_DISABLED         14
#define ATLAS_STRAT_REASON_WARMUP           15
#define ATLAS_STRAT_REASON_MAX_TRADES       16

/**
 * @struct StrategyConfig
 * @brief Per-strategy configuration.
 *
 * Every strategy is individually configurable via this struct.
 */
struct StrategyConfig
{
    bool   enabled;              ///< Is this strategy enabled?
    int    priority;             ///< Priority (lower = higher priority)
    double weight;               ///< Vote weight [0.0, 1.0]
    int    cooldown_sec;         ///< Cooldown between signals (seconds)
    int    max_trades_per_day;   ///< Max signals per day (0 = unlimited)
    int    session_mask;         ///< Bitmask of allowed sessions
    double spread_limit_points;  ///< Max spread (points, 0 = no limit)
    double min_atr_points;       ///< Min ATR (points, 0 = no limit)
    double max_atr_points;       ///< Max ATR (points, 0 = no limit)
    bool   trend_filter;         ///< Require trend confirmation
    int    trend_min_strength;   ///< Min trend strength [0, 100]
    double min_rr;               ///< Minimum risk:reward ratio
    double default_sl_atr;       ///< Default SL = ATR × this
    double default_tp_atr;       ///< Default TP = ATR × this

    StrategyConfig(void)
    {
        enabled            = true;
        priority           = 50;
        weight             = 1.0;
        cooldown_sec       = 300;     // 5 minutes
        max_trades_per_day = 0;       // Unlimited
        session_mask       = 0xFF;    // All sessions
        spread_limit_points = 50.0;
        min_atr_points     = 0.0;
        max_atr_points     = 0.0;
        trend_filter       = false;
        trend_min_strength = 20;
        min_rr             = 1.5;
        default_sl_atr     = 2.0;
        default_tp_atr     = 3.0;
    }
};

/**
 * @class BaseStrategy
 * @brief Abstract base class for all strategies in Strategy Pack V1.
 *
 * Provides:
 *   - Common lifecycle (Initialize/Warmup/Evaluate/Reset/Shutdown)
 *   - Per-strategy configuration (StrategyConfig)
 *   - Cooldown tracking
 *   - Daily trade counting
 *   - Session/spread/ATR pre-filtering
 *   - Vote construction helpers
 *
 * Subclasses must implement:
 *   - DoEvaluate() — the actual strategy logic
 *   - Name() — strategy name
 *   - Version() — strategy version
 *
 * Contract:
 *   - Strategies receive ONLY StrategyContext (read-only).
 *   - Never access MT5 directly.
 *   - Never query broker.
 *   - Never modify positions.
 *   - Never calculate lot size.
 *   - Never send orders.
 *   - Only return StrategyVote.
 *   - No static mutable state.
 *   - No knowledge of other strategies.
 *
 * Performance: Evaluate() must complete in ≤ 2 ms.
 */
class BaseStrategy : public IStrategy
{
protected:
    StrategyConfig m_config;
    int            m_strategy_id;
    string         m_version;
    bool           m_warmed_up;
    bool           m_initialized;

    //--- Cooldown tracking ---
    datetime       m_last_signal_time;
    int            m_daily_signal_count;
    datetime       m_daily_reset_time;

    //--- Health ---
    int            m_health;
    ulong          m_eval_count;

    /**
     * @brief Check pre-conditions before running the strategy logic.
     *
     * Checks: enabled, warmed up, cooldown, daily max, session, spread, ATR.
     *
     * @param ctx The strategy context.
     * @return Reason code (ATLAS_STRAT_REASON_NONE if all checks pass).
     */
    int CheckPreConditions(const StrategyContext &ctx)
    {
        if(!m_config.enabled)
            return ATLAS_STRAT_REASON_DISABLED;

        if(!m_warmed_up)
            return ATLAS_STRAT_REASON_WARMUP;

        //--- Daily reset check
        datetime now = ctx.GetCurrentTime();
        if(now > 0)
        {
            MqlDateTime dt_now, dt_reset;
            TimeToStruct(now, dt_now);
            TimeToStruct(m_daily_reset_time, dt_reset);
            if(dt_now.day != dt_reset.day || dt_now.mon != dt_reset.mon)
            {
                m_daily_signal_count = 0;
                m_daily_reset_time = now;
            }
        }

        //--- Cooldown check
        if(m_config.cooldown_sec > 0 && m_last_signal_time > 0)
        {
            long elapsed = (long)now - (long)m_last_signal_time;
            if(elapsed < m_config.cooldown_sec)
                return ATLAS_STRAT_REASON_COOLDOWN;
        }

        //--- Daily max trades
        if(m_config.max_trades_per_day > 0 &&
           m_daily_signal_count >= m_config.max_trades_per_day)
            return ATLAS_STRAT_REASON_MAX_TRADES;

        //--- Market state validity
        if(!ctx.IsValid())
            return ATLAS_STRAT_REASON_NO_SIGNAL;

        const MarketState &market = ctx.GetMarketState();
        if(!market.is_valid)
            return ATLAS_STRAT_REASON_NO_SIGNAL;

        //--- Spread filter
        if(m_config.spread_limit_points > 0.0 && market.point > 0.0)
        {
            double spread_pts = market.spread / market.point;
            if(spread_pts > m_config.spread_limit_points)
                return ATLAS_STRAT_REASON_FILTER_REJECT;
        }

        //--- ATR filter
        if(market.point > 0.0)
        {
            double atr_pts = market.atr_14 / market.point;
            if(m_config.min_atr_points > 0.0 && atr_pts < m_config.min_atr_points)
                return ATLAS_STRAT_REASON_FILTER_REJECT;
            if(m_config.max_atr_points > 0.0 && atr_pts > m_config.max_atr_points)
                return ATLAS_STRAT_REASON_FILTER_REJECT;
        }

        //--- Session filter
        if(m_config.session_mask != 0xFF)
        {
            int sess = ctx.GetSessionState();
            if(sess < 0 || sess > 4) sess = 0;
            int mask = 1 << sess;
            if((m_config.session_mask & mask) == 0)
                return ATLAS_STRAT_REASON_FILTER_REJECT;
        }

        //--- Trend filter
        if(m_config.trend_filter)
        {
            if(market.trend_strength < m_config.trend_min_strength)
                return ATLAS_STRAT_REASON_FILTER_REJECT;
        }

        return ATLAS_STRAT_REASON_NONE;
    }

    /**
     * @brief Build a BUY vote.
     */
    StrategyVote BuildBuyVote(const StrategyContext &ctx, const double confidence,
                               const int reason_code)
    {
        return BuildVote(ctx, ATLAS_ORDER_BUY, confidence, reason_code);
    }

    /**
     * @brief Build a SELL vote.
     */
    StrategyVote BuildSellVote(const StrategyContext &ctx, const double confidence,
                                const int reason_code)
    {
        return BuildVote(ctx, ATLAS_ORDER_SELL, confidence, reason_code);
    }

    /**
     * @brief Build a NONE vote (no signal).
     */
    StrategyVote BuildNoneVote(const StrategyContext &ctx, const int reason_code)
    {
        StrategyVote vote;
        vote.strategy_id      = m_strategy_id;
        vote.strategy_version = m_version;
        vote.direction        = ATLAS_ORDER_NONE;
        vote.confidence       = 0.0;
        vote.suggested_volume = 0.0;
        vote.suggested_entry  = 0.0;
        vote.suggested_sl     = 0.0;
        vote.suggested_tp     = 0.0;
        vote.snapshot_id      = ctx.GetSnapshotId();
        vote.vote_time        = ctx.GetCurrentTime();
        return vote;
    }

    /**
     * @brief Build a vote with SL/TP calculated from ATR.
     */
    StrategyVote BuildVote(const StrategyContext &ctx, const int direction,
                            const double confidence, const int reason_code)
    {
        StrategyVote vote;
        vote.strategy_id      = m_strategy_id;
        vote.strategy_version = m_version;
        vote.direction        = direction;
        vote.confidence       = confidence;
        vote.suggested_volume = 0.0;  // Let MoneyManagement decide
        vote.snapshot_id      = ctx.GetSnapshotId();
        vote.vote_time        = ctx.GetCurrentTime();

        //--- Calculate SL/TP from ATR
        const MarketState &market = ctx.GetMarketState();
        double atr = market.atr_14;
        double price = ctx.GetMidPrice();

        if(atr > 0.0 && price > 0.0)
        {
            double sl_dist = atr * m_config.default_sl_atr;
            double tp_dist = atr * m_config.default_tp_atr;

            if(direction == ATLAS_ORDER_BUY)
            {
                vote.suggested_entry = price;
                vote.suggested_sl    = price - sl_dist;
                vote.suggested_tp    = price + tp_dist;
            }
            else // SELL
            {
                vote.suggested_entry = price;
                vote.suggested_sl    = price + sl_dist;
                vote.suggested_tp    = price - tp_dist;
            }
        }

        //--- Record signal
        m_last_signal_time = ctx.GetCurrentTime();
        m_daily_signal_count++;

        return vote;
    }

    /**
     * @brief Clamp confidence to [0, 1].
     */
    double ClampConfidence(const double c) const
    {
        if(c < 0.0) return 0.0;
        if(c > 1.0) return 1.0;
        return c;
    }

public:
    /**
     * @brief Constructor.
     * @param id Strategy ID.
     * @param version Strategy version string.
     */
    BaseStrategy(const int id, const string version)
    {
        m_strategy_id       = id;
        m_version           = version;
        m_warmed_up         = false;
        m_initialized       = false;
        m_last_signal_time  = 0;
        m_daily_signal_count = 0;
        m_daily_reset_time  = 0;
        m_health            = ATLAS_STRAT_HEALTH_GREEN;
        m_eval_count        = 0;
    }

    virtual ~BaseStrategy(void) {}

    //=== IStrategy implementation (common) ===

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized = false;
        m_warmed_up   = false;
    }

    virtual void Reset(void) override
    {
        m_daily_signal_count = 0;
        m_last_signal_time   = 0;
        m_daily_reset_time   = TimeCurrent();
        m_health             = ATLAS_STRAT_HEALTH_GREEN;
    }

    /**
     * @brief Warmup the strategy (called after Initialize, before first Evaluate).
     * Subclasses can override to pre-compute indicator values.
     */
    virtual void Warmup(void) { m_warmed_up = true; }

    virtual void OnTick(const StrategyContext &ctx) override { }
    virtual void OnBar(const StrategyContext &ctx) override { }

    /**
     * @brief Main evaluation entry point.
     *
     * Runs pre-conditions, then delegates to DoEvaluate().
     * If pre-conditions fail, returns a NONE vote.
     */
    virtual StrategyVote Evaluate(const StrategyContext &ctx) override
    {
        m_eval_count++;

        int reason = CheckPreConditions(ctx);
        if(reason != ATLAS_STRAT_REASON_NONE)
            return BuildNoneVote(ctx, reason);

        return DoEvaluate(ctx);
    }

    /**
     * @brief Subclass-implemented evaluation logic.
     * @return StrategyVote (BUY, SELL, or NONE).
     */
    virtual StrategyVote DoEvaluate(const StrategyContext &ctx) = 0;

    //=== Metadata ===

    virtual string Version(void) const override { return m_version; }
    virtual int    Priority(void) const override { return m_config.priority; }
    virtual double Weight(void) const override { return m_config.weight; }
    virtual bool   Enabled(void) const override { return m_config.enabled; }
    virtual int    Health(void) const override { return m_health; }

    virtual bool SupportsSymbol(const string symbol) const override { return true; }
    virtual bool SupportsTimeframe(const string timeframe) const override { return true; }

    //=== Configuration ===

    /**
     * @brief Set the strategy configuration.
     */
    void SetConfig(const StrategyConfig &config) { m_config = config; }

    /**
     * @brief Get the strategy configuration.
     */
    const StrategyConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Get the strategy ID.
     */
    int GetId(void) const { return m_strategy_id; }

    /**
     * @brief Get the cooldown remaining (seconds).
     */
    int GetCooldownRemaining(void) const
    {
        if(m_config.cooldown_sec <= 0 || m_last_signal_time <= 0) return 0;
        long elapsed = (long)TimeCurrent() - (long)m_last_signal_time;
        long remaining = (long)m_config.cooldown_sec - elapsed;
        return (remaining > 0) ? (int)remaining : 0;
    }

    /**
     * @brief Get the number of signals today.
     */
    int GetDailySignalCount(void) const { return m_daily_signal_count; }

    /**
     * @brief Get total evaluation count.
     */
    ulong GetEvalCount(void) const { return m_eval_count; }
};

#endif // ATLAS_BASE_STRATEGY_V2_MQH
//+------------------------------------------------------------------+
