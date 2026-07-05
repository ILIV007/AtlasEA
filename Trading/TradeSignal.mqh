//+------------------------------------------------------------------+
//|                     Trading/TradeSignal.mqh                      |
//|       AtlasEA v0.2.0 - Trade Signal DTO (Immutable)              |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_SIGNAL_MQH
#define ATLAS_TRADE_SIGNAL_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"

/**
 * @brief Trade signal source.
 * Identifies what produced the signal.
 */
#define ATLAS_SIGNAL_SOURCE_STRATEGY   1
#define ATLAS_SIGNAL_SOURCE_MANUAL     2
#define ATLAS_SIGNAL_SOURCE_RECOVERY   3

/**
 * @struct TradeSignal
 * @brief Pure immutable Data Transfer Object representing a trading signal.
 *
 * A TradeSignal is the INPUT to the trade lifecycle. It is created by a
 * strategy (or manually) and never mutated after creation. All fields are
 * set at construction time via the constructor.
 *
 * The signal contains ONLY the strategy's intent:
 *   - Direction (buy/sell)
 *   - Confidence (0..1)
 *   - Strategy identity
 *   - Desired entry price
 *   - Stop loss and take profit
 *   - Timestamp
 *
 * The signal does NOT contain:
 *   - Volume (computed by risk/position sizing)
 *   - Order type (determined by entry manager)
 *   - Request ID (assigned by entry manager)
 *   - Broker-specific fields
 *
 * Immutability: there are no setter methods. Once constructed, the signal
 * cannot be changed. This guarantees that the signal validated at the
 * start of the lifecycle is the same signal processed at every subsequent
 * stage.
 *
 * Memory: fixed-size struct (~200 bytes). No dynamic allocation.
 */
struct TradeSignal
{
    //=== Identity ===
    string   signal_id;          ///< Unique signal identifier (e.g., "SIG_12345")
    int      strategy_id;        ///< Producing strategy ID
    string   strategy_version;   ///< Producing strategy version
    int      source;             ///< ATLAS_SIGNAL_SOURCE_*

    //=== Direction + confidence ===
    int      direction;          ///< ATLAS_ORDER_BUY (1) or ATLAS_ORDER_SELL (-1)
    double   confidence;         ///< [0.0, 1.0]

    //=== Price levels ===
    double   entry_price;        ///< Desired entry price (0 = market)
    double   stop_loss;          ///< Stop loss price (must be > 0)
    double   take_profit;        ///< Take profit price (must be > 0)

    //=== Timing ===
    datetime timestamp;          ///< When the signal was generated
    long     snapshot_id;        ///< Market snapshot when signal was generated

    //=== Optional metadata ===
    string   comment;            ///< Free-text comment from strategy

    /**
     * @brief Default constructor — produces an empty signal.
     * Used for array declarations. Use the parameterized constructor
     * for real signals.
     */
    TradeSignal(void)
    {
        signal_id       = "";
        strategy_id     = 0;
        strategy_version = "";
        source          = ATLAS_SIGNAL_SOURCE_STRATEGY;
        direction       = ATLAS_ORDER_NONE;
        confidence      = 0.0;
        entry_price     = 0.0;
        stop_loss       = 0.0;
        take_profit     = 0.0;
        timestamp       = 0;
        snapshot_id     = 0;
        comment         = "";
    }

    /**
     * @brief Construct a fully-populated signal.
     *
     * @param id         Unique signal ID.
     * @param strat_id   Strategy ID.
     * @param strat_ver  Strategy version string.
     * @param dir        Direction (ATLAS_ORDER_BUY or ATLAS_ORDER_SELL).
     * @param conf       Confidence [0, 1].
     * @param entry      Entry price (0 for market order).
     * @param sl         Stop loss price.
     * @param tp         Take profit price.
     * @param ts         Signal timestamp.
     * @param snap       Snapshot ID when signal was generated.
     * @param cmt        Optional comment.
     * @param src        Signal source (default: STRATEGY).
     */
    TradeSignal(const string id,
                const int strat_id,
                const string strat_ver,
                const int dir,
                const double conf,
                const double entry,
                const double sl,
                const double tp,
                const datetime ts,
                const long snap,
                const string cmt = "",
                const int src = ATLAS_SIGNAL_SOURCE_STRATEGY)
    {
        signal_id        = id;
        strategy_id      = strat_id;
        strategy_version = strat_ver;
        source           = src;
        direction        = dir;
        confidence       = conf;
        entry_price      = entry;
        stop_loss        = sl;
        take_profit      = tp;
        timestamp        = ts;
        snapshot_id      = snap;
        comment          = cmt;
    }

