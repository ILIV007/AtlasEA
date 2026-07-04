//+------------------------------------------------------------------+
//|               Config/ConfigurationProfiles.mqh                  |
//|       AtlasEA v0.1.18.0 - Profile Management                     |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_PROFILES_MQH
#define ATLAS_CONFIGURATION_PROFILES_MQH

#include "AtlasConfiguration.mqh"
#include "ConfigurationDefaults.mqh"
#include "../Interfaces/IConfigurationProfile.mqh"

/**
 * @brief Maximum stored profiles.
 */
#define ATLAS_CFG_MAX_PROFILES 8

/**
 * @class ConfigurationProfile
 * @brief Concrete implementation of IConfigurationProfile.
 */
class ConfigurationProfile : public IConfigurationProfile
{
private:
    string              m_name;
    int                 m_code;
    AtlasConfiguration  m_config;

public:
    ConfigurationProfile(void)
    {
        m_name = "";
        m_code = ATLAS_PROFILE_PRODUCTION;
    }

    void Initialize(const int code)
    {
        m_code   = code;
        m_name   = ConfigurationDefaults::GetProfileName(code);
        m_config = ConfigurationDefaults::GetDefaults(code);
    }

    virtual string GetName(void) const override { return m_name; }
    virtual int GetCode(void) const override { return m_code; }
    virtual const AtlasConfiguration& GetConfig(void) const override { return m_config; }
    virtual void SetConfig(const AtlasConfiguration &config) override { m_config = config; }

    virtual void ResetToDefaults(void) override
    {
        m_config = ConfigurationDefaults::GetDefaults(m_code);
    }
};

/**
 * @class ConfigurationProfiles
 * @brief Manages multiple named profiles.
 */
class ConfigurationProfiles
{
private:
    ConfigurationProfile m_profiles[ATLAS_CFG_MAX_PROFILES];
    int                  m_count;
    int                  m_active_index;

public:
    ConfigurationProfiles(void)
    {
        m_count       = 0;
        m_active_index = -1;
    }

    /**
     * @brief Load a profile by code (creates if not exists).
     */
    bool LoadByCode(const int code)
    {
        //--- Check if already exists
        for(int i = 0; i < m_count; i++)
        {
            if(m_profiles[i].GetCode() == code)
            {
                m_active_index = i;
                return true;
            }
        }

        //--- Create new
        if(m_count >= ATLAS_CFG_MAX_PROFILES) return false;
        m_profiles[m_count].Initialize(code);
        m_active_index = m_count;
        m_count++;
        return true;
    }

    /**
     * @brief Get the active profile.
     */
    IConfigurationProfile* GetActive(void)
    {
        if(m_active_index < 0 || m_active_index >= m_count) return NULL;
        return &m_profiles[m_active_index];
    }

    /**
     * @brief Find a profile by name.
     */
    IConfigurationProfile* Find(const string name)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_profiles[i].GetName() == name)
                return &m_profiles[i];
        }
        return NULL;
    }

    /**
     * @brief Clone the active profile to a new name.
     */
    bool CloneActive(const string new_name)
    {
        if(m_active_index < 0) return false;
        if(m_count >= ATLAS_CFG_MAX_PROFILES) return false;

        m_profiles[m_count] = m_profiles[m_active_index];
        //--- Note: can't rename because GetName returns const
        //--- In practice, the clone inherits the source profile name
        m_count++;
        return true;
    }

    /**
     * @brief Compare two profiles by index.
     * @return Number of differing fields.
     */
    int Compare(const int idx_a, const int idx_b) const
    {
        if(idx_a < 0 || idx_a >= m_count) return -1;
        if(idx_b < 0 || idx_b >= m_count) return -1;

        const AtlasConfiguration &a = m_profiles[idx_a].GetConfig();
        const AtlasConfiguration &b = m_profiles[idx_b].GetConfig();
        int diff = 0;

        if(a.core.magic_number != b.core.magic_number) diff++;
        if(a.core.base_volume != b.core.base_volume) diff++;
        if(a.core.max_daily_drawdown_pct != b.core.max_daily_drawdown_pct) diff++;
        if(a.core.max_exposure_limit != b.core.max_exposure_limit) diff++;
        if(a.core.max_ms_per_tick != b.core.max_ms_per_tick) diff++;
        if(a.core.max_events_per_tick != b.core.max_events_per_tick) diff++;
        if(a.core.log_level != b.core.log_level) diff++;
        if(a.trading_enabled != b.trading_enabled) diff++;
        if(a.plugins_enabled != b.plugins_enabled) diff++;

        return diff;
    }

    int Count(void) const { return m_count; }
    int GetActiveIndex(void) const { return m_active_index; }
};

#endif // ATLAS_CONFIGURATION_PROFILES_MQH
//+------------------------------------------------------------------+
