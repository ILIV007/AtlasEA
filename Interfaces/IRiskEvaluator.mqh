//+------------------------------------------------------------------+
//|                                      Interfaces/IRiskEvaluator.mqh
//|                         AtlasEA v2.0 - Risk Evaluator Interface    |
//+------------------------------------------------------------------+
#ifndef ATLAS_IRISK_EVALUATOR_MQH
#define ATLAS_IRISK_EVALUATOR_MQH

#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Risk evaluation interface.
 *
 * Implemented by RiskEngine. Consumed by CoreEngine (PhaseScheduler).
 * Renders a RiskDecision for each AggregatedVote.
 *
 * Kill switch is NON-BYPASSABLE: if active, EvaluateRisk always returns REJECTED
 * with ATLAS_RISK_REASON_KILLSWITCH.
 */
class IRiskEvaluator
{
public:
    /**
     * @brief Evaluate an aggregated vote and render a risk decision.
     * @param vote Confidence-weighted aggregated vote from VoteAggregator.
     * @return RiskDecision (approved or rejected with reason_code).
     */
    virtual RiskDecision EvaluateRisk(const AggregatedVote &vote) = 0;

    /// @brief Update risk state after a fill event (consecutive losses, cooldown, etc.).
    virtual void UpdateRiskState(const ExecutionEvent &event) = 0;

    /// @brief Recompute current exposure from open positions.
    virtual void UpdateExposure(void) = 0;

    /// @brief Reset daily risk limits (called on new trading day).
    virtual void ResetDailyLimits(void) = 0;

    /// @brief Trigger the non-bypassable kill switch.
    virtual void TriggerKillSwitch(const string reason) = 0;

    /// @brief Initialize the risk evaluator.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the risk evaluator.
    virtual void Shutdown(void) = 0;

    virtual ~IRiskEvaluator(void) {}
};

#endif // ATLAS_IRISK_EVALUATOR_MQH
//+------------------------------------------------------------------+
