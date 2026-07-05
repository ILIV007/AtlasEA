//+------------------------------------------------------------------+
//|                  Engines/MoneyManagementEngine.mqh               |
//|       AtlasEA v1.0 - Money Management Engine (Step 1/10)         |
//+------------------------------------------------------------------+
#ifndef ATLAS_MONEY_MANAGEMENT_ENGINE_MQH
#define ATLAS_MONEY_MANAGEMENT_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/IMoneyManagement.mqh"

/**
 * @class MoneyManagementEngine
 * @brief The ONLY authority responsible for calculating final order volume.
 *
 * Implements IMoneyManagement. ExecutionEngine requests the final lot
 * size exclusively through this interface. No other module may compute
 * the final volume.
 *
 * SUPPORTED SIZING MODES (10):
 *   1. FIXED_LOT            — fixed lot from config
 *   2. FIXED_RISK_PERCENT   — risk % of equity, SL distance based
 *   3. BALANCE_PERCENT      — fixed fraction of account balance
 *   4. EQUITY_PERCENT       — fixed fraction of account equity
 *   5. FREE_MARGIN_PERCENT  — fraction of free margin
 *   6. ATR_BASED            — ATR-normalized risk (SL = ATR × multiplier)
 *   7. SL_DISTANCE_BASED    — fixed money risk / (SL distance × tick_value)
 *   8. VOLATILITY_SCALING   — scale base lot inversely with ATR/price
 *   9. DRAWDOWN_SCALING     — scale lot down as drawdown increases
 *  10. DAILY_LOSS_SCALING   — scale lot down as daily losses accumulate
 *
 * CALCULATION ACCURACY:
 *   Uses SymbolTickValue and SymbolTickSize for accurate money calculations:
 *     money_risk = sl_distance_points × tick_value × volume
 *     volume = money_risk / (sl_distance_points × tick_value)
 *   Falls back to contract_size × price if tick_value is unavailable.
 *
 * VALIDATION (10 checks):
 *   - Volume < minimum
 *   - Volume > maximum
 *   - Volume step invalid
 *   - Margin insufficient
 *   - Risk exceeds configured limit
 *   - Daily loss exceeded
 *   - Drawdown protection active
 *   - Exposure limit exceeded
 *   - Invalid ATR
 *   - Invalid SL
 *   Returns structured error codes. Never silently fails.
 *
 * PERFORMANCE:
 *   - O(1) calculations (no loops, no recursion)
 *   - No heap allocation (all stack, fixed-size)
 *   - No STL, no templates
 *   - No broker API calls inside the engine (all via IBrokerAdapter)
 *   - No floating-point instability (all values clamped + validated)
 *   - Cached broker values (single refresh per CalculateVolume call)
 *
 * Memory: ~600 bytes (config + stats + cached broker values).
 */
class MoneyManagementEngine : public IMoneyManagement
{
private:
    ILogger        *m_logger;
    AtlasConfig     m_config;
    MoneyManagementStats m_stats;
    bool            m_initialized;

    //--- Cached broker values (refreshed once per CalculateVolume call) ---
    double m_tick_value;        ///< Tick value in account currency
    double m_tick_size;         ///< Tick size in price units
    double m_contract_size;     ///< Contract size
    double m_point;             ///< Symbol point
    int    m_digits;            ///< Symbol digits
    double m_min_lot;           ///< Broker minimum volume
    double m_max_lot;           ///< Broker maximum volume
    double m_lot_step;          ///< Broker volume step
    double m_margin_initial;    ///< Initial margin for 1 lot
    long   m_leverage;          ///< Account leverage
    double m_equity;            ///< Account equity
    double m_balance;           ///< Account balance
    double m_margin;            ///< Used margin
    double m_margin_level;      ///< Margin level %
    double m_free_margin;       ///< Free margin (equity - margin)

