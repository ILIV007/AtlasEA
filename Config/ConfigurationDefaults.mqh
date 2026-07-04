//+------------------------------------------------------------------+
//|                  Config/ConfigurationDefaults.mqh               |
//|       AtlasEA v0.1.22.0 - Production-Safe Defaults               |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_DEFAULTS_MQH
#define ATLAS_CONFIGURATION_DEFAULTS_MQH

#include "../Config/Settings.mqh"

/**
 * @class ConfigurationDefaults
 * @brief Provides production-safe default values.
 *
 * These are the most conservative values that will not cause
 * immediate harm even if loaded without customization.
 */
class ConfigurationDefaults
{
public:
    /**
     * @brief Apply production-safe defaults to a config.
     */
    static void Apply(AtlasConfig &cfg)
    {
        AtlasConfigDefaults(cfg);
    }

    /**
     * @brief Get the minimum safe value for a parameter.
     * Used by the validator to reject dangerously low values.
     */
    static double GetMinValue(const string key)
    {
        if(key == "base_volume")        return 0.01;
        if(key == "max_daily_drawdown") return 1.0;
        if(key == "max_exposure")       return 0.01;
        if(key == "max_ms_per_tick")    return 10.0;
        return 0.0;
    }

    /**
     * @brief Get the maximum safe value for a parameter.
     */
    static double GetMaxValue(const string key)
    {
        if(key == "base_volume")        return 100.0;
        if(key == "max_daily_drawdown") return 50.0;
        if(key == "max_exposure")       return 5.0;
        if(key == "max_ms_per_tick")    return 1000.0;
        if(key == "max_retries")        return 10.0;
        if(key == "max_events_per_tick") return 1000.0;
        return 1e9;
    }
};

#endif // ATLAS_CONFIGURATION_DEFAULTS_MQH
//+------------------------------------------------------------------+
