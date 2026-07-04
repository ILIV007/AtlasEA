//+------------------------------------------------------------------+
//|                 Interfaces/IConfigurationManager.mqh            |
//|       AtlasEA v0.1.22.0 - Configuration Manager Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONFIGURATION_MANAGER_V2_MQH
#define ATLAS_ICONFIGURATION_MANAGER_V2_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Profile codes.
 */
#define ATLAS_PROFILE_DEVELOPMENT   0
#define ATLAS_PROFILE_TESTING       1
#define ATLAS_PROFILE_BACKTEST      2
#define ATLAS_PROFILE_DEMO          3
#define ATLAS_PROFILE_LIVE          4
#define ATLAS_PROFILE_STRESS_TEST   5

/**
 * @class IConfigurationManager
 * @brief Centralized configuration management interface.
 *
 * Configuration is immutable after validation. Modules receive read-only
 * references via GetConfig(). Only ConfigurationManager may modify
 * configuration (during reload).
 */
class IConfigurationManager
{
public:
    /// @brief Get the active configuration (immutable reference).
    virtual const AtlasConfig& GetConfig(void) const = 0;

    /// @brief Load a profile by code.
    virtual bool LoadProfile(const int profile_code) = 0;

    /// @brief Save current configuration.
    virtual bool SaveConfig(void) = 0;

    /// @brief Reload configuration from disk (if supported).
    virtual bool ReloadConfig(void) = 0;

    /// @brief Validate the current configuration.
    virtual bool Validate(void) const = 0;

    /// @brief Get the active profile code.
    virtual int GetActiveProfile(void) const = 0;

    /// @brief Get the active profile name.
    virtual string GetActiveProfileName(void) const = 0;

    /// @brief Get the configuration version.
    virtual int GetVersion(void) const = 0;

    /// @brief Initialize with a profile.
    virtual bool Initialize(const int profile_code) = 0;

    /// @brief Shutdown.
    virtual void Shutdown(void) = 0;

    virtual ~IConfigurationManager(void) {}
};

#endif // ATLAS_ICONFIGURATION_MANAGER_V2_MQH
//+------------------------------------------------------------------+
