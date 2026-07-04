//+------------------------------------------------------------------+
//|                   Config/ConfigurationProfile.mqh               |
//|       AtlasEA v0.1.22.0 - Configuration Profiles                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_PROFILE_MQH
#define ATLAS_CONFIGURATION_PROFILE_MQH

#include "../Config/Settings.mqh"

/**
 * @struct ConfigurationProfile
 * @brief A named configuration profile with its own parameters.
 *
 * Each profile customizes the base AtlasConfig for a specific
 * execution context (development, testing, live, etc.).
 */
struct ConfigurationProfile
{
    int         code;       ///< ATLAS_PROFILE_*
    string      name;       ///< Human-readable name
    string      description;///< What this profile is for
    AtlasConfig config;     ///< The configuration for this profile

    /**
     * @brief Default constructor.
     */
    ConfigurationProfile(void)
    {
        code        = ATLAS_PROFILE_LIVE;
        name        = "Live";
        description = "Production trading";
        AtlasConfigDefaults(config);
    }
};

/**
 * @class ConfigurationProfiles
 * @brief Factory for creating profile-specific configurations.
 *
 * 6 profiles:
 *   - Development: verbose logging, small volumes, relaxed risk
 *   - Testing: mock-friendly, fast execution
 *   - Backtest: no persistence, full diagnostics
 *   - Demo: production-like but relaxed
 *   - Live: conservative, full persistence, strict risk
 *   - StressTest: extreme parameters
 */
class ConfigurationProfiles
{
public:
    /**
     * @brief Get the configuration for a profile.
     * @param profile_code ATLAS_PROFILE_*
     * @return AtlasConfig with profile-specific settings.
     */
    static AtlasConfig GetConfig(const int profile_code)
    {
        AtlasConfig cfg;
        AtlasConfigDefaults(cfg);

        switch(profile_code)
        {
            case ATLAS_PROFILE_DEVELOPMENT:
                cfg.log_level           = ATLAS_LOG_TRACE;
                cfg.base_volume         = 0.01;
                cfg.max_daily_drawdown_pct = 10.0;
                cfg.max_exposure_limit  = 0.50;
                cfg.max_active_strategies = 2;
                break;

            case ATLAS_PROFILE_TESTING:
                cfg.log_level           = ATLAS_LOG_DEBUG;
                cfg.base_volume         = 0.01;
                cfg.max_daily_drawdown_pct = 20.0;
                cfg.max_exposure_limit  = 1.0;
                cfg.max_ms_per_tick     = 500;
                cfg.max_events_per_tick = 100;
                break;

            case ATLAS_PROFILE_BACKTEST:
                cfg.log_level           = ATLAS_LOG_WARN;
                cfg.base_volume         = 0.10;
                cfg.max_daily_drawdown_pct = 5.0;
                cfg.max_exposure_limit  = 0.20;
                cfg.snapshot_interval_sec = 0;  //--- No snapshots in backtest
                break;

            case ATLAS_PROFILE_DEMO:
                cfg.log_level           = ATLAS_LOG_INFO;
                cfg.base_volume         = 0.10;
                cfg.max_daily_drawdown_pct = 5.0;
                cfg.max_exposure_limit  = 0.20;
                break;

            case ATLAS_PROFILE_LIVE:
                cfg.log_level           = ATLAS_LOG_INFO;
                cfg.base_volume         = 0.10;
                cfg.max_daily_drawdown_pct = 5.0;
                cfg.max_exposure_limit  = 0.20;
                cfg.max_retries         = 3;
                cfg.slippage_points     = 20;
                break;

            case ATLAS_PROFILE_STRESS_TEST:
                cfg.log_level           = ATLAS_LOG_ERROR;
                cfg.base_volume         = 1.00;
                cfg.max_daily_drawdown_pct = 20.0;
                cfg.max_exposure_limit  = 1.0;
                cfg.max_ms_per_tick     = 500;
                cfg.max_events_per_tick = 100;
                cfg.max_active_strategies = 8;
                break;
        }

        return cfg;
    }

    /**
     * @brief Get the profile name.
     */
    static string GetProfileName(const int profile_code)
    {
        switch(profile_code)
        {
            case ATLAS_PROFILE_DEVELOPMENT: return "Development";
            case ATLAS_PROFILE_TESTING:     return "Testing";
            case ATLAS_PROFILE_BACKTEST:    return "Backtest";
            case ATLAS_PROFILE_DEMO:        return "Demo";
            case ATLAS_PROFILE_LIVE:        return "Live";
            case ATLAS_PROFILE_STRESS_TEST: return "StressTest";
        }
        return "Unknown";
    }

    /**
     * @brief Get the profile description.
     */
    static string GetProfileDescription(const int profile_code)
    {
        switch(profile_code)
        {
            case ATLAS_PROFILE_DEVELOPMENT: return "Verbose logging, small volumes, relaxed risk";
            case ATLAS_PROFILE_TESTING:     return "Mock-friendly, fast execution";
            case ATLAS_PROFILE_BACKTEST:    return "No persistence, full diagnostics";
            case ATLAS_PROFILE_DEMO:        return "Production-like but relaxed risk";
            case ATLAS_PROFILE_LIVE:        return "Conservative, full persistence, strict risk";
            case ATLAS_PROFILE_STRESS_TEST: return "Extreme parameters, maximum load";
        }
        return "";
    }
};

#endif // ATLAS_CONFIGURATION_PROFILE_MQH
//+------------------------------------------------------------------+
