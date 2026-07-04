//+------------------------------------------------------------------+
//|              Engines/RiskEngine/RiskRuleSet.mqh                  |
//|       AtlasEA v0.1.11.0 - Configurable Risk Rules                |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_RULE_SET_MQH
#define ATLAS_RISK_RULE_SET_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/RiskDecision.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Contracts/Events.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"
#include "KillSwitch.mqh"
#include "CooldownManager.mqh"
#include "ExposureCalculator.mqh"
#include "DrawdownMonitor.mqh"
#include "MarginMonitor.mqh"

/**
 * @brief Rule check result codes.
 */
#define ATLAS_RULE_PASS              0
#define ATLAS_RULE_FAIL_REJECT       1   ///< Hard fail → REJECTED
#define ATLAS_RULE_FAIL_MODIFY       2   ///< Soft fail → MODIFIED (volume/SL adjusted)
#define ATLAS_RULE_FAIL_KILLSWITCH   3   ///< Critical → Kill switch + REJECTED

/**
 * @struct RuleResult
 * @brief Result of a single rule check.
 */
struct RuleResult
{
    int    code;           ///< ATLAS_RULE_*
    int    reason_code;    ///< ATLAS_RISK_REASON_* (for REJECTED)
    string reason_text;    ///< Human-readable
    double modified_volume;///< If MODIFIED, the new volume
    double modified_sl;    ///< If MODIFIED, the new SL
    double modified_tp;    ///< If MODIFIED, the new TP
};

/**
 * @struct RiskRuleConfig
 * @brief Configuration for all 21 risk rules.
 *
 * Each rule can be enabled/disabled and has configurable thresholds.
 */
struct RiskRuleConfig
{
    //--- Drawdown rules ---
    bool   max_daily_dd_enabled;
    double max_daily_dd_pct;
    bool   max_floating_dd_enabled;
    double max_floating_dd_pct;
    double critical_dd_pct;           ///< Absolute hard limit

    //--- Exposure rules ---
    bool   max_exposure_enabled;
    double max_exposure_pct;          ///< Max total exposure (% of equity)

    //--- Position rules ---
    bool   max_positions_enabled;
    int    max_concurrent_positions;

    //--- Trade frequency rules ---
    bool   max_trades_per_day_enabled;
    int    max_trades_per_day;
    bool   max_trades_per_hour_enabled;
    int    max_trades_per_hour;

    //--- Margin rules ---
    bool   min_free_margin_enabled;
    double min_free_margin;
    bool   min_margin_level_enabled;
    double min_margin_level;
    double critical_margin_level;

    //--- Market condition rules ---
    bool   max_spread_enabled;
    double max_spread_points;
    bool   max_volatility_enabled;
    double max_volatility_atr_mult;   ///< Max ATR / avg ATR ratio
    bool   fast_market_protection_enabled;
    double fast_market_atr_mult;      ///< ATR > avg × this = fast market

    //--- News lock (placeholder — no news API) ---
    bool   news_lock_enabled;
    int    news_lock_duration_sec;    ///< Manual news lock duration

    //--- Session restrictions ---
    bool   session_restriction_enabled;
    int    allowed_sessions;          ///< Bitmask of allowed sessions

    //--- Symbol restrictions ---
    bool   symbol_restriction_enabled;
    string allowed_symbols;           ///< Comma-separated, or "*" for all

    //--- Cooldown rules ---
    bool   strategy_cooldown_enabled;
    int    strategy_cooldown_sec;
    bool   portfolio_cooldown_enabled;
    int    portfolio_cooldown_sec;
    int    loss_streak_threshold;
    int    loss_streak_cooldown_sec;

    //--- Risk-reward validation ---
    bool   rr_validation_enabled;
    double min_rr_ratio;              ///< Minimum reward:risk ratio (e.g., 1.5)

    //--- Stop loss mandatory ---
    bool   mandatory_sl_enabled;

    //--- Volume limits ---
    bool   max_lot_enabled;
    double max_lot;
    bool   min_lot_enabled;
    double min_lot;

