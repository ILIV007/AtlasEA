//+------------------------------------------------------------------+
//|                    Trading/Filters/FilterResult.mqh              |
//|       AtlasEA v0.2.2 - Filter Result + Reason Codes              |
//+------------------------------------------------------------------+
#ifndef ATLAS_FILTER_RESULT_MQH
#define ATLAS_FILTER_RESULT_MQH

#include "../../Config/Settings.mqh"

/**
 * @brief Filter verdict codes.
 * Every filter returns exactly one of these.
 */
#define ATLAS_FILTER_PASS    0   ///< Signal passes this filter
#define ATLAS_FILTER_BLOCK   1   ///< Signal is blocked (rejected)
#define ATLAS_FILTER_SKIP    2   ///< Filter disabled or not applicable

/**
 * @brief Filter reason codes.
 * Precise reason for a BLOCK or SKIP verdict.
 * Grouped by filter type for readability.
 */
//--- General (0-9)
#define ATLAS_FR_OK                      0   ///< No issue (PASS)
#define ATLAS_FR_FILTER_DISABLED         1   ///< Filter is disabled (SKIP)
#define ATLAS_FR_NO_MARKET_DATA          2   ///< Market state not available
#define ATLAS_FR_NO_CONTEXT              3   ///< Context store not available

//--- SpreadFilter (10-19)
#define ATLAS_FR_SPREAD_TOO_HIGH         10  ///< Spread exceeds configured max
#define ATLAS_FR_SPREAD_INVALID          11  ///< Spread is NaN or negative

//--- SessionFilter (20-29)
#define ATLAS_FR_SESSION_CLOSED          20  ///< Outside all allowed sessions
#define ATLAS_FR_SESSION_WEEKEND         21  ///< Weekend (no trading)

//--- VolatilityFilter (30-39)
#define ATLAS_FR_VOLATILITY_TOO_LOW      30  ///< Volatility below minimum
#define ATLAS_FR_VOLATILITY_TOO_HIGH     31  ///< Volatility above maximum (abnormal spike)
#define ATLAS_FR_VOLATILITY_INVALID      32  ///< Volatility index is NaN

//--- MarketStateFilter (40-49)
#define ATLAS_FR_REGIME_NOT_ALLOWED      40  ///< Current market regime not in allowed list
#define ATLAS_FR_REGIME_UNKNOWN          41  ///< Regime could not be determined

//--- CooldownFilter (50-59)
#define ATLAS_FR_COOLDOWN_GLOBAL         50  ///< Global cooldown active
#define ATLAS_FR_COOLDOWN_STRATEGY       51  ///< Strategy-specific cooldown active
#define ATLAS_FR_COOLDOWN_SYMBOL         52  ///< Symbol-specific cooldown active

//--- MaxTradesFilter (60-69)
#define ATLAS_FR_MAX_TOTAL_POSITIONS     60  ///< Maximum total positions reached
#define ATLAS_FR_MAX_SYMBOL_POSITIONS    61  ///< Maximum positions for this symbol reached
#define ATLAS_FR_MAX_STRATEGY_POSITIONS  62  ///< Maximum positions for this strategy reached

//--- TradingPermissionFilter (70-79)
#define ATLAS_FR_AUTOTRADING_DISABLED    70  ///< AutoTrading not enabled
#define ATLAS_FR_MARKET_CLOSED           71  ///< Market is closed
#define ATLAS_FR_SYMBOL_NOT_TRADABLE     72  ///< Symbol is not tradable
#define ATLAS_FR_BROKER_RESTRICTION      73  ///< Broker restriction (margin mode, etc.)

/**
 * @struct FilterResult
 * @brief The result returned by every filter's Evaluate() method.
 *
 * Fields:
 *   - verdict: PASS, BLOCK, or SKIP
 *   - reason_code: ATLAS_FR_* (precise reason for BLOCK or SKIP)
 *   - reason_text: human-readable description
 *   - filter_name: name of the filter that produced this result
 */
struct FilterResult
{
    int    verdict;         ///< ATLAS_FILTER_PASS / BLOCK / SKIP
    int    reason_code;     ///< ATLAS_FR_*
    string reason_text;     ///< Human-readable detail
    string filter_name;     ///< Name of the producing filter

    /**
     * @brief Default constructor — produces a PASS result.
     */
    FilterResult(void)
    {
        verdict      = ATLAS_FILTER_PASS;
        reason_code  = ATLAS_FR_OK;
        reason_text  = "";
        filter_name  = "";
    }

    /**
     * @brief Create a PASS result.
     */
    static FilterResult Pass(const string filter_name)
    {
        FilterResult r;
        r.verdict     = ATLAS_FILTER_PASS;
        r.reason_code = ATLAS_FR_OK;
        r.filter_name = filter_name;
        return r;
    }

