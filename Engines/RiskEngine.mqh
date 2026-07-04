//+------------------------------------------------------------------+
//|                                       Engines/RiskEngine.mqh     |
//|          AtlasEA v0.1.11.0 - Risk Engine (Final Authority)       |
//|                                                                  |
//|  Implements IRiskEvaluator. The Risk Engine is the FINAL         |
//|  authority before any order reaches the Execution Engine.        |
//|  It NEVER generates trading signals. It NEVER interacts with     |
//|  the broker directly. All data comes from IContextStore.         |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_ENGINE_MQH
#define ATLAS_RISK_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "RiskEngine/RiskState.mqh"
#include "RiskEngine/KillSwitch.mqh"
#include "RiskEngine/CooldownManager.mqh"
#include "RiskEngine/ExposureCalculator.mqh"
#include "RiskEngine/PositionSizer.mqh"
#include "RiskEngine/DrawdownMonitor.mqh"
#include "RiskEngine/MarginMonitor.mqh"
#include "RiskEngine/RiskRuleSet.mqh"
#include "RiskEngine/RiskEvaluator.mqh"

/**
 * @class RiskEngine
 * @brief Implements IRiskEvaluator. The final risk authority.
 *
 * This class is a thin adapter that delegates to RiskEvaluator.
 * It receives dependencies via SetDependencies() and forwards
 * IRiskEvaluator calls to the internal RiskEvaluator.
 *
 * The RiskEngine does NOT:
 *   - Generate trading signals
 *   - Call broker APIs directly (OrderSend, AccountInfo, SymbolInfo, PositionGet)
 *   - Modify contracts
 *   - Bypass the kill switch
 *
 * All data comes from IContextStore (read-only) and AtlasConfig.
 */
class RiskEngine : public IRiskEvaluator
{
private:
    //=== Dependencies (injected) ===
    ILogger        *m_logger;
    IContextStore  *m_context;
    IBrokerAdapter *m_broker;       ///< For queries only (equity, margin, contract size)
    AtlasConfig     m_config;

    //=== Internal components (stack-allocated, owned) ===
    RiskEvaluator   m_evaluator;
    RiskRuleConfig  m_rule_config;
    SizerConfig     m_sizer_config;

    //=== Cached market state (updated each tick) ===
    MarketState     m_last_market;

    //=== State ===
    bool m_initialized;

    /// @brief Read equity from broker (via IBrokerAdapter interface).
    double GetEquity(void) const
    {
        if(m_broker != NULL) return m_broker.AccountEquity();
        return 0.0;
    }

    /// @brief Read used margin from broker.
    double GetUsedMargin(void) const
    {
        if(m_broker != NULL) return m_broker.AccountMargin();
        return 0.0;
    }

    /// @brief Read contract size from broker.
    double GetContractSize(void) const
    {
        if(m_broker != NULL) return m_broker.SymbolContractSize();
        return 100000.0;
    }

    /// @brief Read floating PnL from context.
    double GetFloatingPnl(void) const
    {
        if(m_context != NULL) return m_context.GetTotalFloatingPnl();
        return 0.0;
    }

public:
    /**
     * @brief Constructor.
     */
    RiskEngine(void)
    {
        m_logger       = NULL;
        m_context      = NULL;
        m_broker       = NULL;
        m_initialized  = false;
        ZeroMemory(m_config);
        ZeroMemory(m_last_market);
    }

    /**
     * @brief Destructor — calls Shutdown.
     */
    ~RiskEngine(void) { Shutdown(); }

    /**
     * @brief Set dependencies. Must be called before Initialize().
     * @param logger  Logger (REQUIRED).
     * @param context Context store (REQUIRED — source of all state).
     * @param broker  Broker adapter (for equity/margin/contract size queries).
     * @param config  EA configuration.
     */
    void SetDependencies(ILogger *logger, IContextStore *context,
                         IBrokerAdapter *broker, const AtlasConfig &config)
    {
        m_logger  = logger;
        m_context = context;
        m_broker  = broker;
        m_config  = config;
    }

    /**
     * @brief Set the risk rule configuration (optional, uses defaults if not called).
     */
    void SetRuleConfig(const RiskRuleConfig &config) { m_rule_config = config; }

