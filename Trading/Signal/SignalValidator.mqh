//+------------------------------------------------------------------+
//|                  Trading/Signal/SignalValidator.mqh              |
//|       AtlasEA v0.2.1 - Signal Validation                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_VALIDATOR_MQH
#define ATLAS_SIGNAL_VALIDATOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Core/ValidationResult.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"

/**
 * @brief Signal rejection reasons.
 */
#define ATLAS_SIG_REJECT_NONE              0
#define ATLAS_SIG_REJECT_DUPLICATE         1   ///< Signal ID already seen
#define ATLAS_SIG_REJECT_EXPIRED           2   ///< Signal too old
#define ATLAS_SIG_REJECT_INVALID_SL        3   ///< Stop loss invalid
#define ATLAS_SIG_REJECT_INVALID_TP        4   ///< Take profit invalid
#define ATLAS_SIG_REJECT_INVALID_DIRECTION 5   ///< Direction not BUY/SELL
#define ATLAS_SIG_REJECT_INVALID_CONFIDENCE 6  ///< Confidence out of [0,1]
#define ATLAS_SIG_REJECT_INVALID_PRICE     7   ///< Entry/SL/TP price invalid
#define ATLAS_SIG_REJECT_INVALID_TIMESTAMP 8   ///< Timestamp zero or future
#define ATLAS_SIG_REJECT_INVALID_ID        9   ///< Signal ID empty
#define ATLAS_SIG_REJECT_INVALID_STRATEGY  10  ///< Strategy ID <= 0
#define ATLAS_SIG_REJECT_INCONSISTENT      11  ///< Directional inconsistency

/**
 * @brief Maximum signals remembered for duplicate detection.
 */
#define ATLAS_SIGNAL_DEDUP_SLOTS 64

/**
 * @struct SignalValidationConfig
 * @brief Configuration for signal validation.
 */
struct SignalValidationConfig
{
    int    max_signal_age_sec;     ///< Maximum age (reject stale signals)
    double min_confidence;         ///< Minimum confidence
    double min_stop_loss_points;   ///< Minimum SL distance (0 = skip)
    double min_take_profit_points; ///< Minimum TP distance (0 = skip)
    bool   reject_future_timestamps; ///< Reject signals with future timestamps

    SignalValidationConfig(void)
    {
        max_signal_age_sec      = 300;   // 5 minutes
        min_confidence          = 0.0;   // Accept any (normalizer clamped)
        min_stop_loss_points    = 0.0;   // Skip point check (normalizer enforces)
        min_take_profit_points  = 0.0;
        reject_future_timestamps = true;
    }
};

/**
 * @struct SignalValidationResult
 * @brief Result of signal validation.
 */
struct SignalValidationResult
{
    bool   accepted;     ///< True if signal is valid
    int    reject_reason; ///< ATLAS_SIG_REJECT_* (if rejected)
    string detail;       ///< Human-readable detail

    SignalValidationResult(void)
    {
        accepted      = false;
        reject_reason = ATLAS_SIG_REJECT_NONE;
        detail        = "";
    }
};

/**
 * @class SignalValidator
 * @brief Validates signals and rejects invalid ones.
 *
 * SOLE RESPONSIBILITY: reject invalid signals. Does NOT normalize
 * (that's the normalizer's job) or score (that's the scorer's job).
 *
 * Rejection criteria:
 *   1. Duplicate signal (signal_id already seen — dedup ring)
 *   2. Expired signal (age > max_signal_age_sec)
 *   3. Invalid SL (<= 0, NaN, or wrong side of entry)
 *   4. Invalid TP (<= 0, NaN, or wrong side of entry)
 *   5. Invalid direction (not BUY or SELL)
 *   6. Invalid confidence (out of [0, 1] or NaN)
 *   7. Invalid price (NaN, entry < 0)
 *   8. Invalid timestamp (zero or future)
 *   9. Invalid ID (empty)
 *  10. Invalid strategy ID (<= 0)
 *  11. Directional inconsistency (TP/SL on wrong side for the direction)
 *
 * Duplicate detection: a fixed-size ring of ATLAS_SIGNAL_DEDUP_SLOTS
 * signal IDs. When full, the oldest is evicted (FIFO). This provides
 * bounded-memory dedup for recent signals.
 *
 * Memory: ~8 KB (dedup ring of 64 strings + config + logger).
 */
class SignalValidator
{
private:
    ILogger                *m_logger;
    SignalValidationConfig  m_config;

