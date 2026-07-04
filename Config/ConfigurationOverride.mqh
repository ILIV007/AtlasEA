//+------------------------------------------------------------------+
//|               Config/ConfigurationOverride.mqh                  |
//|       AtlasEA v0.1.18.0 - Runtime Override Management           |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_OVERRIDE_MQH
#define ATLAS_CONFIGURATION_OVERRIDE_MQH

#include "AtlasConfiguration.mqh"

/**
 * @brief Maximum override history.
 */
#define ATLAS_CFG_MAX_OVERRIDES 16

/**
 * @struct OverrideEntry
 * @brief One override entry.
 */
struct OverrideEntry
{
    string key;
    string old_value;
    string new_value;
    bool   persistent;
    bool   active;
};

/**
 * @class ConfigurationOverride
 * @brief Manages runtime configuration overrides.
 *
 * Supports:
 *   - Temporary overrides (not persisted)
 *   - Persistent overrides (saved to profile)
 *   - Rollback (undo last override)
 */
class ConfigurationOverride
{
private:
    OverrideEntry m_overrides[ATLAS_CFG_MAX_OVERRIDES];
    int           m_count;

public:
    ConfigurationOverride(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_CFG_MAX_OVERRIDES; i++)
            m_overrides[i].active = false;
    }

    /**
     * @brief Apply an override.
     * @param key Parameter key.
     * @param old_value Current value (for rollback).
     * @param new_value New value.
     * @param persistent True if persistent.
     * @return true if applied.
     */
    bool Apply(const string key, const string old_value,
               const string new_value, const bool persistent)
    {
        if(m_count >= ATLAS_CFG_MAX_OVERRIDES) return false;

        m_overrides[m_count].key        = key;
        m_overrides[m_count].old_value  = old_value;
        m_overrides[m_count].new_value  = new_value;
        m_overrides[m_count].persistent = persistent;
        m_overrides[m_count].active     = true;
        m_count++;
        return true;
    }

    /**
     * @brief Rollback the last override.
     * @param out_key Output: the key that was rolled back.
     * @param out_old_value Output: the restored value.
     * @return true if rolled back.
     */
    bool Rollback(string &out_key, string &out_old_value)
    {
        if(m_count == 0) return false;

        m_count--;
        out_key      = m_overrides[m_count].key;
        out_old_value = m_overrides[m_count].old_value;
        m_overrides[m_count].active = false;
        return true;
    }

    /**
     * @brief Get count of active overrides.
     */
    int ActiveCount(void) const
    {
        int c = 0;
        for(int i = 0; i < m_count; i++)
            if(m_overrides[i].active) c++;
        return c;
    }

    /**
     * @brief Get count of persistent overrides.
     */
    int PersistentCount(void) const
    {
        int c = 0;
        for(int i = 0; i < m_count; i++)
            if(m_overrides[i].active && m_overrides[i].persistent) c++;
        return c;
    }

    /**
     * @brief Clear all overrides.
     */
    void Clear(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_CFG_MAX_OVERRIDES; i++)
            m_overrides[i].active = false;
    }
};

#endif // ATLAS_CONFIGURATION_OVERRIDE_MQH
//+------------------------------------------------------------------+
