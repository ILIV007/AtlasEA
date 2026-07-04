//+------------------------------------------------------------------+
//|              Config/ConfigurationSerializer.mqh                 |
//|       AtlasEA v0.1.18.0 - Configuration Serializer/Deserializer |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_SERIALIZER_MQH
#define ATLAS_CONFIGURATION_SERIALIZER_MQH

#include "AtlasConfiguration.mqh"
#include "../Interfaces/IConfigurationSerializer.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class ConfigurationSerializer
 * @brief Concrete implementation of IConfigurationSerializer.
 *
 * Supports 4 formats:
 *   - INI (human-readable key=value)
 *   - JSON-like (internal format)
 *   - Binary (compact key=value, no whitespace)
 *   - Memory (single-line summary)
 */
class ConfigurationSerializer : public IConfigurationSerializer
{
private:
    ILogger *m_logger;

    void AppendKV(string &buf, const string key, const string val) const
    {
        buf += key + "=" + val + "\n";
    }
    void AppendKV(string &buf, const string key, const long val) const
    {
        buf += key + "=" + IntegerToString(val) + "\n";
    }
    void AppendKV(string &buf, const string key, const double val) const
    {
        buf += key + "=" + DoubleToString(val, 6) + "\n";
    }

public:
    ConfigurationSerializer(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    virtual string Serialize(const AtlasConfiguration &config, const int format) const override
    {
        switch(format)
        {
            case ATLAS_CFG_FORMAT_INI:    return SerializeINI(config);
            case ATLAS_CFG_FORMAT_JSON:   return SerializeJSON(config);
            case ATLAS_CFG_FORMAT_BINARY: return SerializeBinary(config);
            case ATLAS_CFG_FORMAT_MEMORY: return SerializeMemory(config);
            default: return "";
        }
    }

    virtual bool Deserialize(const string &data, const int format,
                              AtlasConfiguration &out) const override
    {
        //--- Parse key=value lines (works for INI and Binary)
        string lines[];
        int line_count = StringSplit(data, '\n', lines);

        for(int i = 0; i < line_count; i++)
        {
            string line = lines[i];
            int eq = StringFind(line, "=");
            if(eq <= 0) continue;

            string key = StringSubstr(line, 0, eq);
            string val = StringSubstr(line, eq + 1);

            ApplyKeyValue(out, key, val);
        }

        return true;
    }

    virtual bool SerializeToFile(const AtlasConfiguration &config, const int format,
                                  const string filename) const override
    {
        string data = Serialize(config, format);
        if(data == "") return false;

        int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE) return false;
        FileWriteString(handle, data);
        FileClose(handle);
        return true;
    }

    virtual bool DeserializeFromFile(const string filename, const int format,
                                      AtlasConfiguration &out) const override
    {
        int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE) return false;

        string data = "";
        while(!FileIsEnding(handle))
            data += FileReadString(handle) + "\n";
        FileClose(handle);

        return Deserialize(data, format, out);
    }