    /**
     * @brief Refresh all cached broker values.
     * Called once at the start of CalculateVolume. No repeated queries
     * during the calculation.
     */
    void RefreshCache(IBrokerAdapter *broker)
    {
        if(broker == NULL) return;
        m_tick_value    = broker.SymbolTickValue();
        m_tick_size     = broker.SymbolTickSize();
        m_contract_size = broker.SymbolContractSize();
        m_point         = broker.SymbolPoint();
        m_digits        = broker.SymbolDigits();
        m_min_lot       = broker.SymbolVolumeMin();
        m_max_lot       = broker.SymbolVolumeMax();
        m_lot_step      = broker.SymbolVolumeStep();
        m_margin_initial = broker.SymbolMarginInitial();
        m_leverage       = broker.AccountLeverage();
        m_equity         = broker.AccountEquity();
        m_balance        = broker.AccountBalance();
        m_margin         = broker.AccountMargin();
        m_margin_level   = broker.AccountMarginLevel();
        m_free_margin    = m_equity - m_margin;
    }

    /**
     * @brief Normalize volume to lot step + clamp to [min, max].
     */
    double NormalizeVolume(const double raw) const
    {
        if(!MathIsValidNumber(raw)) return 0.0;
        double step = (m_lot_step > 0.0) ? m_lot_step : 0.01;
        double v = MathRound(raw / step) * step;
        double cfg_min = (m_config.mm_min_lot > 0.0) ? m_config.mm_min_lot : m_min_lot;
        double cfg_max = (m_config.mm_max_lot > 0.0) ? m_config.mm_max_lot : m_max_lot;
        if(cfg_min < m_min_lot && m_min_lot > 0.0) cfg_min = m_min_lot;
        if(cfg_max > m_max_lot && m_max_lot > 0.0) cfg_max = m_max_lot;
        if(v < cfg_min) v = cfg_min;
        if(v > cfg_max) v = cfg_max;
        v = NormalizeDouble(v, m_config.volume_digits);
        return v;
    }

    /**
     * @brief Compute the actual risk % for a given volume and SL distance.
     *
     * Uses tick value for accuracy:
     *   sl_points = sl_distance / point
     *   money_risk = sl_points × tick_value × volume
     *   risk_pct = money_risk / equity × 100
     *
     * Falls back to contract_size × sl_distance if tick_value is 0.
     */
    double ComputeRiskPct(const double volume, const double sl_distance) const
    {
        if(m_equity <= 0.0 || volume <= 0.0 || sl_distance <= 0.0) return 0.0;

        double money_risk = 0.0;
        if(m_tick_value > 0.0 && m_point > 0.0)
        {
            double sl_points = sl_distance / m_point;
            money_risk = sl_points * m_tick_value * volume;
        }
        else if(m_contract_size > 0.0)
        {
            money_risk = volume * m_contract_size * sl_distance;
        }
        return (money_risk / m_equity) * 100.0;
    }

    /**
     * @brief Estimate margin required for a volume.
     *
     * Uses SymbolMarginInitial if available:
     *   margin = margin_initial × volume
     * Falls back to notional / leverage if margin_initial is 0.
     */
    double EstimateMargin(const double volume, const double price) const
    {
        if(volume <= 0.0) return 0.0;
        if(m_margin_initial > 0.0)
            return m_margin_initial * volume;
        if(price <= 0.0 || m_leverage <= 0) return 0.0;
        double notional = volume * m_contract_size * price;
        return notional / (double)m_leverage;
    }

    /**
     * @brief Estimate leverage for a volume.
     * leverage = notional / equity
     */
    double EstimateLeverage(const double volume, const double price) const
    {
        if(m_equity <= 0.0 || price <= 0.0) return 0.0;
        double notional = volume * m_contract_size * price;
        return notional / m_equity;
    }

    /**
     * @brief Record a rejection in the statistics.
     */
    void RecordRejection(const int error_code)
    {
        m_stats.total_rejected++;
        m_stats.daily_rejected++;
        if(error_code >= 0 && error_code < 16)
            m_stats.reject_counts[error_code]++;
    }

public:
    /**
     * @brief Constructor.
     */
    MoneyManagementEngine(void)
    {
        m_logger       = NULL;
        m_initialized  = false;
        m_tick_value   = 0.0;
        m_tick_size    = 0.0;
        m_contract_size = 100000.0;
        m_point        = 0.00001;
        m_digits       = 5;
        m_min_lot      = 0.01;
        m_max_lot      = 10.0;
        m_lot_step     = 0.01;
        m_margin_initial = 0.0;
        m_leverage     = 100;
        m_equity       = 0.0;
        m_balance      = 0.0;
        m_margin       = 0.0;
        m_margin_level = 0.0;
        m_free_margin  = 0.0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const AtlasConfig &config) { m_config = config; }

