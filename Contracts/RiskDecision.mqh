//+------------------------------------------------------------------+
//|                                         Contracts/RiskDecision.mqh|
//|                       AtlasEA v1.1 - Risk / Decision Contracts   |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_DECISION_MQH
#define ATLAS_RISK_DECISION_MQH

#include "../Config/Settings.mqh"

//+------------------------------------------------------------------+
//| StrategyVote - single strategy evaluation result                 |
//+------------------------------------------------------------------+
struct StrategyVote
{
    int      strategy_id;
    string   strategy_version;
    int      direction;            // ATLAS_ORDER_*
    double   confidence;           // 0..1
    double   suggested_volume;
    double   suggested_entry;
    double   suggested_sl;
    double   suggested_tp;
    long     snapshot_id;
    datetime vote_time;
};

//+------------------------------------------------------------------+
//| AggregatedVote - merged vote ready for risk evaluation           |
//+------------------------------------------------------------------+
struct AggregatedVote
{
    string       aggregation_id;
    int          direction;
    double       confidence;
    StrategyVote votes[ATLAS_MAX_VOTES];
    int          vote_count;
    long         snapshot_id;
};

//+------------------------------------------------------------------+
//| RiskDecision - rendered by RiskEngine                            |
//+------------------------------------------------------------------+
struct RiskDecision
{
    string   decision_id;
    string   aggregation_id;
    int      status;                // ATLAS_DECISION_*
    int      reason_code;           // ATLAS_RISK_REASON_*
    string   rejection_reason;
    double   approved_volume;
    double   approved_price;
    double   approved_sl;
    double   approved_tp;
    int      order_type;            // ATLAS_ORDER_*
    bool     kill_switch_triggered;
    long     snapshot_id;
    datetime decision_time;
};

//+------------------------------------------------------------------+
//| OrderRequest - validated request ready for broker dispatch       |
//+------------------------------------------------------------------+
struct OrderRequest
{
    string   request_id;
    string   decision_id;
    string   symbol;
    int      order_type;            // ENUM_ORDER_TYPE as int
    int      direction;             // ATLAS_ORDER_*
    double   volume;
    double   entry_price;
    double   stop_loss;
    double   take_profit;
    long     magic_number;
    long     snapshot_id;
    string   comment;
};

#endif // ATLAS_RISK_DECISION_MQH
//+------------------------------------------------------------------+
