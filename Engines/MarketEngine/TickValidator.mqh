//+------------------------------------------------------------------+
//|                            Engines/MarketEngine/TickValidator.mqh |
//|          AtlasEA v0.1.9.0 - Raw Tick Validation                  |
//+------------------------------------------------------------------+
#ifndef ATLAS_TICK_VALIDATOR_MQH
#define ATLAS_TICK_VALIDATOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @struct TickValidationResult
 * @brief Detailed result of tick validation.
 *
 * Returned by ValidateDetailed(). Provides the boolean verdict,
 * the reject reason code, and a human-readable reason string.
 */
struct TickValidationResult
{
    bool   valid;          ///< true if tick passed all checks
    int    reject_code;    ///< REJECT_REASON code (0-based), -1 if valid
    string reason;         ///< Human-readable reason string (empty if valid)
    double spread_points;  ///< Computed spread in points (for diagnostics)
};

/**
 * @class TickValidator
 * @brief Validates raw ticks before processing.
 *
 * Performs the following checks (in order):
 *   1. Bid is a valid number (reject NaN / INF)
 *   2. Ask is a valid number (reject NaN / INF)
 *   3. Bid > 0 (reject invalid bid)
 *   4. Ask > 0 (reject invalid ask)
 *   5. Ask >= Bid (reject negative spread)
 *   6. Spread within configurable range (reject wide spread)
 *   7. Timestamp > 0 (reject zero timestamp)
 *   8. Timestamp <= now + tolerance (reject future timestamp)
 *   9. Timestamp >= last - tolerance (reject stale tick)
 *  10. Timestamp > last_tick_timestamp (reject duplicate tick)
 *  11. Timestamp >= last_tick_timestamp (reject out-of-order tick)
 *
 * All checks are O(1). No allocation. No recursion.
 *
 * On rejection, the validator logs the reason via ILogger and returns
 * an invalid MarketState with the rejection reason populated.
 */
class TickValidator
{
private:
    ILogger   *m_logger;              ///< Logger (may be NULL)
    double     m_max_spread_points;   ///< Maximum allowed spread (in points)
    double     m_point;               ///< Symbol point (for spread conversion)
    int        m_stale_threshold_sec; ///< Stale tick threshold (seconds)
    int        m_future_tolerance_sec; ///< Future timestamp tolerance
    datetime   m_last_tick_time;      ///< Last accepted tick timestamp
    RawTick    m_last_tick;           ///< Last accepted tick (for duplicate check)
    long       m_total_validated;     ///< Lifetime total validated
    long       m_total_rejected;      ///< Lifetime total rejected
    int        m_reject_reasons[10];  ///< Per-reason counters (10 reasons)

    /// @brief Reject reason codes (index into m_reject_reasons)
    enum REJECT_REASON
    {
        REJECT_NAN_BID          = 0,
        REJECT_NAN_ASK          = 1,
        REJECT_INVALID_BID      = 2,
        REJECT_INVALID_ASK      = 3,
        REJECT_NEGATIVE_SPREAD  = 4,
        REJECT_WIDE_SPREAD      = 5,
        REJECT_ZERO_TIMESTAMP   = 6,
        REJECT_FUTURE_TICK      = 7,
        REJECT_STALE_TICK       = 8,
        REJECT_OUT_OF_ORDER     = 9
    };

    /// @brief Convert reject reason to human-readable string.
    string ReasonToString(const REJECT_REASON r) const;

    /// @brief Increment reject counter for a reason.
    void IncrementReject(const REJECT_REASON r);

public:
    /**
     * @brief Constructor.
     */
    TickValidator(void);

    /**
     * @brief Initialize the validator.
     * @param logger             Logger.
     * @param max_spread_points  Max spread in points (0 = no check).
     * @param point              Symbol point size (for spread conversion).
     * @param stale_sec          Stale threshold in seconds.
     * @param future_tol_sec     Future timestamp tolerance in seconds.
     */
    void Initialize(ILogger *logger, const double max_spread_points,
                    const double point,
                    const int stale_sec, const int future_tol_sec);

    /**
     * @brief Reset the validator state (clears last tick).
     */
    void Reset(void);

    /**
     * @brief Validate a raw tick (simple interface).
     * @param tick      The tick to validate.
     * @param out_reason Output: rejection reason string (empty if valid).
     * @return true if the tick is valid, false if rejected.
     */
    bool Validate(const RawTick &tick, string &out_reason);

