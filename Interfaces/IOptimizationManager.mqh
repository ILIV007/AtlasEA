//+------------------------------------------------------------------+
//|                   Interfaces/IOptimizationManager.mqh            |
//|       AtlasEA v1.0 Step 6 - Optimization Framework Interface     |
//+------------------------------------------------------------------+
#ifndef ATLAS_IOPTIMIZATION_MANAGER_MQH
#define ATLAS_IOPTIMIZATION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IValidationManager.mqh"

/**
 * @brief Maximum parameters per optimization.
 */
#define ATLAS_OPT_MAX_PARAMS      32

/**
 * @brief Maximum parameter sets per optimization run.
 */
#define ATLAS_OPT_MAX_SETS        500

/**
 * @brief Maximum top/worst sets in the report.
 */
#define ATLAS_OPT_TOP_COUNT       10

/**
 * @brief Optimization search mode codes.
 */
#define ATLAS_OPT_SEARCH_GRID     0   ///< Exhaustive grid search
#define ATLAS_OPT_SEARCH_RANDOM   1   ///< Random search (deterministic seed)
#define ATLAS_OPT_SEARCH_MANUAL   2   ///< Manual parameter sets

/**
 * @brief Objective function codes.
 */
#define ATLAS_OPT_OBJ_NET_PROFIT     0   ///< Maximize net profit
#define ATLAS_OPT_OBJ_PROFIT_FACTOR  1   ///< Maximize profit factor
#define ATLAS_OPT_OBJ_MIN_DD         2   ///< Minimize drawdown
#define ATLAS_OPT_OBJ_SHARPE         3   ///< Maximize Sharpe ratio
#define ATLAS_OPT_OBJ_RECOVERY       4   ///< Maximize recovery factor
#define ATLAS_OPT_OBJ_BALANCED       5   ///< Balanced composite score
#define ATLAS_OPT_OBJ_CUSTOM         6   ///< Custom weighted score

/**
 * @brief Parameter type codes.
 */
#define ATLAS_PARAM_INT     0
#define ATLAS_PARAM_DOUBLE  1
#define ATLAS_PARAM_BOOL    2
#define ATLAS_PARAM_ENUM    3

/**
 * @brief Parameter validation rule codes.
 */
#define ATLAS_PVR_OK                0   ///< Valid
#define ATLAS_PVR_FAST_LT_SLOW      1   ///< Fast EMA >= Slow EMA
#define ATLAS_PVR_RISK_EXCEEDED     2   ///< Risk > max risk
#define ATLAS_PVR_SL_INVALID        3   ///< SL <= 0
#define ATLAS_PVR_TP_INVALID        4   ///< TP <= 0
#define ATLAS_PVR_ATR_MULT_INVALID  5   ///< ATR multiplier <= 0
#define ATLAS_PVR_TRAILING_STEP     6   ///< Trailing step < broker step
#define ATLAS_PVR_EXPOSURE_INVALID  7   ///< Max exposure > 100%
#define ATLAS_PVR_SESSION_INVALID   8   ///< Invalid session combination
#define ATLAS_PVR_DUPLICATE_NAME    9   ///< Duplicate profile name
#define ATLAS_PVR_RANGE_INVALID     10  ///< Min > max or step <= 0
#define ATLAS_PVR_VALUE_OUT_OF_RANGE 11 ///< Value outside [min, max]

/**
 * @brief Anti-overfitting rejection codes.
 */
#define ATLAS_AOF_OK                    0
#define ATLAS_AOF_TOO_FEW_TRADES        1   ///< Trade count below minimum
#define ATLAS_AOF_UNSTABLE_EQUITY       2   ///< Equity curve too volatile
#define ATLAS_AOF_SMALL_SAMPLE          3   ///< Depends on very small samples
#define ATLAS_AOF_WF_FAILED             4   ///< Failed walk-forward
#define ATLAS_AOF_MC_FAILED             5   ///< Failed Monte Carlo
#define ATLAS_AOF_TRAIN_VAL_DEVIATION   6   ///< Large train/validation deviation
#define ATLAS_AOF_UNREALISTIC_PF        7   ///< Unrealistic profit factor
#define ATLAS_AOF_NEGATIVE_NET_PROFIT   8   ///< Net profit < 0

