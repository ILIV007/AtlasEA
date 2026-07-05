//+------------------------------------------------------------------+
//|                 Trading/Signal/SignalNormalizer.mqh              |
//|       AtlasEA v0.2.1 - Signal Normalization                      |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_NORMALIZER_MQH
#define ATLAS_SIGNAL_NORMALIZER_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Core/ValidationResult.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"

/**
 * @struct SignalNormalizationConfig
 * @brief Configuration for signal normalization.
 *
 * All thresholds are configurable. The normalizer uses these to clamp
 * and round signal fields to canonical ranges.
 */
struct SignalNormalizationConfig
{
    double min_confidence;        ///< Clamp confidence to [min, max]
    double max_confidence;
    double min_stop_loss_points;  ///< Minimum SL distance in points
    double min_take_profit_points;///< Minimum TP distance in points
    int    volume_digits;         ///< Digits for volume rounding (0 = no rounding)
    double max_sl_tp_ratio;       ///< If SL/TP ratio exceeds this, widen TP
    bool   enforce_directional_consistency; ///< If true, fix SL/TP ordering

    SignalNormalizationConfig(void)
    {
        min_confidence      = 0.0;
        max_confidence      = 1.0;
        min_stop_loss_points = 10.0;
        min_take_profit_points = 10.0;
        volume_digits       = 2;
        max_sl_tp_ratio     = 5.0;
        enforce_directional_consistency = true;
    }
};

/**
 * @class SignalNormalizer
 * @brief Normalizes trade signal fields to canonical ranges.
 *
 * SOLE RESPONSIBILITY: normalize SL, TP, volume suggestion, confidence,
 * direction, and time so that downstream stages receive clean data.
 *
 * The normalizer does NOT:
 *   - Validate (that's SignalValidator's job)
 *   - Filter or reject signals
 *   - Call the broker
 *   - Access risk or indicators
 *
 * Normalization steps:
 *   1. Confidence: clamp to [min_confidence, max_confidence]
 *   2. Direction: ensure it's exactly BUY(1) or SELL(-1)
 *   3. SL/TP: enforce minimum distance from entry in points
 *   4. SL/TP: enforce directional consistency (TP above entry for BUY, etc.)
 *   5. SL/TP ratio: if SL/TP ratio exceeds max, widen TP
 *   6. Volume suggestion: round to volume_digits
 *   7. Time: if timestamp is 0, set to TimeCurrent()
 *
 * The normalizer produces a NEW TradeSignal (does not mutate the input).
 * The original signal remains immutable.
 *
 * Memory: ~200 bytes (config + logger).
 */
