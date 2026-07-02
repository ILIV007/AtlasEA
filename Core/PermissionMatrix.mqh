//+------------------------------------------------------------------+
//|                                       Core/PermissionMatrix.mqh
//|                AtlasEA v2.0 - Module Permission Matrix            |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERMISSION_MATRIX_MQH
#define ATLAS_PERMISSION_MATRIX_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class PermissionMatrix
 * @brief Module × Contract write-permission table.
 *
 * Defines which module is allowed to write to which contract type.
 * Queried by ContextGuardian to enforce single-writer rule.
 *
 * Design: fixed-size boolean matrix [MAX_MODULES][MAX_CONTRACTS].
 * No dynamic allocation. O(1) lookup.
 *
 * Permission rules:
 *   - Only ONE module may hold write access to a contract at any time.
 *   - A module may re-acquire access it already holds (re-entrant).
 *   - All other combinations are denied.
 */
class PermissionMatrix
{
private:
    /// Maximum number of tracked modules
    static const int MAX_MODULES   = 16;
    /// Maximum number of tracked contract types
    static const int MAX_CONTRACTS = 16;

    /// Permission table: m_allowed[module_id][contract_type] = true if write allowed
    bool m_allowed[MAX_MODULES][MAX_CONTRACTS];

    /// Current write owner per contract: m_owner[contract_type] = module_id (0 = unowned)
    int  m_owner[MAX_CONTRACTS];

    ILogger *m_logger;

    /// @brief Validate module_id is in range.
    bool IsValidModule(const int module_id) const { return (module_id > 0 && module_id < MAX_MODULES); }
    /// @brief Validate contract_type is in range.
    bool IsValidContract(const int contract_type) const { return (contract_type > 0 && contract_type < MAX_CONTRACTS); }

public:
    /**
     * @brief Constructor — initializes an empty (all-denied) matrix.
     */
    PermissionMatrix(void);

    /**
     * @brief Register a write permission for a module on a contract.
     * @param module_id     ATLAS_MODULE_* constant.
     * @param contract_type ATLAS_CONTRACT_* constant.
     * @return true if registered, false if IDs out of range.
     */
    bool GrantPermission(const int module_id, const int contract_type);

    /**
     * @brief Check if a module is permitted to write a contract.
     * @param module_id     ATLAS_MODULE_* constant.
     * @param contract_type ATLAS_CONTRACT_* constant.
     * @return true if permission is granted in the matrix.
     */
    bool IsPermitted(const int module_id, const int contract_type) const;

    /**
     * @brief Attempt to acquire write ownership of a contract.
     * @param module_id     The module requesting ownership.
     * @param contract_type The contract to own.
     * @return true if acquired (or already owned by the same module), false if denied.
     */
    bool AcquireOwnership(const int module_id, const int contract_type);

    /**
     * @brief Release write ownership of a contract.
     * @param module_id     The module releasing ownership.
     * @param contract_type The contract to release.
     */
    void ReleaseOwnership(const int module_id, const int contract_type);

    /**
     * @brief Get the current owner of a contract.
     * @param contract_type The contract to query.
     * @return module_id of the owner, or 0 if unowned.
     */
    int  GetOwner(const int contract_type) const;

    /**
     * @brief Reset all ownerships (called during shutdown).
     */
    void ResetAll(void);

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }
};

//+------------------------------------------------------------------+
//| PermissionMatrix implementation                                  |
//+------------------------------------------------------------------+

PermissionMatrix::PermissionMatrix(void)
{
    m_logger = NULL;
    for(int m = 0; m < MAX_MODULES; m++)
        for(int c = 0; c < MAX_CONTRACTS; c++)
            m_allowed[m][c] = false;

    for(int c = 0; c < MAX_CONTRACTS; c++)
        m_owner[c] = 0;
}

//+------------------------------------------------------------------+
bool PermissionMatrix::GrantPermission(const int module_id, const int contract_type)
{
    if(!IsValidModule(module_id) || !IsValidContract(contract_type))
    {
        if(m_logger != NULL)
            m_logger.Error("PermissionMatrix", "GrantPermission: invalid IDs module=" + IntegerToString(module_id) + " contract=" + IntegerToString(contract_type));
        return false;
    }
    m_allowed[module_id][contract_type] = true;
    return true;
}

//+------------------------------------------------------------------+
bool PermissionMatrix::IsPermitted(const int module_id, const int contract_type) const
{
    if(!IsValidModule(module_id) || !IsValidContract(contract_type))
        return false;
    return m_allowed[module_id][contract_type];
}

//+------------------------------------------------------------------+
bool PermissionMatrix::AcquireOwnership(const int module_id, const int contract_type)
{
    if(!IsValidModule(module_id) || !IsValidContract(contract_type))
    {
        if(m_logger != NULL)
            m_logger.Error("PermissionMatrix", "AcquireOwnership: invalid IDs");
        return false;
    }

    if(!m_allowed[module_id][contract_type])
    {
        if(m_logger != NULL)
            m_logger.Warn("PermissionMatrix", "AcquireOwnership: module " + IntegerToString(module_id) + " not permitted for contract " + IntegerToString(contract_type));
        return false;
    }

    int current = m_owner[contract_type];
    if(current != 0 && current != module_id)
    {
        if(m_logger != NULL)
            m_logger.Warn("PermissionMatrix", "AcquireOwnership: contract " + IntegerToString(contract_type) + " owned by module " + IntegerToString(current));
        return false;
    }

    m_owner[contract_type] = module_id;
    return true;
}

//+------------------------------------------------------------------+
void PermissionMatrix::ReleaseOwnership(const int module_id, const int contract_type)
{
    if(!IsValidModule(module_id) || !IsValidContract(contract_type))
        return;

    if(m_owner[contract_type] == module_id)
        m_owner[contract_type] = 0;
}

//+------------------------------------------------------------------+
int PermissionMatrix::GetOwner(const int contract_type) const
{
    if(!IsValidContract(contract_type))
        return 0;
    return m_owner[contract_type];
}

//+------------------------------------------------------------------+
void PermissionMatrix::ResetAll(void)
{
    for(int c = 0; c < MAX_CONTRACTS; c++)
        m_owner[c] = 0;
}

#endif // ATLAS_PERMISSION_MATRIX_MQH
//+------------------------------------------------------------------+