    //--- Dedup ring (fixed-size, FIFO eviction)
    string m_seen_ids[ATLAS_SIGNAL_DEDUP_SLOTS];
    int    m_seen_count;
    int    m_seen_next;  ///< Next write slot (ring)

    //--- Statistics
    int m_total_validated;
    int m_total_accepted;
    int m_total_rejected;
    int m_reject_counts[12]; ///< By ATLAS_SIG_REJECT_*

public:
    /**
     * @brief Constructor.
     */
    SignalValidator(void)
    {
        m_logger = NULL;
        m_seen_count = 0;
        m_seen_next  = 0;
        m_total_validated = 0;
        m_total_accepted  = 0;
        m_total_rejected  = 0;
        for(int i = 0; i < 12; i++) m_reject_counts[i] = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the validation configuration.
     */
    void SetConfig(const SignalValidationConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const SignalValidationConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Validate a signal.
     *
     * Checks all rejection criteria. If the signal passes, it is
     * recorded in the dedup ring (so future duplicates are caught).
     *
     * @param signal The signal to validate (should be already normalized).
     * @return SignalValidationResult.
     */
    SignalValidationResult Validate(const TradeSignal &signal)
    {
        SignalValidationResult result;
        m_total_validated++;

        //=== 1. Structural validation (delegate to the signal's own Validate) ===
        ValidationResult structural = signal.Validate();
        if(!structural.valid)
        {
            result.reject_reason = MapStructuralCode(structural.code);
            result.detail = structural.Summary();
            RecordRejection(result.reject_reason);
            if(m_logger != NULL)
                m_logger.Warn("SignalValidator",
                    "Rejected " + signal.signal_id + ": " + result.detail);
            return result;
        }

        //=== 2. Duplicate detection ===
        if(IsDuplicate(signal.signal_id))
        {
            result.reject_reason = ATLAS_SIG_REJECT_DUPLICATE;
            result.detail = "Duplicate signal_id: " + signal.signal_id;
            RecordRejection(result.reject_reason);
            if(m_logger != NULL)
                m_logger.Warn("SignalValidator",
                    "Rejected " + signal.signal_id + ": duplicate");
            return result;
        }

        //=== 3. Expired signal ===
        if(m_config.max_signal_age_sec > 0)
        {
            long age = (long)TimeCurrent() - (long)signal.timestamp;
            if(age > m_config.max_signal_age_sec)
            {
                result.reject_reason = ATLAS_SIG_REJECT_EXPIRED;
                result.detail = "Signal age " + IntegerToString(age) +
                                "s exceeds max " +
                                IntegerToString(m_config.max_signal_age_sec) + "s";
                RecordRejection(result.reject_reason);
                if(m_logger != NULL)
                    m_logger.Warn("SignalValidator",
                        "Rejected " + signal.signal_id + ": expired (" +
                        IntegerToString(age) + "s old)");
                return result;
            }
        }

        //=== 4. Future timestamp ===
        if(m_config.reject_future_timestamps && signal.timestamp > TimeCurrent())
        {
            result.reject_reason = ATLAS_SIG_REJECT_INVALID_TIMESTAMP;
            result.detail = "Future timestamp: " +
                            IntegerToString((long)signal.timestamp) +
                            " > " + IntegerToString((long)TimeCurrent());
            RecordRejection(result.reject_reason);
            if(m_logger != NULL)
                m_logger.Warn("SignalValidator",
                    "Rejected " + signal.signal_id + ": future timestamp");
            return result;
        }

        //=== 5. Minimum confidence (post-normalization check) ===
        if(signal.confidence < m_config.min_confidence)
        {
            result.reject_reason = ATLAS_SIG_REJECT_INVALID_CONFIDENCE;
            result.detail = "Confidence " + DoubleToString(signal.confidence, 2) +
                            " below min " + DoubleToString(m_config.min_confidence, 2);
            RecordRejection(result.reject_reason);
            if(m_logger != NULL)
                m_logger.Warn("SignalValidator",
                    "Rejected " + signal.signal_id + ": low confidence");
            return result;
        }

        //=== All checks passed — record in dedup ring ===
        RecordSeen(signal.signal_id);

        result.accepted = true;
        m_total_accepted++;

        if(m_logger != NULL)
            m_logger.Debug("SignalValidator",
                "Accepted " + signal.signal_id);

        return result;
    }

    /**
     * @brief Check if a signal would be accepted (without recording).
     */
    bool WouldAccept(const TradeSignal &signal) const
    {
        //--- Structural
        if(!signal.Validate().valid) return false;
        //--- Duplicate
        if(IsDuplicate(signal.signal_id)) return false;
        //--- Expired
        if(m_config.max_signal_age_sec > 0)
        {
            long age = (long)TimeCurrent() - (long)signal.timestamp;
            if(age > m_config.max_signal_age_sec) return false;
        }
        //--- Future
        if(m_config.reject_future_timestamps && signal.timestamp > TimeCurrent())
            return false;
        //--- Confidence
        if(signal.confidence < m_config.min_confidence) return false;
        return true;
    }

    /**
     * @brief Clear the dedup ring (e.g., on new trading day).
     */
    void ClearDedup(void)
    {
        m_seen_count = 0;
        m_seen_next  = 0;
    }

    /**
     * @brief Reset all statistics.
     */
    void ResetStats(void)
    {
        m_total_validated = 0;
        m_total_accepted  = 0;
        m_total_rejected  = 0;
        for(int i = 0; i < 12; i++) m_reject_counts[i] = 0;
    }

    //=== Statistics accessors ===
    int TotalValidated(void) const { return m_total_validated; }
    int TotalAccepted(void)  const { return m_total_accepted; }
    int TotalRejected(void)  const { return m_total_rejected; }
    int RejectCount(const int reason) const
    {
        if(reason < 0 || reason >= 12) return 0;
        return m_reject_counts[reason];
    }

    /**
     * @brief Get the rejection reason name.
     */
    static string RejectReasonName(const int reason)
    {
        switch(reason)
        {
            case ATLAS_SIG_REJECT_NONE:               return "NONE";
            case ATLAS_SIG_REJECT_DUPLICATE:          return "DUPLICATE";
            case ATLAS_SIG_REJECT_EXPIRED:            return "EXPIRED";
            case ATLAS_SIG_REJECT_INVALID_SL:         return "INVALID_SL";
            case ATLAS_SIG_REJECT_INVALID_TP:         return "INVALID_TP";
            case ATLAS_SIG_REJECT_INVALID_DIRECTION:  return "INVALID_DIRECTION";
            case ATLAS_SIG_REJECT_INVALID_CONFIDENCE: return "INVALID_CONFIDENCE";
            case ATLAS_SIG_REJECT_INVALID_PRICE:      return "INVALID_PRICE";
            case ATLAS_SIG_REJECT_INVALID_TIMESTAMP:  return "INVALID_TIMESTAMP";
            case ATLAS_SIG_REJECT_INVALID_ID:         return "INVALID_ID";
            case ATLAS_SIG_REJECT_INVALID_STRATEGY:   return "INVALID_STRATEGY";
            case ATLAS_SIG_REJECT_INCONSISTENT:       return "INCONSISTENT";
        }
        return "UNKNOWN";
    }

private:
    /**
     * @brief Check if a signal ID has been seen (duplicate detection).
     */
    bool IsDuplicate(const string id) const
    {
        if(StringLen(id) == 0) return false;
        for(int i = 0; i < m_seen_count; i++)
            if(m_seen_ids[i] == id) return true;
        return false;
    }

    /**
     * @brief Record a signal ID in the dedup ring.
     */
    void RecordSeen(const string id)
    {
        m_seen_ids[m_seen_next] = id;
        m_seen_next = (m_seen_next + 1) % ATLAS_SIGNAL_DEDUP_SLOTS;
        if(m_seen_count < ATLAS_SIGNAL_DEDUP_SLOTS) m_seen_count++;
    }

    /**
     * @brief Record a rejection in the statistics.
     */
    void RecordRejection(const int reason)
    {
        m_total_rejected++;
        if(reason >= 0 && reason < 12) m_reject_counts[reason]++;
    }

    /**
     * @brief Map a structural ValidationResult code to a reject reason.
     */
    int MapStructuralCode(const int code) const
    {
        switch(code)
        {
            case ATLAS_V_EMPTY_FIELD:    return ATLAS_SIG_REJECT_INVALID_ID;
            case ATLAS_V_INVALID_RANGE:  return ATLAS_SIG_REJECT_INVALID_PRICE;
            case ATLAS_V_NAN:            return ATLAS_SIG_REJECT_INVALID_PRICE;
            case ATLAS_V_INCONSISTENT:   return ATLAS_SIG_REJECT_INCONSISTENT;
            case ATLAS_V_INVALID_ENUM:   return ATLAS_SIG_REJECT_INVALID_DIRECTION;
        }
        return ATLAS_SIG_REJECT_INVALID_PRICE;
    }
};

#endif // ATLAS_SIGNAL_VALIDATOR_MQH
//+------------------------------------------------------------------+