/**
 * @struct ParameterDef
 * @brief Definition of a single optimizable parameter.
 */
struct ParameterDef
{
    string name;            ///< Parameter name (e.g., "ma_fast_period")
    int    type;            ///< ATLAS_PARAM_*
    double min_val;         ///< Minimum value
    double max_val;         ///< Maximum value
    double default_val;     ///< Default value
    double step;            ///< Step size (for grid search)
    bool   enabled;         ///< Is this parameter optimized?
    int    enum_count;      ///< Number of valid enum values (for ENUM type)

    ParameterDef(void)
    {
        name        = "";
        type        = ATLAS_PARAM_INT;
        min_val     = 0.0;
        max_val     = 0.0;
        default_val = 0.0;
        step        = 1.0;
        enabled     = false;
        enum_count  = 0;
    }
};

/**
 * @struct ParameterValue
 * @brief A single parameter's value in a parameter set.
 */
struct ParameterValue
{
    string name;    ///< Parameter name
    double value;   ///< Parameter value (double covers int/double/bool/enum)

    ParameterValue(void)
    {
        name  = "";
        value = 0.0;
    }
};

/**
 * @struct ParameterSet
 * @brief A complete set of parameter values.
 */
struct ParameterSet
{
    ParameterValue values[ATLAS_OPT_MAX_PARAMS];
    int    count;               ///< Number of parameters in this set
    int    set_index;           ///< Index in the optimization run
    bool   valid;               ///< Passed validation?
    int    validation_code;     ///< ATLAS_PVR_* (if invalid)
    string validation_detail;   ///< Validation failure detail

    ParameterSet(void)
    {
        count           = 0;
        set_index       = 0;
        valid           = true;
        validation_code = ATLAS_PVR_OK;
        validation_detail = "";
    }
};

/**
 * @struct OptimizationScore
 * @brief Composite optimization score for a parameter set.
 */
struct OptimizationScore
{
    double total_score;         ///< Composite score [0, 100]
    double profit_score;        ///< Profit component
    double drawdown_score;      ///< Drawdown component (inverted)
    double risk_score;          ///< Risk component
    double trade_count_score;   ///< Trade count adequacy
    double consistency_score;   ///< Consistency component
    double recovery_score;      ///< Recovery factor component
    double stability_score;     ///< Stability component
    double wf_score;            ///< Walk-forward score
    double mc_score;            ///< Monte Carlo score

    OptimizationScore(void)
    {
        total_score       = 0.0;
        profit_score      = 0.0;
        drawdown_score    = 0.0;
        risk_score        = 0.0;
        trade_count_score = 0.0;
        consistency_score = 0.0;
        recovery_score    = 0.0;
        stability_score   = 0.0;
        wf_score          = 0.0;
        mc_score          = 0.0;
    }
};

/**
 * @struct ParameterSetResult
 * @brief Result of evaluating one parameter set.
 */
struct ParameterSetResult
{
    ParameterSet      params;       ///< The parameter set
    ValidationReport  report;       ///< Validation report for this set
    OptimizationScore score;        ///< Composite optimization score
    int               anti_overfit_code;  ///< ATLAS_AOF_* (0 = pass)
    string            anti_overfit_detail;
    bool              rejected;     ///< Was this set rejected (validation or anti-overfit)?

    ParameterSetResult(void)
    {
        anti_overfit_code   = ATLAS_AOF_OK;
        anti_overfit_detail = "";
        rejected            = false;
    }
};

/**
 * @struct OptimizationConfig
 * @brief Configuration for an optimization run.
 */
struct OptimizationConfig
{
    int    search_mode;          ///< ATLAS_OPT_SEARCH_*
    int    objective;            ///< ATLAS_OPT_OBJ_*
    ulong  random_seed;          ///< Deterministic seed for random search
    int    max_iterations;       ///< Maximum iterations (for random search)
    bool   run_walk_forward;     ///< Run walk-forward per parameter set
    bool   run_monte_carlo;      ///< Run Monte Carlo per parameter set
    int    wf_train_bars;        ///< Walk-forward training window
    int    wf_validate_bars;     ///< Walk-forward validation window
    bool   wf_expanding;         ///< Expanding windows
    int    mc_simulations;       ///< Monte Carlo simulation count
    ulong  mc_seed;              ///< Monte Carlo seed