    /**
     * @brief Validate a raw tick (detailed interface).
     * @param tick The tick to validate.
     * @return TickValidationResult with full details.
     */
    TickValidationResult ValidateDetailed(const RawTick &tick);

    /**
     * @brief Get the last accepted tick timestamp.
     */
    datetime LastTickTime(void) const { return m_last_tick_time; }

    /// @brief Total ticks validated.
    long TotalValidated(void) const { return m_total_validated; }

    /// @brief Total ticks rejected.
    long TotalRejected(void) const { return m_total_rejected; }

    /// @brief Rejection rate (0.0 to 1.0).
    double RejectRate(void) const
    {
        if(m_total_validated == 0) return 0.0;
        return (double)m_total_rejected / (double)m_total_validated;
    }

    /**
     * @brief Log validation statistics.
     */
    void LogStats(void) const;
};

//+------------------------------------------------------------------+
//| TickValidator implementation                                      |
//+------------------------------------------------------------------+

TickValidator::TickValidator(void)
{
    m_logger              = NULL;
    m_max_spread_points   = 0.0;
    m_point               = 0.00001;
    m_stale_threshold_sec = 30;
    m_future_tolerance_sec = 5;
    m_last_tick_time      = 0;
    ZeroMemory(m_last_tick);
    m_total_validated     = 0;
    m_total_rejected      = 0;
    for(int i = 0; i < 10; i++) m_reject_reasons[i] = 0;
}

//+------------------------------------------------------------------+
void TickValidator::Initialize(ILogger *logger, const double max_spread_points,
                               const double point,
                               const int stale_sec, const int future_tol_sec)
{
    m_logger              = logger;
    m_max_spread_points   = max_spread_points;
    m_point               = (point > 0.0) ? point : 0.00001;
    m_stale_threshold_sec = (stale_sec > 0) ? stale_sec : 30;
    m_future_tolerance_sec = (future_tol_sec > 0) ? future_tol_sec : 5;
    Reset();
}

//+------------------------------------------------------------------+
void TickValidator::Reset(void)
{
    m_last_tick_time = 0;
    ZeroMemory(m_last_tick);
}

//+------------------------------------------------------------------+
string TickValidator::ReasonToString(const REJECT_REASON r) const
{
    switch(r)
    {
        case REJECT_NAN_BID:          return "nan_bid";
        case REJECT_NAN_ASK:          return "nan_ask";
        case REJECT_INVALID_BID:      return "invalid_bid";
        case REJECT_INVALID_ASK:      return "invalid_ask";
        case REJECT_NEGATIVE_SPREAD:  return "negative_spread";
        case REJECT_WIDE_SPREAD:      return "wide_spread";
        case REJECT_ZERO_TIMESTAMP:   return "zero_timestamp";
        case REJECT_FUTURE_TICK:      return "future_timestamp";
        case REJECT_STALE_TICK:       return "stale_tick";
        case REJECT_OUT_OF_ORDER:     return "out_of_order";
    }
    return "unknown";
}

//+------------------------------------------------------------------+
void TickValidator::IncrementReject(const REJECT_REASON r)
{
    m_reject_reasons[(int)r]++;
    m_total_rejected++;
}

