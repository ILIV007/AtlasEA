//+------------------------------------------------------------------+
//|                                          Contracts/MarketState.mqh|
//|                            AtlasEA v1.1 - Market Data Contracts  |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_STATE_MQH
#define ATLAS_MARKET_STATE_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"

//+------------------------------------------------------------------+
//| RawTick - normalized broker tick                                 |
//+------------------------------------------------------------------+
struct RawTick
{
    double   bid;
    double   ask;
    double   last;
    long     volume;
    datetime timestamp;

    /**
     * @brief Validate the raw tick.
     * @return ValidationResult.
     *
     * Invariants:
     *   - bid > 0, ask > 0
     *   - ask >= bid
     *   - timestamp > 0
     *   - bid/ask/last are valid numbers (not NaN/INF)
     */
    ValidationResult Validate(void) const
    {
        if(!MathIsValidNumber(bid))
            return ValidationResult::Fail(ATLAS_V_NAN, "bid is NaN/INF", "bid");
        if(!MathIsValidNumber(ask))
            return ValidationResult::Fail(ATLAS_V_NAN, "ask is NaN/INF", "ask");
        if(bid <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE, "bid must be > 0", "bid");
        if(ask <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE, "ask must be > 0", "ask");
        if(ask < bid)
            return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                "ask < bid (inverted spread)", "ask");
        if(timestamp <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "timestamp must be > 0", "timestamp");
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| MarketState - immutable market snapshot (per snapshot_id)        |
//+------------------------------------------------------------------+
struct MarketState
{
    long     snapshot_id;
    datetime timestamp;
    string   symbol;

    double   bid;
    double   ask;
    double   last;
    double   spread;
    double   point;
    int      digits;

    long     tick_volume;
    long     bar_volume;
    long     real_volume;

    double   atr_14;
    double   volatility_index;
    bool     is_fast_market;

    int      trend_direction;     // -1, 0, 1
    int      trend_strength;      // 0..100
    int      trend_duration_bars;

    double   open;
    double   high;
    double   low;
    double   close;
    datetime bar_time;
    int      session_state;

    double   features[ATLAS_FEATURE_SIZE];
    int      feature_count;

    bool     is_valid;
    string   invalid_reason;

    /**
     * @brief Validate the market state against all invariants.
     * @return ValidationResult.
     *
     * Invariants:
     *   - symbol not empty
     *   - bid > 0, ask > 0
     *   - ask >= bid (spread >= 0)
     *   - spread >= 0
     *   - digits valid (0..8)
     *   - point > 0
     *   - snapshot_id > 0 (if state is marked valid)
     *   - trend_direction in {-1, 0, 1}
     *   - trend_strength in [0, 100]
     *   - feature_count in [0, ATLAS_FEATURE_SIZE]
     *   - all doubles are valid numbers (not NaN/INF)
     *   - OHLC consistency: high >= max(open,close,low), low <= min(open,close,high)
     */
    ValidationResult Validate(void) const
    {
        //--- Symbol
        if(StringLen(symbol) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "symbol is empty", "symbol");

        //--- Numeric validity
        if(!MathIsValidNumber(bid))
            return ValidationResult::Fail(ATLAS_V_NAN, "bid is NaN/INF", "bid");
        if(!MathIsValidNumber(ask))
            return ValidationResult::Fail(ATLAS_V_NAN, "ask is NaN/INF", "ask");
        if(!MathIsValidNumber(spread))
            return ValidationResult::Fail(ATLAS_V_NAN, "spread is NaN/INF", "spread");
        if(!MathIsValidNumber(point))
            return ValidationResult::Fail(ATLAS_V_NAN, "point is NaN/INF", "point");
        if(!MathIsValidNumber(atr_14))
            return ValidationResult::Fail(ATLAS_V_NAN, "atr_14 is NaN/INF", "atr_14");
        if(!MathIsValidNumber(open))
            return ValidationResult::Fail(ATLAS_V_NAN, "open is NaN/INF", "open");
        if(!MathIsValidNumber(high))
            return ValidationResult::Fail(ATLAS_V_NAN, "high is NaN/INF", "high");
        if(!MathIsValidNumber(low))
            return ValidationResult::Fail(ATLAS_V_NAN, "low is NaN/INF", "low");
        if(!MathIsValidNumber(close))
            return ValidationResult::Fail(ATLAS_V_NAN, "close is NaN/INF", "close");

        //--- Positive prices
        if(bid <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "bid must be > 0", "bid");
        if(ask <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "ask must be > 0", "ask");

        //--- Spread consistency: ask >= bid
        if(ask < bid)
            return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                "ask < bid (inverted spread)", "ask");

        //--- Spread >= 0
        if(spread < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "spread must be >= 0", "spread");

        //--- Digits
        if(digits < 0 || digits > 8)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "digits must be in [0, 8]", "digits");

        //--- Point
        if(point <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "point must be > 0", "point");

        //--- Snapshot ID (only enforced if state claims to be valid)
        if(is_valid && snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "is_valid=true but snapshot_id <= 0", "snapshot_id");

        //--- Trend direction
        if(trend_direction < -1 || trend_direction > 1)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "trend_direction must be in {-1, 0, 1}", "trend_direction");

        //--- Trend strength
        if(trend_strength < 0 || trend_strength > 100)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "trend_strength must be in [0, 100]", "trend_strength");

        //--- Feature count
        if(feature_count < 0 || feature_count > ATLAS_FEATURE_SIZE)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "feature_count must be in [0, ATLAS_FEATURE_SIZE]", "feature_count");

        //--- OHLC consistency (only if bar_time > 0, meaning a bar exists)
        if(bar_time > 0)
        {
            if(high < open || high < close || high < low)
                return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                    "high < one of O/C/L", "high");
            if(low > open || low > close || low > high)
                return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                    "low > one of O/C/H", "low");
        }

        return ValidationResult::Ok();
    }
};

#endif // ATLAS_MARKET_STATE_MQH
//+------------------------------------------------------------------+
