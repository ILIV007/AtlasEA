//+------------------------------------------------------------------+
//|                      Audit/AuditManager.mqh                     |
//|       AtlasEA v0.1.19.0 - Audit Manager Implementation          |
//+------------------------------------------------------------------+
#ifndef ATLAS_AUDIT_MANAGER_MQH
#define ATLAS_AUDIT_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IAuditManager.mqh"
#include "../Interfaces/ILogger.mqh"
#include "AuditTrail.mqh"
#include "AuditFilter.mqh"
#include "AuditExporter.mqh"

/**
 * @class AuditManager
 * @brief Concrete implementation of IAuditManager.
 *
 * Uses an AuditTrail (ring buffer) as the backing store.
 * Supports filtering and export.
 *
 * Tracks 12 categories of audit events:
 *   Risk decisions, Strategy votes, Order requests, Broker responses,
 *   Executions, Position changes, Recovery actions, Config changes,
 *   Plugin load/unload, Kill switch, System.
 */
class AuditManager : public IAuditManager
{
private:
    ILogger      *m_logger;
    AuditTrail    m_trail;
    AuditFilter   m_filter;
    AuditExporter m_exporter;
    ulong         m_total_recorded;
    ulong         m_total_filtered;

public:
    /**
     * @brief Constructor.
     */
    AuditManager(void)
    {
        m_logger          = NULL;
        m_total_recorded  = 0;
        m_total_filtered  = 0;
    }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_exporter.SetLogger(logger);
    }

    //=== IAuditManager implementation ===

    virtual bool Record(const AuditEntry &entry) override
    {
        //--- Apply filter
        if(!m_filter.Passes(entry))
        {
            m_total_filtered++;
            return false;
        }

        m_trail.Append(entry);
        m_total_recorded++;
        return true;
    }

    virtual long Count(void) const override
    {
        return (long)m_trail.Count();
    }

    virtual bool GetEntry(const int index, AuditEntry &out) const override
    {
        return m_trail.ReadByIndex(index, out);
    }

    virtual int FindByCategory(const int category,
                                AuditEntry out_entries[], const int max_count) const override
    {
        return m_trail.FindByCategory(category, out_entries, max_count);
    }

    virtual int FindByCorrelation(const string correlation_id,
                                   AuditEntry out_entries[], const int max_count) const override
    {
        return m_trail.FindByCorrelation(correlation_id, out_entries, max_count);
    }

    virtual void Clear(void) override
    {
        m_trail.Clear();
        m_total_recorded = 0;
        m_total_filtered = 0;
    }

    //=== Extended API ===

    /**
     * @brief Get the filter (for rule configuration).
     */
    AuditFilter& GetFilter(void) { return m_filter; }

    /**
     * @brief Get the exporter.
     */
    AuditExporter& GetExporter(void) { return m_exporter; }

    /**
     * @brief Export all entries in the specified format.
     */
    string ExportAll(const int format) const
    {
        int count = m_trail.Count();
        if(count == 0) return "";

        AuditEntry entries[ATLAS_AUDIT_CAPACITY];
        int actual = 0;
        for(int i = 0; i < count; i++)
        {
            if(m_trail.ReadByIndex(i, entries[actual]))
                actual++;
        }

        return m_exporter.Export(entries, actual, format);
    }

    /**
     * @brief Export to file.
     */
    bool ExportAllToFile(const int format, const string filename) const
    {
        string data = ExportAll(format);
        if(data == "") return false;

        int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE) return false;
        FileWriteString(handle, data);
        FileClose(handle);
        return true;
    }

    /// @brief Total entries recorded (including evicted).
    ulong TotalRecorded(void) const { return m_total_recorded; }

    /// @brief Total entries filtered out.
    ulong TotalFiltered(void) const { return m_total_filtered; }
};

#endif // ATLAS_AUDIT_MANAGER_MQH
//+------------------------------------------------------------------+
