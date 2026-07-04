//+------------------------------------------------------------------+
//|                       Core/DebugAssert.mqh                      |
//|       AtlasEA v0.1.24.5 - Defensive Assertions (DEBUG only)     |
//+------------------------------------------------------------------+
#ifndef ATLAS_DEBUG_ASSERT_MQH
#define ATLAS_DEBUG_ASSERT_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Debug assertion macros.
 *
 * These compile to no-ops in release builds (when ATLAS_DEBUG is not defined).
 * In debug builds, they log a FATAL error and abort the current operation.
 *
 * Usage:
 *   ATLAS_ASSERT(ptr != NULL, "CoreEngine", "broker is null");
 *   ATLAS_ASSERT_NAN(price, "MarketEngine", "price is NaN");
 *   ATLAS_ASSERT_RANGE(volume, 0.0, 100.0, "ExecutionEngine", "volume out of range");
 */

#ifdef ATLAS_DEBUG

//--- Forward declaration
class ILogger;

/// @brief Internal assertion handler.
static void AtlasAssertFail(ILogger *logger, const string module, const string message,
                            const string file, const int line)
{
    if(logger != NULL)
        logger.Fatal(module, "ASSERTION FAILED: " + message + " (" + file + ":" + IntegerToString(line) + ")");
    //--- In MQL5, we cannot abort; the caller must handle the failure gracefully.
    //--- The assertion logs FATAL and returns; the caller should early-return.
}

/// @brief Assert a condition is true.
#define ATLAS_ASSERT(cond, module, msg) \
    do { if(!(cond)) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

/// @brief Assert a pointer is not null.
#define ATLAS_ASSERT_NOT_NULL(ptr, module, msg) \
    do { if((ptr) == NULL) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

/// @brief Assert a double is not NaN/INF.
#define ATLAS_ASSERT_NAN(val, module, msg) \
    do { if(!MathIsValidNumber(val)) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

/// @brief Assert a value is within [lo, hi].
#define ATLAS_ASSERT_RANGE(val, lo, hi, module, msg) \
    do { if((val) < (lo) || (val) > (hi)) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

/// @brief Assert an enum value is within range.
#define ATLAS_ASSERT_ENUM(val, max_val, module, msg) \
    do { if((val) < 0 || (val) >= (max_val)) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

/// @brief Assert a snapshot ID is positive.
#define ATLAS_ASSERT_SNAPSHOT(id, module, msg) \
    do { if((id) <= 0) AtlasAssertFail(m_logger, module, msg, __FILE__, __LINE__); } while(0)

#else //--- Release build: assertions disappear

#define ATLAS_ASSERT(cond, module, msg)
#define ATLAS_ASSERT_NOT_NULL(ptr, module, msg)
#define ATLAS_ASSERT_NAN(val, module, msg)
#define ATLAS_ASSERT_RANGE(val, lo, hi, module, msg)
#define ATLAS_ASSERT_ENUM(val, max_val, module, msg)
#define ATLAS_ASSERT_SNAPSHOT(id, module, msg)

#endif // ATLAS_DEBUG

#endif // ATLAS_DEBUG_ASSERT_MQH
//+------------------------------------------------------------------+
