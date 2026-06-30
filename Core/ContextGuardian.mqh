//+------------------------------------------------------------------+
//|                                        Core/ContextGuardian.mqh  |
//|          AtlasEA v1.0 - Single-Writer Enforcement Guardian       |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONTEXT_GUARDIAN_MQH
#define ATLAS_CONTEXT_GUARDIAN_MQH

#include "../Config/Settings.mqh"
#include "AtlasContext.mqh"

//+------------------------------------------------------------------+
//| ContextGuardian - enforces single-writer rule on shared context. |
//| A module must AcquireWriteAccess() before mutating a contract.   |
//| Only one (module, contract) pair may hold write access at once.  |
//+------------------------------------------------------------------+
class ContextGuardian
{
private:
    AtlasContext *m_context;

public:
    ContextGuardian(void) { m_context = NULL; }

    void Attach(AtlasContext *ctx) { m_context = ctx; }

    //+--------------------------------------------------------------+
    //| Acquire write access. Returns false if another module owns it.|
    //+--------------------------------------------------------------+
    bool AcquireWriteAccess(const int module_id, const int contract_type)
    {
        if(m_context == NULL) return false;
        if(m_context.current_writer_module != 0)
        {
            // Already locked - only the same (module, contract) may re-acquire
            if(m_context.current_writer_module   != module_id)    return false;
            if(m_context.current_writer_contract != contract_type) return false;
        }
        m_context.current_writer_module   = module_id;
        m_context.current_writer_contract = contract_type;
        return true;
    }

    //+--------------------------------------------------------------+
    //| Release write access. Only the owner may release.             |
    //+--------------------------------------------------------------+
    void ReleaseWriteAccess(const int module_id, const int contract_type)
    {
        if(m_context == NULL) return;
        if(m_context.current_writer_module   == module_id &&
           m_context.current_writer_contract == contract_type)
        {
            m_context.current_writer_module   = 0;
            m_context.current_writer_contract = 0;
        }
    }

    //+--------------------------------------------------------------+
    //| Validate that the caller currently owns write access.          |
    //+--------------------------------------------------------------+
    bool ValidateWriteAccess(const int module_id, const int contract_type) const
    {
        if(m_context == NULL) return false;
        return (m_context.current_writer_module   == module_id &&
                m_context.current_writer_contract == contract_type);
    }

    //+--------------------------------------------------------------+
    int CurrentWriterModule(void)   const { return (m_context == NULL) ? 0 : m_context.current_writer_module;   }
    int CurrentWriterContract(void) const { return (m_context == NULL) ? 0 : m_context.current_writer_contract; }
};

#endif // ATLAS_CONTEXT_GUARDIAN_MQH
//+------------------------------------------------------------------+
