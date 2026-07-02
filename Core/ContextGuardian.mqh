//+------------------------------------------------------------------+
//|                                        Core/ContextGuardian.mqh
//|          AtlasEA v2.0 - Single-Writer Enforcement Guardian        |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONTEXT_GUARDIAN_MQH
#define ATLAS_CONTEXT_GUARDIAN_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "PermissionMatrix.mqh"

/**
 * @class ContextGuardian
 * @brief Enforces single-writer rule on the shared context.
 *
 * A module must call AcquireWriteAccess() before mutating any contract
 * on the context, and ReleaseWriteAccess() when done. The guardian
 * delegates ownership tracking to PermissionMatrix.
 *
 * This is a cooperative guard (MQL5 is single-threaded), not a lock.
 * Its purpose is to catch logic bugs where two modules try to write
 * the same contract simultaneously.
 *
 * Usage pattern (RAII-like):
 *   guardian.AcquireWriteAccess(ATLAS_MODULE_RISK, ATLAS_CONTRACT_CONTEXT);
 *   // ... mutate context ...
 *   guardian.ReleaseWriteAccess(ATLAS_MODULE_RISK, ATLAS_CONTRACT_CONTEXT);
 */
class ContextGuardian
{
private:
    PermissionMatrix *m_matrix;   ///< Permission matrix (owned by CoreEngine)
    ILogger          *m_logger;   ///< Logger (may be NULL)
    int               m_violation_count; ///< Total denied access attempts

public:
    /**
     * @brief Constructor.
     */
    ContextGuardian(void);

    /**
     * @brief Attach to a permission matrix and logger.
     * @param matrix The permission matrix to use for ownership tracking.
     * @param logger Optional logger for violation reporting.
     */
    void Attach(PermissionMatrix *matrix, ILogger *logger = NULL);

    /**
     * @brief Acquire write access to a contract for a module.
     * @param module_id     ATLAS_MODULE_* — the module requesting access.
     * @param contract_type ATLAS_CONTRACT_* — the contract to write.
     * @return true if access was granted (or already held), false if denied.
     */
    bool AcquireWriteAccess(const int module_id, const int contract_type);

    /**
     * @brief Release write access to a contract.
     * @param module_id     ATLAS_MODULE_* — the module releasing access.
     * @param contract_type ATLAS_CONTRACT_* — the contract to release.
     */
    void ReleaseWriteAccess(const int module_id, const int contract_type);

    /**
     * @brief Validate that a module currently owns write access.
     * @param module_id     ATLAS_MODULE_* — the module to check.
     * @param contract_type ATLAS_CONTRACT_* — the contract to check.
     * @return true if the module is the current owner.
     */
    bool ValidateWriteAccess(const int module_id, const int contract_type) const;

    /**
     * @brief Get the current owner of a contract.
     * @param contract_type ATLAS_CONTRACT_* — the contract to query.
     * @return module_id of the owner, or 0 if unowned.
     */
    int  CurrentWriter(const int contract_type) const;

    /// @brief Total number of denied access attempts (for diagnostics).
    int  ViolationCount(void) const { return m_violation_count; }

    /// @brief Reset all ownerships (shutdown).
    void ResetAll(void);
};

//+------------------------------------------------------------------+
//| ContextGuardian implementation                                   |
//+------------------------------------------------------------------+

ContextGuardian::ContextGuardian(void)
{
    m_matrix           = NULL;
    m_logger           = NULL;
    m_violation_count  = 0;
}

//+------------------------------------------------------------------+
void ContextGuardian::Attach(PermissionMatrix *matrix, ILogger *logger)
{
    m_matrix = matrix;
    m_logger = logger;
}

//+------------------------------------------------------------------+
bool ContextGuardian::AcquireWriteAccess(const int module_id, const int contract_type)
{
    if(m_matrix == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("ContextGuardian", "AcquireWriteAccess: no permission matrix attached");
        m_violation_count++;
        return false;
    }

    bool ok = m_matrix.AcquireOwnership(module_id, contract_type);
    if(!ok)
    {
        m_violation_count++;
        if(m_logger != NULL)
            m_logger.Warn("ContextGuardian", "Write access DENIED: module=" + IntegerToString(module_id) + " contract=" + IntegerToString(contract_type));
    }
    return ok;
}

//+------------------------------------------------------------------+
void ContextGuardian::ReleaseWriteAccess(const int module_id, const int contract_type)
{
    if(m_matrix == NULL)
        return;
    m_matrix.ReleaseOwnership(module_id, contract_type);
}

//+------------------------------------------------------------------+
bool ContextGuardian::ValidateWriteAccess(const int module_id, const int contract_type) const
{
    if(m_matrix == NULL)
        return false;
    return (m_matrix.GetOwner(contract_type) == module_id);
}

//+------------------------------------------------------------------+
int ContextGuardian::CurrentWriter(const int contract_type) const
{
    if(m_matrix == NULL)
        return 0;
    return m_matrix.GetOwner(contract_type);
}

//+------------------------------------------------------------------+
void ContextGuardian::ResetAll(void)
{
    if(m_matrix != NULL)
        m_matrix.ResetAll();
}

#endif // ATLAS_CONTEXT_GUARDIAN_MQH
//+------------------------------------------------------------------+