    /**
     * @brief Set the position sizer configuration (optional, uses defaults if not called).
     */
    void SetSizerConfig(const SizerConfig &config) { m_sizer_config = config; }

    //=== IRiskEvaluator implementation ===

    /**
     * @brief Evaluate an aggregated vote and render a risk decision.
     *
     * This is the MAIN entry point. Called by CoreEngine PhaseScheduler.
     *
     * @param vote Confidence-weighted aggregated vote.
     * @return Immutable RiskDecision (APPROVED, REJECTED, or MODIFIED-as-APPROVED).
     */
    virtual RiskDecision EvaluateRisk(const AggregatedVote &vote) override
    {
        if(!m_initialized || m_context == NULL)
        {
            RiskDecision d;
            d.decision_id       = "DEC_ERROR";
            d.aggregation_id    = vote.aggregation_id;
            d.status            = ATLAS_DECISION_REJECTED;
            d.reason_code       = ATLAS_RISK_REASON_NO_CONTEXT;
            d.rejection_reason  = "RiskEngine not initialized or no context";
            d.approved_volume   = 0.0;
            d.approved_price    = 0.0;
            d.approved_sl       = 0.0;
            d.approved_tp       = 0.0;
            d.order_type        = ATLAS_ORDER_NONE;
            d.kill_switch_triggered = false;
            d.snapshot_id       = vote.snapshot_id;
            d.decision_time     = TimeCurrent();
            return d;
        }

        //--- Update internal state from broker (via adapter) + context
        double equity      = GetEquity();
        double used_margin = GetUsedMargin();
        double floating    = GetFloatingPnl();
        m_evaluator.UpdateState(equity, floating, used_margin);

        //--- Get the strategy ID from the vote (first vote's strategy)
        int strategy_id = 0;
        if(vote.vote_count > 0)
            strategy_id = vote.votes[0].strategy_id;

        //--- Evaluate
        return m_evaluator.Evaluate(vote, m_last_market, strategy_id);
    }

    /**
     * @brief Update risk state after a fill event.
     * Called by CoreEngine when EV_TRADE_EXECUTED is processed.
     * @param event The execution event from the broker.
     */
    virtual void UpdateRiskState(const ExecutionEvent &event) override
    {
        if(!m_initialized) return;
        m_evaluator.OnFillEvent(event);
    }

    /**
     * @brief Recompute current exposure from open positions.
     * Called by CoreEngine on heartbeat.
     */
    virtual void UpdateExposure(void) override
    {
        if(!m_initialized || m_context == NULL) return;
        double equity = GetEquity();
        double floating = GetFloatingPnl();
        double used_margin = GetUsedMargin();
        m_evaluator.UpdateState(equity, floating, used_margin);

        //--- Sync exposure back to context
        const RiskState &state = m_evaluator.GetState();
        m_context.SetCurrentExposurePct(state.current_exposure_pct);
        m_context.SetTotalFloatingPnl(state.daily_floating_pnl);
    }

    /**
     * @brief Reset daily risk limits.
     * Called by CoreEngine on new trading day.
     */
    virtual void ResetDailyLimits(void) override
    {
        if(!m_initialized) return;
        m_evaluator.ResetDaily();
    }

    /**
     * @brief Trigger the non-bypassable kill switch.
     * @param reason Human-readable reason.
     */
    virtual void TriggerKillSwitch(const string reason) override
    {
        if(!m_initialized) return;
        m_evaluator.GetKillSwitch().ManualTrigger(reason);
    }

    /**
     * @brief Initialize the risk engine.
     * Requires SetDependencies() first.
     * @return true if initialization succeeded.
     */
    virtual bool Initialize(void) override
    {
        if(m_logger == NULL || m_context == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("RiskEngine", "Initialize: logger or context is NULL");
            return false;
        }

        m_evaluator.Initialize(m_context, m_logger, m_config, m_rule_config, m_sizer_config);

        m_initialized = true;
        m_logger.Info("RiskEngine",
            "Initialized. MaxDD=" + DoubleToString(m_rule_config.max_daily_dd_pct, 1) +
            "% MaxExposure=" + DoubleToString(m_rule_config.max_exposure_pct, 1) +
            "% MaxPositions=" + IntegerToString(m_rule_config.max_concurrent_positions));
        return true;
    }

