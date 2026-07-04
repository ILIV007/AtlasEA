//+------------------------------------------------------------------+
//|                   Interfaces/IAuditManager.mqh                  |
//|       AtlasEA v0.1.19.0 - Audit Manager Interface               |
//+------------------------------------------------------------------+
#ifndef ATLAS_IAUDIT_MANAGER_MQH
#define ATLAS_IAUDIT_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Audit event categories.
 */
#define ATLAS_AUDIT_RISK_DECISION      0
#define ATLAS_AUDIT_STRATEGY_VOTE      1
#define ATLAS_AUDIT_ORDER_REQUEST      2
#define ATLAS_AUDIT_BROKER_RESPONSE    3
#define ATLAS_AUDIT_EXECUTION          4
#define ATLAS_AUDIT_POSITION_CHANGE    5
#define ATLAS_AUDIT_RECOVERY_ACTION    6
#define ATLAS_AUDIT_CONFIG_CHANGE      7
#define ATLAS_AUDIT_PLUGIN_LOAD        8
#define ATLAS_AUDIT_PLUGIN_UNLOAD      9
#define ATLAS_AUDIT_KILL_SWITCH        10
#define ATLAS_AUDIT_SYSTEM             11

/**
 * @struct AuditEntry
 * @brief One audit trail entry.
 */
struct AuditEntry
{
    int      category;       ///< ATLAS_AUDIT_*
    datetime timestamp;      ///< When the audited action occurred
    string   actor;          ///< Who performed the action (module name)
    string   action;         ///< What was done (e.g., "approve", "reject", "open")
    string   target;         ///< What was acted upon (e.g., "order_123", "strategy_5")
    string   details;        ///< Human-readable details
    long     snapshot_id;    ///< Market snapshot at the time
    string   correlation_id; ///< Event correlation ID
};

/**
 * @class IAuditManager
 * @brief Interface for audit trail management.
 *
 * The AuditManager tracks every important state transition:
 *   - Risk decisions
 *   - Strategy votes
 *   - Order requests
 *   - Broker responses
 *   - Executions
 *   - Position changes
 *   - Recovery actions
 *   - Configuration changes
 *   - Plugin load/unload
 *   - Kill switch activations
 */
class IAuditManager
{
public:
    /// @brief Record an audit entry.
    virtual bool Record(const AuditEntry &entry) = 0;

    /// @brief Get total audit entry count.
    virtual long Count(void) const = 0;

    /// @brief Get an audit entry by index.
    virtual bool GetEntry(const int index, AuditEntry &out) const = 0;

    /// @brief Find entries by category.
    virtual int FindByCategory(const int category,
                                AuditEntry out_entries[], const int max_count) const = 0;

    /// @brief Find entries by correlation ID.
    virtual int FindByCorrelation(const string correlation_id,
                                   AuditEntry out_entries[], const int max_count) const = 0;

    /// @brief Clear all audit entries.
    virtual void Clear(void) = 0;

    virtual ~IAuditManager(void) {}
};

#endif // ATLAS_IAUDIT_MANAGER_MQH
//+------------------------------------------------------------------+
