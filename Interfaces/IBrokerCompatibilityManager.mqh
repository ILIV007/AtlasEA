//+------------------------------------------------------------------+
//|               Interfaces/IBrokerCompatibilityManager.mqh         |
//|       AtlasEA v1.0 Step 7 - Broker Compatibility Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_IBROKER_COMPATIBILITY_MQH
#define ATLAS_IBROKER_COMPATIBILITY_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Broker execution mode codes.
 */
#define ATLAS_BROKER_EXEC_MARKET    0   ///< Market execution
#define ATLAS_BROKER_EXEC_INSTANT   1   ///< Instant execution
#define ATLAS_BROKER_EXEC_EXCHANGE  2   ///< Exchange execution
#define ATLAS_BROKER_EXEC_REQUEST   3   ///< Request execution

/**
 * @brief Account margin mode codes.
 */
#define ATLAS_ACCOUNT_NETTING      0   ///< Netting account
#define ATLAS_ACCOUNT_HEDGING      1   ///< Hedging account
#define ATLAS_ACCOUNT_UNKNOWN      2   ///< Unknown

/**
 * @brief Broker health status codes.
 */
#define ATLAS_BROKER_HEALTHY          0
#define ATLAS_BROKER_DEGRADED         1
#define ATLAS_BROKER_UNHEALTHY        2
#define ATLAS_BROKER_DISCONNECTED     3

/**
 * @brief Trading pause reason codes.
 */
#define ATLAS_PAUSE_NONE              0
#define ATLAS_PAUSE_BROKER_UNHEALTHY  1
#define ATLAS_PAUSE_CONNECTION        2
#define ATLAS_PAUSE_SPREAD_ABNORMAL   3
#define ATLAS_PAUSE_LATENCY           4
#define ATLAS_PAUSE_REJECTED_ORDERS   5
#define ATLAS_PAUSE_SESSION_CLOSED    6
#define ATLAS_PAUSE_WEEKEND           7
#define ATLAS_PAUSE_MANUAL            8

/**
 * @brief Symbol validation result codes.
 */
#define ATLAS_SV_OK                  0
#define ATLAS_SV_TRADING_DISABLED    1
#define ATLAS_SV_SESSION_CLOSED      2
#define ATLAS_SV_SPREAD_TOO_HIGH     3
#define ATLAS_SV_VOLUME_INVALID      4
#define ATLAS_SV_STOPS_INVALID       5
#define ATLAS_SV_PRICE_NOT_NORMALIZED 6
#define ATLAS_SV_FREEZE_LEVEL        7
#define ATLAS_SV_STOP_LEVEL          8
#define ATLAS_SV_MARGIN_INSUFFICIENT 9
#define ATLAS_SV_NOT_SYNCHRONIZED    10

/**
 * @brief Environment validation result codes.
 */
#define ATLAS_ENV_OK                    0
#define ATLAS_ENV_AUTOTRADING_DISABLED  1
#define ATLAS_ENV_DLL_DISABLED          2
#define ATLAS_ENV_MARKET_CLOSED         3
#define ATLAS_ENV_DISCONNECTED          4
#define ATLAS_ENV_NO_PRICE_FEED         5
#define ATLAS_ENV_INVALID_ACCOUNT       6
#define ATLAS_ENV_READ_ONLY             7
#define ATLAS_ENV_INSUFFICIENT_PERMS    8

/**
 * @brief Execution safety rejection codes.
 */
#define ATLAS_ES_OK                  0
#define ATLAS_ES_DUPLICATE_ORDER     1
#define ATLAS_ES_DOUBLE_EXECUTION    2
#define ATLAS_ES_RETRY_LOOP          3
#define ATLAS_ES_ORDER_STORM         4
#define ATLAS_ES_TRADE_CONTEXT       5
#define ATLAS_ES_EXCESSIVE_SLIPPAGE  6
#define ATLAS_ES_INVALID_MODIFICATION 7
#define ATLAS_ES_MODIFICATION_LOOP   8

/**
 * @struct BrokerCapabilities
 * @brief Cached broker capabilities (detected once at init).
 */
struct BrokerCapabilities
{
    int    execution_mode;       ///< ATLAS_BROKER_EXEC_*
    int    account_mode;         ///< ATLAS_ACCOUNT_*
    bool   is_ecn;               ///< ECN broker?
    bool   fifo_restricted;      ///< FIFO restrictions?
    double min_lot;              ///< Minimum volume
    double max_lot;              ///< Maximum volume
    double lot_step;             ///< Volume step
    int    digits;               ///< Symbol digits
    double point;                ///< Symbol point
    double tick_size;            ///< Tick size
    double tick_value;           ///< Tick value
    long   freeze_level;         ///< Freeze level (points)
    long   stop_level;           ///< Stop level (points)
    long   filling_mode;         ///< Filling mode
    long   leverage;             ///< Account leverage
    double contract_size;        ///< Contract size
    double margin_initial;       ///< Initial margin per lot
    bool   market_watch_synchronized; ///< Symbol synchronized?
    bool   trading_allowed;      ///< Symbol trading allowed?

