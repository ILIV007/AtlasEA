//+------------------------------------------------------------------+
//|                                              Interfaces/ILogger.mqh
//|                            AtlasEA v2.0 - Logger Interface        |
//+------------------------------------------------------------------+
#ifndef ATLAS_ILOGGER_MQH
#define ATLAS_ILOGGER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Abstract logger interface.
 *
 * Every module receives an ILogger* pointer during initialization.
 * No module may call Print() directly — all logging goes through this interface.
 *
 * The concrete Logger implementation is provided in a later phase.
 * Core provides a NullLogger default so the system runs without a real logger.
 */
class ILogger
{
public:
    /**
     * @brief Log a message at the given level.
     * @param level   ATLAS_LOG_TRACE .. ATLAS_LOG_FATAL
     * @param module  Source module name (e.g. "CoreEngine", "RiskEngine")
     * @param message Human-readable description
     */
    virtual void Log(const int level, const string module, const string message) = 0;

    /// @brief Convenience: TRACE level (finest granularity)
    virtual void Trace(const string module, const string message) = 0;
    /// @brief Convenience: DEBUG level
    virtual void Debug(const string module, const string message) = 0;
    /// @brief Convenience: INFO level
    virtual void Info(const string module, const string message) = 0;
    /// @brief Convenience: WARN level
    virtual void Warn(const string module, const string message) = 0;
    /// @brief Convenience: ERROR level
    virtual void Error(const string module, const string message) = 0;
    /// @brief Convenience: FATAL level
    virtual void Fatal(const string module, const string message) = 0;

    virtual ~ILogger(void) {}
};

#endif // ATLAS_ILOGGER_MQH
//+------------------------------------------------------------------+
