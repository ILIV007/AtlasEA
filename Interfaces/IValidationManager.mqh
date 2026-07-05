//+------------------------------------------------------------------+
//|                   Interfaces/IValidationManager.mqh              |
//|       AtlasEA v1.0 Step 5 - Validation Framework Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_IVALIDATION_MANAGER_MQH
#define ATLAS_IVALIDATION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Validation/ValidationConfig.mqh"

/**
 * @brief Maximum trades a validation can process (fixed-size, no heap).
 */
#define ATLAS_VAL_MAX_TRADES     2000

/**
 * @brief Maximum equity curve points.
 */
#define ATLAS_VAL_MAX_CURVE_PTS  2000

/**
 * @brief Maximum walk-forward segments.
 */
#define ATLAS_VAL_MAX_SEGMENTS   20

/**
 * @brief Maximum Monte Carlo simulations.
 */
#define ATLAS_VAL_MAX_SIMS       1000

/**
 * @brief Validation pass/fail verdict codes.
 */
#define ATLAS_VAL_PASS             0
#define ATLAS_VAL_FAIL             1
#define ATLAS_VAL_INCOMPLETE       2

/**
 * @brief Validation run type codes.
 */
#define ATLAS_VAL_RUN_BACKTEST    0
#define ATLAS_VAL_RUN_WALKFORWARD 1
#define ATLAS_VAL_RUN_MONTECARLO  2

/**
 * @struct TradeRecord
 * @brief A single closed trade record for validation analysis.
 */
struct TradeRecord
{
    int      trade_number;       ///< Sequential trade number
    string   trade_id;           ///< Trade identifier
    int      strategy_id;        ///< Producing strategy
    int      direction;          ///< BUY(1) / SELL(-1)
    double   volume;             ///< Filled volume
    double   entry_price;        ///< Entry price
    double   exit_price;         ///< Exit price
    double   stop_loss;          ///< SL at exit
    double   take_profit;        ///< TP at exit
    double   realized_pnl;       ///< Realized PnL (account currency)
    double   realized_pips;      ///< Realized PnL in pips
    double   risk_amount;        ///< Initial risk (|entry - SL| × value)
    double   rr_ratio;           ///< Realized R:R ratio
    datetime open_time;          ///< Position open time
    datetime close_time;         ///< Position close time
    ulong    holding_time_sec;   ///< Holding time in seconds
    int      exit_reason;        ///< Exit reason code
    bool     is_win;             ///< PnL > 0
    bool     is_loss;            ///< PnL < 0

    TradeRecord(void)
    {
        trade_number    = 0;
        trade_id        = "";
        strategy_id     = 0;
        direction       = 0;
        volume          = 0.0;
        entry_price     = 0.0;
        exit_price      = 0.0;
        stop_loss       = 0.0;
        take_profit     = 0.0;
        realized_pnl    = 0.0;
        realized_pips   = 0.0;
        risk_amount     = 0.0;
        rr_ratio        = 0.0;
        open_time       = 0;
        close_time      = 0;
        holding_time_sec = 0;
        exit_reason     = 0;
        is_win          = false;
        is_loss         = false;
    }
};

/**
 * @struct PerformanceMetrics
 * @brief Complete backtest performance metrics (19 metrics).
 */
struct PerformanceMetrics
{
    //--- Trade counts ---
    int    total_trades;            ///< Total closed trades
    int    winning_trades;          ///< Trades with PnL > 0
    int    losing_trades;           ///< Trades with PnL < 0
    int    breakeven_trades;        ///< Trades with PnL == 0

    //--- Rates ---
    double win_rate;                ///< winning_trades / total_trades (0..1)
    double loss_rate;               ///< losing_trades / total_trades (0..1)

    //--- PnL ---
    double net_profit;              ///< Total realized PnL
    double gross_profit;            ///< Sum of winning PnL
    double gross_loss;              ///< Sum of losing PnL (negative)
    double largest_win;             ///< Single largest winning PnL
    double largest_loss;            ///< Single largest losing PnL (negative)
    double average_win;             ///< Average winning PnL
    double average_loss;            ///< Average losing PnL (negative)

    //--- Ratios ---
    double profit_factor;           ///< gross_profit / abs(gross_loss)
    double recovery_factor;         ///< net_profit / max_drawdown
    double expected_payoff;         ///< Expected PnL per trade
    double payoff_ratio;            ///< average_win / abs(average_loss)

    //--- Risk-adjusted ---
    double sharpe_ratio;            ///< Annualized Sharpe ratio
    double sortino_ratio;           ///< Annualized Sortino ratio

    //--- Drawdown ---
    double max_drawdown;            ///< Maximum drawdown (absolute)
    double max_drawdown_pct;        ///< Maximum drawdown (%)
    double average_drawdown;        ///< Average drawdown
    double max_drawdown_duration;   ///< Max DD duration (seconds)

