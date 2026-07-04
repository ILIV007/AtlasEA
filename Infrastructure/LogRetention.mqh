//+------------------------------------------------------------------+
//|                    Infrastructure/LogRetention.mqh              |
//|       AtlasEA v0.1.24.5 - Log File Retention Manager             |
//+------------------------------------------------------------------+
#ifndef ATLAS_LOG_RETENTION_MQH
#define ATLAS_LOG_RETENTION_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class LogRetention
 * @brief Manages log file retention by deleting old files on startup.
 *
 * Scans the MQL5/Files/ directory for AtlasEA_*.log files
 * older than the retention period and deletes them.
 *
 * Default retention: 30 days.
 * Non-recursive: only scans the top-level directory.
 */
class LogRetention
{
private:
    ILogger *m_logger;
    int      m_retention_days;
    string   m_prefix;

public:
    /**
     * @brief Constructor.
     */
    LogRetention(void)
    {
        m_logger         = NULL;
        m_retention_days = 30;
        m_prefix         = "AtlasEA_";
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the retention period in days.
     */
    void SetRetentionDays(const int days)
    {
        m_retention_days = (days > 0) ? days : 30;
    }

    /**
     * @brief Set the file prefix to scan for.
     */
    void SetPrefix(const string prefix) { m_prefix = prefix; }

    /**
     * @brief Delete log files older than the retention period.
     * Call on startup (OnInit), NOT on the hot path.
     * @return Number of files deleted.
     */
    int CleanupOldLogs(void)
    {
        if(m_retention_days <= 0) return 0;

        int deleted = 0;
        datetime cutoff = TimeCurrent() - (datetime)(m_retention_days * 86400);

        //--- MQL5 FileFind API
        string filename;
        ulong file_handle = FileFindFirst(m_prefix + "*.log", filename);

        if(file_handle == INVALID_HANDLE)
        {
            if(m_logger != NULL)
                m_logger.Debug("LogRetention", "No log files found to clean up");
            return 0;
        }

        do
        {
            //--- Check file age via FileFind
            //--- MQL5 doesn't expose file modification time directly via FileFind
            //--- Parse date from filename: AtlasEA_EURUSD_20250701.log
            //--- Extract YYYYMMDD from the filename
            int date_start = StringFind(filename, "_", StringLen(m_prefix)) + 1;
            if(date_start > 0 && StringLen(filename) >= date_start + 8)
            {
                string date_str = StringSubstr(filename, date_start, 8);
                int year = (int)StringToInteger(StringSubstr(date_str, 0, 4));
                int mon  = (int)StringToInteger(StringSubstr(date_str, 4, 2));
                int day  = (int)StringToInteger(StringSubstr(date_str, 6, 2));

                if(year >= 2020 && mon >= 1 && mon <= 12 && day >= 1 && day <= 31)
                {
                    MqlDateTime dt;
                    ZeroMemory(dt);
                    dt.year = year;
                    dt.mon  = mon;
                    dt.day  = day;
                    datetime file_date = StructToTime(dt);

                    if(file_date < cutoff)
                    {
                        if(FileDelete(filename))
                        {
                            deleted++;
                            if(m_logger != NULL)
                                m_logger.Info("LogRetention", "Deleted old log: " + filename);
                        }
                    }
                }
            }
        }
        while(FileFindNext(file_handle, filename));

        FileFindClose(file_handle);

        if(m_logger != NULL && deleted > 0)
            m_logger.Info("LogRetention",
                "Cleaned up " + IntegerToString(deleted) + " log files older than " +
                IntegerToString(m_retention_days) + " days");

        return deleted;
    }
};

#endif // ATLAS_LOG_RETENTION_MQH
//+------------------------------------------------------------------+
