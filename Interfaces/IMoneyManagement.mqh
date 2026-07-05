//+------------------------------------------------------------------+
//|                    Interfaces/IMoneyManagement.mqh               |
//|       AtlasEA v1.0 - Money Management Interface                  |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMONEY_MANAGEMENT_MQH
#define ATLAS_IMONEY_MANAGEMENT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"

/**
 * @brief Position sizing mode codes.
 *
 * Exactly one mode is active at a time, selected via AtlasConfig.
 */
#define ATLAS_MM_FIXED_LOT            0   ///< Fixed lot size
#define ATLAS_MM_FIXED_RISK_PERCENT   1   ///< Risk % of equity (SL-based)
#define ATLAS_MM_BALANCE_PERCENT      2   ///< Fixed fraction of balance
#define ATLAS_MM_EQUITY_PERCENT       3   ///< Fixed fraction of equity
#define ATLAS_MM_FREE_MARGIN_PERCENT  4   ///< Fraction of free margin
#define ATLAS_MM_ATR_BASED            5   ///< ATR-normalized risk
#define ATLAS_MM_SL_DISTANCE_BASED    6   ///< SL distance based (money risk)
#define ATLAS_MM_VOLATILITY_SCALING   7   ///< Scale inversely with volatility
#define ATLAS_MM_DRAWDOWN_SCALING     8   ///< Scale down as drawdown increases
#define ATLAS_MM_DAILY_LOSS_SCALING   9   ///< Scale down as daily losses accumulate

/**
 * @brief Money management rejection reason codes.
 * Structured error codes returned by CalculateVolume.
 */
#define ATLAS_MM_OK                       0   ///< Success
#define ATLAS_MM_ERR_BELOW_MIN            1   ///< Volume below broker minimum
#define ATLAS_MM_ERR_ABOVE_MAX            2   ///< Volume above broker maximum
#define ATLAS_MM_ERR_STEP_INVALID         3   ///< Volume not aligned to step
#define ATLAS_MM_ERR_MARGIN_INSUFFICIENT  4   ///< Insufficient free margin
#define ATLAS_MM_ERR_RISK_EXCEEDED        5   ///< Risk exceeds configured limit
#define ATLAS_MM_ERR_DAILY_LOSS_EXCEEDED  6   ///< Daily loss limit exceeded
#define ATLAS_MM_ERR_DRAWDOWN_ACTIVE      7   ///< Drawdown protection active
#define ATLAS_MM_ERR_EXPOSURE_EXCEEDED    8   ///< Exposure limit exceeded
#define ATLAS_MM_ERR_INVALID_ATR          9   ///< ATR is NaN/INF/<=0
#define ATLAS_MM_ERR_INVALID_SL          10   ///< Stop loss is NaN/INF/<=0
#define ATLAS_MM_ERR_INVALID_SYMBOL      11   ///< Symbol info unavailable
#define ATLAS_MM_ERR_NAN                 12   ///< Computed volume is NaN/INF
#define ATLAS_MM_ERR_ZERO                13   ///< Computed volume is zero
#define ATLAS_MM_ERR_NO_DATA             14   ///< Missing required input data
#define ATLAS_MM_ERR_KILLSWITCH          15   ///< Kill switch active

/**
 * @struct VolumeResult
 * @brief Structured result of a volume calculation.
 *
 * Returned by IMoneyManagement::CalculateVolume. Contains the final
 * validated volume, or a structured error code with detail.
 */
struct VolumeResult
{
    bool   accepted;            ///< True if volume passed all validation
    double volume;              ///< Final normalized volume (lots)
    double raw_volume;          ///< Volume before normalization
    double risk_percent;        ///< Actual risk % for this trade
    double margin_required;     ///< Estimated margin required (account currency)
    double leverage;            ///< Estimated leverage (notional / equity)
    int    error_code;          ///< ATLAS_MM_ERR_* (0 if accepted)
    string error_detail;        ///< Human-readable error detail
    string mode_name;           ///< Name of the sizing mode used
    ulong  calculation_time_us; ///< Calculation time in microseconds