    //--- Streaks ---
    int    max_consecutive_losses;  ///< Max consecutive losing trades
    int    max_consecutive_wins;    ///< Max consecutive winning trades

    //--- Time ---
    double average_holding_time;    ///< Average holding time (seconds)
    double average_rr;              ///< Average R:R ratio

    PerformanceMetrics(void)
    {
        total_trades           = 0;
        winning_trades         = 0;
        losing_trades          = 0;
        breakeven_trades       = 0;
        win_rate               = 0.0;
        loss_rate              = 0.0;
        net_profit             = 0.0;
        gross_profit           = 0.0;
        gross_loss             = 0.0;
        largest_win            = 0.0;
        largest_loss           = 0.0;
        average_win            = 0.0;
        average_loss           = 0.0;
        profit_factor          = 0.0;
        recovery_factor        = 0.0;
        expected_payoff        = 0.0;
        payoff_ratio           = 0.0;
        sharpe_ratio           = 0.0;
        sortino_ratio          = 0.0;
        max_drawdown           = 0.0;
        max_drawdown_pct       = 0.0;
        average_drawdown       = 0.0;
        max_drawdown_duration  = 0.0;
        max_consecutive_losses = 0;
        max_consecutive_wins   = 0;
        average_holding_time   = 0.0;
        average_rr             = 0.0;
    }
};

/**
 * @struct EquityCurvePoint
 * @brief A single point on the equity curve.
 */
struct EquityCurvePoint
{
    datetime timestamp;    ///< Point timestamp
    double   equity;       ///< Account equity
    double   balance;      ///< Account balance (realized)
    double   drawdown;     ///< Drawdown from peak (absolute)
    double   drawdown_pct; ///< Drawdown from peak (%)

    EquityCurvePoint(void)
    {
        timestamp   = 0;
        equity      = 0.0;
        balance     = 0.0;
        drawdown    = 0.0;
        drawdown_pct = 0.0;
    }
};

/**
 * @struct EquityAnalysis
 * @brief Equity curve analysis results.
 */
struct EquityAnalysis
{
    EquityCurvePoint curve[ATLAS_VAL_MAX_CURVE_PTS];
    int    curve_point_count;

    double initial_equity;
    double final_equity;
    double peak_equity;
    double trough_equity;
    double total_return_pct;
    double max_drawdown;
    double max_drawdown_pct;
    double recovery_factor;

    //--- Returns ---
    double daily_returns[100];   ///< Last 100 daily returns
    int    daily_return_count;
    double monthly_returns[36];  ///< Last 36 monthly returns
    int    monthly_return_count;
    double avg_daily_return;
    double avg_monthly_return;
    double best_daily_return;
    double worst_daily_return;
    double best_monthly_return;
    double worst_monthly_return;

    EquityAnalysis(void)
    {
        curve_point_count    = 0;
        initial_equity       = 0.0;
        final_equity         = 0.0;
        peak_equity          = 0.0;
        trough_equity        = 0.0;
        total_return_pct     = 0.0;
        max_drawdown         = 0.0;
        max_drawdown_pct     = 0.0;
        recovery_factor      = 0.0;
        daily_return_count   = 0;
        monthly_return_count = 0;
        avg_daily_return     = 0.0;
        avg_monthly_return   = 0.0;
        best_daily_return    = 0.0;
        worst_daily_return   = 0.0;
        best_monthly_return  = 0.0;
        worst_monthly_return = 0.0;
    }
};

/**
 * @struct RiskAnalysis
 * @brief Risk analysis results.
 */
struct RiskAnalysis
{
    double max_exposure_pct;          ///< Maximum exposure %
    double avg_exposure_pct;          ///< Average exposure %
    double max_margin_usage_pct;      ///< Maximum margin usage %
    double avg_margin_usage_pct;      ///< Average margin usage %
    double max_daily_loss;            ///< Maximum single-day loss
    double max_weekly_loss;           ///< Maximum single-week loss
    double max_position_size;         ///< Maximum position size (lots)
    double avg_position_size;         ///< Average position size (lots)

    //--- Risk distribution (histogram of R:R outcomes) ---
    int    rr_buckets[10];            ///< Count of trades in each R:R bucket
    double rr_bucket_labels[10];      ///< Bucket labels (R multiples)

    //--- Loss streaks ---
    int    max_loss_streak;           ///< Maximum consecutive losses
    double max_loss_streak_pnl;       ///< Total PnL during max loss streak

