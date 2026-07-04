//+------------------------------------------------------------------+
//|                    Recovery/RecoveryManager.mqh                 |
//|       AtlasEA v0.1.13.0 - Recovery Manager (Full Implementation)|
//+------------------------------------------------------------------+
#ifndef ATLAS_RECOVERY_MANAGER_MQH
#define ATLAS_RECOVERY_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IStateStore.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IRecoveryManager.mqh"
#include "SnapshotValidator.mqh"
#include "EventReplayer.mqh"
#include "StateVerifier.mqh"
#include "BrokerReconciler.mqh"

/**
 * @class RecoveryManager
 * @brief Full implementation of IRecoveryManager.
 *
 * Recovery pipeline:
 *   1. Detect crash (no clean shutdown marker)
 *   2. Load latest snapshot via IStateStore
 *   3. Validate snapshot via SnapshotValidator
 *   4. If snapshot invalid → try fallback (cold start)
 *   5. Check event log integrity via EventReplayer (NOT replay — state from snapshots)
 *   6. Verify state via StateVerifier
 *   7. Reconcile with broker via BrokerReconciler
 *   8. Determine recovery status (GREEN/YELLOW/RED)
 *   9. Enter Safe Mode if recovery failed
 *
 * Safe Mode:
 *   If recovery fails (RED), the system enters Safe Mode:
 *   - No new trades (ATLAS_SAFE_MODE_NO_NEW_TRADES)
 *   - Monitoring only (ATLAS_SAFE_MODE_MONITORING_ONLY)
 *   - Broker sync allowed (ATLAS_SAFE_MODE_BROKER_SYNC)
 *   The operator must manually clear Safe Mode after verifying health.
 */
class RecoveryManager : public IRecoveryManager
{
private:
    //=== Dependencies ===
    ILogger        *m_logger;
    IStateStore    *m_state_store;
    IBrokerAdapter *m_broker;
    IEventBus      *m_event_bus;
    AtlasConfig     m_config;

    //=== Components ===
    SnapshotValidator  m_snapshot_validator;
    EventReplayer      m_event_replayer;
    StateVerifier      m_state_verifier;
    BrokerReconciler   m_broker_reconciler;

    //=== State ===
    RecoveryStatistics m_stats;
    int                m_safe_mode_flags;
    bool               m_recovery_completed;

    /// @brief Detect if the previous session ended cleanly.
    /// In this phase, we check for a shutdown marker file.
    /// If the marker is missing, it indicates an unexpected shutdown.
    int DetectCrash(void) const
    {
        //--- Check for clean shutdown marker
        string marker_file = "AtlasEA_" + m_config.symbol + "_shutdown.marker";
        if(FileIsExist(marker_file))
        {
            //--- Clean shutdown — delete the marker for next time
            FileDelete(marker_file);
            return ATLAS_CRASH_NONE;
        }
        return ATLAS_CRASH_UNEXPECTED_SHUTDOWN;
    }

    /// @brief Initialize statistics.
    void InitStats(void)
    {
        m_stats.status                  = ATLAS_RECOVERY_NONE;
        m_stats.crash_code              = ATLAS_CRASH_NONE;
        m_stats.safe_mode_flags         = ATLAS_SAFE_MODE_NONE;
        m_stats.recovery_time_ms        = 0.0;
        m_stats.replay_count            = 0;
        m_stats.dropped_events          = 0;
        m_stats.recovered_positions     = 0;
        m_stats.position_mismatches     = 0;
        m_stats.risk_state_recovered    = false;
        m_stats.recovery_errors         = 0;
        m_stats.failure_reason          = "";
        m_stats.recovery_time           = 0;
        m_stats.snapshot_found          = false;
        m_stats.snapshot_valid          = false;
        m_stats.event_log_found         = false;
        m_stats.broker_reconciled       = false;

        //--- Reset class-level state members (not just the stats struct).
        //    Without this, safe-mode flags survive across Recover() calls.
        m_safe_mode_flags    = ATLAS_SAFE_MODE_NONE;
        m_recovery_completed = false;
    }

public:
    /**
     * @brief Constructor.
     */
    RecoveryManager(void)
    {
        m_logger             = NULL;
        m_state_store        = NULL;
        m_broker             = NULL;
        m_event_bus          = NULL;
        m_safe_mode_flags    = ATLAS_SAFE_MODE_NONE;
        m_recovery_completed = false;
        InitStats();
    }