    /**
     * @brief Default constructor — sensible production defaults.
     */
    RiskRuleConfig(void)
    {
        //--- Drawdown ---
        max_daily_dd_enabled   = true;
        max_daily_dd_pct       = 5.0;
        max_floating_dd_enabled = true;
        max_floating_dd_pct    = 4.0;
        critical_dd_pct        = 8.0;

        //--- Exposure ---
        max_exposure_enabled   = true;
        max_exposure_pct       = 20.0;  ///< 20% of equity

        //--- Positions ---
        max_positions_enabled  = true;
        max_concurrent_positions = 5;

        //--- Trade frequency ---
        max_trades_per_day_enabled  = true;
        max_trades_per_day          = 20;
        max_trades_per_hour_enabled = true;
        max_trades_per_hour         = 5;

        //--- Margin ---
        min_free_margin_enabled  = true;
        min_free_margin          = 100.0;
        min_margin_level_enabled = true;
        min_margin_level         = 200.0;
        critical_margin_level    = 100.0;

        //--- Market conditions ---
        max_spread_enabled         = true;
        max_spread_points          = 50.0;
        max_volatility_enabled     = true;
        max_volatility_atr_mult    = 3.0;
        fast_market_protection_enabled = true;
        fast_market_atr_mult       = 2.5;

        //--- News lock ---
        news_lock_enabled      = false;  ///< Placeholder, off by default
        news_lock_duration_sec = 300;

        //--- Session ---
        session_restriction_enabled = false;  ///< Off by default
        allowed_sessions = 0x1F;              ///< All sessions allowed

        //--- Symbol ---
        symbol_restriction_enabled = false;
        allowed_symbols = "*";

        //--- Cooldown ---
        strategy_cooldown_enabled  = true;
        strategy_cooldown_sec      = 300;
        portfolio_cooldown_enabled = true;
        portfolio_cooldown_sec     = 1800;
        loss_streak_threshold      = 3;
        loss_streak_cooldown_sec   = 1800;

        //--- Risk-reward ---
        rr_validation_enabled = true;
        min_rr_ratio          = 1.0;

        //--- Stop loss ---
        mandatory_sl_enabled = true;

        //--- Volume ---
        max_lot_enabled = true;
        max_lot         = 10.0;
        min_lot_enabled = true;
        min_lot         = 0.01;
    }
};

/**
 * @class RiskRuleSet
 * @brief Evaluates all risk rules and returns a combined result.
 *
 * Rule Priority (highest to lowest):
 *   1. Kill switch (NON-BYPASSABLE)
 *   2. Daily drawdown (critical)
 *   3. Margin level (critical)
 *   4. Daily drawdown (configured limit)
 *   5. Floating drawdown
 *   6. Exposure limit
 *   7. Max concurrent positions
 *   8. Max trades per day
 *   9. Max trades per hour
 *  10. Cooldown (global + per-strategy)
 *  11. Fast market protection
 *  12. Max volatility
 *  13. Max spread
 *  14. Session restriction
 *  15. Symbol restriction
 *  16. News lock (placeholder)
 *  17. Mandatory stop loss
 *  18. Risk-reward validation
 *  19. Max lot size
 *  20. Min lot size
 *  21. Strategy cooldown (per-strategy)
 *
 * Returns a RuleResult that the RiskEvaluator uses to build the final
 * RiskDecision (APPROVED, REJECTED, or MODIFIED).
 */
class RiskRuleSet
{
private:
    ILogger          *m_logger;
    RiskRuleConfig    m_config;
    KillSwitch       *m_kill_switch;
    CooldownManager  *m_cooldown;
    ExposureCalculator *m_exposure;
    DrawdownMonitor  *m_drawdown;
    MarginMonitor    *m_margin;

    /// @brief Check if a symbol is allowed.
    bool IsSymbolAllowed(const string symbol) const
    {
        if(!m_config.symbol_restriction_enabled) return true;
        if(m_config.allowed_symbols == "*") return true;
        return (StringFind(m_config.allowed_symbols, symbol) >= 0);
    }

