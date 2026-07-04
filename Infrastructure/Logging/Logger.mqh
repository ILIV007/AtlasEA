//+------------------------------------------------------------------+
//|                Infrastructure/Logging/Logger.mqh                |
//|       AtlasEA v0.1.14.0 - Production Logger (Sink-Based)        |
//+------------------------------------------------------------------+
#ifndef ATLAS_LOGGER_MQH
#define ATLAS_LOGGER_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/ILogSink.mqh"
#include "ConsoleSink.mqh"
#include "MemoryRingSink.mqh"
#include "FileSink.mqh"

/**
 * @brief Maximum number of sinks per Logger.
 */
#define ATLAS_MAX_SINKS 4

/**
 * @class Logger
 * @brief Production logger with level filtering and pluggable sinks.
 *
 * Features:
 *   - 6 log levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL
 *   - Level filtering: messages below the configured level are discarded
 *   - Pluggable sinks: dispatches each entry to all registered sinks
 *   - Default: ConsoleSink (always present unless removed)
 *   - Optional: MemoryRingSink, FileSink, future custom sinks
 *
 * Thread model: single-threaded (MQL5). Sinks called synchronously.
 *
 * Memory: ~2 KB (sink pointers + counters). Sinks own their memory.
 */
class Logger : public ILogger
{
private:
    ILogSink *m_sinks[ATLAS_MAX_SINKS];
    int       m_sink_count;
    int       m_level;          ///< Minimum level to log (TRACE=0 .. FATAL=5)

    //--- Default sinks (owned by this Logger)
    ConsoleSink     m_default_console;
    MemoryRingSink  m_default_ring;

    //--- Per-level counters
    ulong m_trace_count;
    ulong m_debug_count;
    ulong m_info_count;
    ulong m_warn_count;
    ulong m_error_count;
    ulong m_fatal_count;

    /// @brief Internal log dispatch.
    void Dispatch(const int level, const string module, const string message)
    {
        if(level < m_level) return;

        //--- Increment per-level counter
        switch(level)
        {
            case ATLAS_LOG_TRACE: m_trace_count++; break;
            case ATLAS_LOG_DEBUG: m_debug_count++; break;
            case ATLAS_LOG_INFO:  m_info_count++;  break;
            case ATLAS_LOG_WARN:  m_warn_count++;  break;
            case ATLAS_LOG_ERROR: m_error_count++; break;
            case ATLAS_LOG_FATAL: m_fatal_count++; break;
        }

        //--- Build the entry
        LogEntry entry;
        entry.level     = level;
        entry.timestamp = TimeCurrent();
        entry.module    = module;
        entry.message   = message;

        //--- Dispatch to all sinks
        for(int i = 0; i < m_sink_count; i++)
        {
            if(m_sinks[i] != NULL)
                m_sinks[i].Write(entry);
        }
    }

public:
    /**
     * @brief Constructor.
     * @param level Minimum log level (default: ATLAS_LOG_INFO).
     */
    Logger(const int level = ATLAS_LOG_INFO)
    {
        m_sink_count   = 0;
        m_level        = level;
        m_trace_count  = 0;
        m_debug_count  = 0;
        m_info_count   = 0;
        m_warn_count   = 0;
        m_error_count  = 0;
        m_fatal_count  = 0;

        //--- Explicitly NULL all sink slots (defensive — MQL5 does not
        //    guarantee zero-initialization of pointer array members)
        for(int i = 0; i < ATLAS_MAX_SINKS; i++)
            m_sinks[i] = NULL;

        //--- Register default sinks: Console + MemoryRing
        m_sinks[0] = &m_default_console;
        m_sinks[1] = &m_default_ring;
        m_sink_count = 2;
    }

    /**
     * @brief Destructor — flushes all sinks before destruction.
     *
     * Ensures no buffered log entries are lost when the Logger is
     * destroyed. The FileSink destructor will also flush, but calling
     * FlushAll() here covers all registered sinks (including custom
     * ones added via AddSink) in the correct order.
     */
    ~Logger(void) { FlushAll(); }

    //=== ILogger implementation ===

    virtual void Log(const int level, const string module, const string message) override
    {
        Dispatch(level, module, message);
    }

    virtual void Trace(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_TRACE, module, message);
    }

    virtual void Debug(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_DEBUG, module, message);
    }

    virtual void Info(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_INFO, module, message);
    }

    virtual void Warn(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_WARN, module, message);
    }

    virtual void Error(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_ERROR, module, message);
    }

    virtual void Fatal(const string module, const string message) override
    {
        Dispatch(ATLAS_LOG_FATAL, module, message);
    }

    //=== Sink Management ===

    /**
     * @brief Add a custom sink. The Logger does NOT own the sink
     * (caller manages lifetime).
     * @param sink Pointer to the sink.
     * @return true if added, false if max sinks reached.
     */
    bool AddSink(ILogSink *sink)
    {
        if(sink == NULL) return false;
        if(m_sink_count >= ATLAS_MAX_SINKS) return false;
        m_sinks[m_sink_count] = sink;
        m_sink_count++;
        return true;
    }

    /**
     * @brief Remove a sink by pointer.
     * Does NOT delete the sink (caller owns lifetime).
     */
    bool RemoveSink(ILogSink *sink)
    {
        for(int i = 0; i < m_sink_count; i++)
        {
            if(m_sinks[i] == sink)
            {
                //--- Shift remaining left
                for(int j = i + 1; j < m_sink_count; j++)
                    m_sinks[j-1] = m_sinks[j];
                m_sink_count--;
                m_sinks[m_sink_count] = NULL;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Flush all sinks.
     */
    void FlushAll(void)
    {
        for(int i = 0; i < m_sink_count; i++)
        {
            if(m_sinks[i] != NULL)
                m_sinks[i].Flush();
        }
    }

    //=== Configuration ===

    /**
     * @brief Set the minimum log level.
     */
    void SetLevel(const int level) { m_level = level; }

    /**
     * @brief Get the current minimum log level.
     */
    int GetLevel(void) const { return m_level; }

    //=== Default Sink Access ===

    /**
     * @brief Get the default MemoryRingSink (for diagnostics).
     */
    MemoryRingSink& GetRingSink(void) { return m_default_ring; }

    //=== Counters ===
    ulong TraceCount(void) const { return m_trace_count; }
    ulong DebugCount(void) const { return m_debug_count; }
    ulong InfoCount(void)  const { return m_info_count; }
    ulong WarnCount(void)  const { return m_warn_count; }
    ulong ErrorCount(void) const { return m_error_count; }
    ulong FatalCount(void) const { return m_fatal_count; }
    ulong TotalCount(void) const
    {
        return m_trace_count + m_debug_count + m_info_count +
               m_warn_count + m_error_count + m_fatal_count;
    }
};

#endif // ATLAS_LOGGER_MQH
//+------------------------------------------------------------------+