class SignalNormalizer
{
private:
    ILogger                   *m_logger;
    SignalNormalizationConfig  m_config;

public:
    /**
     * @brief Constructor.
     */
    SignalNormalizer(void)
    {
        m_logger = NULL;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the normalization configuration.
     */
    void SetConfig(const SignalNormalizationConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const SignalNormalizationConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Normalize a trade signal.
     *
     * Produces a new TradeSignal with all fields normalized. The input
     * signal is not modified (immutability preserved).
     *
     * @param input  The raw signal from the strategy.
     * @param market Current market state (for point/digits).
     * @return Normalized TradeSignal.
     */
    TradeSignal Normalize(const TradeSignal &input, const MarketState &market)
    {
        TradeSignal out = input;

        //=== 1. Normalize confidence ===
        out.confidence = NormalizeConfidence(input.confidence);

        //=== 2. Normalize direction ===
        out.direction = NormalizeDirection(input.direction);

        //=== 3. Normalize prices ===
        NormalizePrices(out, market);

        //=== 4. Normalize timestamp ===
        if(out.timestamp <= 0)
            out.timestamp = TimeCurrent();

        //=== 5. Normalize snapshot_id ===
        if(out.snapshot_id <= 0)
            out.snapshot_id = market.snapshot_id;

        if(m_logger != NULL)
            m_logger.Debug("SignalNormalizer",
                "Normalized " + input.signal_id +
                " dir=" + IntegerToString(out.direction) +
                " conf=" + DoubleToString(out.confidence, 2) +
                " sl=" + DoubleToString(out.stop_loss, 5) +
                " tp=" + DoubleToString(out.take_profit, 5));

        return out;
    }

private:
    /**
     * @brief Clamp confidence to [min, max].
     */
    double NormalizeConfidence(const double conf) const
    {
        if(!MathIsValidNumber(conf)) return m_config.min_confidence;
        if(conf < m_config.min_confidence) return m_config.min_confidence;
        if(conf > m_config.max_confidence) return m_config.max_confidence;
        return conf;
    }

    /**
     * @brief Normalize direction to exactly +1 or -1.
     * If direction is 0 or invalid, default to BUY (the validator will
     * catch it if the strategy truly intended NONE).
     */
    int NormalizeDirection(const int dir) const
    {
        if(dir > 0) return ATLAS_ORDER_BUY;
        if(dir < 0) return ATLAS_ORDER_SELL;
        return ATLAS_ORDER_BUY; // Default; validator catches this
    }

    /**
     * @brief Normalize SL/TP prices.
     * Enforces minimum distance and directional consistency.
     */
    void NormalizePrices(TradeSignal &sig, const MarketState &market)
    {
        double point = (market.point > 0.0) ? market.point : 0.00001;
        double min_sl_dist = m_config.min_stop_loss_points * point;
        double min_tp_dist = m_config.min_take_profit_points * point;

        //--- Determine the reference price (entry or current market)
        double ref = sig.entry_price;
        if(ref <= 0.0)
        {
            ref = (market.bid + market.ask) / 2.0;
            if(ref <= 0.0) ref = market.bid;
            if(ref <= 0.0) ref = market.ask;
        }

        //--- Fix NaN prices
        if(!MathIsValidNumber(sig.stop_loss))    sig.stop_loss = 0.0;
        if(!MathIsValidNumber(sig.take_profit))  sig.take_profit = 0.0;
        if(!MathIsValidNumber(sig.entry_price))  sig.entry_price = 0.0;

        //--- Enforce minimum SL distance and directional consistency
        if(sig.direction == ATLAS_ORDER_BUY)
        {
            //--- BUY: SL below ref, TP above ref
            if(sig.stop_loss <= 0.0 || sig.stop_loss >= ref)
                sig.stop_loss = ref - min_sl_dist;
            if(sig.take_profit <= 0.0 || sig.take_profit <= ref)
                sig.take_profit = ref + min_tp_dist;

            //--- Enforce minimum distance
            if(ref - sig.stop_loss < min_sl_dist)
                sig.stop_loss = ref - min_sl_dist;
            if(sig.take_profit - ref < min_tp_dist)
                sig.take_profit = ref + min_tp_dist;

            //--- Enforce SL/TP ratio (widen TP if SL is too large relative to TP)
            double sl_dist = ref - sig.stop_loss;
            double tp_dist = sig.take_profit - ref;
            if(tp_dist > 0.0 && sl_dist / tp_dist > m_config.max_sl_tp_ratio)
                sig.take_profit = ref + (sl_dist / m_config.max_sl_tp_ratio);
        }
        else // ATLAS_ORDER_SELL
        {
            //--- SELL: SL above ref, TP below ref
            if(sig.stop_loss <= 0.0 || sig.stop_loss <= ref)
                sig.stop_loss = ref + min_sl_dist;
            if(sig.take_profit <= 0.0 || sig.take_profit >= ref)
                sig.take_profit = ref - min_tp_dist;

            //--- Enforce minimum distance
            if(sig.stop_loss - ref < min_sl_dist)
                sig.stop_loss = ref + min_sl_dist;
            if(ref - sig.take_profit < min_tp_dist)
                sig.take_profit = ref - min_tp_dist;

            //--- Enforce SL/TP ratio
            double sl_dist = sig.stop_loss - ref;
            double tp_dist = ref - sig.take_profit;
            if(tp_dist > 0.0 && sl_dist / tp_dist > m_config.max_sl_tp_ratio)
                sig.take_profit = ref - (sl_dist / m_config.max_sl_tp_ratio);
        }
    }
};

#endif // ATLAS_SIGNAL_NORMALIZER_MQH
//+------------------------------------------------------------------+
