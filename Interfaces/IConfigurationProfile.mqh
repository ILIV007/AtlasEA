//+------------------------------------------------------------------+
//|                Interfaces/IConfigurationProfile.mqh             |
//|       AtlasEA v0.1.18.0 - Configuration Profile Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONFIGURATION_PROFILE_MQH
#define ATLAS_ICONFIGURATION_PROFILE_MQH

#include "../Config/Settings.mqh"

//--- Forward
struct AtlasConfiguration;

/**
 * @class IConfigurationProfile
 * @brief Interface for a named configuration profile.
 *
 * A profile is a named, serializable configuration variant.
 * Profiles can be loaded, saved, compared, and cloned.
 */
class IConfigurationProfile
{
public:
    /// @brief Get the profile name.
    virtual string GetName(void) const = 0;

    /// @brief Get the profile code (ATLAS_PROFILE_*).
    virtual int GetCode(void) const = 0;

    /// @brief Get the configuration for this profile.
    virtual const AtlasConfiguration& GetConfig(void) const = 0;

    /// @brief Set the configuration for this profile.
    virtual void SetConfig(const AtlasConfiguration &config) = 0;

    /// @brief Reset to profile defaults.
    virtual void ResetToDefaults(void) = 0;

    virtual ~IConfigurationProfile(void) {}
};

#endif // ATLAS_ICONFIGURATION_PROFILE_MQH
//+------------------------------------------------------------------+
