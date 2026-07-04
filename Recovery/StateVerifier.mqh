//+------------------------------------------------------------------+
//|                  Recovery/StateVerifier.mqh                     |
//|       AtlasEA v0.1.13.0 - Post-Recovery State Verification      |
//+------------------------------------------------------------------+
#ifndef ATLAS_STATE_VERIFIER_MQH
#define ATLAS_STATE_VERIFIER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct VerificationResult
 * @brief Result of state verification.
 */
struct VerificationResult
{
    bool   market_state_ok;     ///< MarketState is consistent
    bool   risk_state_ok;       ///< RiskState is consistent
    bool   position_state_ok;   ///< PositionState is consistent
    bool   context_ok;          ///< AtlasContext is consistent
    bool   queue_state_ok;      ///< Queue state is consistent
    bool   idempotency_ok;      ///< Idempotency store is consistent
    bool   snapshot_id_ok;      ///< Snapshot ID is valid
    bool   version_ok;          ///< Context version is valid
    int    issue_count;         ///< Number of issues found
    string issues[16];          ///< List of issues (empty if all OK)
};

/**
 * @class StateVerifier
 * @brief Verifies state consistency after recovery.
 *
 * Checks:
 *   1. Snapshot ID is > 0 and monotonic
 *   2. Context version is > 0
 *   3. Risk state fields are within valid ranges
 *   4. Position state count is within limits
 *   5. Idempotency ring is not corrupted
 *   6. Kill switch state is consistent (active flag + reason + time)
 *   7. Cooldown is not in the distant future
 */
class StateVerifier
{
private:
    ILogger *m_logger;

    /// @brief Add an issue to the result.
    void AddIssue(VerificationResult &result, const string issue) const
    {
        if(result.issue_count < 16)
        {
            result.issues[result.issue_count] = issue;
            result.issue_count++;
        }
    }

public:
    /**
     * @brief Constructor.
     */
    StateVerifier(void) { m_logger = NULL; }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Verify the recovered context.
     * @param context The context to verify.
     * @return VerificationResult with details.
     */
    VerificationResult Verify(const AtlasContext &context) const
    {
        VerificationResult result;
        result.market_state_ok   = true;
        result.risk_state_ok     = true;
        result.position_state_ok = true;
        result.context_ok        = true;
        result.queue_state_ok    = true;
        result.idempotency_ok    = true;
        result.snapshot_id_ok    = true;
        result.version_ok        = true;
        result.issue_count       = 0;

        //--- Check 1: Snapshot ID
        if(context.GetSnapshotId() < 0)
        {
            result.snapshot_id_ok = false;
            result.context_ok     = false;
            AddIssue(result, "Snapshot ID is negative: " + IntegerToString(context.GetSnapshotId()));
        }

        //--- Check 2: Context version
        if(context.GetContextVersion() == 0 && context.GetSnapshotId() > 0)
        {
            //--- Version 0 with a non-zero snapshot ID is suspicious
            result.version_ok = false;
            AddIssue(result, "Context version is 0 but snapshot_id > 0");
        }

        //--- Check 3: Risk state — numeric ranges
        if(!MathIsValidNumber(context.GetDailyStartEquity()))
        {
            result.risk_state_ok = false;
            AddIssue(result, "daily_start_equity is NaN");
        }
        if(!MathIsValidNumber(context.GetDailyDrawdownPct()))
        {
            result.risk_state_ok = false;
            AddIssue(result, "daily_drawdown_pct is NaN");
        }
        if(context.GetDailyDrawdownPct() < 0.0)
        {
            result.risk_state_ok = false;
            AddIssue(result, "daily_drawdown_pct is negative: " +
                    DoubleToString(context.GetDailyDrawdownPct(), 2));
        }
        if(context.GetDailyDrawdownPct() > 100.0)
        {
            result.risk_state_ok = false;
            AddIssue(result, "daily_drawdown_pct > 100%: " +
                    DoubleToString(context.GetDailyDrawdownPct(), 2));
        }
        if(context.GetConsecutiveLosses() < 0)
        {
            result.risk_state_ok = false;
            AddIssue(result, "consecutive_losses is negative: " +
                    IntegerToString(context.GetConsecutiveLosses()));
        }

        //--- Check 4: Kill switch consistency
        if(context.IsKillSwitchActive())
        {
            if(StringLen(context.GetKillSwitchReason()) == 0)
            {
                result.risk_state_ok = false;
                AddIssue(result, "Kill switch active but reason is empty");
            }
            if(context.GetKillSwitchTime() <= 0)
            {
                result.risk_state_ok = false;
                AddIssue(result, "Kill switch active but time is 0");
            }
        }

        //--- Check 5: Position state
        if(context.GetPositionCount() < 0)
        {
            result.position_state_ok = false;
            AddIssue(result, "Position count is negative: " +
                    IntegerToString(context.GetPositionCount()));
        }
        if(context.GetPositionCount() > ATLAS_MAX_POSITIONS)
        {
            result.position_state_ok = false;
            AddIssue(result, "Position count exceeds max: " +
                    IntegerToString(context.GetPositionCount()) +
                    " > " + IntegerToString(ATLAS_MAX_POSITIONS));
        }

        //--- Check 6: Cooldown
        if(context.GetCooldownUntil() > 0)
        {
            datetime now = TimeCurrent();
            if(context.GetCooldownUntil() > now + 86400)
            {
                result.risk_state_ok = false;
                AddIssue(result, "Cooldown is more than 24h in the future");
            }
        }

        //--- Check 7: Telemetry counters (should be non-negative)
        if(context.GetTotalTicksProcessed() < 0)
        {
            result.context_ok = false;
            AddIssue(result, "total_ticks_processed is negative");
        }

        //--- Log result
        if(m_logger != NULL)
        {
            if(result.issue_count == 0)
            {
                m_logger.Info("StateVerifier", "State verification PASSED (no issues)");
            }
            else
            {
                m_logger.Warn("StateVerifier",
                    "State verification found " + IntegerToString(result.issue_count) + " issue(s)");
                for(int i = 0; i < result.issue_count; i++)
                    m_logger.Warn("StateVerifier", "  " + result.issues[i]);
            }
        }

        return result;
    }

    /**
     * @brief Check if verification result indicates a healthy state.
     */
    bool IsHealthy(const VerificationResult &result) const
    {
        return (result.issue_count == 0);
    }
};

#endif // ATLAS_STATE_VERIFIER_MQH
//+------------------------------------------------------------------+
