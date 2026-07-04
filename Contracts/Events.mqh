//+------------------------------------------------------------------+
//|                                              Contracts/Events.mqh|
//|                            AtlasEA v1.1 - Event Contracts        |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENTS_MQH
#define ATLAS_EVENTS_MQH

#include "../Config/Settings.mqh"
#include "MarketState.mqh"
#include "RiskDecision.mqh"

//+------------------------------------------------------------------+
//| Event types flowing through the event bus                        |
//+------------------------------------------------------------------+
enum ENUM_ATLAS_EVENT_TYPE
{
    EV_TICK_RECEIVED            = 0,
    EV_MARKET_STATE_UPDATED     = 1,
    EV_STRATEGY_VOTE_SUBMITTED  = 2,
    EV_VOTES_AGGREGATED         = 3,
    EV_RISK_DECISION_RENDERED   = 4,
    EV_ORDER_REQUESTED          = 5,
    EV_ORDER_DISPATCHED         = 6,
    EV_TRADE_EXECUTED           = 7,
    EV_ERROR_OCCURRED           = 8,
    EV_HEARTBEAT                = 9,
    EV_STATE_PERSISTED          = 10,
    EV_SYSTEM_SHUTDOWN          = 11,
    EV_KILL_SWITCH_ACTIVATED    = 12
};

/// @brief Total number of event types (for array sizing).
#define ATLAS_EVENT_TYPE_COUNT 13

//+------------------------------------------------------------------+
//| ExecutionEvent - result of a broker OrderSend                    |
//+------------------------------------------------------------------+
struct ExecutionEvent
{
    string   event_id;
    string   request_id;
    int      fill_status;          // ATLAS_FILL_*
    int      mql_error;            // raw retcode
    double   filled_volume;
    double   fill_price;
    double   commission;
    double   swap;
    datetime execution_time;

