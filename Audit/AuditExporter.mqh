//+------------------------------------------------------------------+
//|                      Audit/AuditExporter.mqh                    |
//|       AtlasEA v0.1.19.0 - Audit Exporter                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_AUDIT_EXPORTER_MQH
#define ATLAS_AUDIT_EXPORTER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IAuditExporter.mqh"
#include "../Interfaces/IAuditManager.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class AuditExporter
 * @brief Concrete implementation of IAuditExporter.
 *
 * Exports audit entries in 4 formats:
 *   - CSV (human-readable)
 *   - Binary (compact)
 *   - JSON-like (structured)
 *   - Memory (single-line summary)
 */
class AuditExporter : public IAuditExporter
{
private:
    ILogger *m_logger;

    /// @brief Convert category to string.
    string CategoryToString(const int category) const
    {
        switch(category)
        {
            case ATLAS_AUDIT_RISK_DECISION:   return "RISK_DECISION";
            case ATLAS_AUDIT_STRATEGY_VOTE:   return "STRATEGY_VOTE";
            case ATLAS_AUDIT_ORDER_REQUEST:   return "ORDER_REQUEST";
            case ATLAS_AUDIT_BROKER_RESPONSE: return "BROKER_RESPONSE";
            case ATLAS_AUDIT_EXECUTION:       return "EXECUTION";
            case ATLAS_AUDIT_POSITION_CHANGE: return "POSITION_CHANGE";
            case ATLAS_AUDIT_RECOVERY_ACTION: return "RECOVERY_ACTION";
            case ATLAS_AUDIT_CONFIG_CHANGE:   return "CONFIG_CHANGE";
            case ATLAS_AUDIT_PLUGIN_LOAD:     return "PLUGIN_LOAD";
            case ATLAS_AUDIT_PLUGIN_UNLOAD:   return "PLUGIN_UNLOAD";
            case ATLAS_AUDIT_KILL_SWITCH:     return "KILL_SWITCH";
            case ATLAS_AUDIT_SYSTEM:          return "SYSTEM";
        }
        return "UNKNOWN";
    }

public:
    AuditExporter(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    virtual string Export(const AuditEntry entries[], const int count,
                           const int format) const override
    {
        switch(format)
        {
            case ATLAS_AUDIT_EXPORT_CSV:    return ExportCSV(entries, count);
            case ATLAS_AUDIT_EXPORT_BINARY: return ExportBinary(entries, count);
            case ATLAS_AUDIT_EXPORT_JSON:   return ExportJSON(entries, count);
            case ATLAS_AUDIT_EXPORT_MEMORY: return ExportMemory(entries, count);
            default: return "";
        }
    }

    virtual bool ExportToFile(const AuditEntry entries[], const int count,
                               const int format, const string filename) const override
    {
        string data = Export(entries, count, format);
        if(data == "") return false;

        int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            if(m_logger != NULL)
                m_logger.Error("AuditExporter", "Cannot open: " + filename);
            return false;
        }
        FileWriteString(handle, data);
        FileClose(handle);

        if(m_logger != NULL)
            m_logger.Info("AuditExporter", "Exported " + IntegerToString(count) +
                          " entries to " + filename);
        return true;
    }

private:
    string ExportCSV(const AuditEntry entries[], const int count) const
    {
        string out = "category,timestamp,actor,action,target,snapshot_id,correlation_id,details\n";
        for(int i = 0; i < count; i++)
        {
            out += CategoryToString(entries[i].category) + "," +
                   IntegerToString((long)entries[i].timestamp) + "," +
                   entries[i].actor + "," +
                   entries[i].action + "," +
                   entries[i].target + "," +
                   IntegerToString(entries[i].snapshot_id) + "," +
                   entries[i].correlation_id + "," +
                   entries[i].details + "\n";
        }
        return out;
    }

    string ExportBinary(const AuditEntry entries[], const int count) const
    {
        string out = "";
        for(int i = 0; i < count; i++)
        {
            out += IntegerToString(entries[i].category) + "|" +
                   IntegerToString((long)entries[i].timestamp) + "|" +
                   entries[i].actor + "|" +
                   entries[i].action + "|" +
                   entries[i].target + "|" +
                   IntegerToString(entries[i].snapshot_id) + "\n";
        }
        return out;
    }

    string ExportJSON(const AuditEntry entries[], const int count) const
    {
        string out = "[\n";
        for(int i = 0; i < count; i++)
        {
            out += "  {";
            out += "\"category\":\"" + CategoryToString(entries[i].category) + "\"";
            out += ",\"ts\":" + IntegerToString((long)entries[i].timestamp);
            out += ",\"actor\":\"" + entries[i].actor + "\"";
            out += ",\"action\":\"" + entries[i].action + "\"";
            out += ",\"target\":\"" + entries[i].target + "\"";
            out += ",\"snap\":" + IntegerToString(entries[i].snapshot_id);
            out += "}";
            if(i < count - 1) out += ",";
            out += "\n";
        }
        out += "]\n";
        return out;
    }

    string ExportMemory(const AuditEntry entries[], const int count) const
    {
        if(count == 0) return "empty";
        return "count=" + IntegerToString(count) +
               " first=" + CategoryToString(entries[0].category) +
               " last=" + CategoryToString(entries[count-1].category);
    }
};

#endif // ATLAS_AUDIT_EXPORTER_MQH
//+------------------------------------------------------------------+
