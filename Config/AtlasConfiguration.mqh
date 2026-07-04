//+------------------------------------------------------------------+
//|                 Config/AtlasConfiguration.mqh                   |
//|       AtlasEA v0.1.18.0 - Unified Configuration Struct           |
//+------------------------------------------------------------------+
#ifndef ATLAS_ATLAS_CONFIGURATION_MQH
#define ATLAS_ATLAS_CONFIGURATION_MQH

#include "Settings.mqh"

/**
 * @brief Configuration version (incremented on schema changes).
 */
#define ATLAS_CONFIG_VERSION 2

/**
 * @brief Configuration category codes.
 */
#define ATLAS_CFG_CAT_TRADING       0
#define ATLAS_CFG_CAT_RISK          1
#define ATLAS_CFG_CAT_BROKER        2
#define ATLAS_CFG_CAT_EXECUTION     3
#define ATLAS_CFG_CAT_LOGGING       4
#define ATLAS_CFG_CAT_PERSISTENCE   5
#define ATLAS_CFG_CAT_RECOVERY      6
#define ATLAS_CFG_CAT_PERFORMANCE   7
#define ATLAS_CFG_CAT_DIAGNOSTICS   8
#define ATLAS_CFG_CAT_PLUGINS       9
#define ATLAS_CFG_CAT_TESTING       10

/**
 * @struct AtlasConfiguration
 * @brief Complete, versioned configuration for AtlasEA.
 *
 * This is the v2 unified configuration struct. It wraps the original
 * AtlasConfig (from Settings.mqh) and adds:
 *   - Versioning
 *   - Profile code
 *   - Extended fields for all 11 categories
 *
 * The original AtlasConfig is preserved for backward compatibility —
 * existing code that uses AtlasConfig continues to work. The new
 * AtlasConfiguration wraps it and adds new fields.
 */
struct AtlasConfiguration
{
    //=== Versioning ===
    int    version;             ///< Schema version (ATLAS_CONFIG_VERSION)
    int    profile_code;        ///< ATLAS_PROFILE_*
    string profile_name;        ///< Human-readable profile name

    //=== Core configuration (backward compatible with AtlasConfig) ===
    AtlasConfig core;           ///< Original config struct

    //=== Extended: Trading ===
    bool   trading_enabled;
    int    max_concurrent_trades;

    //=== Extended: Risk ===
    double max_floating_loss;
    int    loss_streak_cooldown_sec;
    double min_rr_ratio;
    bool   mandatory_stop_loss;

    //=== Extended: Broker ===
    int    broker_retry_base_ms;
    double broker_max_slippage_points;
    bool   broker_auto_reconnect;

    //=== Extended: Execution ===
    int    execution_timeout_ms;
    bool   execution_require_idempotency;

    //=== Extended: Logging ===
    int    log_ring_buffer_size;
    bool   log_to_file;
    string log_file_path;

    //=== Extended: Persistence ===
    int    persistence_flush_interval_sec;
    bool   persistence_compress_snapshots;
    int    persistence_retention_days;

    //=== Extended: Recovery ===
    bool   recovery_auto_safe_mode;
    int    recovery_max_attempts;

    //=== Extended: Performance ===
    bool   perf_profiler_enabled;
    bool   perf_latency_monitor_enabled;
    int    perf_sample_window;

    //=== Extended: Diagnostics ===
    bool   diag_health_monitor_enabled;
    int    diag_health_check_interval_sec;
    bool   diag_memory_tracking_enabled;

    //=== Extended: Plugins ===
    bool   plugins_enabled;
    int    plugins_max_count;
    bool   plugins_auto_load;

    //=== Extended: Testing ===
    bool   testing_mock_broker;
    ulong  testing_random_seed;
    int    testing_tick_speed_ms;

    /**
     * @brief Default constructor.
     */
    AtlasConfiguration(void)
    {
        version                  = ATLAS_CONFIG_VERSION;
        profile_code             = ATLAS_PROFILE_PRODUCTION;
        profile_name             = "Production";
        AtlasConfigDefaults(core);

        //--- Trading
        trading_enabled          = true;
        max_concurrent_trades    = 5;

        //--- Risk
        max_floating_loss        = 500.0;
        loss_streak_cooldown_sec = 1800;
        min_rr_ratio             = 1.0;
        mandatory_stop_loss      = true;

        //--- Broker
        broker_retry_base_ms     = 200;
        broker_max_slippage_points = 20.0;
        broker_auto_reconnect    = true;

        //--- Execution
        execution_timeout_ms     = 5000;
        execution_require_idempotency = true;

        //--- Logging
        log_ring_buffer_size     = 256;
        log_to_file              = false;
        log_file_path            = "AtlasEA.log";

        //--- Persistence
        persistence_flush_interval_sec = 10;
        persistence_compress_snapshots = false;
        persistence_retention_days     = 30;

        //--- Recovery
        recovery_auto_safe_mode  = true;
        recovery_max_attempts    = 3;

        //--- Performance
        perf_profiler_enabled    = true;
        perf_latency_monitor_enabled = true;
        perf_sample_window       = 256;

        //--- Diagnostics
        diag_health_monitor_enabled = true;
        diag_health_check_interval_sec = 10;
        diag_memory_tracking_enabled = true;

        //--- Plugins
        plugins_enabled          = true;
        plugins_max_count        = 64;
        plugins_auto_load        = false;

        //--- Testing
        testing_mock_broker      = false;
        testing_random_seed      = 12345;
        testing_tick_speed_ms    = 0;
    }
};

#endif // ATLAS_ATLAS_CONFIGURATION_MQH
//+------------------------------------------------------------------+