    //--- Anti-overfitting thresholds ---
    int    min_trades;           ///< Min trades (reject if fewer)
    double max_profit_factor;    ///< Max PF (reject if unrealistically high)
    double max_train_val_dev;    ///< Max train/validation deviation ratio
    double min_wf_pass_rate;     ///< Min WF pass rate
    double min_mc_p5_pnl;        ///< Min MC p5 net profit (relative to equity)

    //--- Scoring weights (for balanced/custom objective) ---
    double weight_profit;        ///< Weight for profit component
    double weight_drawdown;      ///< Weight for drawdown component
    double weight_risk;          ///< Weight for risk component
    double weight_trade_count;   ///< Weight for trade count
    double weight_consistency;   ///< Weight for consistency
    double weight_recovery;      ///< Weight for recovery factor
    double weight_stability;     ///< Weight for stability
    double weight_wf;            ///< Weight for walk-forward score
    double weight_mc;            ///< Weight for Monte Carlo score

    OptimizationConfig(void)
    {
        search_mode        = ATLAS_OPT_SEARCH_GRID;
        objective          = ATLAS_OPT_OBJ_BALANCED;
        random_seed        = 42;
        max_iterations     = 100;
        run_walk_forward   = true;
        run_monte_carlo    = false;
        wf_train_bars      = 500;
        wf_validate_bars   = 250;
        wf_expanding       = false;
        mc_simulations     = 100;
        mc_seed            = 12345;

        min_trades         = 30;
        max_profit_factor  = 10.0;
        max_train_val_dev  = 3.0;
        min_wf_pass_rate   = 0.60;
        min_mc_p5_pnl      = -0.05;

        weight_profit      = 15.0;
        weight_drawdown    = 20.0;
        weight_risk        = 10.0;
        weight_trade_count = 10.0;
        weight_consistency = 10.0;
        weight_recovery    = 10.0;
        weight_stability   = 10.0;
        weight_wf          = 10.0;
        weight_mc          = 5.0;
    }
};

/**
 * @struct OptimizationSummary
 * @brief Summary of the optimization run.
 */
struct OptimizationSummary
{
    int    total_sets;           ///< Total parameter sets generated
    int    valid_sets;           ///< Sets that passed validation
    int    rejected_sets;        ///< Sets rejected (validation + anti-overfit)
    int    evaluated_sets;       ///< Sets that were fully evaluated
    int    best_set_index;       ///< Index of the best parameter set
    double best_score;           ///< Best composite score
    double avg_score;            ///< Average score (of evaluated sets)
    double worst_score;          ///< Worst score (of evaluated sets)
    int    search_mode;          ///< Search mode used
    int    objective;            ///< Objective function used
    ulong  random_seed;          ///< Seed used
    int    duration_sec;         ///< Run duration in seconds

    OptimizationSummary(void)
    {
        total_sets      = 0;
        valid_sets      = 0;
        rejected_sets   = 0;
        evaluated_sets  = 0;
        best_set_index  = -1;
        best_score      = 0.0;
        avg_score       = 0.0;
        worst_score     = 0.0;
        search_mode     = ATLAS_OPT_SEARCH_GRID;
        objective       = ATLAS_OPT_OBJ_BALANCED;
        random_seed     = 0;
        duration_sec    = 0;
    }
};

/**
 * @class IOptimizationManager
 * @brief The ONLY interface through which any module may run optimization.
 *
 * Implemented by OptimizationManager (Optimization/). Consumed by
 * CoreEngine or operator-initiated optimization runs.
 *
 * Contract:
 *   - Reuses Validation Framework (no duplicated calculations).
 *   - No AI, no genetic algorithms, no machine learning.
 *   - Deterministic (same seed → same results).
 *   - No heap allocation in hot path.
 */
class IOptimizationManager
{
public:
    /**
     * @brief Run optimization.
     * @param config Optimization configuration.
     * @return true if optimization completed successfully.
     */
    virtual bool RunOptimization(const OptimizationConfig &config) = 0;

    /**
     * @brief Get the optimization summary.
     */
    virtual const OptimizationSummary& GetSummary(void) const = 0;

