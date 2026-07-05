//+------------------------------------------------------------------+
//|               Trading/MoneyManagement/MoneyManagementConfig.mqh  |
//|       AtlasEA v0.2.3 - Money Management Configuration            |
//+------------------------------------------------------------------+
#ifndef ATLAS_MONEY_MANAGEMENT_CONFIG_LEGACY_MQH
#define ATLAS_MONEY_MANAGEMENT_CONFIG_LEGACY_MQH

#include "../../Config/Settings.mqh"

/**
 * @brief Position sizing method codes.
 *
 * Exactly one of these is selected via config. The MoneyManagementEngine
 * uses the selected mode to compute the final lot size.
 */
#define ATLAS_MM_FIXED_LOT          0   ///< Fixed lot size (config.fixed_lot)
#define ATLAS_MM_RISK_PERCENT       1   ///< Risk % of equity (SL distance based)
#define ATLAS_MM_ATR_BASED          2   ///< ATR-based lot (volatility-normalized risk)
#define ATLAS_MM_BALANCE_BASED      3   ///< Fixed fraction of balance
#define ATLAS_MM_EQUITY_BASED       4   ///< Fixed fraction of equity
#define ATLAS_MM_FREE_MARGIN_BASED  5   ///< Fraction of free margin
#define ATLAS_MM_VOLATILITY_SCALING 6   ///< Scale lot inversely with volatility
#define ATLAS_MM_DRAWDOWN_SCALING   7   ///< Scale lot down as drawdown increases
#define ATLAS_MM_DAILY_LOSS_SCALING 8   ///< Scale lot down as daily losses accumulate

/**
 * @brief Money management rejection reason codes.
 */
#define ATLAS_MM_REJECT_OK                0   ///< No rejection
#define ATLAS_MM_REJECT_BELOW_MIN         1   ///< Lot below broker minimum
#define ATLAS_MM_REJECT_ABOVE_MAX         2   ///< Lot above broker maximum
#define ATLAS_MM_REJECT_STEP_INVALID      3   ///< Lot not aligned to step
#define ATLAS_MM_REJECT_MARGIN_INSUFFICIENT 4 ///< Insufficient free margin
#define ATLAS_MM_REJECT_RISK_EXCEEDED     5   ///< Risk exceeds configured max
#define ATLAS_MM_REJECT_EXPOSURE_EXCEEDED 6   ///< Exposure exceeds configured max
#define ATLAS_MM_REJECT_NAN               7   ///< Computed lot is NaN/INF
#define ATLAS_MM_REJECT_NO_DATA           8   ///< Missing required input data
#define ATLAS_MM_REJECT_ZERO              9   ///< Computed lot is zero

/**
 * @struct MoneyManagementConfig
 * @brief Complete configuration for the Money Management Engine.
 *
 * All 9 sizing modes are configured here. The active mode is selected
 * via `mode`. All modes share the min/max/step clamping and risk
 * validation thresholds.
 */
struct MoneyManagementConfig
{
    //=== Active mode ===
    int    mode;                    ///< ATLAS_MM_* (active sizing mode)

    //=== Base parameters (used by all modes) ===
    double fixed_lot;               ///< Fixed lot size (ATLAS_MM_FIXED_LOT)
    double risk_percent;            ///< Risk % of equity (ATLAS_MM_RISK_PERCENT, ATLAS_MM_DAILY_LOSS_SCALING)
    double balance_fraction;        ///< Fraction of balance (ATLAS_MM_BALANCE_BASED)
    double equity_fraction;         ///< Fraction of equity (ATLAS_MM_EQUITY_BASED)
    double free_margin_fraction;    ///< Fraction of free margin (ATLAS_MM_FREE_MARGIN_BASED)
    double sl_atr_multiplier;       ///< SL = ATR × multiplier (ATLAS_MM_ATR_BASED)

    //=== Volatility scaling ===
    double vol_scale_base_atr;      ///< Reference ATR for vol scaling (lot scales inversely)
    double vol_scale_min_mult;      ///< Minimum multiplier (when ATR is very high)
    double vol_scale_max_mult;      ///< Maximum multiplier (when ATR is very low)