    BrokerCapabilities(void)
    {
        execution_mode  = ATLAS_BROKER_EXEC_MARKET;
        account_mode    = ATLAS_ACCOUNT_HEDGING;
        is_ecn          = false;
        fifo_restricted = false;
        min_lot         = 0.01;
        max_lot         = 100.0;
        lot_step        = 0.01;
        digits          = 5;
        point           = 0.00001;
        tick_size       = 0.00001;
        tick_value      = 1.0;
        freeze_level    = 0;
        stop_level      = 0;
        filling_mode    = 1;
        leverage        = 100;
        contract_size   = 100000.0;
        margin_initial  = 1000.0;
        market_watch_synchronized = true;
        trading_allowed = true;
    }
};

/**
 * @struct SymbolValidationResult
 * @brief Result of pre-order symbol validation.
 */
struct SymbolValidationResult
{
    int    code;           ///< ATLAS_SV_*
    string detail;         ///< Human-readable detail
    double spread_points;  ///< Current spread in points
    double stop_level_pts; ///< Stop level in points
    double freeze_level_pts; ///< Freeze level in points

    SymbolValidationResult(void)
    {
        code            = ATLAS_SV_OK;
        detail          = "";
        spread_points   = 0.0;
        stop_level_pts  = 0.0;
        freeze_level_pts = 0.0;
    }

    bool Passed(void) const { return code == ATLAS_SV_OK; }
};

/**
 * @struct EnvironmentValidationResult
 * @brief Result of environment validation.
 */
struct EnvironmentValidationResult
{
    int    code;           ///< ATLAS_ENV_*
    string detail;         ///< Human-readable detail
    bool   autotrading_enabled;
    bool   terminal_connected;
    bool   market_open;
    bool   price_feed_active;
    bool   account_valid;
    bool   trade_allowed;
    bool   expert_allowed;

    EnvironmentValidationResult(void)
    {
        code            = ATLAS_ENV_OK;
        detail          = "";
        autotrading_enabled  = true;
        terminal_connected   = true;
        market_open          = true;
        price_feed_active    = true;
        account_valid        = true;
        trade_allowed        = true;
        expert_allowed       = true;
    }

    bool Passed(void) const { return code == ATLAS_ENV_OK; }
};

/**
 * @struct ExecutionSafetyResult
 * @brief Result of execution safety check.
 */
struct ExecutionSafetyResult
{
    int    code;           ///< ATLAS_ES_*
    string detail;         ///< Human-readable detail

    ExecutionSafetyResult(void)
    {
        code   = ATLAS_ES_OK;
        detail = "";
    }

    bool Passed(void) const { return code == ATLAS_ES_OK; }
};

/**
 * @struct BrokerHealthStatus
 * @brief Current broker health status.
 */
struct BrokerHealthStatus
{
    int    status;             ///< ATLAS_BROKER_HEALTHY / DEGRADED / UNHEALTHY / DISCONNECTED
    string status_name;        ///< Human-readable
    int    pause_reason;       ///< ATLAS_PAUSE_* (0 = not paused)
    double avg_execution_ms;   ///< Average execution time
    int    rejected_orders;    ///< Rejected orders today
    int    total_orders;       ///< Total orders today
    double avg_spread_points;  ///< Average spread
    double max_spread_points;  ///< Max spread today
    double server_latency_ms;  ///< Server latency estimate
    bool   price_feed_active;  ///< Price feed active?
    bool   trading_paused;     ///< Is trading paused?
    datetime last_check_time;  ///< Last health check

    BrokerHealthStatus(void)
    {
        status            = ATLAS_BROKER_HEALTHY;
        status_name       = "HEALTHY";
        pause_reason      = ATLAS_PAUSE_NONE;
        avg_execution_ms  = 0.0;
        rejected_orders   = 0;
        total_orders      = 0;
        avg_spread_points = 0.0;
        max_spread_points = 0.0;
        server_latency_ms = 0.0;
        price_feed_active = true;
        trading_paused    = false;
        last_check_time   = 0;
    }
};

/**
 * @struct SafetyLimits
 * @brief Configurable safety limits.
 */
struct SafetyLimits
{
    int    max_daily_trades;           ///< Max trades per day
    int    max_simultaneous_trades;    ///< Max open positions
    int    max_failed_orders;          ///< Max failed orders before pause
    int    max_retries;                ///< Max retries per order
    double max_slippage_points;        ///< Max acceptable slippage
    double max_spread_multiplier;      ///< Max spread × average spread
    int    max_execution_latency_ms;   ///< Max execution latency before pause
    int    max_modification_per_position; ///< Max SL/TP modifications per position
    int    min_orders_per_minute;      ///< Anti-order-storm: min interval
    int    max_orders_per_minute;      ///< Anti-order-storm: max per minute