    /// @brief Check if a session is allowed.
    bool IsSessionAllowed(const int session) const
    {
        if(!m_config.session_restriction_enabled) return true;
        int mask = (1 << session);
        return ((m_config.allowed_sessions & mask) != 0);
    }

    /// @brief Check risk-reward ratio.
    bool IsRRValid(const double entry, const double sl, const double tp, const int direction) const
    {
        if(!m_config.rr_validation_enabled) return true;
        if(entry <= 0.0 || sl <= 0.0 || tp <= 0.0) return false;

        double risk = MathAbs(entry - sl);
        double reward = MathAbs(tp - entry);
        if(risk <= 0.0) return false;

        double rr = reward / risk;
        return (rr >= m_config.min_rr_ratio);
    }

public:
    /**
     * @brief Constructor.
     */
    RiskRuleSet(void)
    {
        m_logger    = NULL;
        m_kill_switch = NULL;
        m_cooldown  = NULL;
        m_exposure  = NULL;
        m_drawdown  = NULL;
        m_margin    = NULL;
    }

    /**
     * @brief Initialize.
     */
    void Initialize(ILogger *logger,
                    const RiskRuleConfig &config,
                    KillSwitch *ks,
                    CooldownManager *cd,
                    ExposureCalculator *ex,
                    DrawdownMonitor *dd,
                    MarginMonitor *mm)
    {
        m_logger      = logger;
        m_config      = config;
        m_kill_switch = ks;
        m_cooldown    = cd;
        m_exposure    = ex;
        m_drawdown    = dd;
        m_margin      = mm;
    }

    /**
     * @brief Evaluate all rules against a vote.
     * @param vote The aggregated vote to evaluate.
     * @param state Current risk state.
     * @param market Current market state.
     * @param context Shared context.
     * @param equity Current account equity.
     * @param strategy_id The strategy that produced the vote (for per-strategy cooldown).
     * @return RuleResult with the verdict.
     */
    RuleResult Evaluate(const AggregatedVote &vote,
                        const RiskState &state,
                        const MarketState &market,
                        IContextStore *context,
                        const double equity,
                        const int strategy_id) const
    {
        RuleResult result;
        result.code            = ATLAS_RULE_PASS;
        result.reason_code     = ATLAS_RISK_REASON_OK;
        result.reason_text     = "";
        result.modified_volume = 0.0;
        result.modified_sl     = 0.0;
        result.modified_tp     = 0.0;

        //==============================================================
        // RULE 1: Kill Switch (NON-BYPASSABLE)
        //==============================================================
        if(m_kill_switch != NULL && m_kill_switch.IsActive())
        {
            result.code        = ATLAS_RULE_FAIL_KILLSWITCH;
            result.reason_code = ATLAS_RISK_REASON_KILLSWITCH;
            result.reason_text = "Kill switch active: " + m_kill_switch.GetReason();
            return result;
        }

        //==============================================================
        // RULE 2: Daily Drawdown (Critical)
        //==============================================================
        if(m_config.max_daily_dd_enabled && m_drawdown != NULL)
        {
            if(m_drawdown.IsCritical(state))
            {
                if(m_kill_switch != NULL)
                    m_kill_switch.Activate(ATLAS_KS_REASON_DAILY_DD,
                                          m_drawdown.GetBreachReason(state));
                result.code        = ATLAS_RULE_FAIL_KILLSWITCH;
                result.reason_code = ATLAS_RISK_REASON_KILLSWITCH;
                result.reason_text = m_drawdown.GetBreachReason(state);
                return result;
            }
        }

        //==============================================================
        // RULE 3: Margin Level (Critical)
        //==============================================================
        if(m_config.min_margin_level_enabled && m_margin != NULL)
        {
            if(m_margin.IsCritical(state))
            {
                if(m_kill_switch != NULL)
                    m_kill_switch.Activate(ATLAS_KS_REASON_MARGIN_CRITICAL,
                                          m_margin.GetBreachReason(state));
                result.code        = ATLAS_RULE_FAIL_KILLSWITCH;
                result.reason_code = ATLAS_RISK_REASON_KILLSWITCH;
                result.reason_text = m_margin.GetBreachReason(state);
                return result;
            }
        }

        //==============================================================
        // RULE 4: Daily Drawdown (Configured Limit)
        //==============================================================
        if(m_config.max_daily_dd_enabled && m_drawdown != NULL)
        {
            if(!m_drawdown.IsWithinLimits(state))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_DRAWDOWN;
                result.reason_text = m_drawdown.GetBreachReason(state);
                return result;
            }
        }