    //=== Drawdown scaling ===
    double dd_scale_start_pct;      ///< Drawdown % at which scaling begins (e.g., 2.0)
    double dd_scale_end_pct;        ///< Drawdown % at which lot is fully reduced (e.g., 5.0)
    double dd_scale_min_mult;       ///< Minimum multiplier at dd_scale_end_pct (e.g., 0.25)

    //=== Daily loss scaling ===
    double dl_scale_start_losses;   ///< Number of daily losses at which scaling begins
    double dl_scale_min_mult;       ///< Minimum multiplier after max losses (e.g., 0.5)

    //=== Risk validation thresholds ===
    double max_risk_percent;        ///< Max risk per trade (reject if exceeded)
    double max_exposure_pct;        ///< Max total exposure (reject if exceeded)
    double min_free_margin_pct;     ///< Min free margin as % of equity (reject if below)

    //=== Lot clamping ===
    double min_lot;                 ///< Minimum lot (from broker, cached)
    double max_lot;                 ///< Maximum lot (from broker, cached)
    double lot_step;                ///< Lot step (from broker, cached)
    int    volume_digits;           ///< Digits for volume rounding

    /**
     * @brief Default constructor with sensible defaults.
     */
    MoneyManagementConfig(void)
    {
        mode                 = ATLAS_MM_RISK_PERCENT;
        fixed_lot            = 0.10;
        risk_percent         = 1.0;       // 1% of equity
        balance_fraction     = 0.02;      // 2% of balance
        equity_fraction      = 0.02;      // 2% of equity
        free_margin_fraction = 0.10;      // 10% of free margin
        sl_atr_multiplier    = 2.0;       // SL = 2 × ATR

        vol_scale_base_atr   = 0.0010;    // Reference ATR/price ratio
        vol_scale_min_mult   = 0.25;      // Min 25% of base lot (high vol)
        vol_scale_max_mult   = 2.00;      // Max 200% of base lot (low vol)

        dd_scale_start_pct   = 2.0;       // Start scaling at 2% drawdown
        dd_scale_end_pct     = 5.0;       // Full reduction at 5% drawdown
        dd_scale_min_mult    = 0.25;      // Min 25% of base lot at max DD

        dl_scale_start_losses = 3;        // Start scaling after 3 losses
        dl_scale_min_mult     = 0.50;     // Min 50% of base lot after many losses

        max_risk_percent     = 3.0;       // Max 3% risk per trade
        max_exposure_pct     = 20.0;      // Max 20% total exposure
        min_free_margin_pct  = 30.0;      // Min 30% free margin

        min_lot              = 0.01;
        max_lot              = 10.0;
        lot_step             = 0.01;
        volume_digits        = 2;
    }
};

/**
 * @struct MoneyManagementStats
 * @brief Statistics tracked by the Money Management Engine.
 *
 * All counters are cumulative for the session. Reset via ResetStats().
 */
struct MoneyManagementStats
{
    ulong total_calculations;       ///< Total CalculateLot() calls
    ulong total_accepted;           ///< Lots that passed validation
    ulong total_rejected;           ///< Lots that were rejected

    double sum_lot;                 ///< Sum of all accepted lots (for average)
    double max_lot_seen;            ///< Largest accepted lot
    double min_lot_seen;            ///< Smallest accepted lot

    double sum_risk_pct;            ///< Sum of risk % (for average)
    double sum_margin_used;         ///< Sum of margin used (for average)
    double sum_leverage;            ///< Sum of leverage (for average)

    int    reject_counts[10];       ///< Per-reason rejection counts

    /**
     * @brief Default constructor — zero everything.
     */
    MoneyManagementStats(void)
    {
        total_calculations = 0;
        total_accepted     = 0;
        total_rejected     = 0;
        sum_lot            = 0.0;
        max_lot_seen       = 0.0;
        min_lot_seen       = 0.0;
        sum_risk_pct       = 0.0;
        sum_margin_used    = 0.0;
        sum_leverage       = 0.0;
        for(int i = 0; i < 10; i++) reject_counts[i] = 0;
    }

