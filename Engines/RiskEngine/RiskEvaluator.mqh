//+------------------------------------------------------------------+
//|             Engines/RiskEngine/RiskEvaluator.mqh                 |
//|       AtlasEA v0.1.11.0 - Risk Evaluation Orchestrator           |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_EVALUATOR_MQH
#define ATLAS_RISK_EVALUATOR_MQH

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
#include "PositionSizer.mqh"
#include "DrawdownMonitor.mqh"
#include "MarginMonitor.mqh"
#include "RiskRuleSet.mqh"

/**
 * @class RiskEvaluator
 * @brief Orchestrates risk evaluation.
 *
 * Pipeline:
 *   1. Update RiskState from context (equity, exposure, margin)
 *   2. Run RiskRuleSet.Evaluate()
 *   3. Build RiskDecision (APPROVED, REJECTED, or MODIFIED)
 *
 * The RiskDecision is IMMUTABLE once built. The caller (CoreEngine)
 * passes it to the ExecutionEngine if approved.
 */
class RiskEvaluator
{
private:
    ILogger              *m_logger;
    IContextStore        *m_context;
    RiskState             m_state;
    RiskRuleSet           m_rules;
    KillSwitch            m_kill_switch;
    CooldownManager       m_cooldown;
    ExposureCalculator    m_exposure;
    PositionSizer         m_sizer;
    DrawdownMonitor       m_drawdown;
    MarginMonitor         m_margin;
    SizerConfig           m_sizer_config;
    RiskRuleConfig        m_rule_config;
    double                m_contract_size;
    string                m_symbol;
    int                   m_decision_counter;

    /// @brief Generate a unique decision ID.
    string GenerateDecisionId(void)
    {
        m_decision_counter++;
        return "DEC_" + IntegerToString((long)TimeCurrent()) + "_" + IntegerToString(m_decision_counter);
    }

    /// @brief Build an APPROVED decision.
    RiskDecision BuildApproved(const AggregatedVote &vote, const RuleResult &rule,
                               const long snapshot_id)
    {
        RiskDecision d;
        d.decision_id            = GenerateDecisionId();
        d.aggregation_id         = vote.aggregation_id;
        d.status                 = ATLAS_DECISION_APPROVED;
        d.reason_code            = ATLAS_RISK_REASON_OK;
        d.rejection_reason       = "";

        //--- Use modified volume if the rule set adjusted it
        double vol = 0.0;
        if(rule.modified_volume > 0.0)
            vol = rule.modified_volume;
        else if(vote.vote_count > 0)
            vol = vote.votes[0].suggested_volume;

        //--- If volume still 0, use position sizer
        if(vol <= 0.0 && vote.vote_count > 0)
        {
            double entry = vote.votes[0].suggested_entry;
            double sl    = vote.votes[0].suggested_sl;
            double sl_dist = MathAbs(entry - sl);
            double equity = m_state.current_equity;
            vol = m_sizer.Calculate(equity, sl_dist, 0.0, 0.5);
        }

        d.approved_volume = vol;
        d.approved_price  = (vote.vote_count > 0) ? vote.votes[0].suggested_entry : 0.0;
        d.approved_sl     = (vote.vote_count > 0) ? vote.votes[0].suggested_sl : 0.0;
        d.approved_tp     = (vote.vote_count > 0) ? vote.votes[0].suggested_tp : 0.0;
        d.order_type      = vote.direction;
        d.kill_switch_triggered = false;
        d.snapshot_id     = snapshot_id;
        d.decision_time   = TimeCurrent();
        return d;
    }

    /// @brief Build a MODIFIED decision (trade allowed but adjusted).
    RiskDecision BuildModified(const AggregatedVote &vote, const RuleResult &rule,
                               const long snapshot_id)
    {
        RiskDecision d = BuildApproved(vote, rule, snapshot_id);
        d.status = ATLAS_DECISION_APPROVED;  ///< MODIFIED is still approved, just adjusted
        //--- Note: ATLAS_DECISION_DEFERRED exists but we use APPROVED for modified trades
        //--- The modification is reflected in approved_volume being different from suggested
        return d;
    }

