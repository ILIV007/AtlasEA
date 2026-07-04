//+------------------------------------------------------------------+
//|                      Audit/AuditTrail.mqh                       |
//|       AtlasEA v0.1.19.0 - Audit Trail (Ring Buffer)             |
//+------------------------------------------------------------------+
#ifndef ATLAS_AUDIT_TRAIL_MQH
#define ATLAS_AUDIT_TRAIL_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IAuditManager.mqh"

/**
 * @brief Maximum audit entries in the ring buffer.
 */
#define ATLAS_AUDIT_CAPACITY 512

/**
 * @class AuditTrail
 * @brief In-memory ring buffer for audit entries.
 *
 * Fixed-capacity. FIFO eviction when full. No dynamic allocation.
 */
class AuditTrail
{
private:
    AuditEntry m_entries[ATLAS_AUDIT_CAPACITY];
    int        m_head;
    int        m_tail;
    int        m_count;

public:
    /**
     * @brief Constructor.
     */
    AuditTrail(void)
    {
        m_head  = 0;
        m_tail  = 0;
        m_count = 0;
    }

    /**
     * @brief Append an audit entry. O(1).
     */
    bool Append(const AuditEntry &entry)
    {
        m_entries[m_head] = entry;
        m_head = (m_head + 1) % ATLAS_AUDIT_CAPACITY;

        if(m_count < ATLAS_AUDIT_CAPACITY)
            m_count++;
        else
            m_tail = (m_tail + 1) % ATLAS_AUDIT_CAPACITY;

        return true;
    }

    /**
     * @brief Read by index (0 = oldest). O(1).
     */
    bool ReadByIndex(const int index, AuditEntry &out) const
    {
        if(index < 0 || index >= m_count) return false;
        int idx = (m_tail + index) % ATLAS_AUDIT_CAPACITY;
        out = m_entries[idx];
        return true;
    }

    /**
     * @brief Find entries by category. O(N).
     */
    int FindByCategory(const int category, AuditEntry out_entries[], const int max_count) const
    {
        int found = 0;
        for(int i = 0; i < m_count && found < max_count; i++)
        {
            int idx = (m_tail + i) % ATLAS_AUDIT_CAPACITY;
            if(m_entries[idx].category == category)
            {
                out_entries[found] = m_entries[idx];
                found++;
            }
        }
        return found;
    }

    /**
     * @brief Find entries by correlation ID. O(N).
     */
    int FindByCorrelation(const string correlation_id, AuditEntry out_entries[], const int max_count) const
    {
        int found = 0;
        for(int i = 0; i < m_count && found < max_count; i++)
        {
            int idx = (m_tail + i) % ATLAS_AUDIT_CAPACITY;
            if(m_entries[idx].correlation_id == correlation_id)
            {
                out_entries[found] = m_entries[idx];
                found++;
            }
        }
        return found;
    }

    int Count(void) const { return m_count; }

    void Clear(void)
    {
        m_head  = 0;
        m_tail  = 0;
        m_count = 0;
    }
};

#endif // ATLAS_AUDIT_TRAIL_MQH
//+------------------------------------------------------------------+