    VolumeResult(void)
    {
        accepted          = false;
        volume            = 0.0;
        raw_volume        = 0.0;
        risk_percent      = 0.0;
        margin_required   = 0.0;
        leverage          = 0.0;
        error_code        = ATLAS_MM_OK;
        error_detail      = "";
        mode_name         = "";
        calculation_time_us = 0;
    }
};

/**
 * @struct MoneyManagementStats
 * @brief Statistics tracked by the Money Management Engine.
 */
struct MoneyManagementStats
{
    ulong total_calculations;       ///< Total CalculateVolume calls
    ulong total_accepted;           ///< Volumes that passed validation
    ulong total_rejected;           ///< Volumes that were rejected

    double sum_volume;              ///< Sum of accepted volumes (for average)
    double max_volume;              ///< Largest accepted volume
    double min_volume;              ///< Smallest accepted volume

    double sum_risk_pct;            ///< Sum of risk % (for average)
    double sum_margin_used;         ///< Sum of margin used (for average)
    double sum_leverage;            ///< Sum of leverage (for average)

    ulong  sum_calc_time_us;        ///< Sum of calculation times (for average)
    ulong  max_calc_time_us;        ///< Peak calculation time

    int    reject_counts[16];       ///< Per-reason rejection counts

    //--- Daily statistics (reset on new trading day) ---
    int    daily_calculations;      ///< Calculations today
    int    daily_accepted;          ///< Accepted today
    int    daily_rejected;          ///< Rejected today
    double daily_sum_volume;        ///< Sum of volume today
    double daily_sum_risk;          ///< Sum of risk % today

    MoneyManagementStats(void)
    {
        total_calculations = 0;
        total_accepted     = 0;
        total_rejected     = 0;
        sum_volume         = 0.0;
        max_volume         = 0.0;
        min_volume         = 0.0;
        sum_risk_pct       = 0.0;
        sum_margin_used    = 0.0;
        sum_leverage       = 0.0;
        sum_calc_time_us   = 0;
        max_calc_time_us   = 0;
        daily_calculations = 0;
        daily_accepted     = 0;
        daily_rejected     = 0;
        daily_sum_volume   = 0.0;
        daily_sum_risk     = 0.0;
        for(int i = 0; i < 16; i++) reject_counts[i] = 0;
    }

    double AverageVolume(void) const
    {
        return (total_accepted > 0) ? sum_volume / (double)total_accepted : 0.0;
    }
    double AverageRisk(void) const
    {
        return (total_accepted > 0) ? sum_risk_pct / (double)total_accepted : 0.0;
    }
    double AverageMarginUsage(void) const
    {
        return (total_accepted > 0) ? sum_margin_used / (double)total_accepted : 0.0;
    }
    double AverageLeverage(void) const
    {
        return (total_accepted > 0) ? sum_leverage / (double)total_accepted : 0.0;
    }
    double AverageCalcTimeUs(void) const
    {
        return (total_calculations > 0) ? (double)sum_calc_time_us / (double)total_calculations : 0.0;
    }
};

/**
 * @class IMoneyManagement
 * @brief The ONLY interface through which any module may request
 *        the final order volume.
 *
 * Implemented by MoneyManagementEngine. Consumed by ExecutionEngine.
 *
 * Contract:
 *   - Neither StrategyEngine, RiskEngine, nor ExecutionEngine may
 *     calculate lot sizes. They must call this interface.
 *   - RiskEngine validates the request but never recalculates volume.
 *   - Strategies may only suggest a preferred risk profile (via the
 *     StrategyVote's suggested_volume, which is a hint, not the final).
 *   - Final volume always comes from IMoneyManagement.
 *
 * Thread safety: MQL5 single-threaded — no synchronization needed.
 */