    RiskAnalysis(void)
    {
        max_exposure_pct     = 0.0;
        avg_exposure_pct     = 0.0;
        max_margin_usage_pct = 0.0;
        avg_margin_usage_pct = 0.0;
        max_daily_loss       = 0.0;
        max_weekly_loss      = 0.0;
        max_position_size    = 0.0;
        avg_position_size    = 0.0;
        max_loss_streak      = 0;
        max_loss_streak_pnl  = 0.0;
        for(int i = 0; i < 10; i++)
        {
            rr_buckets[i]    = 0;
            rr_bucket_labels[i] = 0.0;
        }
    }
};

/**
 * @struct PassFailCriteria
 * @brief Configurable pass/fail thresholds.
 */
struct PassFailCriteria
{
    double min_profit_factor;     ///< Minimum profit factor (0 = skip)
    double max_drawdown_pct;      ///< Maximum drawdown % (0 = skip)
    double min_win_rate;          ///< Minimum win rate (0..1, 0 = skip)
    int    min_trade_count;       ///< Minimum trade count (0 = skip)
    double max_exposure_pct;      ///< Maximum exposure % (0 = skip)
    double min_net_profit;        ///< Minimum net profit (0 = skip)
    double min_sharpe_ratio;      ///< Minimum Sharpe ratio (0 = skip)
    int    max_consecutive_losses; ///< Max consecutive losses (0 = skip)

    PassFailCriteria(void)
    {
        min_profit_factor     = 1.2;
        max_drawdown_pct      = 25.0;
        min_win_rate          = 0.35;
        min_trade_count       = 30;
        max_exposure_pct      = 25.0;
        min_net_profit        = 0.0;
        min_sharpe_ratio      = 0.5;
        max_consecutive_losses = 6;
    }
};

/**
 * @struct ValidationReport
 * @brief Complete validation report.
 *
 * v2 (Step 5.5): added schema_version, report_version, confidence_level,
 * confidence_factor, fingerprint, scoring_profile, scoring_breakdown,
 * wf_classification, cache_hit.
 */
struct ValidationReport
{
    //=== Schema / versioning (v2) ===
    int    schema_version;          ///< Schema version for this report
    int    report_version;          ///< Report version for this report

    //=== Verdict ===
    int    verdict;                ///< ATLAS_VAL_PASS / FAIL / INCOMPLETE
    int    run_type;               ///< ATLAS_VAL_RUN_*
    string run_name;               ///< Name of the validation run
    string start_time;             ///< Run start time (string)
    string end_time;               ///< Run end time (string)
    int    duration_sec;           ///< Run duration in seconds

    //=== Metrics ===
    PerformanceMetrics performance;
    EquityAnalysis     equity;
    RiskAnalysis       risk;

    //=== Pass/fail ===
    PassFailCriteria   criteria;
    int    criteria_checked;
    int    criteria_passed;
    int    criteria_failed;
    string fail_reasons[16];       ///< Reasons for failure (if any)
    int    fail_reason_count;

    //=== Validation score [0, 100] ===
    double validation_score;

    //=== Scoring (v2) ===
    int    scoring_profile;         ///< ATLAS_SCORING_* profile used
    double score_profit_factor;     ///< Score breakdown components
    double score_win_rate;
    double score_drawdown;
    double score_sharpe;
    double score_recovery;
    double score_trade_count;
    double score_sortino;

    //=== Confidence (v2) ===
    int    confidence_level;        ///< ATLAS_CONFIDENCE_LOW/MEDIUM/HIGH/VERY_HIGH
    double confidence_factor;       ///< Overall confidence [0, 1]
    double confidence_trade_count;  ///< Trade count factor
    double confidence_wf_stability; ///< WF stability factor
    double confidence_mc_stability; ///< MC stability factor
    double confidence_dd_consistency; ///< DD consistency factor

    //=== Dataset fingerprint (v2) ===
    string fingerprint_symbol;      ///< Fingerprint: symbol
    int    fingerprint_trade_count; ///< Fingerprint: trade count
    datetime fingerprint_data_from; ///< Fingerprint: data start
    datetime fingerprint_data_to;   ///< Fingerprint: data end
    ulong  fingerprint_hash;        ///< Fingerprint: hash

    //=== Walk-forward summary (v2) ===
    int    wf_classification;       ///< ATLAS_WF_STABLE/WEAK/UNSTABLE/OVERFITTED
    double wf_pass_rate;            ///< WF pass rate [0, 1]
    double wf_pf_cv;                ///< PF coefficient of variation

    //=== Cache (v2) ===
    bool   cache_hit;               ///< Was this result from cache?

    //--- Walk-forward / Monte Carlo specifics ---
    int    segment_count;          ///< Number of WF segments
    int    simulation_count;       ///< Number of MC simulations

