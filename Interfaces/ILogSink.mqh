//+------------------------------------------------------------------+
//|                   Interfaces/ILogSink.mqh                        |
//|       AtlasEA v0.1.14.0 - Log Sink Interface (Pluggable)         |
//+------------------------------------------------------------------+
#ifndef ATLAS_ILOG_SINK_MQH
#define ATLAS_ILOG_SINK_MQH

#include "../Config/Settings.mqh"

/**
 * @struct LogEntry
 * @brief One log entry passed to sinks.
 *
 * Immutable once constructed. The Logger creates this and dispatches
 * to all registered sinks.
 */
struct LogEntry
{
    int      level;       ///< ATLAS_LOG_TRACE .. ATLAS_LOG_FATAL
    datetime timestamp;   ///< When the entry was logged
    string   module;      ///< Source module name
    string   message;     ///< Log message
};

/**
 * @class ILogSink
 * @brief Interface for a log output sink.
 *
 * A Logger dispatches each log entry to all registered sinks.
 * Sinks are pluggable — new sinks (network, database, remote) can be
 * added without modifying the Logger.
 *
 * Thread model: single-threaded (MQL5). Sinks are called synchronously.
 *
 * Performance: sinks must NOT allocate memory or do heavy I/O in the
 * hot path. File sinks should buffer writes.
 */
class ILogSink
{
public:
    /**
     * @brief Write a log entry to the sink.
     * @param entry The log entry to write.
     */
    virtual void Write(const LogEntry &entry) = 0;

    /**
     * @brief Flush any buffered data (called on shutdown).
     */
    virtual void Flush(void) = 0;

    /**
     * @brief Get the sink name (for diagnostics).
     */
    virtual string GetName(void) const = 0;

    virtual ~ILogSink(void) {}
};

#endif // ATLAS_ILOG_SINK_MQH
//+------------------------------------------------------------------+
