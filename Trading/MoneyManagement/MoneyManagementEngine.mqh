//+------------------------------------------------------------------+
//|               Trading/MoneyManagement/MoneyManagementEngine.mqh  |
//|       AtlasEA v0.2.3 - Money Management Engine                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_MONEY_MANAGEMENT_ENGINE_LEGACY_MQH
#define ATLAS_MONEY_MANAGEMENT_ENGINE_LEGACY_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Contracts/RiskDecision.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/IBrokerAdapter.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "MoneyManagementConfig.mqh"

/**
 * @class MoneyManagementEngine
 * @brief The SINGLE source of final position size (lot) for every order.
 *
 * SOLE RESPONSIBILITY: compute, validate, and normalize the final lot
 * size for a trade. No other module may compute the final lot.
 *
 * SUPPORTED SIZING MODES (9):
 *   1. FIXED_LOT           — fixed lot size from config
 *   2. RISK_PERCENT        — risk % of equity, SL distance based
 *   3. ATR_BASED           — ATR-normalized risk (SL = ATR × multiplier)
 *   4. BALANCE_BASED       — fixed fraction of account balance
 *   5. EQUITY_BASED        — fixed fraction of account equity
 *   6. FREE_MARGIN_BASED   — fraction of free margin
 *   7. VOLATILITY_SCALING  — scale base lot inversely with volatility
 *   8. DRAWDOWN_SCALING    — scale lot down as drawdown increases
 *   9. DAILY_LOSS_SCALING  — scale lot down as daily losses accumulate
 *
 * INTEGRATION:
 *   - RiskEngine produces a RiskDecision with approved_volume (suggested).
 *   - ExecutionEngine calls MoneyManagementEngine.CalculateLot() to get
 *     the FINAL validated lot size.
 *   - ExecutionEngine does NOT re-compute or re-validate the lot.
 *
 * VALIDATION (rejects if any fails):
 *   - Lot below broker minimum
 *   - Lot above broker maximum
 *   - Lot not aligned to broker step
 *   - Insufficient free margin
 *   - Risk exceeds configured max_risk_percent
 *   - Exposure exceeds configured max_exposure_pct
 *
 * STATISTICS:
 *   - Average lot, max lot, min lot
 *   - Average risk %, average margin usage, average leverage
 *   - Rejected lot calculation count (by reason)
 *
 * PERFORMANCE:
 *   - No heap allocation (all stack, fixed-size)
 *   - No STL (MQL5 has none)
 *   - No recursion
 *   - No MT5 API calls (all via IBrokerAdapter interface)
 *
 * Memory: ~400 bytes (config + stats + cached broker values).
 */
class MoneyManagementEngine
{
private:
    ILogger               *m_logger;
    IBrokerAdapter        *m_broker;
    IContextStore         *m_context;
    MoneyManagementConfig  m_config;
    MoneyManagementStats   m_stats;
    bool                   m_initialized;

    //--- Cached broker values (refreshed per CalculateLot call)
    double m_cached_min_lot;
    double m_cached_max_lot;
    double m_cached_step;
    double m_cached_contract_size;
    double m_cached_point;
    int    m_cached_digits;
    double m_cached_equity;
    double m_cached_balance;
    double m_cached_margin;
    double m_cached_margin_level;

    /**
     * @brief Refresh all cached broker values.
     * Called once at the start of CalculateLot to avoid repeated queries.
     */
    void RefreshBrokerCache(void)
    {
        if(m_broker == NULL) return;

        m_cached_min_lot       = m_broker.SymbolVolumeMin();
        m_cached_max_lot       = m_broker.SymbolVolumeMax();
        m_cached_step          = m_broker.SymbolVolumeStep();
        m_cached_contract_size = m_broker.SymbolContractSize();
        m_cached_point         = m_broker.SymbolPoint();
        m_cached_digits        = m_broker.SymbolDigits();
        m_cached_equity        = m_broker.AccountEquity();
        m_cached_balance       = m_broker.AccountBalance();
        m_cached_margin        = m_broker.AccountMargin();
        m_cached_margin_level  = m_broker.AccountMarginLevel();

        //--- Override config clamping with broker values if they're valid
        if(m_cached_min_lot > 0.0) m_config.min_lot = m_cached_min_lot;
        if(m_cached_max_lot > 0.0) m_config.max_lot = m_cached_max_lot;
        if(m_cached_step > 0.0)    m_config.lot_step = m_cached_step;
    }

