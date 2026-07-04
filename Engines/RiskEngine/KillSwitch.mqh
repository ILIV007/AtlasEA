//+------------------------------------------------------------------+
//|              Engines/RiskEngine/KillSwitch.mqh                   |
//|       AtlasEA v0.1.11.0 - Non-Bypassable Kill Switch             |
//+------------------------------------------------------------------+
#ifndef ATLAS_KILL_SWITCH_MQH
#define ATLAS_KILL_SWITCH_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"

/**
 * @class KillSwitch
 * @brief Non-bypassable emergency stop.
 *
 * When active, ALL trades are rejected. No automatic reset.
 * Only manual reset (via Deactivate) or daily reset clears it.
 *
 * Triggers:
 *   - Daily drawdown exceeded
 *   - Floating drawdown exceeded
 *   - Margin level critical
 *   - Reconciliation mismatch
 *   - Corrupted RiskState
 *   - Manual activation
 *   - Consecutive losses exceeded
 *
 * Memory: stateless (operates on IContextStore + RiskState).
 */
class KillSwitch
{
private:
    ILogger       *m_logger;
    IContextStore *m_context;

public:
    /**
     * @brief Constructor.
     */
    KillSwitch(void) { m_logger = NULL; m_context = NULL; }

    /**
     * @brief Initialize.
     * @param context The shared context store.
     * @param logger  Logger.
     */
    void Initialize(IContextStore *context, ILogger *logger)
    {
        m_context = context;
        m_logger  = logger;
    }

    /**
     * @brief Check if the kill switch is currently active.
     * @return true if active (all trades must be rejected).
     */
    bool IsActive(void) const
    {
        if(m_context == NULL) return true;  ///< Defensive: no context = no trading
        return m_context.IsKillSwitchActive();
    }

    /**
     * @brief Get the activation reason.
     */
    string GetReason(void) const
    {
        if(m_context == NULL) return "no_context";
        return m_context.GetKillSwitchReason();
    }

    /**
     * @brief Get the activation time.
     */
    datetime GetTime(void) const
    {
        if(m_context == NULL) return 0;
        return m_context.GetKillSwitchTime();
    }

    /**
     * @brief Activate the kill switch.
     * Idempotent — activating when already active is a no-op.
     * @param reason_code Machine-readable reason (ATLAS_KS_REASON_*).
     * @param reason_text Human-readable reason.
     */
    void Activate(const int reason_code, const string reason_text)
    {
        if(m_context == NULL) return;
        if(m_context.IsKillSwitchActive())
        {
            if(m_logger != NULL)
                m_logger.Debug("KillSwitch", "Already active: " + m_context.GetKillSwitchReason());
            return;
        }

        m_context.ActivateKillSwitch(reason_text);

        if(m_logger != NULL)
            m_logger.Fatal("KillSwitch", "*** KILL SWITCH ACTIVATED *** [" +
                          IntegerToString(reason_code) + "] " + reason_text);
    }

    /**
     * @brief Deactivate the kill switch (manual reset only).
     * This is the ONLY way to clear the kill switch besides daily reset.
     */
    void Deactivate(void)
    {
        if(m_context == NULL) return;
        if(!m_context.IsKillSwitchActive()) return;

        string prev_reason = m_context.GetKillSwitchReason();
        m_context.DeactivateKillSwitch();

        if(m_logger != NULL)
            m_logger.Info("KillSwitch", "Deactivated (was: " + prev_reason + ")");
    }

    /**
     * @brief Manual trigger (operator-initiated).
     */
    void ManualTrigger(const string reason)
    {
        Activate(ATLAS_KS_REASON_MANUAL, "MANUAL: " + reason);
    }
};

#endif // ATLAS_KILL_SWITCH_MQH
//+------------------------------------------------------------------+