private:
    string SerializeINI(const AtlasConfiguration &c) const
    {
        string out = "";
        out += "[General]\n";
        AppendKV(out, "version", c.version);
        AppendKV(out, "profile_code", c.profile_code);
        AppendKV(out, "profile_name", c.profile_name);

        out += "\n[Trading]\n";
        AppendKV(out, "magic_number", c.core.magic_number);
        AppendKV(out, "symbol", c.core.symbol);
        AppendKV(out, "base_volume", c.core.base_volume);
        AppendKV(out, "trading_enabled", c.trading_enabled ? "1" : "0");
        AppendKV(out, "max_concurrent_trades", c.max_concurrent_trades);

        out += "\n[Risk]\n";
        AppendKV(out, "max_daily_drawdown_pct", c.core.max_daily_drawdown_pct);
        AppendKV(out, "max_exposure_limit", c.core.max_exposure_limit);
        AppendKV(out, "max_floating_loss", c.max_floating_loss);
        AppendKV(out, "loss_streak_cooldown_sec", c.loss_streak_cooldown_sec);
        AppendKV(out, "min_rr_ratio", c.min_rr_ratio);
        AppendKV(out, "mandatory_stop_loss", c.mandatory_stop_loss ? "1" : "0");

        out += "\n[Broker]\n";
        AppendKV(out, "max_retries", c.core.max_retries);
        AppendKV(out, "retry_delay_ms", c.core.retry_delay_ms);
        AppendKV(out, "broker_max_slippage_points", c.broker_max_slippage_points);
        AppendKV(out, "broker_auto_reconnect", c.broker_auto_reconnect ? "1" : "0");

        out += "\n[Execution]\n";
        AppendKV(out, "execution_timeout_ms", c.execution_timeout_ms);
        AppendKV(out, "execution_require_idempotency", c.execution_require_idempotency ? "1" : "0");

        out += "\n[Logging]\n";
        AppendKV(out, "log_level", c.core.log_level);
        AppendKV(out, "log_to_file", c.log_to_file ? "1" : "0");
        AppendKV(out, "log_file_path", c.log_file_path);
        AppendKV(out, "log_ring_buffer_size", c.log_ring_buffer_size);

        out += "\n[Persistence]\n";
        AppendKV(out, "snapshot_interval_sec", c.core.snapshot_interval_sec);
        AppendKV(out, "persistence_flush_interval_sec", c.persistence_flush_interval_sec);
        AppendKV(out, "persistence_retention_days", c.persistence_retention_days);

        out += "\n[Recovery]\n";
        AppendKV(out, "recovery_auto_safe_mode", c.recovery_auto_safe_mode ? "1" : "0");
        AppendKV(out, "recovery_max_attempts", c.recovery_max_attempts);

        out += "\n[Performance]\n";
        AppendKV(out, "max_ms_per_tick", (long)c.core.max_ms_per_tick);
        AppendKV(out, "max_events_per_tick", c.core.max_events_per_tick);
        AppendKV(out, "perf_profiler_enabled", c.perf_profiler_enabled ? "1" : "0");
        AppendKV(out, "perf_latency_monitor_enabled", c.perf_latency_monitor_enabled ? "1" : "0");
        AppendKV(out, "perf_sample_window", c.perf_sample_window);

        out += "\n[Plugins]\n";
        AppendKV(out, "plugins_enabled", c.plugins_enabled ? "1" : "0");
        AppendKV(out, "plugins_max_count", c.plugins_max_count);
        AppendKV(out, "plugins_auto_load", c.plugins_auto_load ? "1" : "0");

        return out;
    }

    string SerializeJSON(const AtlasConfiguration &c) const
    {
        string out = "{\n";
        out += "  \"version\": " + IntegerToString(c.version) + ",\n";
        out += "  \"profile\": \"" + c.profile_name + "\",\n";
        out += "  \"trading\": {\n";
        out += "    \"magic\": " + IntegerToString(c.core.magic_number) + ",\n";
        out += "    \"symbol\": \"" + c.core.symbol + "\",\n";
        out += "    \"volume\": " + DoubleToString(c.core.base_volume, 2) + "\n";
        out += "  },\n";
        out += "  \"risk\": {\n";
        out += "    \"max_dd\": " + DoubleToString(c.core.max_daily_drawdown_pct, 1) + ",\n";
        out += "    \"max_exposure\": " + DoubleToString(c.core.max_exposure_limit, 2) + "\n";
        out += "  },\n";
        out += "  \"performance\": {\n";
        out += "    \"max_ms_per_tick\": " + IntegerToString((long)c.core.max_ms_per_tick) + ",\n";
        out += "    \"max_events_per_tick\": " + IntegerToString(c.core.max_events_per_tick) + "\n";
        out += "  }\n";
        out += "}\n";
        return out;
    }

    string SerializeBinary(const AtlasConfiguration &c) const
    {
        //--- Compact format: no section headers, no whitespace
        string out = "";
        AppendKV(out, "v", c.version);
        AppendKV(out, "p", c.profile_code);
        AppendKV(out, "m", c.core.magic_number);
        AppendKV(out, "s", c.core.symbol);
        AppendKV(out, "vol", c.core.base_volume);
        AppendKV(out, "dd", c.core.max_daily_drawdown_pct);
        AppendKV(out, "exp", c.core.max_exposure_limit);
        AppendKV(out, "ms", (long)c.core.max_ms_per_tick);
        AppendKV(out, "ev", c.core.max_events_per_tick);
        AppendKV(out, "ll", c.core.log_level);
        return out;
    }

    string SerializeMemory(const AtlasConfiguration &c) const
    {
        return "v=" + IntegerToString(c.version) +
               " p=" + c.profile_name +
               " m=" + IntegerToString(c.core.magic_number) +
               " vol=" + DoubleToString(c.core.base_volume, 2) +
               " dd=" + DoubleToString(c.core.max_daily_drawdown_pct, 1);
    }

    /// @brief Apply a key-value pair to a config struct.
    void ApplyKeyValue(AtlasConfiguration &out, const string key, const string val) const
    {
        if(key == "version")              out.version = (int)StringToInteger(val);
        else if(key == "profile_code")    out.profile_code = (int)StringToInteger(val);
        else if(key == "profile_name")    out.profile_name = val;
        else if(key == "magic_number" || key == "m") out.core.magic_number = StringToInteger(val);
        else if(key == "symbol" || key == "s")       out.core.symbol = val;
        else if(key == "base_volume" || key == "vol") out.core.base_volume = StringToDouble(val);
        else if(key == "max_daily_drawdown_pct" || key == "dd") out.core.max_daily_drawdown_pct = StringToDouble(val);
        else if(key == "max_exposure_limit" || key == "exp") out.core.max_exposure_limit = StringToDouble(val);
        else if(key == "max_ms_per_tick" || key == "ms") out.core.max_ms_per_tick = (ulong)StringToInteger(val);
        else if(key == "max_events_per_tick" || key == "ev") out.core.max_events_per_tick = (int)StringToInteger(val);
        else if(key == "log_level" || key == "ll") out.core.log_level = (int)StringToInteger(val);
        else if(key == "trading_enabled") out.trading_enabled = (val == "1" || val == "true");
        else if(key == "plugins_enabled") out.plugins_enabled = (val == "1" || val == "true");
    }
};

#endif // ATLAS_CONFIGURATION_SERIALIZER_MQH
//+------------------------------------------------------------------+