    SafetyLimits(void)
    {
        max_daily_trades           = 50;
        max_simultaneous_trades     = 10;
        max_failed_orders           = 5;
        max_retries                 = 3;
        max_slippage_points         = 20.0;
        max_spread_multiplier       = 3.0;
        max_execution_latency_ms    = 5000;
        max_modification_per_position = 10;
        min_orders_per_minute       = 2;
        max_orders_per_minute       = 20;
    }
};

/**
 * @class IBrokerCompatibilityManager
 * @brief The ONLY interface for broker compatibility, safety, and health.
 *
 * Implemented by BrokerCompatibilityManager (Production/). Consumed by
 * CoreEngine before every order and on every heartbeat.
 *
 * Contract:
 *   - Caches broker capabilities after initialization (no repeated queries).
 *   - Validates symbol + environment before every order.
 *   - Prevents duplicate orders, order storms, retry loops.
 *   - Monitors broker health continuously.
 *   - Pauses trading automatically when unhealthy; resumes when healthy.
 *   - No blocking operations in OnTick().
 */
class IBrokerCompatibilityManager
{
public:
    /**
     * @brief Detect and cache broker capabilities.
     * Called once at initialization. No repeated SymbolInfo calls after this.
     */
    virtual bool DetectCapabilities(void) = 0;

    /**
     * @brief Get cached broker capabilities.
     */
    virtual const BrokerCapabilities& GetCapabilities(void) const = 0;

    /**
     * @brief Validate symbol before sending an order.
     * O(1) — uses cached capabilities + current market data.
     */
    virtual SymbolValidationResult ValidateSymbol(const double volume,
                                                    const double sl,
                                                    const double tp,
                                                    const double entry_price,
                                                    const int direction) = 0;

    /**
     * @brief Validate the trading environment (terminal, account, permissions).
     */
    virtual EnvironmentValidationResult ValidateEnvironment(void) = 0;

    /**
     * @brief Check execution safety for a new order.
     * Prevents duplicates, storms, retry loops, trade context conflicts.
     */
    virtual ExecutionSafetyResult CheckExecutionSafety(const string request_id) = 0;

    /**
     * @brief Record an order result (for health monitoring + safety tracking).
     */
    virtual void RecordOrderResult(const bool success, const ulong execution_ms) = 0;

    /**
     * @brief Check broker health (called on heartbeat).
     */
    virtual BrokerHealthStatus CheckHealth(void) = 0;

    /**
     * @brief Is trading currently paused?
     */
    virtual bool IsTradingPaused(void) const = 0;

    /**
     * @brief Get the current pause reason.
     */
    virtual int GetPauseReason(void) const = 0;

    /**
     * @brief Get the current health status.
     */
    virtual const BrokerHealthStatus& GetHealthStatus(void) const = 0;

    /**
     * @brief Get the safety limits.
     */
    virtual const SafetyLimits& GetSafetyLimits(void) const = 0;

    /**
     * @brief Set the safety limits.
     */
    virtual void SetSafetyLimits(const SafetyLimits &limits) = 0;

    /**
     * @brief Manually pause trading.
     */
    virtual void PauseTrading(const int reason) = 0;

    /**
     * @brief Manually resume trading (only if all conditions are healthy).
     */
    virtual bool ResumeTrading(void) = 0;

    /**
     * @brief Get session status (weekend, rollover, DST, etc.).
     */
    virtual bool IsSessionOpen(void) const = 0;

    /**
     * @brief Check if a session event is occurring (weekend close, rollover, etc.).
     * @return Event code (0 = none, 1 = weekend_close, 2 = daily_rollover, 3 = dst_change, 4 = server_restart).
     */
    virtual int CheckSessionEvent(void) = 0;

    /**
     * @brief Log the current status.
     */
    virtual void LogStatus(void) const = 0;

    /**
     * @brief Initialize the manager.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the manager.
     */
    virtual void Shutdown(void) = 0;

    virtual ~IBrokerCompatibilityManager(void) {}
};

//--- Helper name functions
string BrokerHealthName(const int status)
{
    switch(status)
    {
        case ATLAS_BROKER_HEALTHY:      return "HEALTHY";
        case ATLAS_BROKER_DEGRADED:     return "DEGRADED";
        case ATLAS_BROKER_UNHEALTHY:    return "UNHEALTHY";
        case ATLAS_BROKER_DISCONNECTED: return "DISCONNECTED";
    }
    return "UNKNOWN";
}