    /**
     * @brief Get a specific parameter set result.
     * @param index Index of the result.
     */
    virtual const ParameterSetResult& GetResult(const int index) const = 0;

    /**
     * @brief Get the number of results.
     */
    virtual int GetResultCount(void) const = 0;

    /**
     * @brief Get the best parameter set result.
     */
    virtual const ParameterSetResult& GetBestResult(void) const = 0;

    /**
     * @brief Export the optimization report as CSV.
     */
    virtual bool ExportCSV(const string filename) const = 0;

    /**
     * @brief Log the optimization summary.
     */
    virtual void LogSummary(void) const = 0;

    /**
     * @brief Initialize the optimization manager.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the optimization manager.
     */
    virtual void Shutdown(void) = 0;

    virtual ~IOptimizationManager(void) {}
};

/**
 * @brief Get the name of a search mode.
 */
string OptimizationSearchModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_OPT_SEARCH_GRID:   return "GRID";
        case ATLAS_OPT_SEARCH_RANDOM: return "RANDOM";
        case ATLAS_OPT_SEARCH_MANUAL: return "MANUAL";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of an objective function.
 */
string OptimizationObjectiveName(const int obj)
{
    switch(obj)
    {
        case ATLAS_OPT_OBJ_NET_PROFIT:    return "NET_PROFIT";
        case ATLAS_OPT_OBJ_PROFIT_FACTOR: return "PROFIT_FACTOR";
        case ATLAS_OPT_OBJ_MIN_DD:        return "MIN_DRAWDOWN";
        case ATLAS_OPT_OBJ_SHARPE:        return "SHARPE";
        case ATLAS_OPT_OBJ_RECOVERY:      return "RECOVERY";
        case ATLAS_OPT_OBJ_BALANCED:      return "BALANCED";
        case ATLAS_OPT_OBJ_CUSTOM:        return "CUSTOM";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of a parameter validation rejection.
 */
string ParamValidationRejectName(const int code)
{
    switch(code)
    {
        case ATLAS_PVR_OK:                return "OK";
        case ATLAS_PVR_FAST_LT_SLOW:      return "FAST_LT_SLOW";
        case ATLAS_PVR_RISK_EXCEEDED:     return "RISK_EXCEEDED";
        case ATLAS_PVR_SL_INVALID:        return "SL_INVALID";
        case ATLAS_PVR_TP_INVALID:        return "TP_INVALID";
        case ATLAS_PVR_ATR_MULT_INVALID:  return "ATR_MULT_INVALID";
        case ATLAS_PVR_TRAILING_STEP:     return "TRAILING_STEP";
        case ATLAS_PVR_EXPOSURE_INVALID:  return "EXPOSURE_INVALID";
        case ATLAS_PVR_SESSION_INVALID:   return "SESSION_INVALID";
        case ATLAS_PVR_DUPLICATE_NAME:    return "DUPLICATE_NAME";
        case ATLAS_PVR_RANGE_INVALID:     return "RANGE_INVALID";
        case ATLAS_PVR_VALUE_OUT_OF_RANGE: return "VALUE_OUT_OF_RANGE";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of an anti-overfitting rejection.
 */
string AntiOverfitRejectName(const int code)
{
    switch(code)
    {
        case ATLAS_AOF_OK:                  return "OK";
        case ATLAS_AOF_TOO_FEW_TRADES:      return "TOO_FEW_TRADES";
        case ATLAS_AOF_UNSTABLE_EQUITY:     return "UNSTABLE_EQUITY";
        case ATLAS_AOF_SMALL_SAMPLE:        return "SMALL_SAMPLE";
        case ATLAS_AOF_WF_FAILED:           return "WF_FAILED";
        case ATLAS_AOF_MC_FAILED:           return "MC_FAILED";
        case ATLAS_AOF_TRAIN_VAL_DEVIATION: return "TRAIN_VAL_DEVIATION";
        case ATLAS_AOF_UNREALISTIC_PF:      return "UNREALISTIC_PF";
        case ATLAS_AOF_NEGATIVE_NET_PROFIT: return "NEGATIVE_NET_PROFIT";
    }
    return "UNKNOWN";
}

#endif // ATLAS_IOPTIMIZATION_MANAGER_MQH
//+------------------------------------------------------------------+