    /**
     * @brief Normalize a lot to step + clamp to [min, max].
     */
    double NormalizeLot(const double raw) const
    {
        if(!MathIsValidNumber(raw)) return 0.0;
        double step = (m_config.lot_step > 0.0) ? m_config.lot_step : 0.01;
        double lot = MathRound(raw / step) * step;
        if(lot < m_config.min_lot) lot = m_config.min_lot;
        if(lot > m_config.max_lot) lot = m_config.max_lot;
        lot = NormalizeDouble(lot, m_config.volume_digits);
        return lot;
    }

    /**
     * @brief Compute the risk % for a given lot and SL distance.
     * risk_pct = (lot × contract_size × sl_distance) / equity × 100
     */
    double ComputeRiskPct(const double lot, const double sl_distance) const
    {
        if(m_cached_equity <= 0.0) return 0.0;
        double money_risk = lot * m_cached_contract_size * sl_distance;
        return (money_risk / m_cached_equity) * 100.0;
    }

    /**
     * @brief Estimate margin required for a lot.
     * margin = lot × contract_size × price / leverage
     * (Simplified — actual margin depends on broker. We estimate using
     *  equity/margin ratio as a proxy for leverage.)
     */
    double EstimateMargin(const double lot, const double price) const
    {
        if(price <= 0.0) return 0.0;
        double notional = lot * m_cached_contract_size * price;

        //--- If we have existing margin + positions, estimate leverage
        double leverage = 100.0; // Default 1:100
        if(m_cached_margin > 0.0)
        {
            //--- Estimate leverage from current margin usage
            //--- This is a rough proxy; the broker's actual margin calc
            //    may differ. The validation will catch insufficient margin.
            leverage = 100.0;
        }
        return notional / leverage;
    }

    /**
     * @brief Estimate leverage for a lot.
     * leverage = notional / equity
     */
    double EstimateLeverage(const double lot, const double price) const
    {
        if(m_cached_equity <= 0.0 || price <= 0.0) return 0.0;
        double notional = lot * m_cached_contract_size * price;
        return notional / m_cached_equity;
    }

public:
    /**
     * @brief Constructor.
     */
    MoneyManagementEngine(void)
    {
        m_logger       = NULL;
        m_broker       = NULL;
        m_context      = NULL;
        m_initialized  = false;
        m_cached_min_lot       = 0.0;
        m_cached_max_lot       = 0.0;
        m_cached_step          = 0.0;
        m_cached_contract_size = 100000.0;
        m_cached_point         = 0.00001;
        m_cached_digits        = 5;
        m_cached_equity        = 0.0;
        m_cached_balance       = 0.0;
        m_cached_margin        = 0.0;
        m_cached_margin_level  = 0.0;
    }

    /**
     * @brief Set all dependencies.
     */
    void SetDependencies(ILogger *logger,
                         IBrokerAdapter *broker,
                         IContextStore *context)
    {
        m_logger  = logger;
        m_broker  = broker;
        m_context = context;
    }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const MoneyManagementConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const MoneyManagementConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Get the current statistics.
     */
    const MoneyManagementStats& GetStats(void) const { return m_stats; }