    /**
     * @brief Create a BLOCK result with a reason.
     */
    static FilterResult Block(const string filter_name,
                               const int reason_code,
                               const string reason_text)
    {
        FilterResult r;
        r.verdict      = ATLAS_FILTER_BLOCK;
        r.reason_code  = reason_code;
        r.reason_text  = reason_text;
        r.filter_name  = filter_name;
        return r;
    }

    /**
     * @brief Create a SKIP result (filter disabled or not applicable).
     */
    static FilterResult Skip(const string filter_name,
                              const int reason_code,
                              const string reason_text)
    {
        FilterResult r;
        r.verdict      = ATLAS_FILTER_SKIP;
        r.reason_code  = reason_code;
        r.reason_text  = reason_text;
        r.filter_name  = filter_name;
        return r;
    }

    /**
     * @brief Check if the signal passed this filter.
     */
    bool Passed(void) const { return verdict == ATLAS_FILTER_PASS; }

    /**
     * @brief Check if the signal was blocked.
     */
    bool Blocked(void) const { return verdict == ATLAS_FILTER_BLOCK; }

    /**
     * @brief Check if the filter was skipped.
     */
    bool Skipped(void) const { return verdict == ATLAS_FILTER_SKIP; }

    /**
     * @brief Format for logging.
     */
    string Summary(void) const
    {
        string v;
        switch(verdict)
        {
            case ATLAS_FILTER_PASS:  v = "PASS";  break;
            case ATLAS_FILTER_BLOCK: v = "BLOCK"; break;
            case ATLAS_FILTER_SKIP:  v = "SKIP";  break;
            default:                 v = "UNKNOWN"; break;
        }
        string s = v + " [" + filter_name + "] code=" + IntegerToString(reason_code);
        if(StringLen(reason_text) > 0) s += " " + reason_text;
        return s;
    }
};

/**
 * @brief Get the name of a reason code.
 */
string FilterReasonName(const int code)
{
    switch(code)
    {
        //--- General
        case ATLAS_FR_OK:                  return "OK";
        case ATLAS_FR_FILTER_DISABLED:     return "FILTER_DISABLED";
        case ATLAS_FR_NO_MARKET_DATA:      return "NO_MARKET_DATA";
        case ATLAS_FR_NO_CONTEXT:          return "NO_CONTEXT";
        //--- Spread
        case ATLAS_FR_SPREAD_TOO_HIGH:     return "SPREAD_TOO_HIGH";
        case ATLAS_FR_SPREAD_INVALID:      return "SPREAD_INVALID";
        //--- Session
        case ATLAS_FR_SESSION_CLOSED:      return "SESSION_CLOSED";
        case ATLAS_FR_SESSION_WEEKEND:     return "SESSION_WEEKEND";
        //--- Volatility
        case ATLAS_FR_VOLATILITY_TOO_LOW:  return "VOLATILITY_TOO_LOW";
        case ATLAS_FR_VOLATILITY_TOO_HIGH: return "VOLATILITY_TOO_HIGH";
        case ATLAS_FR_VOLATILITY_INVALID:  return "VOLATILITY_INVALID";
        //--- MarketState
        case ATLAS_FR_REGIME_NOT_ALLOWED:  return "REGIME_NOT_ALLOWED";
        case ATLAS_FR_REGIME_UNKNOWN:      return "REGIME_UNKNOWN";
        //--- Cooldown
        case ATLAS_FR_COOLDOWN_GLOBAL:     return "COOLDOWN_GLOBAL";
        case ATLAS_FR_COOLDOWN_STRATEGY:   return "COOLDOWN_STRATEGY";
        case ATLAS_FR_COOLDOWN_SYMBOL:     return "COOLDOWN_SYMBOL";
        //--- MaxTrades
        case ATLAS_FR_MAX_TOTAL_POSITIONS:    return "MAX_TOTAL_POSITIONS";
        case ATLAS_FR_MAX_SYMBOL_POSITIONS:   return "MAX_SYMBOL_POSITIONS";
        case ATLAS_FR_MAX_STRATEGY_POSITIONS: return "MAX_STRATEGY_POSITIONS";
        //--- TradingPermission
        case ATLAS_FR_AUTOTRADING_DISABLED: return "AUTOTRADING_DISABLED";
        case ATLAS_FR_MARKET_CLOSED:        return "MARKET_CLOSED";
        case ATLAS_FR_SYMBOL_NOT_TRADABLE:  return "SYMBOL_NOT_TRADABLE";
        case ATLAS_FR_BROKER_RESTRICTION:   return "BROKER_RESTRICTION";
    }
    return "UNKNOWN";
}

#endif // ATLAS_FILTER_RESULT_MQH
//+------------------------------------------------------------------+