    /**
     * @brief Set dependencies (called by Bootstrap before Recover()).
     * @param logger Logger.
     * @param state_store State store (persistence).
     * @param broker Broker adapter (for reconciliation).
     * @param event_bus Event bus (for reconcile events).
     * @param config EA configuration.
     */
    void SetDependencies(ILogger *logger, IStateStore *state_store,
                         IBrokerAdapter *broker, IEventBus *event_bus,
                         const AtlasConfig &config)
    {
        m_logger      = logger;
        m_state_store = state_store;
        m_broker      = broker;
        m_event_bus   = event_bus;
        m_config      = config;

        //--- Initialize components
        m_snapshot_validator.Initialize(logger, config.magic_number, 1, config.symbol);
        m_event_replayer.Initialize(logger, state_store);
        m_state_verifier.SetLogger(logger);
        m_broker_reconciler.Initialize(logger, broker, event_bus, config.magic_number);
    }

    /**
     * @brief Validate runtime invariants of the RecoveryManager.
     *
     * Contract:
     *   - If dependencies have been injected (m_logger != NULL or
     *     m_state_store != NULL), then m_state_store MUST be non-NULL
     *     (recovery cannot proceed without a state store) and
     *     m_safe_mode_flags MUST be >= 0.
     *   - Pre-init state (all pointers NULL before SetDependencies)
     *     is explicitly valid — callers may run Validate() before wiring.
     *
     * @return ValidationResult::Ok() on success, Fail() on first violation.
     */
    ValidationResult Validate(void) const
    {
        //--- Pre-init state: nothing wired yet. Validating here is allowed
        //    and must return Ok() (e.g. Bootstrapper may validate before
        //    SetDependencies completes).
        bool initialized = (m_logger != NULL || m_state_store != NULL);
        if(!initialized)
            return ValidationResult::Ok();

        //--- Post-init invariants
        if(m_state_store == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "State store is NULL after SetDependencies",
                "m_state_store");

        if(m_safe_mode_flags < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "Safe-mode flags must be >= 0",
                "m_safe_mode_flags");

        return ValidationResult::Ok();
    }

    //=== IRecoveryManager implementation ===

