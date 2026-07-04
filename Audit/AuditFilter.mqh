//+------------------------------------------------------------------+
//|                      Audit/AuditFilter.mqh                      |
//|       AtlasEA v0.1.19.0 - Audit Filter                           |
//+------------------------------------------------------------------+
#ifndef ATLAS_AUDIT_FILTER_MQH
#define ATLAS_AUDIT_FILTER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IAuditManager.mqh"

/**
 * @struct AuditFilterRule
 * @brief One filter rule for audit entries.
 */
struct AuditFilterRule
{
    int    category;    ///< ATLAS_AUDIT_* or -1 for all
    string actor;       ///< Module name or "" for all
    string action;      ///< Action or "" for all
    bool   enabled;     ///< Is this rule active?
};

/**
 * @brief Maximum filter rules.
 */
#define ATLAS_AUDIT_FILTER_MAX 16

/**
 * @class AuditFilter
 * @brief Filters audit entries based on configurable rules.
 *
 * Rules can include/exclude entries by category, actor, or action.
 */
class AuditFilter
{
private:
    AuditFilterRule m_rules[ATLAS_AUDIT_FILTER_MAX];
    int             m_count;
    bool            m_default_include;  ///< If no rule matches, include?

public:
    /**
     * @brief Constructor — default: include all.
     */
    AuditFilter(void)
    {
        m_count          = 0;
        m_default_include = true;
    }

    /**
     * @brief Add a filter rule.
     */
    bool AddRule(const int category, const string actor, const string action)
    {
        if(m_count >= ATLAS_AUDIT_FILTER_MAX) return false;
        m_rules[m_count].category = category;
        m_rules[m_count].actor    = actor;
        m_rules[m_count].action   = action;
        m_rules[m_count].enabled  = true;
        m_count++;
        return true;
    }

    /**
     * @brief Check if an entry passes the filter.
     */
    bool Passes(const AuditEntry &entry) const
    {
        //--- If no rules, use default
        if(m_count == 0) return m_default_include;

        for(int i = 0; i < m_count; i++)
        {
            if(!m_rules[i].enabled) continue;

            bool match_cat = (m_rules[i].category < 0 || m_rules[i].category == entry.category);
            bool match_actor = (m_rules[i].actor == "" || m_rules[i].actor == entry.actor);
            bool match_action = (m_rules[i].action == "" || m_rules[i].action == entry.action);

            if(match_cat && match_actor && match_action)
                return true;  //--- At least one rule matches
        }

        return false;  //--- No rule matched
    }

    /**
     * @brief Set default behavior when no rule matches.
     */
    void SetDefaultInclude(const bool include) { m_default_include = include; }

    /**
     * @brief Clear all rules.
     */
    void Clear(void) { m_count = 0; }

    int RuleCount(void) const { return m_count; }
};

#endif // ATLAS_AUDIT_FILTER_MQH
//+------------------------------------------------------------------+
