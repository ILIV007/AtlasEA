//+------------------------------------------------------------------+
//|                    Diagnostics/MetricsExporter.mqh              |
//|       AtlasEA v0.1.14.0 - Metrics Export (Snapshot-Based)       |
//+------------------------------------------------------------------+
#ifndef ATLAS_METRICS_EXPORTER_MQH
#define ATLAS_METRICS_EXPORTER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IMetricsExporter.mqh"
#include "../Interfaces/IMetricsSnapshot.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Export format codes (expanded).
 */
#define ATLAS_EXPORT_CSV      0
#define ATLAS_EXPORT_BINARY   1
#define ATLAS_EXPORT_MEMORY   2
#define ATLAS_EXPORT_JSON     3   ///< NEW in v0.1.14.0

/**
 * @class MetricsExporter
 * @brief Exports an immutable MetricsSnapshot to various formats.
 *
 * The exporter receives a MetricsSnapshot (captured by the provider)
 * and formats it. It does NOT know about individual monitoring
 * interfaces — only the snapshot struct.
 *
 * Uses the Strategy pattern for format selection. New formats can be
 * added by extending the Export() switch.
 */
class MetricsExporter : public IMetricsExporter
{
private:
    ILogger *m_logger;

    /// @brief Helper: append key=value line.
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

    /// @brief Helper: append JSON key-value pair.
    void AppendJSON(string &buf, const string key, const string val, const bool last) const
    {
        buf += "  \"" + key + "\": \"" + val + "\"" + (last ? "" : ",") + "\n";
    }
    void AppendJSON(string &buf, const string key, const long val, const bool last) const
    {
        buf += "  \"" + key + "\": " + IntegerToString(val) + (last ? "" : ",") + "\n";
    }
    void AppendJSON(string &buf, const string key, const double val, const bool last) const
    {
        buf += "  \"" + key + "\": " + DoubleToString(val, 6) + (last ? "" : ",") + "\n";
    }

public:
    /**
     * @brief Constructor.
     */
    MetricsExporter(void) { m_logger = NULL; }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Export a snapshot in the specified format.
     * @param snapshot The immutable metrics snapshot.
     * @param format ATLAS_EXPORT_CSV/BINARY/MEMORY/JSON.
     * @param out_buffer Output: formatted string.
     * @return true if export succeeded.
     */
    bool ExportSnapshot(const MetricsSnapshot &snapshot, const int format, string &out_buffer)
    {
        switch(format)
        {
            case ATLAS_EXPORT_CSV:    return ExportCSV(snapshot, out_buffer);
            case ATLAS_EXPORT_BINARY: return ExportCSV(snapshot, out_buffer); // Binary = compact CSV for now
            case ATLAS_EXPORT_MEMORY: return ExportMemory(snapshot, out_buffer);
            case ATLAS_EXPORT_JSON:   return ExportJSON(snapshot, out_buffer);
            default: return false;
        }
    }

    //=== IMetricsExporter (backward compatible — uses empty snapshot) ===

    virtual bool Export(const int format, string &out_buffer) override
    {
        //--- Backward compat: create an empty snapshot
        MetricsSnapshot empty;
        ZeroMemory(empty);
        return ExportSnapshot(empty, format, out_buffer);
    }

    virtual bool ExportToFile(const int format, const string filename) override
    {
        //--- Backward compat — requires a snapshot via the new API
        if(m_logger != NULL)
            m_logger.Warn("MetricsExporter", "ExportToFile requires a snapshot — use ExportSnapshotToFile()");
        return false;
    }

    /**
     * @brief Export a snapshot to a file.
     */
    bool ExportSnapshotToFile(const MetricsSnapshot &snapshot, const int format, const string filename)
    {
        string buffer;
        if(!ExportSnapshot(snapshot, format, buffer)) return false;

        int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            if(m_logger != NULL)
                m_logger.Error("MetricsExporter", "Cannot open file: " + filename);
            return false;
        }

        FileWriteString(handle, buffer);
        FileClose(handle);
        return true;
    }

