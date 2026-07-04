//+------------------------------------------------------------------+
//|               Interfaces/IHealthMonitor.mqh                     |
//|       AtlasEA v0.1.14.0 - Structured Health Report              |
//+------------------------------------------------------------------+
#ifndef ATLAS_IHEALTH_MONITOR_MQH
#define ATLAS_IHEALTH_MONITOR_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Health status codes.
 */
#define ATLAS_HEALTH_GREEN   0
#define ATLAS_HEALTH_YELLOW  1
#define ATLAS_HEALTH_RED     2

/**
 * @brief Health issue codes (machine-readable, replaces string-only reasons).
 */
enum ENUM_HEALTH_ISSUE_CODE
{
    HEALTH_OK                  = 0,
    QUEUE_OVERFLOW             = 1,
    PIPELINE_TIMEOUT           = 2,
    BROKER_DISCONNECTED        = 3,
    BROKER_TIMEOUT             = 4,
    MEMORY_GROWTH              = 5,
    SNAPSHOT_CORRUPTED         = 6,
    SNAPSHOT_FAILURE           = 7,
    RECOVERY_FAILED            = 8,
    EVENT_REPLAY_FAILED        = 9,
    PERSISTENCE_ERROR          = 10,
    SLOW_TICK                  = 11,
    SLOW_ORDER                 = 12,
    HIGH_SLIPPAGE              = 13,
    KILL_SWITCH_ACTIVE         = 14,
    FATAL_ERROR                = 15,
    MEMORY_CRITICAL            = 16,
    POSITION_MISMATCH          = 17
};

/**
 * @struct HealthIssue
 * @brief A single health issue with structured data.
 */
struct HealthIssue
{
    ENUM_HEALTH_ISSUE_CODE code;    ///< Machine-readable code
    string                 description; ///< Human-readable description
    datetime               timestamp;   ///< When the issue was detected
    int                    severity;    ///< ATLAS_HEALTH_YELLOW or ATLAS_HEALTH_RED
};

/**
 * @struct HealthReport
 * @brief Complete structured health report (replaces string-only version).
 */
struct HealthReport
{
    int         status;             ///< ATLAS_HEALTH_GREEN/YELLOW/RED
    string      summary;            ///< Human-readable summary
    HealthIssue issues[16];         ///< List of active issues
    int         issue_count;        ///< Number of active issues

    //--- Sub-system flags (backward compatible)
    bool   queue_overflow;
    bool   pipeline_timeout;
    bool   memory_growth;
    bool   snapshot_failure;
    bool   persistence_failure;
    bool   broker_connected;
    bool   recovery_failure;
    bool   slow_tick;
    bool   slow_order;
    bool   high_slippage;
    bool   kill_switch_active;
};

/**
 * @struct HealthSnapshot
 * @brief Point-in-time health metrics.
 */
struct HealthSnapshot
{
    int    queue_depth;
    int    priority_queue_depth;
    ulong  total_dropped_events;
    double avg_pipeline_latency_ms;
    double peak_pipeline_latency_ms;
    double avg_tick_latency_ms;
    double peak_tick_latency_ms;
    bool   broker_connected;
    bool   trading_enabled;
    bool   market_open;
    ulong  memory_used_mb;
    string last_fatal_error;
    datetime last_fatal_time;
    ulong  total_errors;
    bool   system_healthy;
    string health_reason;
};

/**
 * @class IHealthMonitor
 * @brief Interface for system health monitoring.
 */
class IHealthMonitor
{
public:
    virtual HealthSnapshot GetSnapshot(void) const = 0;
    virtual void ReportFatal(const string message) = 0;
    virtual void ReportError(void) = 0;
    virtual bool IsHealthy(void) const = 0;

    //--- NEW in v0.1.14.0 ---
    virtual HealthReport GetReport(void) const = 0;
    virtual void LogReport(void) const = 0;

    virtual ~IHealthMonitor(void) {}
};

#endif // ATLAS_IHEALTH_MONITOR_MQH
//+------------------------------------------------------------------+
