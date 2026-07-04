//+------------------------------------------------------------------+
//|               Config/ConfigurationSnapshot.mqh                  |
//|       AtlasEA v0.1.18.0 - Configuration Snapshot Management     |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_SNAPSHOT_MQH
#define ATLAS_CONFIGURATION_SNAPSHOT_MQH

#include "AtlasConfiguration.mqh"
#include "../Interfaces/IConfigurationSerializer.mqh"

/**
 * @brief Maximum stored snapshots.
 */
#define ATLAS_CFG_MAX_SNAPSHOTS 8

/**
 * @struct ConfigSnapshot
 * @brief A named configuration snapshot.
 */
struct ConfigSnapshot
{
    string              name;
    datetime            timestamp;
    AtlasConfiguration  config;
    bool                valid;
};

/**
 * @class ConfigurationSnapshot
 * @brief Manages configuration snapshots for recovery and comparison.
 *
 * Supports:
 *   - TakeSnapshot() — capture current config
 *   - RestoreSnapshot() — restore a named snapshot
 *   - CompareSnapshot() — diff current vs snapshot
 *   - ExportSnapshot() — serialize to string
 */
class ConfigurationSnapshot
{
private:
    ConfigSnapshot m_snapshots[ATLAS_CFG_MAX_SNAPSHOTS];
    int            m_count;

public:
    ConfigurationSnapshot(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_CFG_MAX_SNAPSHOTS; i++)
            m_snapshots[i].valid = false;
    }

    /**
     * @brief Take a snapshot of the current configuration.
     * @param name Snapshot name.
     * @param config Current config.
     * @return true if captured.
     */
    bool Take(const string name, const AtlasConfiguration &config)
    {
        //--- Check if name exists (update)
        for(int i = 0; i < m_count; i++)
        {
            if(m_snapshots[i].name == name)
            {
                m_snapshots[i].config    = config;
                m_snapshots[i].timestamp = TimeCurrent();
                m_snapshots[i].valid     = true;
                return true;
            }
        }

        if(m_count >= ATLAS_CFG_MAX_SNAPSHOTS) return false;

        m_snapshots[m_count].name      = name;
        m_snapshots[m_count].config    = config;
        m_snapshots[m_count].timestamp = TimeCurrent();
        m_snapshots[m_count].valid     = true;
        m_count++;
        return true;
    }

    /**
     * @brief Restore a snapshot.
     * @param name Snapshot name.
     * @param out_config Output: restored config.
     * @return true if restored.
     */
    bool Restore(const string name, AtlasConfiguration &out_config) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_snapshots[i].valid && m_snapshots[i].name == name)
            {
                out_config = m_snapshots[i].config;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Compare current config with a snapshot.
     * @param name Snapshot name.
     * @param current Current config.
     * @return Number of differing fields.
     */
    int Compare(const string name, const AtlasConfiguration &current) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_snapshots[i].valid && m_snapshots[i].name == name)
            {
                const AtlasConfiguration &snap = m_snapshots[i].config;
                int diff = 0;

                if(snap.core.magic_number != current.core.magic_number) diff++;
                if(snap.core.base_volume != current.core.base_volume) diff++;
                if(snap.core.max_daily_drawdown_pct != current.core.max_daily_drawdown_pct) diff++;
                if(snap.core.max_exposure_limit != current.core.max_exposure_limit) diff++;
                if(snap.core.max_ms_per_tick != current.core.max_ms_per_tick) diff++;
                if(snap.core.max_events_per_tick != current.core.max_events_per_tick) diff++;
                if(snap.core.log_level != current.core.log_level) diff++;
                if(snap.trading_enabled != current.trading_enabled) diff++;
                if(snap.plugins_enabled != current.plugins_enabled) diff++;

                return diff;
            }
        }
        return -1;  ///< Not found
    }

    /**
     * @brief Export a snapshot to a string (INI-like format).
     */
    string Export(const string name) const
    {
        string out = "";
        for(int i = 0; i < m_count; i++)
        {
            if(m_snapshots[i].valid && m_snapshots[i].name == name)
            {
                const AtlasConfiguration &c = m_snapshots[i].config;
                out += "version=" + IntegerToString(c.version) + "\n";
                out += "profile=" + c.profile_name + "\n";
                out += "magic=" + IntegerToString(c.core.magic_number) + "\n";
                out += "symbol=" + c.core.symbol + "\n";
                out += "volume=" + DoubleToString(c.core.base_volume, 2) + "\n";
                out += "max_dd=" + DoubleToString(c.core.max_daily_drawdown_pct, 1) + "\n";
                out += "max_exposure=" + DoubleToString(c.core.max_exposure_limit, 2) + "\n";
                out += "log_level=" + IntegerToString(c.core.log_level) + "\n";
                out += "trading_enabled=" + (c.trading_enabled ? "1" : "0") + "\n";
                return out;
            }
        }
        return "";
    }

    int Count(void) const { return m_count; }
};

#endif // ATLAS_CONFIGURATION_SNAPSHOT_MQH
//+------------------------------------------------------------------+
