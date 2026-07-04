//+------------------------------------------------------------------+
//|                                      Core/SnapshotManager.mqh
//|               AtlasEA v2.0 - Snapshot ID & Lifecycle Manager      |
//+------------------------------------------------------------------+
#ifndef ATLAS_SNAPSHOT_MANAGER_MQH
#define ATLAS_SNAPSHOT_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "ValidationResult.mqh"

/**
 * @class SnapshotManager
 * @brief Manages monotonic snapshot IDs and snapshot lifecycle.
 *
 * Each market tick is assigned a unique, monotonically increasing snapshot_id.
 * This ID is stamped on every event, vote, decision, and order request,
 * providing end-to-end correlation across the pipeline.
 *
 * Lifecycle:
 *   1. AssignId()     — called at the start of each tick; increments the counter.
 *   2. (pipeline runs — all events carry this snapshot_id)
 *   3. TriggerSnapshot() — called periodically (snapshot_interval_sec) to persist.
 *   4. RecoverState()    — called on startup to restore the counter from disk.
 *
 * The counter is stored on IContextStore so it survives across phases.
 */
class SnapshotManager
{
private:
    IContextStore *m_context;       ///< Context (owns the snapshot_id)
    ILogger       *m_logger;        ///< Logger (may be NULL)
    long           m_last_assigned; ///< Last assigned snapshot_id
    datetime       m_last_snapshot_time; ///< Last persistence time
    int            m_snapshot_interval_sec; ///< Interval between snapshots

public:
    /**
     * @brief Constructor.
     */
    SnapshotManager(void);

    /**
     * @brief Initialize the snapshot manager.
     * @param context     The context store (owns snapshot_id).
     * @param logger      Optional logger.
     * @param interval_sec Snapshot persistence interval in seconds.
     */
    void Initialize(IContextStore *context, ILogger *logger, const int interval_sec);

    /**
     * @brief Assign the next monotonic snapshot ID.
     * Stores the new ID on the context and returns it.
     * @return The newly assigned snapshot_id (> 0).
     */
    long AssignId(void);

    /**
     * @brief Get the current snapshot ID without incrementing.
     * @return The current snapshot_id.
     */
    long CurrentId(void) const { return m_last_assigned; }

    /**
     * @brief Check if a snapshot is due based on the interval.
     * @param now Current server time.
     * @return true if (now - last_snapshot_time) >= interval.
     */
    bool IsSnapshotDue(const datetime now) const;

    /**
     * @brief Record that a snapshot was persisted at the given time.
     * @param when The timestamp of the snapshot.
     */
    void MarkSnapshotPersisted(const datetime when);

    /**
     * @brief Recover the snapshot ID from a previously persisted value.
     * @param saved_id The ID loaded from disk.
     */
    void RecoverId(const long saved_id);

    /**
     * @brief Validate that a snapshot_id is consistent (not stale).
     * @param id The ID to validate.
     * @return true if id == m_last_assigned (current), false if stale.
     */
    bool ValidateSnapshotId(const long id) const;

    /// @brief Last assigned snapshot ID.
    long LastAssigned(void) const { return m_last_assigned; }

    /// @brief Last snapshot persistence time.
    datetime LastSnapshotTime(void) const { return m_last_snapshot_time; }

    /**
     * @brief Validate snapshot manager integrity.
     * @return ValidationResult.
     *
     * Invariants:
     *   - m_last_assigned >= 0 (monotonic counter, never negative)
     *   - m_snapshot_interval_sec > 0
     *   - if m_context != NULL, m_last_assigned == m_context.GetSnapshotId()
     *     (the manager and context must agree on the current ID)
     */
    ValidationResult Validate(void) const
    {
        if(m_last_assigned < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "last_assigned < 0", "last_assigned");
        if(m_snapshot_interval_sec <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_interval_sec <= 0", "snapshot_interval_sec");
        if(m_context != NULL)
        {
            if(m_context.GetSnapshotId() != m_last_assigned)
                return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                    "context snapshot_id != manager last_assigned",
                    "snapshot_id");
        }
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| SnapshotManager implementation                                   |
//+------------------------------------------------------------------+

SnapshotManager::SnapshotManager(void)
{
    m_context              = NULL;
    m_logger               = NULL;
    m_last_assigned        = 0;
    m_last_snapshot_time   = 0;
    m_snapshot_interval_sec = 300;
}

//+------------------------------------------------------------------+
void SnapshotManager::Initialize(IContextStore *context, ILogger *logger, const int interval_sec)
{
    m_context = context;
    m_logger  = logger;
    m_snapshot_interval_sec = (interval_sec > 0) ? interval_sec : 300;

    if(m_context != NULL)
        m_last_assigned = m_context.GetSnapshotId();

    if(m_logger != NULL)
        m_logger.Info("SnapshotManager", "Initialized. interval=" + IntegerToString(m_snapshot_interval_sec) + "s start_id=" + IntegerToString(m_last_assigned));
}

//+------------------------------------------------------------------+
long SnapshotManager::AssignId(void)
{
    if(m_context == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("SnapshotManager", "AssignId: no context attached");
        return 0;
    }

    m_last_assigned++;
    m_context.SetSnapshotId(m_last_assigned);
    return m_last_assigned;
}

//+------------------------------------------------------------------+
bool SnapshotManager::IsSnapshotDue(const datetime now) const
{
    if(m_last_snapshot_time == 0)
        return true;
    return ((long)(now - m_last_snapshot_time) >= m_snapshot_interval_sec);
}

//+------------------------------------------------------------------+
void SnapshotManager::MarkSnapshotPersisted(const datetime when)
{
    m_last_snapshot_time = when;
    if(m_logger != NULL)
        m_logger.Debug("SnapshotManager", "Snapshot persisted at " + IntegerToString((long)when) + " id=" + IntegerToString(m_last_assigned));
}

//+------------------------------------------------------------------+
void SnapshotManager::RecoverId(const long saved_id)
{
    if(saved_id > m_last_assigned)
    {
        m_last_assigned = saved_id;
        if(m_context != NULL)
            m_context.SetSnapshotId(m_last_assigned);
        if(m_logger != NULL)
            m_logger.Info("SnapshotManager", "Recovered snapshot_id=" + IntegerToString(m_last_assigned));
    }
}

//+------------------------------------------------------------------+
bool SnapshotManager::ValidateSnapshotId(const long id) const
{
    return (id == m_last_assigned && id > 0);
}

#endif // ATLAS_SNAPSHOT_MANAGER_MQH
//+------------------------------------------------------------------+
