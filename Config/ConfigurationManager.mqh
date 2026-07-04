//+------------------------------------------------------------------+
//|                 Config/ConfigurationManager.mqh                 |
//|       AtlasEA v0.1.22.0 - Centralized Configuration Manager     |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_MANAGER_MQH
#define ATLAS_CONFIGURATION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IConfigurationManager.mqh"
#include "../Interfaces/IConfigurationValidator.mqh"
#include "../Interfaces/IConfigurationWatcher.mqh"
#include "../Interfaces/ILogger.mqh"
#include "ConfigurationVersion.mqh"
#include "ConfigurationProfile.mqh"
#include "ConfigurationDefaults.mqh"
#include "ConfigurationValidator.mqh"
#include "ConfigurationWatcher.mqh"

/**
 * @class ConfigurationManager
 * @brief Concrete implementation of IConfigurationManager.
 *
 * Centralized configuration management with:
 *   - 6 profiles (Development, Testing, Backtest, Demo, Live, StressTest)
 *   - Validation (all fields checked against safe ranges)
 *   - Versioning (schema version + migration)
 *   - Runtime reload (via ConfigurationWatcher)
 *   - Read-only access (modules receive const AtlasConfig&)
 *
 * Configuration is immutable after validation. Modules receive
 * read-only references via GetConfig(). Only ConfigurationManager
 * may modify configuration (during reload).
 *
 * Thread model: single-threaded (MQL5). No locks.
 */
class ConfigurationManager : public IConfigurationManager
{
private:
    ILogger              *m_logger;
    AtlasConfig           m_config;        ///< Active configuration (immutable after validation)
    int                   m_active_profile;
    ConfigurationVersion  m_version;
    ConfigurationValidator m_validator;
    ConfigurationWatcher  m_watcher;
    bool                  m_initialized;
    bool                  m_validated;

public:
    /**
     * @brief Constructor.
     */
    ConfigurationManager(void)
    {
        m_logger       = NULL;
        m_active_profile = ATLAS_PROFILE_LIVE;
        m_initialized  = false;
        m_validated    = false;
        AtlasConfigDefaults(m_config);
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_validator.SetLogger(logger);
    }

    //=== IConfigurationManager implementation ===

    virtual const AtlasConfig& GetConfig(void) const override
    {
        return m_config;
    }

    virtual bool LoadProfile(const int profile_code) override
    {
        m_config = ConfigurationProfiles.GetConfig(profile_code);
        m_active_profile = profile_code;

        if(m_logger != NULL)
            m_logger.Info("ConfigurationManager",
                "Loaded profile: " + ConfigurationProfiles.GetProfileName(profile_code) +
                " (" + ConfigurationProfiles.GetProfileDescription(profile_code) + ")");

        return Validate();
    }

    virtual bool SaveConfig(void) override
    {
        //--- In this phase, saving to file is not implemented
        //--- Configuration is in-memory only
        if(m_logger != NULL)
            m_logger.Info("ConfigurationManager", "SaveConfig: in-memory only (no file I/O)");
        return true;
    }

    virtual bool ReloadConfig(void) override
    {
        if(m_logger != NULL)
            m_logger.Info("ConfigurationManager", "Reloading configuration...");

        //--- Reload from current profile (in-memory)
        AtlasConfig new_config = ConfigurationProfiles.GetConfig(m_active_profile);

        //--- Validate before applying
        ConfigValidationReport report = m_validator.Validate(new_config);
        if(!report.valid)
        {
            if(m_logger != NULL)
            {
                m_logger.Error("ConfigurationManager",
                    "Reload failed: " + IntegerToString(report.error_count) + " errors");
                for(int i = 0; i < report.error_idx; i++)
                    m_logger.Error("ConfigurationManager", "  " + report.errors[i]);
            }
            return false;
        }

        //--- Apply (atomic swap)
        m_config    = new_config;
        m_validated = true;

        if(m_logger != NULL)
            m_logger.Info("ConfigurationManager", "Reload complete");

        return true;
    }

    virtual bool Validate(void) const override
    {
        ConfigValidationReport report = m_validator.Validate(m_config);
        return report.valid;
    }

    virtual int GetActiveProfile(void) const override
    {
        return m_active_profile;
    }

    virtual string GetActiveProfileName(void) const override
    {
        return ConfigurationProfiles.GetProfileName(m_active_profile);
    }

    virtual int GetVersion(void) const override
    {
        return m_version.schema_version;
    }

    virtual bool Initialize(const int profile_code) override
    {
        if(m_logger == NULL)
            return false;

        m_active_profile = profile_code;

        //--- Load profile
        if(!LoadProfile(profile_code))
        {
            m_logger.Error("ConfigurationManager", "Initialize: LoadProfile failed");
            return false;
        }

        //--- Validate
        ConfigValidationReport report = m_validator.Validate(m_config);
        if(!report.valid)
        {
            m_logger.Error("ConfigurationManager",
                "Initialize: validation failed (" + IntegerToString(report.error_count) + " errors)");
            for(int i = 0; i < report.error_idx; i++)
                m_logger.Error("ConfigurationManager", "  " + report.errors[i]);
            return false;
        }

        m_validated   = true;
        m_initialized = true;

        m_logger.Info("ConfigurationManager",
            "Initialized: profile=" + GetActiveProfileName() +
            " version=" + m_version.ToString() +
            " symbol=" + m_config.symbol);

        return true;
    }

    virtual void Shutdown(void) override
    {
        if(m_logger != NULL)
            m_logger.Info("ConfigurationManager", "Shutdown");
        m_initialized = false;
    }

    //=== Extended API ===

    /**
     * @brief Get the validator (for direct access).
     */
    ConfigurationValidator& GetValidator(void) { return m_validator; }

    /**
     * @brief Get the watcher (for registering callbacks).
     */
    ConfigurationWatcher& GetWatcher(void) { return m_watcher; }

    /**
     * @brief Get the version info.
     */
    const ConfigurationVersion& GetVersionInfo(void) const { return m_version; }

    /**
     * @brief Is the configuration validated?
     */
    bool IsValidated(void) const { return m_validated; }

    /**
     * @brief Is the manager initialized?
     */
    bool IsInitialized(void) const { return m_initialized; }
};

#endif // ATLAS_CONFIGURATION_MANAGER_MQH
//+------------------------------------------------------------------+