    ValidationReport(void)
    {
        schema_version          = ATLAS_VALIDATION_SCHEMA_VERSION;
        report_version          = ATLAS_VALIDATION_REPORT_VERSION;
        verdict                 = ATLAS_VAL_INCOMPLETE;
        run_type                = ATLAS_VAL_RUN_BACKTEST;
        run_name                = "";
        start_time              = "";
        end_time                = "";
        duration_sec            = 0;
        criteria_checked        = 0;
        criteria_passed         = 0;
        criteria_failed         = 0;
        fail_reason_count       = 0;
        validation_score        = 0.0;
        scoring_profile         = ATLAS_SCORING_BALANCED;
        score_profit_factor     = 0.0;
        score_win_rate          = 0.0;
        score_drawdown          = 0.0;
        score_sharpe            = 0.0;
        score_recovery          = 0.0;
        score_trade_count       = 0.0;
        score_sortino           = 0.0;
        confidence_level        = ATLAS_CONFIDENCE_LOW;
        confidence_factor       = 0.0;
        confidence_trade_count  = 0.0;
        confidence_wf_stability = 0.0;
        confidence_mc_stability = 0.0;
        confidence_dd_consistency = 0.0;
        fingerprint_symbol      = "";
        fingerprint_trade_count = 0;
        fingerprint_data_from   = 0;
        fingerprint_data_to     = 0;
        fingerprint_hash        = 0;
        wf_classification       = ATLAS_WF_WEAK;
        wf_pass_rate            = 0.0;
        wf_pf_cv                = 0.0;
        cache_hit               = false;
        segment_count           = 0;
        simulation_count        = 0;
    }
};

/**
 * @class IValidationManager
 * @brief The ONLY interface through which any module may run validation.
 *
 * Implemented by ValidationManager (Validation/). Consumed by CoreEngine
 * or operator-initiated validation runs.
 *
 * Contract:
 *   - Uses existing Testing framework, Replay engine, and Metrics.
 *   - Does not duplicate functionality.
 *   - Deterministic (same input → same output).
 *   - No heap allocation in hot path.
 *   - No architecture redesign.
 */
class IValidationManager
{
public:
    /**
     * @brief Run a full historical backtest.
     * @param from_time Start timestamp.
     * @param to_time End timestamp.
     * @return ValidationReport with results.
     */
    virtual ValidationReport RunBacktest(const datetime from_time,
                                          const datetime to_time) = 0;

    /**
     * @brief Run walk-forward analysis.
     * @param from_time Start timestamp.
     * @param to_time End timestamp.
     * @param train_bars Training window size (bars).
     * @param validate_bars Validation window size (bars).
     * @param expanding Use expanding windows (true) or rolling (false).
     * @return ValidationReport with aggregated results.
     */
    virtual ValidationReport RunWalkForward(const datetime from_time,
                                             const datetime to_time,
                                             const int train_bars,
                                             const int validate_bars,
                                             const bool expanding) = 0;

    /**
     * @brief Run Monte Carlo simulation.
     * @param simulation_count Number of simulations to run.
     * @param seed Random seed (deterministic).
     * @param shuffle_trades Shuffle trade order.
     * @param vary_spread Vary spread.
     * @param vary_slippage Vary slippage.
     * @param vary_delay Vary execution delay.
     * @return ValidationReport with confidence intervals.
     */
    virtual ValidationReport RunMonteCarlo(const int simulation_count,
                                            const ulong seed,
                                            const bool shuffle_trades,
                                            const bool vary_spread,
                                            const bool vary_slippage,
                                            const bool vary_delay) = 0;

    /**
     * @brief Get the last validation report.
     */
    virtual const ValidationReport& GetLastReport(void) const = 0;

    /**
     * @brief Set pass/fail criteria.
     */
    virtual void SetCriteria(const PassFailCriteria &criteria) = 0;

    /**
     * @brief Set the full validation configuration (v2: Step 5.5).
     * Includes thresholds, scoring profile, quality gate, cache settings.
     */
    virtual void SetValidationConfig(const ValidationConfig &config) = 0;

    /**
     * @brief Set the scoring profile (v2: Step 5.5).
     * @param profile ATLAS_SCORING_* code.
     */
    virtual void SetScoringProfile(const int profile) = 0;

    /**
     * @brief Export report as CSV.
     * @param filename Output filename.
     * @return true if exported successfully.
     */
    virtual bool ExportCSV(const string filename) const = 0;

    /**
     * @brief Log the report summary.
     */
    virtual void LogReport(void) const = 0;

    /**
     * @brief Initialize the validation manager.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the validation manager.
     */
    virtual void Shutdown(void) = 0;

    virtual ~IValidationManager(void) {}
};

#endif // ATLAS_IVALIDATION_MANAGER_MQH
//+------------------------------------------------------------------+