    /**
     * @brief Get the average lot size.
     */
    double AverageLot(void) const
    {
        if(total_accepted == 0) return 0.0;
        return sum_lot / (double)total_accepted;
    }

    /**
     * @brief Get the average risk %.
     */
    double AverageRisk(void) const
    {
        if(total_accepted == 0) return 0.0;
        return sum_risk_pct / (double)total_accepted;
    }

    /**
     * @brief Get the average margin usage.
     */
    double AverageMarginUsage(void) const
    {
        if(total_accepted == 0) return 0.0;
        return sum_margin_used / (double)total_accepted;
    }

    /**
     * @brief Get the average leverage.
     */
    double AverageLeverage(void) const
    {
        if(total_accepted == 0) return 0.0;
        return sum_leverage / (double)total_accepted;
    }
};

/**
 * @struct LotCalculationResult
 * @brief Result of a lot size calculation.
 */
struct LotCalculationResult
{
    bool   accepted;            ///< True if the lot passed all validation
    double lot;                 ///< Computed lot size (normalized)
    double raw_lot;             ///< Raw lot before normalization
    double risk_pct;            ///< Actual risk % for this trade
    double margin_required;     ///< Estimated margin required
    double leverage;            ///< Estimated leverage (notional / equity)
    int    reject_reason;       ///< ATLAS_MM_REJECT_* (if rejected)
    string reject_detail;       ///< Human-readable rejection detail
    string mode_name;           ///< Name of the sizing mode used

    LotCalculationResult(void)
    {
        accepted        = false;
        lot             = 0.0;
        raw_lot         = 0.0;
        risk_pct        = 0.0;
        margin_required = 0.0;
        leverage        = 0.0;
        reject_reason   = ATLAS_MM_REJECT_OK;
        reject_detail   = "";
        mode_name       = "";
    }
};

/**
 * @brief Get the name of a sizing mode.
 */
string MoneyManagementModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_MM_FIXED_LOT:          return "FIXED_LOT";
        case ATLAS_MM_RISK_PERCENT:       return "RISK_PERCENT";
        case ATLAS_MM_ATR_BASED:          return "ATR_BASED";
        case ATLAS_MM_BALANCE_BASED:      return "BALANCE_BASED";
        case ATLAS_MM_EQUITY_BASED:       return "EQUITY_BASED";
        case ATLAS_MM_FREE_MARGIN_BASED:  return "FREE_MARGIN_BASED";
        case ATLAS_MM_VOLATILITY_SCALING: return "VOLATILITY_SCALING";
        case ATLAS_MM_DRAWDOWN_SCALING:   return "DRAWDOWN_SCALING";
        case ATLAS_MM_DAILY_LOSS_SCALING: return "DAILY_LOSS_SCALING";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of a rejection reason.
 */
string MoneyManagementRejectName(const int reason)
{
    switch(reason)
    {
        case ATLAS_MM_REJECT_OK:                  return "OK";
        case ATLAS_MM_REJECT_BELOW_MIN:           return "BELOW_MIN";
        case ATLAS_MM_REJECT_ABOVE_MAX:           return "ABOVE_MAX";
        case ATLAS_MM_REJECT_STEP_INVALID:        return "STEP_INVALID";
        case ATLAS_MM_REJECT_MARGIN_INSUFFICIENT: return "MARGIN_INSUFFICIENT";
        case ATLAS_MM_REJECT_RISK_EXCEEDED:       return "RISK_EXCEEDED";
        case ATLAS_MM_REJECT_EXPOSURE_EXCEEDED:   return "EXPOSURE_EXCEEDED";
        case ATLAS_MM_REJECT_NAN:                 return "NAN";
        case ATLAS_MM_REJECT_NO_DATA:             return "NO_DATA";
        case ATLAS_MM_REJECT_ZERO:                return "ZERO";
    }
    return "UNKNOWN";
}

#endif // ATLAS_MONEY_MANAGEMENT_CONFIG_LEGACY_MQH
//+------------------------------------------------------------------+