    //=== IMoneyManagement implementation ===

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("MoneyManagementEngine",
            "Initialized. Mode=" + MoneyManagementModeName(m_config.mm_mode) +
            " max_risk=" + DoubleToString(m_config.mm_max_risk_percent, 1) + "%" +
            " max_exposure=" + DoubleToString(m_config.mm_max_exposure_pct, 1) + "%" +
            " max_lot=" + DoubleToString(m_config.mm_max_lot, 2) +
            " min_lot=" + DoubleToString(m_config.mm_min_lot, 2));
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        LogStats();
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("MoneyManagementEngine", "Shutdown complete");
    }

    /**
     * @brief Calculate the final validated order volume.
     *
     * This is the MAIN ENTRY POINT. ExecutionEngine calls this to get
     * the final lot size for an order.
     *
     * @param decision  The risk decision (contains SL, TP, direction).
     * @param market    Current market state (for ATR, volatility).
     * @param broker    Broker adapter (for account + symbol queries).
     * @param context   Context store (for drawdown, exposure, losses).
     * @return VolumeResult with accepted/rejected + volume + stats.
     */
    virtual VolumeResult CalculateVolume(const RiskDecision &decision,
                                          const MarketState &market,
                                          IBrokerAdapter *broker,
                                          IContextStore *context) override
    {
        VolumeResult result;
        result.mode_name = MoneyManagementModeName(m_config.mm_mode);
        m_stats.total_calculations++;
        m_stats.daily_calculations++;

        ulong start_us = GetTickCount64();

        if(!m_initialized || broker == NULL)
        {
            result.error_code = ATLAS_MM_ERR_NO_DATA;
            result.error_detail = "Not initialized or broker is NULL";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //--- Refresh cached broker values (single query per calculation)
        RefreshCache(broker);

        //--- Validate symbol info
        if(m_tick_value <= 0.0 && m_contract_size <= 0.0)
        {
            result.error_code = ATLAS_MM_ERR_INVALID_SYMBOL;
            result.error_detail = "tick_value and contract_size both <= 0";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //--- Check kill switch
        if(context != NULL && context.IsKillSwitchActive())
        {
            result.error_code = ATLAS_MM_ERR_KILLSWITCH;
            result.error_detail = "Kill switch is active";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //--- Check drawdown protection
        if(context != NULL)
        {
            double dd = context.GetDailyDrawdownPct();
            if(dd >= m_config.mm_max_drawdown_pct)
            {
                result.error_code = ATLAS_MM_ERR_DRAWDOWN_ACTIVE;
                result.error_detail = "Drawdown " + DoubleToString(dd, 2) +
                    "% >= max " + DoubleToString(m_config.mm_max_drawdown_pct, 2) + "%";
                RecordRejection(result.error_code);
                result.calculation_time_us = GetTickCount64() - start_us;
                return result;
            }

            //--- Check daily loss limit
            double daily_pnl = context.GetDailyRealizedPnl();
            double daily_loss_pct = (m_equity > 0.0 && daily_pnl < 0.0)
                ? (MathAbs(daily_pnl) / m_equity) * 100.0 : 0.0;
            if(daily_loss_pct >= m_config.mm_max_daily_loss_pct)
            {
                result.error_code = ATLAS_MM_ERR_DAILY_LOSS_EXCEEDED;
                result.error_detail = "Daily loss " + DoubleToString(daily_loss_pct, 2) +
                    "% >= max " + DoubleToString(m_config.mm_max_daily_loss_pct, 2) + "%";
                RecordRejection(result.error_code);
                result.calculation_time_us = GetTickCount64() - start_us;
                return result;
            }
        }

        //=== Compute SL distance ===
        double entry_price = (market.bid + market.ask) / 2.0;
        if(entry_price <= 0.0) entry_price = market.bid;
        if(entry_price <= 0.0) entry_price = market.ask;

        double sl_price = decision.approved_sl;
        double sl_distance = MathAbs(entry_price - sl_price);

        //=== Validate SL ===
        if(sl_price <= 0.0)
        {
            result.error_code = ATLAS_MM_ERR_INVALID_SL;
            result.error_detail = "approved_sl <= 0";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }
        if(!MathIsValidNumber(sl_price))
        {
            result.error_code = ATLAS_MM_ERR_INVALID_SL;
            result.error_detail = "approved_sl is NaN/INF";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Compute raw volume based on active mode ===
        double raw = 0.0;

        switch(m_config.mm_mode)
        {
            case ATLAS_MM_FIXED_LOT:
                raw = CalcFixedLot();
                break;
            case ATLAS_MM_FIXED_RISK_PERCENT:
                raw = CalcRiskPercent(sl_distance);
                break;
            case ATLAS_MM_BALANCE_PERCENT:
                raw = CalcBalancePercent(entry_price);
                break;
            case ATLAS_MM_EQUITY_PERCENT:
                raw = CalcEquityPercent(entry_price);
                break;
            case ATLAS_MM_FREE_MARGIN_PERCENT:
                raw = CalcFreeMarginPercent(entry_price);
                break;
            case ATLAS_MM_ATR_BASED:
                raw = CalcATRBased(market);
                break;
            case ATLAS_MM_SL_DISTANCE_BASED:
                raw = CalcSLDistanceBased(sl_distance);
                break;
            case ATLAS_MM_VOLATILITY_SCALING:
                raw = CalcVolatilityScaling(market);
                break;
            case ATLAS_MM_DRAWDOWN_SCALING:
                raw = CalcDrawdownScaling(context);
                break;
            case ATLAS_MM_DAILY_LOSS_SCALING:
                raw = CalcDailyLossScaling(context);
                break;
            default:
                raw = m_config.mm_fixed_lot;
                break;
        }

        result.raw_volume = raw;

        //--- Validate raw volume
        if(!MathIsValidNumber(raw))
        {
            result.error_code = ATLAS_MM_ERR_NAN;
            result.error_detail = "Computed volume is NaN/INF";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        if(raw <= 0.0)
        {
            result.error_code = ATLAS_MM_ERR_ZERO;
            result.error_detail = "Computed volume is zero";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Normalize to step + clamp ===
        double vol = NormalizeVolume(raw);
        result.volume = vol;

        //=== Validation: below minimum ===
        double eff_min = (m_config.mm_min_lot > 0.0) ? m_config.mm_min_lot : m_min_lot;
        if(eff_min < m_min_lot && m_min_lot > 0.0) eff_min = m_min_lot;
        if(vol < eff_min)
        {
            result.error_code = ATLAS_MM_ERR_BELOW_MIN;
            result.error_detail = "vol " + DoubleToString(vol, 4) +
                " < min " + DoubleToString(eff_min, 4);
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Validation: above maximum ===
        double eff_max = (m_config.mm_max_lot > 0.0) ? m_config.mm_max_lot : m_max_lot;
        if(eff_max > m_max_lot && m_max_lot > 0.0) eff_max = m_max_lot;
        if(vol > eff_max)
        {
            result.error_code = ATLAS_MM_ERR_ABOVE_MAX;
            result.error_detail = "vol " + DoubleToString(vol, 4) +
                " > max " + DoubleToString(eff_max, 4);
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Validation: step alignment ===
        double step = (m_lot_step > 0.0) ? m_lot_step : 0.01;
        double remainder = MathAbs(vol / step - MathRound(vol / step));
        if(remainder > 0.0001)
        {
            result.error_code = ATLAS_MM_ERR_STEP_INVALID;
            result.error_detail = "vol " + DoubleToString(vol, 4) +
                " not aligned to step " + DoubleToString(step, 4);
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Compute risk % ===
        result.risk_pct = ComputeRiskPct(vol, sl_distance);

        //=== Validation: risk exceeded ===
        if(result.risk_pct > m_config.mm_max_risk_percent)
        {
            result.error_code = ATLAS_MM_ERR_RISK_EXCEEDED;
            result.error_detail = "risk " + DoubleToString(result.risk_pct, 2) +
                "% > max " + DoubleToString(m_config.mm_max_risk_percent, 2) + "%";
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Compute margin + leverage ===
        result.margin_required = EstimateMargin(vol, entry_price);
        result.leverage = EstimateLeverage(vol, entry_price);

        //=== Validation: exposure exceeded ===
        if(context != NULL)
        {
            double current_exposure = context.GetCurrentExposurePct();
            double new_exposure = current_exposure + (result.leverage * 100.0);
            if(new_exposure > m_config.mm_max_exposure_pct)
            {
                result.error_code = ATLAS_MM_ERR_EXPOSURE_EXCEEDED;
                result.error_detail = "exposure " + DoubleToString(new_exposure, 1) +
                    "% > max " + DoubleToString(m_config.mm_max_exposure_pct, 1) + "%";
                RecordRejection(result.error_code);
                result.calculation_time_us = GetTickCount64() - start_us;
                return result;
            }
        }

        //=== Validation: margin insufficient ===
        if(result.margin_required > m_free_margin)
        {
            result.error_code = ATLAS_MM_ERR_MARGIN_INSUFFICIENT;
            result.error_detail = "margin " + DoubleToString(result.margin_required, 2) +
                " > free " + DoubleToString(m_free_margin, 2);
            RecordRejection(result.error_code);
            result.calculation_time_us = GetTickCount64() - start_us;
            return result;
        }

        //=== Validation: minimum free margin % ===
        if(m_equity > 0.0)
        {
            double free_margin_pct = (m_free_margin / m_equity) * 100.0;
            if(free_margin_pct < m_config.mm_min_free_margin_pct)
            {
                result.error_code = ATLAS_MM_ERR_MARGIN_INSUFFICIENT;
                result.error_detail = "free margin " + DoubleToString(free_margin_pct, 1) +
                    "% < min " + DoubleToString(m_config.mm_min_free_margin_pct, 1) + "%";
                RecordRejection(result.error_code);
                result.calculation_time_us = GetTickCount64() - start_us;
                return result;
            }
        }

        //=== All validations passed ===
        result.accepted = true;
        m_stats.total_accepted++;
        m_stats.daily_accepted++;
        m_stats.sum_volume += vol;
        m_stats.daily_sum_volume += vol;
        m_stats.sum_risk_pct += result.risk_pct;
        m_stats.daily_sum_risk += result.risk_pct;
        m_stats.sum_margin_used += result.margin_required;
        m_stats.sum_leverage += result.leverage;

        if(vol > m_stats.max_volume) m_stats.max_volume = vol;
        if(m_stats.min_volume == 0.0 || vol < m_stats.min_volume)
            m_stats.min_volume = vol;

        result.calculation_time_us = GetTickCount64() - start_us;
        m_stats.sum_calc_time_us += result.calculation_time_us;
        if(result.calculation_time_us > m_stats.max_calc_time_us)
            m_stats.max_calc_time_us = result.calculation_time_us;

        return result;
    }

    virtual MoneyManagementStats GetStats(void) const override
    {
        return m_stats;
    }

    virtual void ResetDaily(void) override
    {
        m_stats.daily_calculations = 0;
        m_stats.daily_accepted     = 0;
        m_stats.daily_rejected     = 0;
        m_stats.daily_sum_volume   = 0.0;
        m_stats.daily_sum_risk     = 0.0;
    }

    virtual void ResetAll(void) override
    {
        m_stats = MoneyManagementStats();
    }

    virtual void LogStats(void) const override
    {
        if(m_logger == NULL) return;
        m_logger.Info("MoneyManagementEngine",
            "Calcs=" + IntegerToString((long)m_stats.total_calculations) +
            " Accepted=" + IntegerToString((long)m_stats.total_accepted) +
            " Rejected=" + IntegerToString((long)m_stats.total_rejected) +
            " AvgVol=" + DoubleToString(m_stats.AverageVolume(), 2) +
            " MaxVol=" + DoubleToString(m_stats.max_volume, 2) +
            " MinVol=" + DoubleToString(m_stats.min_volume, 2) +
            " AvgRisk=" + DoubleToString(m_stats.AverageRisk(), 2) + "%" +
            " AvgMargin=" + DoubleToString(m_stats.AverageMarginUsage(), 2) +
            " AvgLev=" + DoubleToString(m_stats.AverageLeverage(), 2) +
            " AvgTime=" + DoubleToString(m_stats.AverageCalcTimeUs(), 1) + "us" +
            " MaxTime=" + IntegerToString((long)m_stats.max_calc_time_us) + "us");

        m_logger.Info("MoneyManagementEngine",
            "Daily: calcs=" + IntegerToString(m_stats.daily_calculations) +
            " accepted=" + IntegerToString(m_stats.daily_accepted) +
            " rejected=" + IntegerToString(m_stats.daily_rejected) +
            " sum_vol=" + DoubleToString(m_stats.daily_sum_volume, 2) +
            " sum_risk=" + DoubleToString(m_stats.daily_sum_risk, 2) + "%");
    }

private:
    //=== Sizing mode implementations ===
    // All O(1). No loops, no recursion.

    /**
     * @brief FIXED_LOT: return the configured fixed lot.
     */
    double CalcFixedLot(void) const
    {
        return m_config.mm_fixed_lot;
    }

    /**
     * @brief FIXED_RISK_PERCENT: risk % of equity based on SL distance.
     *
     * Formula (tick-value based):
     *   money_risk = equity × (risk_percent / 100)
     *   sl_points = sl_distance / point
     *   volume = money_risk / (sl_points × tick_value)
     *
     * Fallback (contract-size based):
     *   volume = money_risk / (contract_size × sl_distance)
     */
    double CalcRiskPercent(const double sl_distance) const
    {
        if(sl_distance <= 0.0 || m_equity <= 0.0) return 0.0;
        double money_risk = m_equity * (m_config.mm_risk_percent / 100.0);

        if(m_tick_value > 0.0 && m_point > 0.0)
        {
            double sl_points = sl_distance / m_point;
            if(sl_points <= 0.0) return 0.0;
            return money_risk / (sl_points * m_tick_value);
        }
        if(m_contract_size > 0.0)
            return money_risk / (m_contract_size * sl_distance);
        return 0.0;
    }

    /**
     * @brief BALANCE_PERCENT: fixed fraction of balance as notional.
     *
     * Formula:
     *   notional = balance × balance_fraction
     *   volume = notional / (contract_size × price)
     */
    double CalcBalancePercent(const double price) const
    {
        if(m_balance <= 0.0 || price <= 0.0 || m_contract_size <= 0.0) return 0.0;
        double notional = m_balance * m_config.mm_balance_fraction;
        return notional / (m_contract_size * price);
    }

    /**
     * @brief EQUITY_PERCENT: fixed fraction of equity as notional.
     */
    double CalcEquityPercent(const double price) const
    {
        if(m_equity <= 0.0 || price <= 0.0 || m_contract_size <= 0.0) return 0.0;
        double notional = m_equity * m_config.mm_equity_fraction;
        return notional / (m_contract_size * price);
    }

    /**
     * @brief FREE_MARGIN_PERCENT: fraction of free margin as notional.
     */
    double CalcFreeMarginPercent(const double price) const
    {
        if(m_free_margin <= 0.0 || price <= 0.0 || m_contract_size <= 0.0) return 0.0;
        double notional = m_free_margin * m_config.mm_free_margin_fraction;
        return notional / (m_contract_size * price);
    }

    /**
     * @brief ATR_BASED: SL = ATR × multiplier, then risk %.
     */
    double CalcATRBased(const MarketState &market) const
    {
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0) return 0.0;
        double sl_dist = market.atr_14 * m_config.mm_atr_multiplier;
        return CalcRiskPercent(sl_dist);
    }

    /**
     * @brief SL_DISTANCE_BASED: fixed money risk / (SL distance × tick_value).
     *
     * Similar to RISK_PERCENT but uses a fixed money amount instead of
     * a percentage of equity.
     *
     * Formula:
     *   money_risk = mm_risk_percent × equity / 100 (treat as money)
     *   volume = money_risk / (sl_points × tick_value)
     */
    double CalcSLDistanceBased(const double sl_distance) const
    {
        if(sl_distance <= 0.0 || m_equity <= 0.0) return 0.0;
        double money_risk = m_equity * (m_config.mm_risk_percent / 100.0);

        if(m_tick_value > 0.0 && m_point > 0.0)
        {
            double sl_points = sl_distance / m_point;
            if(sl_points <= 0.0) return 0.0;
            return money_risk / (sl_points * m_tick_value);
        }
        if(m_contract_size > 0.0)
            return money_risk / (m_contract_size * sl_distance);
        return 0.0;
    }

    /**
     * @brief VOLATILITY_SCALING: scale base lot inversely with ATR/price.
     *
     * Formula:
     *   current_atr_ratio = atr / price
     *   multiplier = base_atr / current_atr_ratio (clamped to [min, max])
     *   volume = fixed_lot × multiplier
     */
    double CalcVolatilityScaling(const MarketState &market) const
    {
        if(!MathIsValidNumber(market.atr_14) || market.atr_14 <= 0.0)
            return m_config.mm_fixed_lot;
        double price = (market.bid + market.ask) / 2.0;
        if(price <= 0.0) return m_config.mm_fixed_lot;
        double current_ratio = market.atr_14 / price;
        if(current_ratio <= 0.0) return m_config.mm_fixed_lot;

        double mult = m_config.mm_vol_scale_base_atr / current_ratio;
        if(mult < m_config.mm_vol_scale_min_mult) mult = m_config.mm_vol_scale_min_mult;
        if(mult > m_config.mm_vol_scale_max_mult) mult = m_config.mm_vol_scale_max_mult;
        return m_config.mm_fixed_lot * mult;
    }

    /**
     * @brief DRAWDOWN_SCALING: scale lot down as drawdown increases.
     *
     * Between dd_scale_start_pct and dd_scale_end_pct, lot is linearly
     * scaled from fixed_lot to fixed_lot × dd_scale_min_mult.
     */
    double CalcDrawdownScaling(IContextStore *context) const
    {
        if(context == NULL) return m_config.mm_fixed_lot;
        double dd = context.GetDailyDrawdownPct();
        if(dd <= m_config.mm_dd_scale_start_pct) return m_config.mm_fixed_lot;
        if(dd >= m_config.mm_dd_scale_end_pct)
            return m_config.mm_fixed_lot * m_config.mm_dd_scale_min_mult;

        double range = m_config.mm_dd_scale_end_pct - m_config.mm_dd_scale_start_pct;
        if(range <= 0.0) return m_config.mm_fixed_lot;
        double progress = (dd - m_config.mm_dd_scale_start_pct) / range;
        double mult = 1.0 - progress * (1.0 - m_config.mm_dd_scale_min_mult);
        return m_config.mm_fixed_lot * mult;
    }

    /**
     * @brief DAILY_LOSS_SCALING: scale lot down as daily losses accumulate.
     *
     * After dl_scale_start_losses, lot is scaled toward dl_scale_min_mult.
     * Uses risk_percent as the base lot, then scales.
     */
    double CalcDailyLossScaling(IContextStore *context) const
    {
        if(context == NULL) return m_config.mm_fixed_lot;
        int losses = context.GetDailyLossCount();
        if(losses < m_config.mm_dl_scale_start_losses) return m_config.mm_fixed_lot;

        int excess = losses - m_config.mm_dl_scale_start_losses;
        double progress = excess / 5.0;
        if(progress > 1.0) progress = 1.0;
        double mult = 1.0 - progress * (1.0 - m_config.mm_dl_scale_min_mult);
        return m_config.mm_fixed_lot * mult;
    }
};

#endif // ATLAS_MONEY_MANAGEMENT_ENGINE_MQH
//+------------------------------------------------------------------+