    /**
     * @brief Validate the execution event.
     * @return ValidationResult.
     *
     * Invariants:
     *   - event_id not empty
     *   - request_id not empty (links back to the order)
     *   - fill_status in {PENDING, FILLED, PARTIAL, REJECTED, TIMEOUT}
     *   - filled_volume >= 0
     *   - fill_price >= 0 (0 acceptable for REJECTED)
     *   - execution_time > 0
     *   - all doubles are valid numbers
     */
    ValidationResult Validate(void) const
    {
        if(StringLen(event_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "event_id is empty", "event_id");
        if(StringLen(request_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "request_id is empty", "request_id");
        if(fill_status < ATLAS_FILL_PENDING || fill_status > ATLAS_FILL_TIMEOUT)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "fill_status out of range", "fill_status");
        if(!MathIsValidNumber(filled_volume))
            return ValidationResult::Fail(ATLAS_V_NAN, "filled_volume is NaN/INF", "filled_volume");
        if(!MathIsValidNumber(fill_price))
            return ValidationResult::Fail(ATLAS_V_NAN, "fill_price is NaN/INF", "fill_price");
        if(!MathIsValidNumber(commission))
            return ValidationResult::Fail(ATLAS_V_NAN, "commission is NaN/INF", "commission");
        if(!MathIsValidNumber(swap))
            return ValidationResult::Fail(ATLAS_V_NAN, "swap is NaN/INF", "swap");
        if(filled_volume < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "filled_volume must be >= 0", "filled_volume");
        if(fill_price < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "fill_price must be >= 0", "fill_price");
        if(execution_time <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "execution_time must be > 0", "execution_time");
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| AtlasEvent - envelope on the event bus                           |
//| (payload is fixed-size: MQL5 structs cannot hold dynamic arrays) |
//+------------------------------------------------------------------+
struct AtlasEvent
{
    ENUM_ATLAS_EVENT_TYPE type;
    string                source_module;
    datetime              timestamp;
    long                  snapshot_id;
    uchar                 payload[ATLAS_PAYLOAD_MAX_SIZE];
    int                   payload_size;

    /**
     * @brief Validate the event envelope.
     * @return ValidationResult.
     *
     * Invariants:
     *   - type in [EV_TICK_RECEIVED, EV_KILL_SWITCH_ACTIVATED]
     *   - source_module not empty
     *   - timestamp > 0
     *   - payload_size in [0, ATLAS_PAYLOAD_MAX_SIZE]
     */
    ValidationResult Validate(void) const
    {
        if(type < EV_TICK_RECEIVED || type > EV_KILL_SWITCH_ACTIVATED)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "type out of range: " + IntegerToString((int)type), "type");
        if(StringLen(source_module) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "source_module is empty", "source_module");
        if(timestamp <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "timestamp must be > 0", "timestamp");
        if(payload_size < 0 || payload_size > ATLAS_PAYLOAD_MAX_SIZE)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "payload_size out of range", "payload_size");
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| PositionState - tracked position (internal + broker-verified)    |
//+------------------------------------------------------------------+
struct PositionState
{
    string   position_id;
    string   symbol;
    int      type;                 // POSITION_TYPE_*
    double   volume;
    double   open_price;
    double   current_sl;
    double   current_tp;
    double   pnl;
    datetime open_time;
    bool     broker_verified;

    /**
     * @brief Validate the position state.
     * @return ValidationResult.
     *
     * Invariants:
     *   - position_id not empty
     *   - symbol not empty
     *   - type valid (POSITION_TYPE_BUY=0 or POSITION_TYPE_SELL=1)
     *   - volume >= 0
     *   - open_price > 0
     *   - current_sl >= 0 (0 = none)
     *   - current_tp >= 0 (0 = none)
     *   - all doubles are valid numbers
     */
    ValidationResult Validate(void) const
    {
        if(StringLen(position_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "position_id is empty", "position_id");
        if(StringLen(symbol) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "symbol is empty", "symbol");
        if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "type must be POSITION_TYPE_BUY or POSITION_TYPE_SELL", "type");
        if(!MathIsValidNumber(volume))
            return ValidationResult::Fail(ATLAS_V_NAN, "volume is NaN/INF", "volume");
        if(!MathIsValidNumber(open_price))
            return ValidationResult::Fail(ATLAS_V_NAN, "open_price is NaN/INF", "open_price");
        if(!MathIsValidNumber(current_sl))
            return ValidationResult::Fail(ATLAS_V_NAN, "current_sl is NaN/INF", "current_sl");
        if(!MathIsValidNumber(current_tp))
            return ValidationResult::Fail(ATLAS_V_NAN, "current_tp is NaN/INF", "current_tp");
        if(!MathIsValidNumber(pnl))
            return ValidationResult::Fail(ATLAS_V_NAN, "pnl is NaN/INF", "pnl");
        if(volume < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "volume must be >= 0", "volume");
        if(open_price <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "open_price must be > 0", "open_price");
        if(current_sl < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "current_sl must be >= 0", "current_sl");
        if(current_tp < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "current_tp must be >= 0", "current_tp");
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| PositionSnapshotEvent - bulk broker position query result        |
//+------------------------------------------------------------------+
struct PositionSnapshotEvent
{
    PositionState broker_positions[ATLAS_MAX_POSITIONS];
    int           count;
    datetime      timestamp;

    /**
     * @brief Validate the position snapshot.
     * @return ValidationResult.
     *
     * Invariants:
     *   - count in [0, ATLAS_MAX_POSITIONS]
     *   - timestamp > 0
     *   - each position in [0, count) validates
     */
    ValidationResult Validate(void) const
    {
        if(count < 0 || count > ATLAS_MAX_POSITIONS)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "count out of range", "count");
        if(timestamp <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "timestamp must be > 0", "timestamp");
        for(int i = 0; i < count; i++)
        {
            ValidationResult r = broker_positions[i].Validate();
            if(!r.valid)
            {
                r.field = "broker_positions[" + IntegerToString(i) + "]." + r.field;
                return r;
            }
        }
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_EVENTS_MQH
//+------------------------------------------------------------------+