        //==============================================================
        // RULE 5: Floating Drawdown (covered by Rule 4 in IsWithinLimits)
        //==============================================================

        //==============================================================
        // RULE 6: Exposure Limit
        //==============================================================
        if(m_config.max_exposure_enabled && m_exposure != NULL)
        {
            double proposed_vol = (vote.vote_count > 0) ? vote.votes[0].suggested_volume : 0.0;
            if(proposed_vol <= 0.0) proposed_vol = 0.10;  ///< Default assumption
            double projected = m_exposure.CalculateProjectedExposure(equity, proposed_vol);
            if(projected > m_config.max_exposure_pct)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_EXPOSURE;
                result.reason_text = "Exposure exceeded: " + DoubleToString(projected, 2) +
                                     "% >= " + DoubleToString(m_config.max_exposure_pct, 2) + "%";
                return result;
            }
        }

        //==============================================================
        // RULE 7: Max Concurrent Positions
        //==============================================================
        if(m_config.max_positions_enabled && context != NULL)
        {
            int pos_count = context.GetPositionCount();
            if(pos_count >= m_config.max_concurrent_positions)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_EXPOSURE;
                result.reason_text = "Max positions reached: " + IntegerToString(pos_count) +
                                     " >= " + IntegerToString(m_config.max_concurrent_positions);
                return result;
            }
        }

        //==============================================================
        // RULE 8: Max Trades Per Day
        //==============================================================
        if(m_config.max_trades_per_day_enabled)
        {
            if(state.trades_today >= m_config.max_trades_per_day)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_COOLDOWN;
                result.reason_text = "Max trades per day reached: " +
                                     IntegerToString(state.trades_today) + " >= " +
                                     IntegerToString(m_config.max_trades_per_day);
                return result;
            }
        }

        //==============================================================
        // RULE 9: Max Trades Per Hour
        //==============================================================
        if(m_config.max_trades_per_hour_enabled)
        {
            if(state.trades_this_hour >= m_config.max_trades_per_hour)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_COOLDOWN;
                result.reason_text = "Max trades per hour reached: " +
                                     IntegerToString(state.trades_this_hour) + " >= " +
                                     IntegerToString(m_config.max_trades_per_hour);
                return result;
            }
        }

        //==============================================================
        // RULE 10: Cooldown (Global)
        //==============================================================
        if(m_cooldown != NULL)
        {
            if(m_cooldown.IsGlobalCooldownActive(state))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_COOLDOWN;
                long remaining = m_cooldown.RemainingSeconds(state);
                result.reason_text = "Global cooldown active: " + IntegerToString(remaining) + "s remaining";
                return result;
            }
        }

        //==============================================================
        // RULE 11: Fast Market Protection
        //==============================================================
        if(m_config.fast_market_protection_enabled)
        {
            if(market.is_fast_market)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Fast market protection: market too volatile";
                return result;
            }
        }

        //==============================================================
        // RULE 12: Max Volatility
        //==============================================================
        if(m_config.max_volatility_enabled && market.atr_14 > 0.0)
        {
            //--- Use volatility_index as the ATR/price ratio × 10000
            if(market.volatility_index > m_config.max_volatility_atr_mult * 10.0)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Volatility too high: " + DoubleToString(market.volatility_index, 2);
                return result;
            }
        }

        //==============================================================
        // RULE 13: Max Spread
        //==============================================================
        if(m_config.max_spread_enabled && market.point > 0.0)
        {
            double spread_points = market.spread / market.point;
            if(spread_points > m_config.max_spread_points)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Spread too wide: " + DoubleToString(spread_points, 1) +
                                     " >= " + DoubleToString(m_config.max_spread_points, 1);
                return result;
            }
        }

        //==============================================================
        // RULE 14: Session Restriction
        //==============================================================
        if(m_config.session_restriction_enabled)
        {
            if(!IsSessionAllowed(market.session_state))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Session not allowed: " + IntegerToString(market.session_state);
                return result;
            }
        }

        //==============================================================
        // RULE 15: Symbol Restriction
        //==============================================================
        if(m_config.symbol_restriction_enabled)
        {
            if(!IsSymbolAllowed(market.symbol))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Symbol not allowed: " + market.symbol;
                return result;
            }
        }

        //==============================================================
        // RULE 16: News Lock (Placeholder)
        //==============================================================
        if(m_config.news_lock_enabled)
        {
            //--- Placeholder: no news API. Always pass.
            //--- Future: check economic calendar, lock trading around news events.
        }

        //==============================================================
        // RULE 17: Mandatory Stop Loss
        //==============================================================
        if(m_config.mandatory_sl_enabled && vote.vote_count > 0)
        {
            if(vote.votes[0].suggested_sl <= 0.0)
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Mandatory stop loss not set";
                return result;
            }
        }

        //==============================================================
        // RULE 18: Risk-Reward Validation
        //==============================================================
        if(m_config.rr_validation_enabled && vote.vote_count > 0)
        {
            if(!IsRRValid(vote.votes[0].suggested_entry,
                         vote.votes[0].suggested_sl,
                         vote.votes[0].suggested_tp,
                         vote.direction))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_INVALID;
                result.reason_text = "Risk-reward ratio too low (min " +
                                     DoubleToString(m_config.min_rr_ratio, 2) + ")";
                return result;
            }
        }

        //==============================================================
        // RULE 19: Max Lot Size (MODIFY if exceeded)
        //==============================================================
        if(m_config.max_lot_enabled && vote.vote_count > 0)
        {
            double vol = vote.votes[0].suggested_volume;
            if(vol > m_config.max_lot)
            {
                result.code            = ATLAS_RULE_FAIL_MODIFY;
                result.modified_volume = m_config.max_lot;
                if(m_logger != NULL)
                    m_logger.Info("RiskRuleSet",
                        "Volume reduced: " + DoubleToString(vol, 2) + " → " +
                        DoubleToString(m_config.max_lot, 2));
            }
        }

        //==============================================================
        // RULE 20: Min Lot Size (MODIFY if below)
        //==============================================================
        if(m_config.min_lot_enabled && vote.vote_count > 0)
        {
            double vol = (result.modified_volume > 0.0) ? result.modified_volume : vote.votes[0].suggested_volume;
            if(vol < m_config.min_lot)
            {
                result.code            = (result.code == ATLAS_RULE_PASS) ? ATLAS_RULE_FAIL_MODIFY : result.code;
                result.modified_volume = m_config.min_lot;
            }
        }

        //==============================================================
        // RULE 21: Strategy Cooldown (Per-Strategy)
        //==============================================================
        if(m_config.strategy_cooldown_enabled && m_cooldown != NULL)
        {
            if(m_cooldown.IsStrategyInCooldown(state, strategy_id))
            {
                result.code        = ATLAS_RULE_FAIL_REJECT;
                result.reason_code = ATLAS_RISK_REASON_COOLDOWN;
                result.reason_text = "Strategy " + IntegerToString(strategy_id) + " in cooldown";
                return result;
            }
        }

        //==============================================================
        // All rules passed (or only modifications applied)
        //==============================================================
        if(result.code == ATLAS_RULE_PASS)
        {
            result.reason_code = ATLAS_RISK_REASON_OK;
            result.reason_text = "";
        }

        return result;
    }

    /**
     * @brief Get the rule configuration.
     */
    const RiskRuleConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Set the rule configuration (runtime change).
     */
    void SetConfig(const RiskRuleConfig &config) { m_config = config; }
};

#endif // ATLAS_RISK_RULE_SET_MQH
//+------------------------------------------------------------------+