    /// @brief Build a REJECTED decision.
    RiskDecision BuildRejected(const AggregatedVote &vote, const RuleResult &rule,
                               const long snapshot_id)
    {
        RiskDecision d;
        d.decision_id            = GenerateDecisionId();
        d.aggregation_id         = vote.aggregation_id;
        d.status                 = ATLAS_DECISION_REJECTED;
        d.reason_code            = rule.reason_code;
        d.rejection_reason       = rule.reason_text;
        d.approved_volume        = 0.0;
        d.approved_price         = 0.0;
        d.approved_sl            = 0.0;
        d.approved_tp            = 0.0;
        d.order_type             = ATLAS_ORDER_NONE;
        d.kill_switch_triggered  = (rule.code == ATLAS_RULE_FAIL_KILLSWITCH);
        d.snapshot_id            = snapshot_id;
        d.decision_time          = TimeCurrent();
        return d;
    }

public:
    /**
     * @brief Constructor.
     */
    RiskEvaluator(void)
    {
        m_logger            = NULL;
        m_context           = NULL;
        m_contract_size     = 100000.0;
        m_symbol            = "";
        m_decision_counter  = 0;
    }

    /**
     * @brief Initialize.
     * @param context Shared context store.
     * @param logger Logger.
     * @param config EA configuration.
     * @param rule_config Risk rule configuration.
     * @param sizer_config Position sizer configuration.
     */
    void Initialize(IContextStore *context, ILogger *logger,
                    const AtlasConfig &config,
                    const RiskRuleConfig &rule_config,
                    const SizerConfig &sizer_config)
    {
        m_logger        = logger;
        m_context       = context;
        m_contract_size = 100000.0;  ///< Would come from IBrokerAdapter in full integration
        m_symbol        = config.symbol;
        m_rule_config   = rule_config;
        m_sizer_config  = sizer_config;

        //--- Initialize components
        m_kill_switch.Initialize(context, logger);
        m_cooldown.Initialize(logger, rule_config.loss_streak_threshold,
                              rule_config.loss_streak_cooldown_sec);
        m_exposure.Initialize(context, logger, m_contract_size, m_symbol);
        m_sizer.Initialize(logger, sizer_config, m_contract_size);
        m_drawdown.Initialize(logger, rule_config.max_daily_dd_pct,
                              rule_config.max_floating_dd_pct,
                              rule_config.critical_dd_pct);
        m_margin.Initialize(logger, rule_config.min_free_margin,
                            rule_config.min_margin_level,
                            rule_config.critical_margin_level);
        m_rules.Initialize(logger, rule_config, &m_kill_switch, &m_cooldown,
                          &m_exposure, &m_drawdown, &m_margin);

        m_state.ResetAll();

        if(m_logger != NULL)
            m_logger.Info("RiskEvaluator", "Initialized (contract_size=" +
                          DoubleToString(m_contract_size, 0) + ")");
    }

    /**
     * @brief Get the current risk state (read-only).
     */
    const RiskState& GetState(void) const { return m_state; }

    /**
     * @brief Get the kill switch (for manual activation).
     */
    KillSwitch& GetKillSwitch(void) { return m_kill_switch; }

    /**
     * @brief Get the cooldown manager.
     */
    CooldownManager& GetCooldownManager(void) { return m_cooldown; }

    /**
     * @brief Get the position sizer.
     */
    PositionSizer& GetPositionSizer(void) { return m_sizer; }

    /**
     * @brief Get the rule set (for runtime config changes).
     */
    RiskRuleSet& GetRuleSet(void) { return m_rules; }

    /**
     * @brief Update risk state from context.
     * Called before evaluation to ensure state is current.
     * @param equity Current account equity (from broker adapter, passed via context).
     * @param floating_pnl Current floating PnL.
     * @param used_margin Current used margin.
     */
    void UpdateState(const double equity, const double floating_pnl, const double used_margin)
    {
        m_state.timestamp = TimeCurrent();

        //--- Update margin
        m_margin.Update(m_state, equity, used_margin);

        //--- Update drawdown
        m_drawdown.Update(m_state, m_context, equity, floating_pnl);

        //--- Update exposure
        m_exposure.UpdateState(m_state, equity);

        //--- Sync with context
        if(m_context != NULL)
        {
            m_state.consecutive_losses = m_context.GetConsecutiveLosses();
            m_state.trades_today       = m_context.GetDailyTradeCount();
            m_state.losses_today       = m_context.GetDailyLossCount();
            m_state.last_trade_time    = m_context.GetLastTradeTime();
            m_state.cooldown_until     = m_context.GetCooldownUntil();
            m_state.kill_switch_active = m_context.IsKillSwitchActive();
        }

        m_state.daily_pnl = m_state.daily_realized_pnl + m_state.daily_floating_pnl;
    }