string PauseReasonName(const int reason)
{
    switch(reason)
    {
        case ATLAS_PAUSE_NONE:              return "NONE";
        case ATLAS_PAUSE_BROKER_UNHEALTHY:  return "BROKER_UNHEALTHY";
        case ATLAS_PAUSE_CONNECTION:        return "CONNECTION";
        case ATLAS_PAUSE_SPREAD_ABNORMAL:   return "SPREAD_ABNORMAL";
        case ATLAS_PAUSE_LATENCY:           return "LATENCY";
        case ATLAS_PAUSE_REJECTED_ORDERS:   return "REJECTED_ORDERS";
        case ATLAS_PAUSE_SESSION_CLOSED:    return "SESSION_CLOSED";
        case ATLAS_PAUSE_WEEKEND:           return "WEEKEND";
        case ATLAS_PAUSE_MANUAL:            return "MANUAL";
    }
    return "UNKNOWN";
}

string ExecutionModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_BROKER_EXEC_MARKET:   return "MARKET";
        case ATLAS_BROKER_EXEC_INSTANT:  return "INSTANT";
        case ATLAS_BROKER_EXEC_EXCHANGE: return "EXCHANGE";
        case ATLAS_BROKER_EXEC_REQUEST:  return "REQUEST";
    }
    return "UNKNOWN";
}

string AccountModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_ACCOUNT_NETTING: return "NETTING";
        case ATLAS_ACCOUNT_HEDGING: return "HEDGING";
        case ATLAS_ACCOUNT_UNKNOWN: return "UNKNOWN";
    }
    return "UNKNOWN";
}

string SymbolValidationName(const int code)
{
    switch(code)
    {
        case ATLAS_SV_OK:                  return "OK";
        case ATLAS_SV_TRADING_DISABLED:    return "TRADING_DISABLED";
        case ATLAS_SV_SESSION_CLOSED:      return "SESSION_CLOSED";
        case ATLAS_SV_SPREAD_TOO_HIGH:     return "SPREAD_TOO_HIGH";
        case ATLAS_SV_VOLUME_INVALID:      return "VOLUME_INVALID";
        case ATLAS_SV_STOPS_INVALID:       return "STOPS_INVALID";
        case ATLAS_SV_PRICE_NOT_NORMALIZED: return "PRICE_NOT_NORMALIZED";
        case ATLAS_SV_FREEZE_LEVEL:        return "FREEZE_LEVEL";
        case ATLAS_SV_STOP_LEVEL:          return "STOP_LEVEL";
        case ATLAS_SV_MARGIN_INSUFFICIENT: return "MARGIN_INSUFFICIENT";
        case ATLAS_SV_NOT_SYNCHRONIZED:    return "NOT_SYNCHRONIZED";
    }
    return "UNKNOWN";
}

string EnvironmentValidationName(const int code)
{
    switch(code)
    {
        case ATLAS_ENV_OK:                    return "OK";
        case ATLAS_ENV_AUTOTRADING_DISABLED:  return "AUTOTRADING_DISABLED";
        case ATLAS_ENV_DLL_DISABLED:          return "DLL_DISABLED";
        case ATLAS_ENV_MARKET_CLOSED:         return "MARKET_CLOSED";
        case ATLAS_ENV_DISCONNECTED:          return "DISCONNECTED";
        case ATLAS_ENV_NO_PRICE_FEED:         return "NO_PRICE_FEED";
        case ATLAS_ENV_INVALID_ACCOUNT:       return "INVALID_ACCOUNT";
        case ATLAS_ENV_READ_ONLY:             return "READ_ONLY";
        case ATLAS_ENV_INSUFFICIENT_PERMS:    return "INSUFFICIENT_PERMS";
    }
    return "UNKNOWN";
}

string ExecutionSafetyName(const int code)
{
    switch(code)
    {
        case ATLAS_ES_OK:                  return "OK";
        case ATLAS_ES_DUPLICATE_ORDER:     return "DUPLICATE_ORDER";
        case ATLAS_ES_DOUBLE_EXECUTION:    return "DOUBLE_EXECUTION";
        case ATLAS_ES_RETRY_LOOP:          return "RETRY_LOOP";
        case ATLAS_ES_ORDER_STORM:         return "ORDER_STORM";
        case ATLAS_ES_TRADE_CONTEXT:       return "TRADE_CONTEXT";
        case ATLAS_ES_EXCESSIVE_SLIPPAGE:  return "EXCESSIVE_SLIPPAGE";
        case ATLAS_ES_INVALID_MODIFICATION: return "INVALID_MODIFICATION";
        case ATLAS_ES_MODIFICATION_LOOP:   return "MODIFICATION_LOOP";
    }
    return "UNKNOWN";
}

#endif // ATLAS_IBROKER_COMPATIBILITY_MQH
//+------------------------------------------------------------------+
