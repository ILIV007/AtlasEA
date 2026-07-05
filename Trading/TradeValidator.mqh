//+------------------------------------------------------------------+
//|                    Trading/TradeValidator.mqh                    |
//|       AtlasEA v0.2.0 - Trade Signal Validator                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_VALIDATOR_MQH
#define ATLAS_TRADE_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILogger.mqh"
#include "TradeSignal.mqh"

/**
 * @class TradeValidator
 * @brief Validates trade signals for structural integrity.
 *
 * SOLE RESPONSIBILITY: determine whether a TradeSignal is structurally
 * valid and internally consistent.
 *
 * This class does NOT:
 *   - Call the broker (no IBrokerAdapter)
 *   - Perform risk calculations (no IRiskEvaluator)
 *   - Compute position size
 *   - Build orders
 *   - Access the context store
 *
 * It ONLY checks the signal's own fields: direction, confidence, prices,
 * timestamps, and directional consistency (TP above entry for BUY, etc.).
 *
 * The validation is a two-stage process:
 *   1. Structural validation (signal.Validate()) — checks all fields
 *   2. Policy validation (ValidatePolicy()) — checks configurable
 *      constraints like minimum confidence, maximum SL/TP ratio
 *
 * Memory: stateless. ~64 bytes (logger pointer + config thresholds).
 */
class TradeValidator
{
private:
    ILogger *m_logger;

    //--- Policy thresholds (configurable) ---
    double m_min_confidence;        ///< Minimum confidence to accept
    double m_max_sl_tp_ratio;       ///< Max SL/TP ratio (SL must not be > N * TP distance)
    bool   m_require_entry_price;   ///< If true, entry_price must be > 0 (no market orders)
    int    m_max_signal_age_sec;    ///< Maximum age of signal (reject stale signals)

public:
    /**
     * @brief Constructor with sensible defaults.
     */
    TradeValidator(void)
    {
        m_logger             = NULL;
        m_min_confidence     = ATLAS_MIN_CONFIDENCE;  ///< 0.30
        m_max_sl_tp_ratio    = 5.0;                    ///< SL distance <= 5x TP distance
        m_require_entry_price = false;                 ///< Market orders allowed
        m_max_signal_age_sec  = 300;                   ///< 5 minutes
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Configure policy thresholds.
     */
    void SetPolicy(const double min_confidence,
                   const double max_sl_tp_ratio,
                   const bool require_entry_price,
                   const int max_signal_age_sec)
    {
        m_min_confidence      = min_confidence;
        m_max_sl_tp_ratio     = max_sl_tp_ratio;
        m_require_entry_price = require_entry_price;
        m_max_signal_age_sec  = max_signal_age_sec;
    }

    /**
     * @brief Validate a trade signal (structural + policy).
     *
     * This is the MAIN entry point. It first checks the signal's
     * structural integrity (delegating to signal.Validate()), then
     * applies policy constraints.
     *
     * @param signal The signal to validate.
     * @return ValidationResult.
     */
    ValidationResult Validate(const TradeSignal &signal)
    {
        //=== Stage 1: Structural validation ===
        ValidationResult structural = signal.Validate();
        if(!structural.valid)
        {
            if(m_logger != NULL)
                m_logger.Warn("TradeValidator",
                    "Signal " + signal.signal_id + " structural validation failed: " +
                    structural.Summary());
            return structural;
        }

        //=== Stage 2: Policy validation ===
        ValidationResult policy = ValidatePolicy(signal);
        if(!policy.valid)
        {
            if(m_logger != NULL)
                m_logger.Warn("TradeValidator",
                    "Signal " + signal.signal_id + " policy validation failed: " +
                    policy.Summary());
            return policy;
        }

        if(m_logger != NULL)
            m_logger.Debug("TradeValidator",
                "Signal " + signal.signal_id + " validated OK");

        return ValidationResult::Ok();
    }

    /**
     * @brief Check if a signal is valid (convenience wrapper).
     * @param signal The signal to check.
     * @return true if valid.
     */
    bool IsValid(const TradeSignal &signal)
    {
        return Validate(signal).valid;
    }

private:
    /**
     * @brief Validate policy constraints.
     */
    ValidationResult ValidatePolicy(const TradeSignal &signal) const
    {
        //--- Minimum confidence
        if(signal.confidence < m_min_confidence)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "confidence " + DoubleToString(signal.confidence, 2) +
                " below minimum " + DoubleToString(m_min_confidence, 2),
                "confidence");

        //--- Entry price requirement
        if(m_require_entry_price && signal.entry_price <= 0.0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "entry_price required but not set", "entry_price");

        //--- Signal age (reject stale signals)
        if(m_max_signal_age_sec > 0)
        {
            long age = (long)TimeCurrent() - (long)signal.timestamp;
            if(age > m_max_signal_age_sec)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "signal age " + IntegerToString(age) + "s exceeds max " +
                    IntegerToString(m_max_signal_age_sec) + "s", "timestamp");
        }

        //--- SL/TP ratio (risk/reward sanity)
        if(m_max_sl_tp_ratio > 0.0 && signal.entry_price > 0.0)
        {
            double sl_dist = MathAbs(signal.entry_price - signal.stop_loss);
            double tp_dist = MathAbs(signal.take_profit - signal.entry_price);
            if(tp_dist > 0.0)
            {
                double ratio = sl_dist / tp_dist;
                if(ratio > m_max_sl_tp_ratio)
                    return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                        "SL/TP ratio " + DoubleToString(ratio, 2) +
                        " exceeds max " + DoubleToString(m_max_sl_tp_ratio, 2),
                        "stop_loss");
            }
        }

        return ValidationResult::Ok();
    }
};

#endif // ATLAS_TRADE_VALIDATOR_MQH
//+------------------------------------------------------------------+