    virtual bool Recover(AtlasContext &context, RecoveryStatistics &stats) override
    {
        InitStats();
        ulong start_ms = GetTickCount64();

        if(m_logger != NULL)
            m_logger.Info("RecoveryManager", "=== Recovery started ===");

        //==============================================================
        // STEP 1: Crash Detection
        //==============================================================
        m_stats.crash_code = DetectCrash();
        if(m_stats.crash_code != ATLAS_CRASH_NONE)
        {
            if(m_logger != NULL)
                m_logger.Warn("RecoveryManager",
                    "Crash detected: code=" + IntegerToString(m_stats.crash_code));
        }

        //==============================================================
        // STEP 2: Load Latest Snapshot
        //==============================================================
        if(m_state_store == NULL)
        {
            m_stats.status         = ATLAS_RECOVERY_RED;
            m_stats.failure_reason = "State store is NULL";
            m_stats.recovery_errors++;
            EnterSafeMode();
            FinalizeRecovery(start_ms);
            stats = m_stats;
            return false;
        }

        bool snapshot_loaded = m_state_store.RecoverState(context);

        if(!snapshot_loaded)
        {
            //--- No snapshot found — cold start (not an error)
            if(m_logger != NULL)
                m_logger.Info("RecoveryManager", "No snapshot found — cold start");

            m_stats.snapshot_found = false;
            m_stats.snapshot_valid = false;
            m_stats.status         = ATLAS_RECOVERY_GREEN;  ///< Cold start is OK

            //--- Still reconcile with broker
            ReconcileBroker(context);

            FinalizeRecovery(start_ms);
            stats = m_stats;
            return true;
        }

        m_stats.snapshot_found = true;
        m_stats.snapshot_valid = true;

        if(m_logger != NULL)
            m_logger.Info("RecoveryManager",
                "Snapshot loaded: id=" + IntegerToString(context.GetSnapshotId()));

        //==============================================================
        // STEP 2b: Validate Recovered Context Invariants
        //==============================================================
        //--- The snapshot may have deserialized corrupt or inconsistent
        //    state (NaN equity, broken monotonicity, etc.). AtlasContext.
        //    Validate() runs the full Design-by-Contract invariant suite.
        //    If it fails, the recovered context MUST NOT be used — enter
        //    safe mode and abort recovery (same path as a RED snapshot).
        ValidationResult ctx_result = context.Validate();
        if(!ctx_result.valid)
        {
            m_stats.snapshot_valid = false;
            m_stats.recovery_errors++;

            if(m_logger != NULL)
                m_logger.Error("RecoveryManager",
                    "Recovered context validation failed: " + ctx_result.Summary());

            m_stats.status         = ATLAS_RECOVERY_RED;
            m_stats.failure_reason = "Context invalid: " + ctx_result.Summary();
            EnterSafeMode();
            FinalizeRecovery(start_ms);
            stats = m_stats;
            return false;
        }

        //==============================================================
        // STEP 3: Validate Snapshot
        //==============================================================
        SnapshotValidationResult snap_result = m_snapshot_validator.Validate(context);

        if(!snap_result.valid)
        {
            m_stats.snapshot_valid = false;
            m_stats.recovery_errors++;

            if(m_logger != NULL)
                m_logger.Error("RecoveryManager",
                    "Snapshot validation failed: " + snap_result.reason);

            if(snap_result.can_fallback)
            {
                //--- Fallback: cold start (we don't have multiple snapshots in this phase)
                if(m_logger != NULL)
                    m_logger.Warn("RecoveryManager", "Falling back to cold start");
                context.ResetAll();
                m_stats.status = ATLAS_RECOVERY_YELLOW;
                m_stats.failure_reason = "Snapshot invalid, cold start: " + snap_result.reason;
            }
            else
            {
                //--- Cannot fallback — enter safe mode
                m_stats.status         = ATLAS_RECOVERY_RED;
                m_stats.failure_reason = snap_result.reason;
                EnterSafeMode();
                FinalizeRecovery(start_ms);
                stats = m_stats;
                return false;
            }
        }

        //==============================================================
        // STEP 4: Check Event Log Integrity (NOT replay)
        //==============================================================
        //--- Recovery restores state from SNAPSHOTS, not from event replay.
        //--- The event log is checked for integrity only.
        //--- If actual replay is needed, use Replay/ReplayEngine.
        EventLogCheckResult log_result = m_event_replayer.CheckLogIntegrity(context.GetSnapshotId());

        m_stats.event_log_found = log_result.log_found;
        m_stats.replay_count    = log_result.valid_events;  //--- Events checked (not replayed)
        m_stats.dropped_events  = log_result.invalid_events;

        if(m_logger != NULL)
            m_logger.Info("RecoveryManager",
                "Event log integrity check: " + IntegerToString(log_result.total_events) +
                " events, " + IntegerToString(log_result.invalid_events) + " invalid, " +
                IntegerToString(log_result.duplicate_events) + " duplicates");

        //==============================================================
        // STEP 5: Verify State
        //==============================================================
        VerificationResult verify_result = m_state_verifier.Verify(context);

        if(!m_state_verifier.IsHealthy(verify_result))
        {
            m_stats.recovery_errors += verify_result.issue_count;
            if(m_stats.status == ATLAS_RECOVERY_GREEN)
                m_stats.status = ATLAS_RECOVERY_YELLOW;
        }

        //--- Check risk state
        m_stats.risk_state_recovered = verify_result.risk_state_ok;

        //==============================================================
        // STEP 6: Reconcile with Broker
        //==============================================================
        ReconcileBroker(context);

        //==============================================================
        // STEP 7: Determine Final Status
        //==============================================================
        if(m_stats.status == ATLAS_RECOVERY_NONE)
            m_stats.status = ATLAS_RECOVERY_GREEN;

        if(m_stats.status == ATLAS_RECOVERY_RED)
        {
            EnterSafeMode();
        }

        FinalizeRecovery(start_ms);
        stats = m_stats;

        if(m_logger != NULL)
        {
            string status_str;
            switch(m_stats.status)
            {
                case ATLAS_RECOVERY_GREEN:  status_str = "GREEN";  break;
                case ATLAS_RECOVERY_YELLOW: status_str = "YELLOW"; break;
                case ATLAS_RECOVERY_RED:    status_str = "RED";    break;
                default:                    status_str = "UNKNOWN"; break;
            }
            m_logger.Info("RecoveryManager",
                "=== Recovery complete: " + status_str + " (" +
                DoubleToString(m_stats.recovery_time_ms, 1) + "ms) ===");
        }

        return (m_stats.status == ATLAS_RECOVERY_GREEN || m_stats.status == ATLAS_RECOVERY_YELLOW);
    }

