//+------------------------------------------------------------------+
//|            Infrastructure/Logging/FileSink.mqh                  |
//|       AtlasEA v0.1.14.0 - File Log Sink                           |
//+------------------------------------------------------------------+
#ifndef ATLAS_FILE_SINK_MQH
#define ATLAS_FILE_SINK_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogSink.mqh"

/**
 * @brief Maximum lines buffered before flushing to file.
 */
#define ATLAS_FILE_SINK_BUFFER 64

/**
 * @class FileSink
 * @brief Writes log entries to a file in MQL5/Files/.
 *
 * Buffers entries and flushes periodically to avoid file I/O on every
 * log call. Flushes automatically when the buffer is full or on
 * explicit Flush().
 *
 * File naming: AtlasEA_{symbol}_{YYYYMMDD}.log
 */
class FileSink : public ILogSink
{
private:
    string   m_filename;
    string   m_buffer[ATLAS_FILE_SINK_BUFFER];
    int      m_buffer_count;
    bool     m_initialized;
    string   m_name;

    /// @brief Convert level to string prefix.
    string LevelToString(const int level) const
    {
        switch(level)
        {
            case ATLAS_LOG_TRACE: return "TRACE";
            case ATLAS_LOG_DEBUG: return "DEBUG";
            case ATLAS_LOG_INFO:  return "INFO ";
            case ATLAS_LOG_WARN:  return "WARN ";
            case ATLAS_LOG_ERROR: return "ERROR";
            case ATLAS_LOG_FATAL: return "FATAL";
        }
        return "?????";
    }

public:
    /**
     * @brief Constructor.
     * @param filename The file path (relative to MQL5/Files/).
     */
    FileSink(const string filename = "")
    {
        m_filename     = (StringLen(filename) > 0) ? filename : "AtlasEA.log";
        m_buffer_count = 0;
        m_initialized  = false;
        m_name         = "FileSink";
    }

    /**
     * @brief Destructor — flushes any buffered entries to file.
     *
     * Without this, log entries buffered but not yet flushed would be
     * lost when the FileSink is destroyed (e.g. during shutdown if
     * FlushAll() was not called explicitly).
     */
    ~FileSink(void) { Flush(); }

    /**
     * @brief Set the filename.
     */
    void SetFilename(const string filename)
    {
        Flush();
        m_filename = filename;
        m_initialized = false;
    }

    virtual void Write(const LogEntry &entry) override
    {
        //--- Format the entry
        string ts = TimeToString(entry.timestamp, TIME_DATE | TIME_SECONDS);
        string line = "[" + ts + "] [" + LevelToString(entry.level) + "] [" +
                      entry.module + "] " + entry.message;

        //--- Buffer the line
        if(m_buffer_count < ATLAS_FILE_SINK_BUFFER)
        {
            m_buffer[m_buffer_count] = line;
            m_buffer_count++;
        }

        //--- Auto-flush if buffer full
        if(m_buffer_count >= ATLAS_FILE_SINK_BUFFER)
            Flush();
    }

    virtual void Flush(void) override
    {
        if(m_buffer_count == 0) return;

        int handle = FileOpen(m_filename, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            //--- Try write-only if read fails (file doesn't exist yet)
            handle = FileOpen(m_filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
            if(handle == INVALID_HANDLE)
                return;
        }

        //--- Seek to end for append
        FileSeek(handle, 0, SEEK_END);

        //--- Write buffered lines
        for(int i = 0; i < m_buffer_count; i++)
        {
            FileWriteString(handle, m_buffer[i] + "\n");
        }

        FileClose(handle);

        //--- Clear buffer
        m_buffer_count = 0;
        m_initialized  = true;
    }

    virtual string GetName(void) const override { return m_name; }
};

#endif // ATLAS_FILE_SINK_MQH
//+------------------------------------------------------------------+