    /**
     * @brief Shutdown the risk engine.
     */
    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;

        if(m_logger != NULL)
        {
            const RiskState &state = m_evaluator.GetState();
            m_logger.Info("RiskEngine",
                "Shutdown. Trades=" + IntegerToString(state.trades_today) +
                " Wins=" + IntegerToString(state.wins_today) +
                " Losses=" + IntegerToString(state.losses_today) +
                " KillSwitch=" + (state.kill_switch_active ? "ACTIVE" : "inactive"));
        }

        //--- Clear cached market state so a re-Initialize() starts clean.
        //    Without this, the first EvaluateRisk() after restart would use
        //    stale market data from the previous session.
        ZeroMemory(m_last_market);

        m_initialized = false;
    }

    //=== Extended API (not part of IRiskEvaluator) ===

    /**
     * @brief Update the last seen market state.
     * Called by CoreEngine before EvaluateRisk() to provide current market data.
     * @param market The current market state.
     */
    void UpdateMarketState(const MarketState &market)
    {
        m_last_market = market;
    }

    /**
     * @brief Get the current risk state (for diagnostics).
     */
    const RiskState& GetRiskState(void) const { return m_evaluator.GetState(); }

    /**
     * @brief Get the kill switch (for manual control).
     */
    KillSwitch& GetKillSwitch(void) { return m_evaluator.GetKillSwitch(); }

    /**
     * @brief Get the position sizer (for runtime config).
     */
    PositionSizer& GetPositionSizer(void) { return m_evaluator.GetPositionSizer(); }

    /**
     * @brief Get the rule set (for runtime config changes).
     */
    RiskRuleSet& GetRuleSet(void) { return m_evaluator.GetRuleSet(); }

    /**
     * @brief Log diagnostics.
     */
    void LogDiagnostics(void) const
    {
        if(m_logger == NULL) return;
        const RiskState &s = m_evaluator.GetState();
        m_logger.Info("RiskEngine",
            "Equity=" + DoubleToString(s.current_equity, 2) +
            " DD=" + DoubleToString(s.daily_drawdown_pct, 2) + "%" +
            " FloatDD=" + DoubleToString(s.floating_drawdown_pct, 2) + "%" +
            " Exposure=" + DoubleToString(s.current_exposure_pct, 2) + "%" +
            " Margin=" + DoubleToString(s.margin_level, 1) + "%" +
            " Trades=" + IntegerToString(s.trades_today) +
            " LossStreak=" + IntegerToString(s.consecutive_losses) +
            " KillSwitch=" + (s.kill_switch_active ? "ACTIVE" : "off"));
    }

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate internal state for consistency.
     * @return ValidationResult — Ok() if all invariants hold, Fail() otherwise.
     *
     * Invariants checked:
     *   - m_logger != NULL (required dependency)
     *   - m_context != NULL (required dependency — source of all state)
     *   - m_broker != NULL (required dependency — for equity/margin/contract size)
     *   - m_initialized is true
     *   - if m_last_market.snapshot_id > 0, the cached MarketState must be
     *     valid (delegated to MarketState.Validate()). When snapshot_id == 0
     *     the cached state has not yet been populated by UpdateMarketState(),
     *     so its validation is skipped.
     *
     * Non-throwing (MQL5 has no exceptions).
     */
    ValidationResult Validate(void) const
    {
        if(m_logger == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "logger is NULL", "m_logger");
        if(m_context == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "context store is NULL", "m_context");
        if(m_broker == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "broker adapter is NULL", "m_broker");
        if(!m_initialized)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "engine not initialized", "m_initialized");
        if(m_last_market.snapshot_id > 0)
        {
            ValidationResult mr = m_last_market.Validate();
            if(!mr.valid) return mr;
        }
        return ValidationResult::Ok();
    }

    /// @brief Convenience wrapper — true if Validate() passes.
    bool IsValid(void) const { return Validate().valid; }
};

#endif // ATLAS_RISK_ENGINE_MQH
//+------------------------------------------------------------------+