private:

    bool ExportCSV(const MetricsSnapshot &snap, string &out) const
    {
        out = "";
        out += "=== AtlasEA Metrics Export ===\n";
        out += "timestamp=" + IntegerToString((long)snap.timestamp) + "\n";

        //--- Phases
        string phase_names[ATLAS_PHASE_COUNT] = {
            "Market", "Strategy", "Risk", "Execution",
            "Persistence", "Broker", "Dispatch", "Queue"
        };
        for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
        {
            AppendKV(out, "perf." + phase_names[i] + ".count", (long)snap.phases[i].count);
            AppendKV(out, "perf." + phase_names[i] + ".total_us", (long)snap.phases[i].total_microseconds);
            AppendKV(out, "perf." + phase_names[i] + ".min_us", (long)snap.phases[i].min_microseconds);
            AppendKV(out, "perf." + phase_names[i] + ".max_us", (long)snap.phases[i].max_microseconds);
        }

        //--- Latencies
        string lat_names[ATLAS_LATENCY_COUNT] = {
            "Tick", "Pipeline", "Order", "Broker",
            "TradeFill", "Persistence", "Recovery"
        };
        for(int i = 0; i < ATLAS_LATENCY_COUNT; i++)
        {
            AppendKV(out, "latency." + lat_names[i] + ".count", (long)snap.latencies[i].count);
            AppendKV(out, "latency." + lat_names[i] + ".avg_ms", snap.latencies[i].avg_ms);
            AppendKV(out, "latency." + lat_names[i] + ".p95_ms", snap.latencies[i].p95_ms);
            AppendKV(out, "latency." + lat_names[i] + ".p99_ms", snap.latencies[i].p99_ms);
        }

        //--- Memory
        AppendKV(out, "memory.current_mb", (long)snap.memory.current_memory_mb);
        AppendKV(out, "memory.peak_mb", (long)snap.memory.peak_memory_mb);
        AppendKV(out, "memory.growth_pct", snap.memory.memory_growth_pct);

        //--- Events
        AppendKV(out, "events.generated", (long)snap.events.events_generated);
        AppendKV(out, "events.processed", (long)snap.events.events_processed);
        AppendKV(out, "events.dropped", (long)snap.events.events_dropped);

        //--- Queues
        for(int i = 0; i < ATLAS_QUEUE_COUNT; i++)
        {
            string qn = (i == 0) ? "Normal" : "Priority";
            AppendKV(out, "queue." + qn + ".current", (long)snap.queues[i].current_count);
            AppendKV(out, "queue." + qn + ".peak", (long)snap.queues[i].peak_count);
        }

        return true;
    }

    bool ExportJSON(const MetricsSnapshot &snap, string &out) const
    {
        out = "{\n";
        AppendJSON(out, "timestamp", (long)snap.timestamp, false);

        //--- Phases
        out += "  \"phases\": {\n";
        string phase_names[ATLAS_PHASE_COUNT] = {
            "Market", "Strategy", "Risk", "Execution",
            "Persistence", "Broker", "Dispatch", "Queue"
        };
        for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
        {
            out += "    \"" + phase_names[i] + "\": {";
            out += "\"count\":" + IntegerToString((long)snap.phases[i].count);
            out += ",\"avg_us\":" + IntegerToString((long)(snap.phases[i].count > 0 ? snap.phases[i].total_microseconds / snap.phases[i].count : 0));
            out += ",\"max_us\":" + IntegerToString((long)snap.phases[i].max_microseconds);
            out += "}" + (i < ATLAS_PHASE_COUNT - 1 ? "," : "") + "\n";
        }
        out += "  },\n";

        //--- Latencies
        out += "  \"latencies\": {\n";
        string lat_names[ATLAS_LATENCY_COUNT] = {
            "Tick", "Pipeline", "Order", "Broker",
            "TradeFill", "Persistence", "Recovery"
        };
        for(int i = 0; i < ATLAS_LATENCY_COUNT; i++)
        {
            out += "    \"" + lat_names[i] + "\": {";
            out += "\"avg_ms\":" + DoubleToString(snap.latencies[i].avg_ms, 3);
            out += ",\"p95_ms\":" + DoubleToString(snap.latencies[i].p95_ms, 3);
            out += ",\"p99_ms\":" + DoubleToString(snap.latencies[i].p99_ms, 3);
            out += "}" + (i < ATLAS_LATENCY_COUNT - 1 ? "," : "") + "\n";
        }
        out += "  },\n";

        //--- Memory
        out += "  \"memory\": {";
        out += "\"current_mb\":" + IntegerToString((long)snap.memory.current_memory_mb);
        out += ",\"peak_mb\":" + IntegerToString((long)snap.memory.peak_memory_mb);
        out += ",\"growth_pct\":" + DoubleToString(snap.memory.memory_growth_pct, 2);
        out += "},\n";

        //--- Events
        out += "  \"events\": {";
        out += "\"generated\":" + IntegerToString((long)snap.events.events_generated);
        out += ",\"processed\":" + IntegerToString((long)snap.events.events_processed);
        out += ",\"dropped\":" + IntegerToString((long)snap.events.events_dropped);
        out += "}\n";

        out += "}\n";
        return true;
    }

    bool ExportMemory(const MetricsSnapshot &snap, string &out) const
    {
        out = "";
        out += "ts=" + IntegerToString((long)snap.timestamp);
        out += " mem=" + IntegerToString((long)snap.memory.current_memory_mb) + "MB";
        out += " peak=" + IntegerToString((long)snap.memory.peak_memory_mb) + "MB";
        out += " gen=" + IntegerToString((long)snap.events.events_generated);
        out += " drop=" + IntegerToString((long)snap.events.events_dropped);
        return true;
    }
};

#endif // ATLAS_METRICS_EXPORTER_MQH
//+------------------------------------------------------------------+