    /**
     * @brief Validate the signal's structural integrity.
     *
     * This is a STRUCTURAL validation only — it checks that all fields
     * are within valid ranges and internally consistent. It does NOT
     * check broker constraints (stops level, volume min/max) or risk
     * constraints (exposure, drawdown). Those are checked by the
     * TradeEntryManager and RiskEngine respectively.
     *
     * @return ValidationResult.
     *
     * Invariants:
     *   - signal_id not empty
     *   - strategy_id > 0
     *   - direction is BUY or SELL (not NONE)
     *   - confidence in [0, 1]
     *   - stop_loss > 0
     *   - take_profit > 0
     *   - entry_price >= 0 (0 = market order)
     *   - timestamp > 0
     *   - snapshot_id > 0
     *   - for BUY: take_profit > entry_price > stop_loss (if entry > 0)
     *   - for SELL: stop_loss > entry_price > take_profit (if entry > 0)
     *   - all doubles are valid numbers (not NaN/INF)
     */
    ValidationResult Validate(void) const
    {
        //--- Identity
        if(StringLen(signal_id) == 0)
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "signal_id is empty", "signal_id");
        if(strategy_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "strategy_id must be > 0", "strategy_id");

        //--- Direction
        if(direction != ATLAS_ORDER_BUY && direction != ATLAS_ORDER_SELL)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "direction must be BUY(1) or SELL(-1)", "direction");

        //--- Confidence
        if(!MathIsValidNumber(confidence))
            return ValidationResult::Fail(ATLAS_V_NAN,
                "confidence is NaN/INF", "confidence");
        if(confidence < 0.0 || confidence > 1.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "confidence must be in [0, 1]", "confidence");

        //--- Prices
        if(!MathIsValidNumber(entry_price))
            return ValidationResult::Fail(ATLAS_V_NAN,
                "entry_price is NaN/INF", "entry_price");
        if(!MathIsValidNumber(stop_loss))
            return ValidationResult::Fail(ATLAS_V_NAN,
                "stop_loss is NaN/INF", "stop_loss");
        if(!MathIsValidNumber(take_profit))
            return ValidationResult::Fail(ATLAS_V_NAN,
                "take_profit is NaN/INF", "take_profit");
        if(entry_price < 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "entry_price must be >= 0 (0 = market)", "entry_price");
        if(stop_loss <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "stop_loss must be > 0", "stop_loss");
        if(take_profit <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "take_profit must be > 0", "take_profit");

        //--- Timing
        if(timestamp <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "timestamp must be > 0", "timestamp");
        if(snapshot_id <= 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "snapshot_id must be > 0", "snapshot_id");

        //--- Directional consistency (only if entry price is specified)
        if(entry_price > 0.0)
        {
            if(direction == ATLAS_ORDER_BUY)
            {
                //--- BUY: TP above entry, SL below entry
                if(take_profit <= entry_price)
                    return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                        "BUY: take_profit must be > entry_price", "take_profit");
                if(stop_loss >= entry_price)
                    return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                        "BUY: stop_loss must be < entry_price", "stop_loss");
            }
            else // ATLAS_ORDER_SELL
            {
                //--- SELL: SL above entry, TP below entry
                if(stop_loss <= entry_price)
                    return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                        "SELL: stop_loss must be > entry_price", "stop_loss");
                if(take_profit >= entry_price)
                    return ValidationResult::Fail(ATLAS_V_INCONSISTENT,
                        "SELL: take_profit must be < entry_price", "take_profit");
            }
        }

        return ValidationResult::Ok();
    }

    /**
     * @brief Check if this is a market order (entry_price == 0).
     */
    bool IsMarketOrder(void) const { return entry_price <= 0.0; }

    /**
     * @brief Check if this is a limit order (entry_price > 0).
     */
    bool IsLimitOrder(void) const { return entry_price > 0.0; }
};

#endif // ATLAS_TRADE_SIGNAL_MQH
//+------------------------------------------------------------------+