    /**
     * @brief Evaluate a vote and return a risk decision.
     * @param vote The aggregated vote to evaluate.
     * @param market Current market state.
     * @param strategy_id The strategy that produced the vote.
     * @return Immutable RiskDecision.
     */
    RiskDecision Evaluate(const AggregatedVote &vote, const MarketState &market,
                          const int strategy_id)
    {
        //--- Run all rules
        RuleResult rule = m_rules.Evaluate(vote, m_state, market, m_context,
                                           m_state.current_equity, strategy_id);

        //--- Build decision based on rule result
        RiskDecision decision;
        switch(rule.code)
        {
            case ATLAS_RULE_PASS:
                decision = BuildApproved(vote, rule, vote.snapshot_id);
                break;

            case ATLAS_RULE_FAIL_MODIFY:
                decision = BuildModified(vote, rule, vote.snapshot_id);
                break;

            case ATLAS_RULE_FAIL_REJECT:
                decision = BuildRejected(vote, rule, vote.snapshot_id);
                break;

            case ATLAS_RULE_FAIL_KILLSWITCH:
                decision = BuildRejected(vote, rule, vote.snapshot_id);
                break;

            default:
                decision = BuildRejected(vote, rule, vote.snapshot_id);
                break;
        }

        return decision;
    }

    /**
     * @brief Handle a fill event (update consecutive losses, cooldowns).
     * @param event The execution event.
     */
    void OnFillEvent(const ExecutionEvent &event)
    {
        m_state.last_trade_time = event.execution_time;

        if(event.fill_status == ATLAS_FILL_FILLED || event.fill_status == ATLAS_FILL_PARTIAL)
        {
            m_state.trades_today++;
            if(m_context != NULL) m_context.IncrementDailyTradeCount();
        }

        if(event.fill_status == ATLAS_FILL_REJECTED || event.fill_status == ATLAS_FILL_TIMEOUT)
        {
            m_state.consecutive_losses++;
            m_state.losses_today++;
            if(m_context != NULL)
            {
                m_context.SetConsecutiveLosses(m_state.consecutive_losses);
                m_context.IncrementDailyLossCount();
            }

            //--- Check loss streak cooldown
            if(m_cooldown.CheckLossStreak(m_state))
            {
                if(m_context != NULL)
                    m_context.SetCooldownUntil(m_state.cooldown_until);

                //--- Critical consecutive losses → kill switch
                if(m_state.consecutive_losses >= ATLAS_KILL_SWITCH_LOSSES)
                {
                    m_kill_switch.Activate(ATLAS_KS_REASON_CONSECUTIVE_LOSSES,
                        "Consecutive losses: " + IntegerToString(m_state.consecutive_losses));
                }
            }
        }
        else if(event.fill_status == ATLAS_FILL_FILLED)
        {
            //--- Reset consecutive losses on a successful fill
            m_state.consecutive_losses = 0;
            if(m_context != NULL)
                m_context.SetConsecutiveLosses(0);
        }
    }

    /**
     * @brief Reset daily limits (called on new trading day).
     */
    void ResetDaily(void)
    {
        m_state.ResetDaily();
        m_cooldown.ClearAll(m_state);

        //--- Deactivate kill switch on new day
        m_kill_switch.Deactivate();

        if(m_context != NULL)
        {
            m_context.ResetDaily();
            m_context.SetConsecutiveLosses(0);
            m_context.SetCooldownUntil(0);
        }

        if(m_logger != NULL)
            m_logger.Info("RiskEvaluator", "Daily reset complete");
    }
};

#endif // ATLAS_RISK_EVALUATOR_MQH
//+------------------------------------------------------------------+
