//+------------------------------------------------------------------+
//|                      Interfaces/IRecoveryManager.mqh            |
//|       AtlasEA v0.1.13.0 - Recovery Manager Interface            |
//+------------------------------------------------------------------+
#ifndef ATLAS_IRECOVERY_MANAGER_MQH
#define ATLAS_IRECOVERY_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"

/**
 * @brief Recovery status codes.
 */
#define ATLAS_RECOVERY_NONE      0   ///< No recovery attempted yet
#define ATLAS_RECOVERY_GREEN     1   ///< Full recovery successful
#define ATLAS_RECOVERY_YELLOW    2   ///< Recovery with warnings
#define ATLAS_RECOVERY_RED       3   ///< Recovery failed
#define ATLAS_RECOVERY_SAFE_MODE 4   ///< System in safe mode

/**
 * @brief Crash detection codes.
 */
#define ATLAS_CRASH_NONE                0
#define ATLAS_CRASH_UNEXPECTED_SHUTDOWN 1   ///< No clean shutdown marker
#define ATLAS_CRASH_CORRUPTED_SNAPSHOT  2   ///< Snapshot checksum mismatch
#define ATLAS_CRASH_BROKEN_EVENT_LOG    3   ///< Event log parse failure
#define ATLAS_CRASH_VERSION_MISMATCH    4   ///< Snapshot version != current
#define ATLAS_CRASH_CLOCK_ROLLBACK      5   ///< Server time went backward
#define ATLAS_CRASH_INCOMPLETE_SNAPSHOT 6   ///< Snapshot missing fields

/**
 * @brief Safe mode restrictions.
 */
#define ATLAS_SAFE_MODE_NONE            0x00
#define ATLAS_SAFE_MODE_NO_NEW_TRADES   0x01
#define ATLAS_SAFE_MODE_MONITORING_ONLY 0x02
#define ATLAS_SAFE_MODE_BROKER_SYNC     0x04

/**
 * @struct RecoveryStatistics
 * @brief Statistics from the last recovery operation.
 */
struct RecoveryStatistics
{
    int    status;                  ///< ATLAS_RECOVERY_*
    int    crash_code;              ///< ATLAS_CRASH_* (0 if no crash detected)
    int    safe_mode_flags;         ///< ATLAS_SAFE_MODE_* bitmask

    double recovery_time_ms;        ///< Total recovery duration
    int    replay_count;            ///< Events replayed
    int    dropped_events;          ///< Events dropped (invalid/duplicate)
    int    recovered_positions;     ///< Positions reconciled
    int    position_mismatches;     ///< Position discrepancies found
    bool   risk_state_recovered;    ///< Risk state successfully recovered
    int    recovery_errors;         ///< Number of errors during recovery

    string failure_reason;          ///< Human-readable failure reason (if RED)
    datetime recovery_time;         ///< When recovery completed

    bool   snapshot_found;          ///< Was a snapshot file found?
    bool   snapshot_valid;          ///< Did the snapshot pass validation?
    bool   event_log_found;         ///< Was an event log file found?
    bool   broker_reconciled;       ///< Did broker reconciliation succeed?
};

/**
 * @class IRecoveryManager
 * @brief Interface for startup recovery and crash recovery.
 *
 * The RecoveryManager is called once during OnInit(). It:
 *   1. Detects if the previous session ended cleanly
 *   2. Loads and validates the latest snapshot
 *   3. Replays events from the event log
 *   4. Reconstructs the AtlasContext
 *   5. Verifies state consistency
 *   6. Reconciles with broker positions
 *   7. Produces a RecoveryStatistics report
 *
 * If recovery fails, the system enters Safe Mode.
 */
class IRecoveryManager
{
public:
    /**
     * @brief Perform full startup recovery.
     * @param context The context to populate (mutated).
     * @param stats Output: recovery statistics.
     * @return true if recovery succeeded (GREEN or YELLOW), false if failed (RED).
     */
    virtual bool Recover(AtlasContext &context, RecoveryStatistics &stats) = 0;

    /**
     * @brief Check if the system is in safe mode.
     * @return true if safe mode is active.
     */
    virtual bool IsSafeMode(void) const = 0;

    /**
     * @brief Get the current safe mode flags.
     * @return ATLAS_SAFE_MODE_* bitmask.
     */
    virtual int GetSafeModeFlags(void) const = 0;

    /**
     * @brief Get the last recovery statistics.
     */
    virtual const RecoveryStatistics& GetStatistics(void) const = 0;

    /**
     * @brief Clear safe mode (manual operator action).
     * Only allowed after the operator has verified the system is healthy.
     */
    virtual void ClearSafeMode(void) = 0;

    virtual ~IRecoveryManager(void) {}
};

#endif // ATLAS_IRECOVERY_MANAGER_MQH
//+------------------------------------------------------------------+