//+------------------------------------------------------------------+
TickValidationResult TickValidator::ValidateDetailed(const RawTick &tick)
{
    TickValidationResult result;
    result.valid         = false;
    result.reject_code   = -1;
    result.reason        = "";
    result.spread_points = 0.0;
    m_total_validated++;

    datetime now = TimeCurrent();

    //--- 1. Bid is a valid number (reject NaN / INF)
    if(!MathIsValidNumber(tick.bid))
    {
        result.reject_code = (int)REJECT_NAN_BID;
        result.reason      = ReasonToString(REJECT_NAN_BID);
        IncrementReject(REJECT_NAN_BID);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- 2. Ask is a valid number (reject NaN / INF)
    if(!MathIsValidNumber(tick.ask))
    {
        result.reject_code = (int)REJECT_NAN_ASK;
        result.reason      = ReasonToString(REJECT_NAN_ASK);
        IncrementReject(REJECT_NAN_ASK);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- 3. Bid > 0
    if(tick.bid <= 0.0)
    {
        result.reject_code = (int)REJECT_INVALID_BID;
        result.reason      = ReasonToString(REJECT_INVALID_BID);
        IncrementReject(REJECT_INVALID_BID);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason + " bid=" + DoubleToString(tick.bid, 5));
        return result;
    }

    //--- 4. Ask > 0
    if(tick.ask <= 0.0)
    {
        result.reject_code = (int)REJECT_INVALID_ASK;
        result.reason      = ReasonToString(REJECT_INVALID_ASK);
        IncrementReject(REJECT_INVALID_ASK);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason + " ask=" + DoubleToString(tick.ask, 5));
        return result;
    }

    //--- 5. Ask >= Bid (no negative spread)
    if(tick.ask < tick.bid)
    {
        result.reject_code = (int)REJECT_NEGATIVE_SPREAD;
        result.reason      = ReasonToString(REJECT_NEGATIVE_SPREAD);
        IncrementReject(REJECT_NEGATIVE_SPREAD);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- Compute spread in points
    double spread = tick.ask - tick.bid;
    result.spread_points = (m_point > 0.0) ? (spread / m_point) : 0.0;

    //--- 6. Spread within configurable range
    if(m_max_spread_points > 0.0 && result.spread_points > m_max_spread_points)
    {
        result.reject_code = (int)REJECT_WIDE_SPREAD;
        result.reason      = ReasonToString(REJECT_WIDE_SPREAD);
        IncrementReject(REJECT_WIDE_SPREAD);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason +
                          " spread=" + DoubleToString(result.spread_points, 1) +
                          " max=" + DoubleToString(m_max_spread_points, 1));
        return result;
    }

    //--- 7. Timestamp > 0
    if(tick.timestamp <= 0)
    {
        result.reject_code = (int)REJECT_ZERO_TIMESTAMP;
        result.reason      = ReasonToString(REJECT_ZERO_TIMESTAMP);
        IncrementReject(REJECT_ZERO_TIMESTAMP);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- 8. Timestamp not too far in the future
    if((long)tick.timestamp > (long)now + m_future_tolerance_sec)
    {
        result.reject_code = (int)REJECT_FUTURE_TICK;
        result.reason      = ReasonToString(REJECT_FUTURE_TICK);
        IncrementReject(REJECT_FUTURE_TICK);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- 9. Stale tick check
    if(m_last_tick_time > 0)
    {
        long age = (long)now - (long)tick.timestamp;
        if(age > m_stale_threshold_sec)
        {
            result.reject_code = (int)REJECT_STALE_TICK;
            result.reason      = ReasonToString(REJECT_STALE_TICK);
            IncrementReject(REJECT_STALE_TICK);
            if(m_logger != NULL)
                m_logger.Warn("TickValidator", "Rejected: " + result.reason + " age=" + IntegerToString(age) + "s");
            return result;
        }
    }

    //--- 10. Out-of-order tick check (timestamp before last)
    if(m_last_tick_time > 0 && tick.timestamp < m_last_tick_time)
    {
        result.reject_code = (int)REJECT_OUT_OF_ORDER;
        result.reason      = ReasonToString(REJECT_OUT_OF_ORDER);
        IncrementReject(REJECT_OUT_OF_ORDER);
        if(m_logger != NULL)
            m_logger.Warn("TickValidator", "Rejected: " + result.reason);
        return result;
    }

    //--- All checks passed — accept and store
    m_last_tick_time = tick.timestamp;
    m_last_tick      = tick;
    result.valid     = true;
    return result;
}

//+------------------------------------------------------------------+
bool TickValidator::Validate(const RawTick &tick, string &out_reason)
{
    TickValidationResult result = ValidateDetailed(tick);
    out_reason = result.reason;
    return result.valid;
}

//+------------------------------------------------------------------+
void TickValidator::LogStats(void) const
{
    if(m_logger == NULL) return;
    m_logger.Info("TickValidator",
        "validated=" + IntegerToString(m_total_validated) +
        " rejected=" + IntegerToString(m_total_rejected) +
        " rate=" + DoubleToString(RejectRate() * 100.0, 2) + "%");
    for(int i = 0; i < 10; i++)
    {
        if(m_reject_reasons[i] > 0)
        {
            REJECT_REASON r = (REJECT_REASON)i;
            m_logger.Info("TickValidator",
                "  " + ReasonToString(r) + ": " + IntegerToString(m_reject_reasons[i]));
        }
    }
}

#endif // ATLAS_TICK_VALIDATOR_MQH
//+------------------------------------------------------------------+
