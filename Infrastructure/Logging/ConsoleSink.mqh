//+------------------------------------------------------------------+
//|            Infrastructure/Logging/ConsoleSink.mqh               |
//|       AtlasEA v0.1.14.0 - Console Log Sink (Print)               |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONSOLE_SINK_MQH
#define ATLAS_CONSOLE_SINK_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogSink.mqh"

/**
 * @class ConsoleSink
 * @brief Writes log entries to the MT5 terminal console via Print().
 *
 * This is the default sink. Every Logger has a ConsoleSink unless
 * explicitly removed.
 *
 * Performance: Print() is synchronous and relatively slow. In the hot
 * path, log level filtering in the Logger prevents most calls from
 * reaching the sink.
 */
class ConsoleSink : public ILogSink
{
private:
    string m_name;

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
     */
    ConsoleSink(void) { m_name = "ConsoleSink"; }

    virtual void Write(const LogEntry &entry) override
    {
        string ts = TimeToString(entry.timestamp, TIME_DATE | TIME_SECONDS);
        Print("[", ts, "] [", LevelToString(entry.level), "] [", entry.module, "] ", entry.message);
    }

    virtual void Flush(void) override { /* Console is unbuffered */ }

    virtual string GetName(void) const override { return m_name; }
};

#endif // ATLAS_CONSOLE_SINK_MQH
//+------------------------------------------------------------------+
