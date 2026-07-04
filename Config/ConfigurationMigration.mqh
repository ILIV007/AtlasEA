//+------------------------------------------------------------------+
//|               Config/ConfigurationMigration.mqh                 |
//|       AtlasEA v0.1.18.0 - Configuration Migration               |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_MIGRATION_MQH
#define ATLAS_CONFIGURATION_MIGRATION_MQH

#include "AtlasConfiguration.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct MigrationStep
 * @brief One migration step in history.
 */
struct MigrationStep
{
    int      from_version;
    int      to_version;
    datetime timestamp;
    string   description;
};

/**
 * @class ConfigurationMigration
 * @brief Handles configuration version upgrades and downgrades.
 *
 * Migration history is tracked. Each upgrade adds a MigrationStep.
 *
 * Currently supports:
 *   v1 → v2: adds new fields (extended config), preserves existing AtlasConfig
 */
class ConfigurationMigration
{
private:
    ILogger        *m_logger;
    MigrationStep   m_history[16];
    int             m_history_count;

public:
    ConfigurationMigration(void)
    {
        m_logger        = NULL;
        m_history_count = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Migrate from an older version to current.
     * @param config The config to migrate (mutated).
     * @param from_version The current version of the config.
     * @return true if migration succeeded.
     */
    bool Migrate(AtlasConfiguration &config, const int from_version)
    {
        if(from_version == ATLAS_CONFIG_VERSION)
        {
            if(m_logger != NULL)
                m_logger.Debug("ConfigurationMigration", "Already at current version " +
                              IntegerToString(ATLAS_CONFIG_VERSION));
            return true;
        }

        if(from_version > ATLAS_CONFIG_VERSION)
        {
            if(m_logger != NULL)
                m_logger.Warn("ConfigurationMigration",
                    "Downgrade from v" + IntegerToString(from_version) +
                    " to v" + IntegerToString(ATLAS_CONFIG_VERSION));
            //--- Downgrade: just set version (new fields keep their defaults)
            config.version = ATLAS_CONFIG_VERSION;
            RecordStep(from_version, ATLAS_CONFIG_VERSION, "Downgrade");
            return true;
        }

        //--- Upgrade path
        int current = from_version;
        while(current < ATLAS_CONFIG_VERSION)
        {
            int next = current + 1;
            if(!Upgrade(config, current, next))
            {
                if(m_logger != NULL)
                    m_logger.Error("ConfigurationMigration",
                        "Upgrade failed: v" + IntegerToString(current) +
                        " → v" + IntegerToString(next));
                return false;
            }
            current = next;
        }

        config.version = ATLAS_CONFIG_VERSION;

        if(m_logger != NULL)
            m_logger.Info("ConfigurationMigration",
                "Migrated from v" + IntegerToString(from_version) +
                " to v" + IntegerToString(ATLAS_CONFIG_VERSION));

        return true;
    }

    /**
     * @brief Get migration history count.
     */
    int GetHistoryCount(void) const { return m_history_count; }

    /**
     * @brief Get a history entry.
     */
    bool GetHistoryEntry(const int index, MigrationStep &out) const
    {
        if(index < 0 || index >= m_history_count) return false;
        out = m_history[index];
        return true;
    }

private:
    /// @brief Perform a single version upgrade.
    bool Upgrade(AtlasConfiguration &config, const int from_v, const int to_v)
    {
        if(from_v == 1 && to_v == 2)
        {
            //--- v1 → v2: Initialize new fields with defaults
            //--- The AtlasConfiguration constructor already sets defaults,
            //--- so we just need to ensure the version field is updated.
            //--- Existing AtlasConfig fields are preserved.

            config.trading_enabled          = true;
            config.max_concurrent_trades    = 5;
            config.max_floating_loss        = 500.0;
            config.loss_streak_cooldown_sec = 1800;
            config.min_rr_ratio             = 1.0;
            config.mandatory_stop_loss      = true;
            config.broker_retry_base_ms     = 200;
            config.broker_max_slippage_points = 20.0;
            config.broker_auto_reconnect    = true;
            config.execution_timeout_ms     = 5000;
            config.execution_require_idempotency = true;
            config.log_ring_buffer_size     = 256;
            config.log_to_file              = false;
            config.log_file_path            = "AtlasEA.log";
            config.persistence_flush_interval_sec = 10;
            config.persistence_compress_snapshots = false;
            config.persistence_retention_days     = 30;
            config.recovery_auto_safe_mode  = true;
            config.recovery_max_attempts    = 3;
            config.perf_profiler_enabled    = true;
            config.perf_latency_monitor_enabled = true;
            config.perf_sample_window       = 256;
            config.diag_health_monitor_enabled = true;
            config.diag_health_check_interval_sec = 10;
            config.diag_memory_tracking_enabled = true;
            config.plugins_enabled          = true;
            config.plugins_max_count        = 64;
            config.plugins_auto_load        = false;
            config.testing_mock_broker      = false;
            config.testing_random_seed      = 12345;
            config.testing_tick_speed_ms    = 0;

            RecordStep(from_v, to_v, "v1→v2: add extended fields");
            return true;
        }

        //--- Unknown upgrade path
        return false;
    }

    /// @brief Record a migration step.
    void RecordStep(const int from_v, const int to_v, const string desc)
    {
        if(m_history_count < 16)
        {
            m_history[m_history_count].from_version = from_v;
            m_history[m_history_count].to_version   = to_v;
            m_history[m_history_count].timestamp    = TimeCurrent();
            m_history[m_history_count].description  = desc;
            m_history_count++;
        }
    }
};

#endif // ATLAS_CONFIGURATION_MIGRATION_MQH
//+------------------------------------------------------------------+