class IMoneyManagement
{
public:
    /**
     * @brief Calculate the final validated order volume.
     *
     * This is the SINGLE ENTRY POINT for position sizing. The
     * ExecutionEngine calls this to get the final lot size for
     * an order.
     *
     * @param decision     The risk decision (contains SL, TP, direction).
     * @param market       Current market state (for ATR, volatility).
     * @param broker       Broker adapter (for account + symbol queries).
     * @param context      Context store (for drawdown, exposure, losses).
     * @return VolumeResult with accepted/rejected + volume + stats.
     */
    virtual VolumeResult CalculateVolume(const RiskDecision &decision,
                                          const MarketState &market,
                                          class IBrokerAdapter *broker,
                                          class IContextStore *context) = 0;

    /**
     * @brief Get the current statistics.
     */
    virtual MoneyManagementStats GetStats(void) const = 0;

    /**
     * @brief Reset daily statistics (called on new trading day).
     */
    virtual void ResetDaily(void) = 0;

    /**
     * @brief Reset all statistics.
     */
    virtual void ResetAll(void) = 0;

    /**
     * @brief Log the current statistics.
     */
    virtual void LogStats(void) const = 0;

    /**
     * @brief Initialize the engine.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the engine.
     */
    virtual void Shutdown(void) = 0;

    virtual ~IMoneyManagement(void) {}
};

/**
 * @brief Get the name of a sizing mode.
 */
string MoneyManagementModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_MM_FIXED_LOT:            return "FIXED_LOT";
        case ATLAS_MM_FIXED_RISK_PERCENT:   return "FIXED_RISK_PERCENT";
        case ATLAS_MM_BALANCE_PERCENT:      return "BALANCE_PERCENT";
        case ATLAS_MM_EQUITY_PERCENT:       return "EQUITY_PERCENT";
        case ATLAS_MM_FREE_MARGIN_PERCENT:  return "FREE_MARGIN_PERCENT";
        case ATLAS_MM_ATR_BASED:            return "ATR_BASED";
        case ATLAS_MM_SL_DISTANCE_BASED:    return "SL_DISTANCE_BASED";
        case ATLAS_MM_VOLATILITY_SCALING:   return "VOLATILITY_SCALING";
        case ATLAS_MM_DRAWDOWN_SCALING:     return "DRAWDOWN_SCALING";
        case ATLAS_MM_DAILY_LOSS_SCALING:   return "DAILY_LOSS_SCALING";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of an error code.
 */
string MoneyManagementErrorName(const int code)
{
    switch(code)
    {
        case ATLAS_MM_OK:                       return "OK";
        case ATLAS_MM_ERR_BELOW_MIN:            return "BELOW_MIN";
        case ATLAS_MM_ERR_ABOVE_MAX:            return "ABOVE_MAX";
        case ATLAS_MM_ERR_STEP_INVALID:         return "STEP_INVALID";
        case ATLAS_MM_ERR_MARGIN_INSUFFICIENT:  return "MARGIN_INSUFFICIENT";
        case ATLAS_MM_ERR_RISK_EXCEEDED:        return "RISK_EXCEEDED";
        case ATLAS_MM_ERR_DAILY_LOSS_EXCEEDED:  return "DAILY_LOSS_EXCEEDED";
        case ATLAS_MM_ERR_DRAWDOWN_ACTIVE:      return "DRAWDOWN_ACTIVE";
        case ATLAS_MM_ERR_EXPOSURE_EXCEEDED:    return "EXPOSURE_EXCEEDED";
        case ATLAS_MM_ERR_INVALID_ATR:          return "INVALID_ATR";
        case ATLAS_MM_ERR_INVALID_SL:           return "INVALID_SL";
        case ATLAS_MM_ERR_INVALID_SYMBOL:       return "INVALID_SYMBOL";
        case ATLAS_MM_ERR_NAN:                  return "NAN";
        case ATLAS_MM_ERR_ZERO:                 return "ZERO";
        case ATLAS_MM_ERR_NO_DATA:              return "NO_DATA";
        case ATLAS_MM_ERR_KILLSWITCH:           return "KILLSWITCH";
    }
    return "UNKNOWN";
}

#endif // ATLAS_IMONEY_MANAGEMENT_MQH
//+------------------------------------------------------------------+