    virtual bool IsSafeMode(void) const override
    {
        return (m_safe_mode_flags != ATLAS_SAFE_MODE_NONE);
    }

    virtual int GetSafeModeFlags(void) const override
    {
        return m_safe_mode_flags;
    }

    virtual const RecoveryStatistics& GetStatistics(void) const override
    {
        return m_stats;
    }

    virtual void ClearSafeMode(void) override
    {
        if(m_logger != NULL)
            m_logger.Info("RecoveryManager", "Safe mode cleared by operator");
        m_safe_mode_flags = ATLAS_SAFE_MODE_NONE;
    }

    /**
     * @brief Shutdown — clear all recovery state.
     *
     * Resets statistics, safe-mode flags, and recovery-completed flag so
     * that a subsequent Recover() call starts from a clean state. Also
     * drops injected dependency pointers (they are non-owning).
     *
     * Idempotent: safe to call multiple times.
     */
    void Shutdown(void)
    {
        InitStats();
        m_logger      = NULL;
        m_state_store = NULL;
        m_broker      = NULL;
        m_event_bus   = NULL;
    }

    /**
     * @brief Destructor — ensures state is cleared.
     */
    ~RecoveryManager(void) { Shutdown(); }

private:

    /// @brief Reconcile with broker positions.
    void ReconcileBroker(AtlasContext &context)
    {
        if(m_broker == NULL)
        {
            if(m_logger != NULL)
                m_logger.Warn("RecoveryManager", "No broker adapter — skipping reconciliation");
            return;
        }

        ReconciliationResult recon = m_broker_reconciler.Reconcile(context);

        m_stats.recovered_positions = recon.matched_count;
        m_stats.position_mismatches = recon.mismatch_count;
        m_stats.broker_reconciled   = recon.success;

        if(!recon.success || recon.mismatch_count > 0)
        {
            if(m_stats.status == ATLAS_RECOVERY_GREEN)
                m_stats.status = ATLAS_RECOVERY_YELLOW;
            m_stats.recovery_errors++;
        }
    }

    /// @brief Enter safe mode.
    void EnterSafeMode(void)
    {
        m_safe_mode_flags = ATLAS_SAFE_MODE_NO_NEW_TRADES |
                           ATLAS_SAFE_MODE_MONITORING_ONLY |
                           ATLAS_SAFE_MODE_BROKER_SYNC;
        m_stats.safe_mode_flags = m_safe_mode_flags;

        if(m_logger != NULL)
            m_logger.Fatal("RecoveryManager",
                "*** SAFE MODE ACTIVATED *** Reason: " + m_stats.failure_reason);
    }

    /// @brief Finalize recovery (record timing).
    void FinalizeRecovery(const ulong start_ms)
    {
        m_stats.recovery_time_ms = (double)(GetTickCount64() - start_ms);
        m_stats.recovery_time    = TimeCurrent();
        m_recovery_completed     = true;
    }
};

#endif // ATLAS_RECOVERY_MANAGER_MQH
//+------------------------------------------------------------------+
