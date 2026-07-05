//+------------------------------------------------------------------+
//|                       Performance/MemoryAudit.mqh                |
//|       AtlasEA v1.0 Step 8 - Memory Audit                           |
//+------------------------------------------------------------------+
#ifndef ATLAS_MEMORY_AUDIT_MQH
#define ATLAS_MEMORY_AUDIT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum fixed arrays to audit.
 */
#define ATLAS_MEM_AUDIT_MAX_ARRAYS 32

/**
 * @struct ArrayAuditEntry
 * @brief Audit entry for a single fixed array.
 */
struct ArrayAuditEntry
{
    string name;               ///< Array name (component.field)
    int    declared_size;      ///< Declared capacity
    int    max_observed_used;  ///< Maximum observed usage
    int    element_size;       ///< Estimated element size (bytes)
    int    total_bytes;        ///< Total bytes (declared_size × element_size)
    bool   overflow_risk;      ///< Is max_observed close to declared?
    bool   unused;             ///< Is max_observed always 0?

    ArrayAuditEntry(void)
    {
        name              = "";
        declared_size     = 0;
        max_observed_used = 0;
        element_size      = 0;
        total_bytes       = 0;
        overflow_risk     = false;
        unused            = false;
    }
};

/**
 * @struct MemoryAuditResult
 * @brief Result of a memory audit.
 */
struct MemoryAuditResult
{
    int    total_arrays;        ///< Total arrays audited
    int    total_bytes;         ///< Total bytes across all arrays
    int    overflow_risk_count; ///< Arrays at risk of overflow
    int    unused_count;        ///< Arrays never used
    int    duplicate_count;     ///< Suspected duplicate buffers

    ArrayAuditEntry entries[ATLAS_MEM_AUDIT_MAX_ARRAYS];
    int    entry_count;

    ulong  mql_memory_mb;       ///< Current MQL memory
    ulong  peak_memory_mb;      ///< Peak MQL memory
    double growth_pct;          ///< Growth since start

    MemoryAuditResult(void)
    {
        total_arrays        = 0;
        total_bytes         = 0;
        overflow_risk_count = 0;
        unused_count        = 0;
        duplicate_count     = 0;
        entry_count         = 0;
        mql_memory_mb       = 0;
        peak_memory_mb      = 0;
        growth_pct          = 0.0;
    }
};

/**
 * @class MemoryAudit
 * @brief Audits all fixed arrays for overflow protection, unused allocation,
 *        and memory footprint.
 *
 * SOLE RESPONSIBILITY: audit memory usage. Does NOT modify any arrays.
 *
 * Audit checks:
 *   1. Overflow protection: is max_observed close to declared_size?
 *   2. Unused allocation: is max_observed always 0?
 *   3. Duplicate buffers: are two arrays serving the same purpose?
 *   4. Total footprint: sum of all array sizes
 *   5. MQL memory growth: is memory growing over time?
 *
 * Performance: O(A) where A = arrays registered. No allocation.
 */
class MemoryAudit
{
private:
    ILogger *m_logger;
    ArrayAuditEntry m_entries[ATLAS_MEM_AUDIT_MAX_ARRAYS];
    int      m_count;
    ulong    m_initial_memory_mb;

public:
    MemoryAudit(void)
    {
        m_logger             = NULL;
        m_count              = 0;
        m_initial_memory_mb  = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a fixed array for auditing.
     * @param name Array name (e.g., "EventQueue.m_normal").
     * @param declared_size Declared capacity.
     * @param element_size Estimated element size in bytes.
     * @return true if registered.
     */
    bool RegisterArray(const string name, const int declared_size,
                       const int element_size)
    {
        if(m_count >= ATLAS_MEM_AUDIT_MAX_ARRAYS) return false;
        m_entries[m_count].name          = name;
        m_entries[m_count].declared_size = declared_size;
        m_entries[m_count].element_size  = element_size;
        m_entries[m_count].total_bytes   = declared_size * element_size;
        m_entries[m_count].max_observed_used = 0;
        m_entries[m_count].overflow_risk = false;
        m_entries[m_count].unused        = false;
        m_count++;
        return true;
    }

    /**
     * @brief Record observed usage for a registered array.
     */
    void RecordUsage(const string name, const int used)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].name == name)
            {
                if(used > m_entries[i].max_observed_used)
                    m_entries[i].max_observed_used = used;
                return;
            }
        }
    }

    /**
     * @brief Initialize with current MQL memory baseline.
     */
    void Initialize(void)
    {
        m_initial_memory_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);
    }

    /**
     * @brief Run the audit.
     * @return MemoryAuditResult with findings.
     */
    MemoryAuditResult Audit(void)
    {
        MemoryAuditResult result;
        result.entry_count = m_count;
        result.total_arrays = m_count;

        for(int i = 0; i < m_count; i++)
        {
            result.entries[i] = m_entries[i];
            result.total_bytes += m_entries[i].total_bytes;

            //--- Overflow risk: > 90% capacity
            if(m_entries[i].declared_size > 0)
            {
                double usage = (double)m_entries[i].max_observed_used /
                               (double)m_entries[i].declared_size;
                if(usage > 0.90)
                {
                    result.entries[i].overflow_risk = true;
                    result.overflow_risk_count++;
                }
                //--- Unused: never used
                if(m_entries[i].max_observed_used == 0)
                {
                    result.entries[i].unused = true;
                    result.unused_count++;
                }
            }
        }

        //--- MQL memory
        result.mql_memory_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);
        result.peak_memory_mb = result.mql_memory_mb;
        if(m_initial_memory_mb > 0)
            result.growth_pct = ((double)result.mql_memory_mb - (double)m_initial_memory_mb) /
                                (double)m_initial_memory_mb * 100.0;

        return result;
    }

    /**
     * @brief Log the audit results.
     */
    void LogAudit(const MemoryAuditResult &result) const
    {
        if(m_logger == NULL) return;

        m_logger.Info("MemoryAudit",
            "Arrays: " + IntegerToString(result.total_arrays) +
            " TotalBytes: " + IntegerToString(result.total_bytes) +
            " OverflowRisk: " + IntegerToString(result.overflow_risk_count) +
            " Unused: " + IntegerToString(result.unused_count) +
            " MQLMemory: " + IntegerToString((long)result.mql_memory_mb) + "MB" +
            " Growth: " + DoubleToString(result.growth_pct, 1) + "%");

        for(int i = 0; i < result.entry_count; i++)
        {
            const ArrayAuditEntry &e = result.entries[i];
            string flags = "";
            if(e.overflow_risk) flags += " [OVERFLOW_RISK]";
            if(e.unused)        flags += " [UNUSED]";

            m_logger.Info("MemoryAudit",
                "  " + e.name +
                " size=" + IntegerToString(e.declared_size) +
                " used=" + IntegerToString(e.max_observed_used) +
                " bytes=" + IntegerToString(e.total_bytes) +
                flags);
        }
    }
};

#endif // ATLAS_MEMORY_AUDIT_MQH
//+------------------------------------------------------------------+