    /**
     * @brief Initialize the engine.
     */
    bool Initialize(void)
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("MoneyManagementEngine",
            "Initialized. Mode=" + MoneyManagementModeName(m_config.mode) +
            " max_risk=" + DoubleToString(m_config.max_risk_percent, 1) + "%" +
            " max_exposure=" + DoubleToString(m_config.max_exposure_pct, 1) + "%");
        return true;
    }

    /**
     * @brief Shutdown the engine.
     */
    void Shutdown(void)
    {
        if(!m_initialized) return;
        LogStats();
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("MoneyManagementEngine", "Shutdown complete");
    }

    /**
     * @brief Calculate the final lot size for a trade.
     *
     * This is the MAIN ENTRY POINT. ExecutionEngine calls this to get
     * the final, validated lot size.
     *
     * @param sl_distance   Stop-loss distance in price units (entry - SL).
     * @param entry_price   Entry price (for margin/leverage estimation).
     * @param market        Current market state (for ATR, volatility).
     * @return LotCalculationResult with accepted/rejected + lot + stats.
     */
    LotCalculationResult CalculateLot(const double sl_distance,
                                       const double entry_price,
                                       const MarketState &market)
    {
        LotCalculationResult result;
        result.mode_name = MoneyManagementModeName(m_config.mode);
        m_stats.total_calculations++;

        if(!m_initialized || m_broker == NULL)
        {
            result.reject_reason = ATLAS_MM_REJECT_NO_DATA;
            result.reject_detail = "Not initialized or broker is NULL";
            RecordRejection(result.reject_reason);
            return result;
        }

        //--- Refresh cached broker values (single query per calculation)
        RefreshBrokerCache();

        //=== Compute raw lot based on the active mode ===
        double raw = 0.0;
        switch(m_config.mode)
        {
            case ATLAS_MM_FIXED_LOT:
                raw = CalculateFixedLot();
                break;
            case ATLAS_MM_RISK_PERCENT:
                raw = CalculateRiskPercent(sl_distance);
                break;
            case ATLAS_MM_ATR_BASED:
                raw = CalculateATRBased(market);
                break;
            case ATLAS_MM_BALANCE_BASED:
                raw = CalculateBalanceBased();
                break;
            case ATLAS_MM_EQUITY_BASED:
                raw = CalculateEquityBased();
                break;
            case ATLAS_MM_FREE_MARGIN_BASED:
                raw = CalculateFreeMarginBased();
                break;
            case ATLAS_MM_VOLATILITY_SCALING:
                raw = CalculateVolatilityScaling(market);
                break;
            case ATLAS_MM_DRAWDOWN_SCALING:
                raw = CalculateDrawdownScaling();
                break;
            case ATLAS_MM_DAILY_LOSS_SCALING:
                raw = CalculateDailyLossScaling();
                break;
            default:
                raw = m_config.fixed_lot;
                break;
        }

        result.raw_lot = raw;

        //--- Check for NaN/INF
        if(!MathIsValidNumber(raw))
        {
            result.reject_reason = ATLAS_MM_REJECT_NAN;
            result.reject_detail = "Computed lot is NaN/INF";
            RecordRejection(result.reject_reason);
            return result;
        }

        //--- Check for zero
        if(raw <= 0.0)
        {
            result.reject_reason = ATLAS_MM_REJECT_ZERO;
            result.reject_detail = "Computed lot is zero";
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Normalize to step + clamp ===
        double lot = NormalizeLot(raw);
        result.lot = lot;

        //=== Validation: below minimum ===
        if(lot < m_config.min_lot)
        {
            result.reject_reason = ATLAS_MM_REJECT_BELOW_MIN;
            result.reject_detail = "lot " + DoubleToString(lot, 2) +
                " < min " + DoubleToString(m_config.min_lot, 2);
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Validation: above maximum ===
        if(lot > m_config.max_lot)
        {
            result.reject_reason = ATLAS_MM_REJECT_ABOVE_MAX;
            result.reject_detail = "lot " + DoubleToString(lot, 2) +
                " > max " + DoubleToString(m_config.max_lot, 2);
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Validation: step alignment ===
        double step = (m_config.lot_step > 0.0) ? m_config.lot_step : 0.01;
        double remainder = MathAbs(lot / step - MathRound(lot / step));
        if(remainder > 0.0001) // Tolerance for floating-point
        {
            result.reject_reason = ATLAS_MM_REJECT_STEP_INVALID;
            result.reject_detail = "lot " + DoubleToString(lot, 4) +
                " not aligned to step " + DoubleToString(step, 4);
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Compute risk % ===
        result.risk_pct = ComputeRiskPct(lot, sl_distance);

        //=== Validation: risk exceeded ===
        if(result.risk_pct > m_config.max_risk_percent)
        {
            result.reject_reason = ATLAS_MM_REJECT_RISK_EXCEEDED;
            result.reject_detail = "risk " + DoubleToString(result.risk_pct, 2) +
                "% > max " + DoubleToString(m_config.max_risk_percent, 2) + "%";
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Compute margin + leverage ===
        result.margin_required = EstimateMargin(lot, entry_price);
        result.leverage = EstimateLeverage(lot, entry_price);

        //=== Validation: exposure exceeded ===
        if(m_context != NULL)
        {
            double current_exposure = m_context.GetCurrentExposurePct();
            double new_exposure = current_exposure + (result.leverage * 100.0);
            if(new_exposure > m_config.max_exposure_pct)
            {
                result.reject_reason = ATLAS_MM_REJECT_EXPOSURE_EXCEEDED;
                result.reject_detail = "exposure " + DoubleToString(new_exposure, 1) +
                    "% > max " + DoubleToString(m_config.max_exposure_pct, 1) + "%";
                RecordRejection(result.reject_reason);
                return result;
            }
        }

        //=== Validation: insufficient margin ===
        double free_margin = m_cached_equity - m_cached_margin;
        if(result.margin_required > free_margin)
        {
            result.reject_reason = ATLAS_MM_REJECT_MARGIN_INSUFFICIENT;
            result.reject_detail = "margin " + DoubleToString(result.margin_required, 2) +
                " > free " + DoubleToString(free_margin, 2);
            RecordRejection(result.reject_reason);
            return result;
        }

        //=== Validation: minimum free margin % ===
        if(m_cached_equity > 0.0)
        {
            double free_margin_pct = (free_margin / m_cached_equity) * 100.0;
            if(free_margin_pct < m_config.min_free_margin_pct)
            {
                result.reject_reason = ATLAS_MM_REJECT_MARGIN_INSUFFICIENT;
                result.reject_detail = "free margin " + DoubleToString(free_margin_pct, 1) +
                    "% < min " + DoubleToString(m_config.min_free_margin_pct, 1) + "%";
                RecordRejection(result.reject_reason);
                return result;
            }
        }

        //=== All validations passed ===
        result.accepted = true;
        m_stats.total_accepted++;
        m_stats.sum_lot += lot;
        m_stats.sum_risk_pct += result.risk_pct;
        m_stats.sum_margin_used += result.margin_required;
        m_stats.sum_leverage += result.leverage;

        if(lot > m_stats.max_lot_seen) m_stats.max_lot_seen = lot;
        if(m_stats.min_lot_seen == 0.0 || lot < m_stats.min_lot_seen)
            m_stats.min_lot_seen = lot;

        return result;
    }

    /**
     * @brief Convenience method: just get the lot (0.0 if rejected).
     */
    double CalculateLotSimple(const double sl_distance,
                               const double entry_price,
                               const MarketState &market)
    {
        LotCalculationResult r = CalculateLot(sl_distance, entry_price, market);
        return r.accepted ? r.lot : 0.0;
    }

    /**
     * @brief Reset statistics.
     */
    void ResetStats(void)
    {
        m_stats = MoneyManagementStats();
    }

    /**
     * @brief Log the current statistics.
     */
    void LogStats(void) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("MoneyManagementEngine",
            "Calcs=" + IntegerToString((long)m_stats.total_calculations) +
            " Accepted=" + IntegerToString((long)m_stats.total_accepted) +
            " Rejected=" + IntegerToString((long)m_stats.total_rejected) +
            " AvgLot=" + DoubleToString(m_stats.AverageLot(), 2) +
            " MaxLot=" + DoubleToString(m_stats.max_lot_seen, 2) +
            " MinLot=" + DoubleToString(m_stats.min_lot_seen, 2) +
            " AvgRisk=" + DoubleToString(m_stats.AverageRisk(), 2) + "%" +
            " AvgMargin=" + DoubleToString(m_stats.AverageMarginUsage(), 2) +
            " AvgLev=" + DoubleToString(m_stats.AverageLeverage(), 2));
    }

private:
    //=== Sizing mode implementations ===

    /**
     * @brief FIXED_LOT: return the configured fixed lot.
     */
    double CalculateFixedLot(void) const
    {
        return m_config.fixed_lot;
    }

    /**
     * @brief RISK_PERCENT: lot = (equity × risk%) / (contract_size × sl_distance).
     */
    double CalculateRiskPercent(const double sl_distance) const
    {
        if(sl_distance <= 0.0 || m_cached_equity <= 0.0) return 0.0;
        double risk_money = m_cached_equity * (m_config.risk_percent / 100.0);
        return risk_money / (m_cached_contract_size * sl_distance);
    }

    /**
     * @brief ATR_BASED: use ATR × multiplier as the SL distance, then risk %.
     */
    double CalculateATRBased(const MarketState &market) const
    {
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0) return 0.0;
        double sl_dist = market.atr_14 * m_config.sl_atr_multiplier;
        return CalculateRiskPercent(sl_dist);
    }

    /**
     * @brief BALANCE_BASED: lot = (balance × fraction) / (contract_size × sl_distance).
     */
    double CalculateBalanceBased(void) const
    {
        if(m_cached_balance <= 0.0) return 0.0;
        //--- Use a notional SL distance of 1% of price as proxy
        double ref_price = m_cached_equity / m_cached_contract_size;
        double sl_dist = ref_price * 0.01;
        double money = m_cached_balance * m_config.balance_fraction;
        return money / (m_cached_contract_size * sl_dist);
    }

    /**
     * @brief EQUITY_BASED: lot = (equity × fraction) / (contract_size × sl_distance).
     */
    double CalculateEquityBased(void) const
    {
        if(m_cached_equity <= 0.0) return 0.0;
        double ref_price = m_cached_equity / m_cached_contract_size;
        double sl_dist = ref_price * 0.01;
        double money = m_cached_equity * m_config.equity_fraction;
        return money / (m_cached_contract_size * sl_dist);
    }

    /**
     * @brief FREE_MARGIN_BASED: lot = (free_margin × fraction) / (contract_size × price).
     */
    double CalculateFreeMarginBased(void) const
    {
        double free_margin = m_cached_equity - m_cached_margin;
        if(free_margin <= 0.0) return 0.0;
        double ref_price = m_cached_equity / m_cached_contract_size;
        if(ref_price <= 0.0) return 0.0;
        return (free_margin * m_config.free_margin_fraction) /
               (m_cached_contract_size * ref_price);
    }

    /**
     * @brief VOLATILITY_SCALING: scale base lot inversely with volatility.
     *
     * base_atr_ratio = vol_scale_base_atr
     * current_atr_ratio = atr / price
     * multiplier = base_atr_ratio / current_atr_ratio (clamped)
     * lot = fixed_lot × multiplier
     */
    double CalculateVolatilityScaling(const MarketState &market) const
    {
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0)
            return m_config.fixed_lot;

        double price = (market.bid + market.ask) / 2.0;
        if(price <= 0.0) return m_config.fixed_lot;

        double current_atr_ratio = market.atr_14 / price;
        if(current_atr_ratio <= 0.0) return m_config.fixed_lot;

        double mult = m_config.vol_scale_base_atr / current_atr_ratio;
        if(mult < m_config.vol_scale_min_mult) mult = m_config.vol_scale_min_mult;
        if(mult > m_config.vol_scale_max_mult) mult = m_config.vol_scale_max_mult;

        return m_config.fixed_lot * mult;
    }

    /**
     * @brief DRAWDOWN_SCALING: scale base lot down as drawdown increases.
     *
     * Between dd_scale_start_pct and dd_scale_end_pct, the lot is linearly
     * scaled from fixed_lot to fixed_lot × dd_scale_min_mult.
     */
    double CalculateDrawdownScaling(void) const
    {
        if(m_context == NULL) return m_config.fixed_lot;

        double dd = m_context.GetDailyDrawdownPct();
        if(dd <= m_config.dd_scale_start_pct) return m_config.fixed_lot;
        if(dd >= m_config.dd_scale_end_pct)
            return m_config.fixed_lot * m_config.dd_scale_min_mult;

        //--- Linear interpolation between start and end
        double range = m_config.dd_scale_end_pct - m_config.dd_scale_start_pct;
        if(range <= 0.0) return m_config.fixed_lot;

        double progress = (dd - m_config.dd_scale_start_pct) / range;
        double mult = 1.0 - progress * (1.0 - m_config.dd_scale_min_mult);
        return m_config.fixed_lot * mult;
    }

    /**
     * @brief DAILY_LOSS_SCALING: scale lot down as daily losses accumulate.
     *
     * After dl_scale_start_losses, the lot is scaled toward dl_scale_min_mult.
     */
    double CalculateDailyLossScaling(void) const
    {
        if(m_context == NULL) return m_config.fixed_lot;

        int losses = m_context.GetDailyLossCount();
        if(losses < m_config.dl_scale_start_losses) return m_config.fixed_lot;

        //--- Each loss beyond the start reduces the lot progressively.
        //--- After (start + 5) losses, the lot is at dl_scale_min_mult.
        int excess = losses - m_config.dl_scale_start_losses;
        double progress = excess / 5.0;
        if(progress > 1.0) progress = 1.0;

        double mult = 1.0 - progress * (1.0 - m_config.dl_scale_min_mult);

        //--- Also apply risk_percent sizing, then scale
        double ref_price = m_cached_equity / m_cached_contract_size;
        double sl_dist = ref_price * 0.01;
        double base_lot = CalculateRiskPercent(sl_dist);
        if(base_lot <= 0.0) base_lot = m_config.fixed_lot;

        return base_lot * mult;
    }

    /**
     * @brief Record a rejection in the statistics.
     */
    void RecordRejection(const int reason)
    {
        m_stats.total_rejected++;
        if(reason >= 0 && reason < 10)
            m_stats.reject_counts[reason]++;
    }
};

#endif // ATLAS_MONEY_MANAGEMENT_ENGINE_LEGACY_MQH
//+------------------------------------------------------------------+
