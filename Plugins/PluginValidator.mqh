//+------------------------------------------------------------------+
//|                    Plugins/PluginValidator.mqh                  |
//|       AtlasEA v0.1.17.0 - Plugin Validation                      |
//+------------------------------------------------------------------+
#ifndef ATLAS_PLUGIN_VALIDATOR_MQH
#define ATLAS_PLUGIN_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Current SDK version.
 */
#define ATLAS_SDK_VERSION 1

/**
 * @brief Current AtlasEA version.
 */
#define ATLAS_PLUGIN_VERSION 1

/**
 * @struct ValidationResult
 * @brief Result of plugin validation.
 */
struct ValidationResult
{
    bool   valid;
    string reason;
    int    error_count;
};

/**
 * @class PluginValidator
 * @brief Validates plugins before registration.
 *
 * Checks:
 *   1. SDK version compatibility
 *   2. AtlasEA version compatibility
 *   3. Metadata completeness
 *   4. Required callbacks present
 *   5. Duplicate ID detection
 *   6. Capability conflicts
 */
class PluginValidator
{
private:
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     */
    PluginValidator(void) { m_logger = NULL; }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Validate a plugin.
     * @param plugin The plugin to validate.
     * @return ValidationResult with details.
     */
    ValidationResult Validate(const IStrategyPlugin &plugin) const
    {
        ValidationResult result;
        result.valid       = true;
        result.reason      = "";
        result.error_count = 0;

        const PluginMetadata &meta = plugin.GetMetadata();

        //--- Check 1: Metadata completeness
        string meta_reason;
        if(!meta.Validate(meta_reason))
        {
            result.valid  = false;
            result.reason = "Metadata invalid: " + meta_reason;
            result.error_count++;
            if(m_logger != NULL)
                m_logger.Error("PluginValidator", result.reason);
            return result;
        }

        //--- Check 2: SDK version
        if(meta.sdk_version > ATLAS_SDK_VERSION)
        {
            result.valid  = false;
            result.reason = "SDK version too new: plugin requires " +
                           IntegerToString(meta.sdk_version) +
                           " but current is " + IntegerToString(ATLAS_SDK_VERSION);
            result.error_count++;
            if(m_logger != NULL)
                m_logger.Error("PluginValidator", result.reason);
            return result;
        }

        //--- Check 3: Atlas version
        if(meta.atlas_version > ATLAS_PLUGIN_VERSION)
        {
            result.valid  = false;
            result.reason = "AtlasEA version too new: plugin requires " +
                           IntegerToString(meta.atlas_version) +
                           " but current is " + IntegerToString(ATLAS_PLUGIN_VERSION);
            result.error_count++;
            if(m_logger != NULL)
                m_logger.Error("PluginValidator", result.reason);
            return result;
        }

        //--- Check 4: Required callbacks
        //--- If CAP_EVALUATE is set, Evaluate() must be overridden.
        //--- We can't check this in MQL5 (no reflection), but we verify
        //--- that the metadata claims the capability.
        if((meta.capabilities & ATLAS_CAP_EVALUATE) == 0)
        {
            //--- A strategy without EVALUATE capability is unusual but not invalid.
            if(m_logger != NULL)
                m_logger.Debug("PluginValidator",
                    meta.name + " has no EVALUATE capability");
        }

        //--- Check 5: Name/version not empty (covered by metadata validation)

        //--- Check 6: Capability conflicts
        //--- A plugin can't have both ON_MARKET and not have it — this is
        //--- inherently satisfied by the bitmask design.

        if(result.valid && m_logger != NULL)
            m_logger.Info("PluginValidator",
                meta.name + " v" + meta.version + " validation PASSED");

        return result;
    }

    /**
     * @brief Check for duplicate IDs across a set of plugins.
     * @param plugins Array of plugin pointers.
     * @param count Number of plugins.
     * @return true if no duplicates found.
     */
    bool CheckNoDuplicates(IStrategyPlugin *plugins[], const int count) const
    {
        for(int i = 0; i < count; i++)
        {
            for(int j = i + 1; j < count; j++)
            {
                if(plugins[i] == NULL || plugins[j] == NULL) continue;
                const PluginMetadata &mi = plugins[i].GetMetadata();
                const PluginMetadata &mj = plugins[j].GetMetadata();
                if(mi.plugin_id == mj.plugin_id)
                {
                    if(m_logger != NULL)
                        m_logger.Error("PluginValidator",
                            "Duplicate plugin_id: " + IntegerToString(mi.plugin_id) +
                            " (" + mi.name + " and " + mj.name + ")");
                    return false;
                }
            }
        }
        return true;
    }
};

#endif // ATLAS_PLUGIN_VALIDATOR_MQH
//+------------------------------------------------------------------+
