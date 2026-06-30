//+------------------------------------------------------------------+
//|                                              Contracts/Events.mqh|
//|                            AtlasEA v1.0 - Event Contracts        |
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
};

//+------------------------------------------------------------------+
//| PositionSnapshotEvent - bulk broker position query result        |
//+------------------------------------------------------------------+
struct PositionSnapshotEvent
{
    PositionState broker_positions[ATLAS_MAX_POSITIONS];
    int           count;
    datetime      timestamp;
};

#endif // ATLAS_EVENTS_MQH
//+------------------------------------------------------------------+
