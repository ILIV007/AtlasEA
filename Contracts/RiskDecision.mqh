//+------------------------------------------------------------------+
//|                                         Contracts/RiskDecision.mqh|
//|                       AtlasEA v1.1 - Risk / Decision Contracts   |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_DECISION_MQH
#define ATLAS_RISK_DECISION_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"

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

    /**
     * @brief Validate the strategy vote.
     * @return ValidationResult.
     *
     * Invariants:
     *   - direction in {ATLAS_ORDER_BUY, ATLAS_ORDER_SELL, ATLAS_ORDER_NONE}
     *   - confidence in [0.0, 1.0]
     *   - suggested_volume >= 0
     *   - snapshot_id > 0
     *   - vote_time > 0
     *   - all doubles are valid numbers
     */
    ValidationResult Validate(void) const
    {
        if(direction < ATLAS_ORDER_SELL || direction > ATLAS_ORDER_BUY)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "direction must be in {-1, 0, 1}", "direction");
        if(!MathIsValidNumber(confidence))
            return ValidationResult::Fail(ATLAS_V_NAN, "confidence is NaN/INF", "confidence");
        if(confidence < 0.0 || confidence > 1.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "confidence must be in [0, 1]", "confidence");
        if(!MathIsValidNumber(suggested_volume))
            return ValidationResult::Fail(ATLAS_V_NAN, "suggested_volume is NaN/INF", "suggested_volume");
        if(suggested_volume < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "suggested_volume must be >= 0", "suggested_volume");
        if(snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_id must be > 0", "snapshot_id");
        if(vote_time <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "vote_time must be > 0", "vote_time");
        return ValidationResult::Ok();
    }
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

    /**
     * @brief Validate the aggregated vote.
     * @return ValidationResult.
     *
     * Invariants:
     *   - aggregation_id not empty
     *   - direction valid
     *   - confidence in [0, 1]
     *   - vote_count in [0, ATLAS_MAX_VOTES]
     *   - snapshot_id > 0
     *   - each individual vote validates
     */
    ValidationResult Validate(void) const
    {
        if(StringLen(aggregation_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "aggregation_id is empty", "aggregation_id");
        if(direction < ATLAS_ORDER_SELL || direction > ATLAS_ORDER_BUY)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "direction must be in {-1, 0, 1}", "direction");
        if(!MathIsValidNumber(confidence))
            return ValidationResult::Fail(ATLAS_V_NAN, "confidence is NaN/INF", "confidence");
        if(confidence < 0.0 || confidence > 1.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "confidence must be in [0, 1]", "confidence");
        if(vote_count < 0 || vote_count > ATLAS_MAX_VOTES)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "vote_count out of range", "vote_count");
        if(snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_id must be > 0", "snapshot_id");
        //--- Validate each vote
        for(int i = 0; i < vote_count; i++)
        {
            ValidationResult r = votes[i].Validate();
            if(!r.valid)
            {
                r.field = "votes[" + IntegerToString(i) + "]." + r.field;
                return r;
            }
        }
        return ValidationResult::Ok();
    }
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

    /**
     * @brief Validate the risk decision.
     * @return ValidationResult.
     *
     * Invariants:
     *   - decision_id not empty
     *   - status in {APPROVED, REJECTED, DEFERRED}
     *   - order_type valid
     *   - approved_volume >= 0
     *   - if APPROVED: approved_price > 0, approved_volume > 0
     *   - SL/TP non-negative (0 = none)
     *   - all doubles are valid numbers
     *   - snapshot_id > 0
     *   - decision_time > 0
     */
    ValidationResult Validate(void) const
    {
        if(StringLen(decision_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "decision_id is empty", "decision_id");
        if(status != ATLAS_DECISION_APPROVED &&
           status != ATLAS_DECISION_REJECTED &&
           status != ATLAS_DECISION_DEFERRED)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "status must be APPROVED/REJECTED/DEFERRED", "status");
        if(order_type < ATLAS_ORDER_SELL || order_type > ATLAS_ORDER_BUY)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "order_type must be in {-1, 0, 1}", "order_type");
        if(!MathIsValidNumber(approved_volume))
            return ValidationResult::Fail(ATLAS_V_NAN, "approved_volume is NaN/INF", "approved_volume");
        if(!MathIsValidNumber(approved_price))
            return ValidationResult::Fail(ATLAS_V_NAN, "approved_price is NaN/INF", "approved_price");
        if(!MathIsValidNumber(approved_sl))
            return ValidationResult::Fail(ATLAS_V_NAN, "approved_sl is NaN/INF", "approved_sl");
        if(!MathIsValidNumber(approved_tp))
            return ValidationResult::Fail(ATLAS_V_NAN, "approved_tp is NaN/INF", "approved_tp");
        if(approved_volume < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "approved_volume must be >= 0", "approved_volume");
        if(approved_sl < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "approved_sl must be >= 0", "approved_sl");
        if(approved_tp < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "approved_tp must be >= 0", "approved_tp");
        if(status == ATLAS_DECISION_APPROVED)
        {
            if(approved_volume <= 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "APPROVED but approved_volume <= 0", "approved_volume");
            if(approved_price <= 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "APPROVED but approved_price <= 0", "approved_price");
        }
        if(snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_id must be > 0", "snapshot_id");
        if(decision_time <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "decision_time must be > 0", "decision_time");
        return ValidationResult::Ok();
    }
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

    /**
     * @brief Validate the order request.
     * @return ValidationResult.
     *
     * Invariants:
     *   - request_id not empty
     *   - decision_id not empty
     *   - symbol not empty
     *   - direction valid (BUY or SELL, not NONE for a real order)
     *   - volume > 0 (normalized, positive)
     *   - entry_price > 0 (normalized, positive)
     *   - stop_loss >= 0 (0 = none)
     *   - take_profit >= 0 (0 = none)
     *   - magic_number != 0
     *   - snapshot_id > 0
     *   - all doubles are valid numbers
     */
    ValidationResult Validate(void) const
    {
        if(StringLen(request_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "request_id is empty", "request_id");
        if(StringLen(decision_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "decision_id is empty", "decision_id");
        if(StringLen(symbol) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "symbol is empty", "symbol");
        if(direction != ATLAS_ORDER_BUY && direction != ATLAS_ORDER_SELL)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "direction must be BUY(1) or SELL(-1)", "direction");
        if(!MathIsValidNumber(volume))
            return ValidationResult::Fail(ATLAS_V_NAN, "volume is NaN/INF", "volume");
        if(!MathIsValidNumber(entry_price))
            return ValidationResult::Fail(ATLAS_V_NAN, "entry_price is NaN/INF", "entry_price");
        if(!MathIsValidNumber(stop_loss))
            return ValidationResult::Fail(ATLAS_V_NAN, "stop_loss is NaN/INF", "stop_loss");
        if(!MathIsValidNumber(take_profit))
            return ValidationResult::Fail(ATLAS_V_NAN, "take_profit is NaN/INF", "take_profit");
        if(volume <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "volume must be > 0", "volume");
        if(entry_price <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "entry_price must be > 0", "entry_price");
        if(stop_loss < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "stop_loss must be >= 0", "stop_loss");
        if(take_profit < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "take_profit must be >= 0", "take_profit");
        if(magic_number == 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "magic_number must be != 0", "magic_number");
        if(snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_id must be > 0", "snapshot_id");
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_RISK_DECISION_MQH
//+------------------------------------------------------------------+
