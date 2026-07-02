//+------------------------------------------------------------------+
//|                                             Core/NullLogger.mqh
//|                          AtlasEA v2.0 - Null Logger (default)     |
//+------------------------------------------------------------------+
#ifndef ATLAS_NULL_LOGGER_MQH
#define ATLAS_NULL_LOGGER_MQH

#include "../Interfaces/ILogger.mqh"

/**
 * @brief No-op logger implementation.
 *
 * Used as the default when no real ILogger is injected.
 * All methods are empty — zero overhead in release builds.
 *
 * This class is stateless and can be shared across all modules.
 */
class NullLogger : public ILogger
{
public:
    NullLogger(void) {}
    ~NullLogger(void) {}

    virtual void Log(const int level, const string module, const string message) override {}
    virtual void Debug(const string module, const string message) override {}
    virtual void Info(const string module, const string message) override {}
    virtual void Warn(const string module, const string message) override {}
    virtual void Error(const string module, const string message) override {}
    virtual void Fatal(const string module, const string message) override {}
};

#endif // ATLAS_NULL_LOGGER_MQH
//+------------------------------------------------------------------+
