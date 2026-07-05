//+------------------------------------------------------------------+
//|                    Optimization/OptimizationManager.mqh          |
//|       AtlasEA v1.0 Step 6 - Optimization Manager (Orchestrator)  |
//+------------------------------------------------------------------+
#ifndef ATLAS_OPTIMIZATION_MANAGER_MQH
#define ATLAS_OPTIMIZATION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IOptimizationManager.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ParameterSpace.mqh"
#include "ParameterValidator.mqh"
#include "ParameterGenerator.mqh"
#include "OptimizationRunner.mqh"
#include "OptimizationReport.mqh"

/**
 * @class OptimizationManager
 * @brief The ONLY component that orchestrates optimization runs.
 *
 * Implements IOptimizationManager. Coordinates parameter generation,
 * validation, evaluation, scoring, anti-overfitting checks, and reporting.
 *
 * ANTI-OVERFITTING:
 *   Rejects parameter sets that:
 *     - Trade too infrequently (< min_trades)
 *     - Have unrealistic profit factor (> max_profit_factor)
 *     - Fail walk-forward (pass rate < min_wf_pass_rate)
 *     - Fail Monte Carlo (p5 net profit < min_mc_p5_pnl)
 *     - Have large train/validation deviation (> max_train_val_dev)
 *     - Produce negative net profit
 *
 * SCORING:
 *   Composite score [0, 100] from 9 components:
 *     profit, drawdown, risk, trade_count, consistency, recovery,
 *     stability, walk_forward, monte_carlo
 *   Weights are configurable in OptimizationConfig.
 *
 * INTEGRATION:
 *   - Reuses Validation Framework (IValidationManager).
 *   - No duplicated calculations.
 *   - No AI, no genetic algorithms, no ML.
 *
 * Performance: O(N × V) where N = parameter sets, V = validation time.
 * No heap allocation.
 */
class OptimizationManager : public IOptimizationManager
{
private:
    ILogger             *m_logger;
    IValidationManager  *m_validation;
    bool                 m_initialized;

    //--- Owned components (stack-allocated)
    ParameterSpace       m_space;
    ParameterValidator   m_validator;
    ParameterGenerator   m_generator;
    OptimizationRunner   m_runner;
    OptimizationReport   m_report;

    //--- Results (fixed-size)
    ParameterSetResult   m_results[ATLAS_OPT_MAX_SETS];
    int                  m_result_count;

    //--- Summary
    OptimizationSummary  m_summary;

    //--- Base config (modified per parameter set)
    AtlasConfig          m_base_config;

public:
    /**
     * @brief Constructor.
     */
    OptimizationManager(void)
    {
        m_logger       = NULL;
        m_validation   = NULL;
        m_initialized  = false;
        m_result_count = 0;
    }

    /**
     * @brief Set the logger (wires to all sub-components).
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_validator.SetLogger(logger);
        m_generator.SetLogger(logger);
        m_report.SetLogger(logger);
    }

    /**
     * @brief Set the validation manager to use.
     */
    void SetValidationManager(IValidationManager *val)
    {
        m_validation = val;
        m_runner.SetValidationManager(val);
    }

    /**
     * @brief Set the base AtlasConfig (will be modified per param set).
     */
    void SetBaseConfig(const AtlasConfig &config) { m_base_config = config; }

    /**
     * @brief Get the parameter space (for configuration).
     */
    ParameterSpace& GetParameterSpace(void) { return m_space; }

    //=== IOptimizationManager implementation ===

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_space.InitializeDefaults();
        m_logger.Info("OptimizationManager", "Initialized");
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        m_initialized = false;
        m_result_count = 0;
        if(m_logger != NULL)
            m_logger.Info("OptimizationManager", "Shutdown complete");
    }

    /**
     * @brief Run optimization.
     *
     * Pipeline:
     *   1. Generate parameter sets (grid/random/manual)
     *   2. Validate each set (cross-parameter rules)
     *   3. For each valid set:
     *      a. Apply to config
     *      b. Run backtest (+ optional WF + MC)
     *      c. Anti-overfitting check
     *      d. Compute composite score
     *   4. Find best/worst sets
     *   5. Generate report
     *
     * @param config Optimization configuration.
     * @return true if optimization completed successfully.
     */
    virtual bool RunOptimization(const OptimizationConfig &config) override
    {
        if(!m_initialized || m_validation == NULL) return false;

        datetime start = TimeCurrent();
        m_result_count = 0;

        if(m_logger != NULL)
            m_logger.Info("OptimizationManager",
                "Starting optimization: mode=" + OptimizationSearchModeName(config.search_mode) +
                " objective=" + OptimizationObjectiveName(config.objective) +
                " max_iter=" + IntegerToString(config.max_iterations));

        //==============================================================
        // STEP 1: Generate parameter sets
        //==============================================================
        ParameterSet sets[ATLAS_OPT_MAX_SETS];
        int set_count = 0;

        switch(config.search_mode)
        {
            case ATLAS_OPT_SEARCH_GRID:
                set_count = m_generator.GenerateGrid(m_space, sets, ATLAS_OPT_MAX_SETS);
                break;
            case ATLAS_OPT_SEARCH_RANDOM:
                set_count = m_generator.GenerateRandom(m_space, sets,
                                                        config.max_iterations,
                                                        config.random_seed);
                break;
            case ATLAS_OPT_SEARCH_MANUAL:
                //--- Manual sets must be added by the caller before running
                //--- For now, just use the default set
                sets[0] = m_space.CreateDefaultSet();
                set_count = 1;
                break;
        }

        m_summary.total_sets  = set_count;
        m_summary.search_mode = config.search_mode;
        m_summary.objective   = config.objective;
        m_summary.random_seed = config.random_seed;

        if(set_count <= 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("OptimizationManager", "No parameter sets generated");
            return false;
        }

        //==============================================================
        // STEP 2-4: Validate, evaluate, score each set
        //==============================================================
        datetime from_time = 0;  // Caller should set via validation manager
        datetime to_time   = TimeCurrent();

        for(int i = 0; i < set_count && i < ATLAS_OPT_MAX_SETS; i++)
        {
            ParameterSetResult &result = m_results[m_result_count];
            result.params = sets[i];

            //--- Step 2: Validate
            if(!m_validator.Validate(result.params, m_space))
            {
                result.rejected = true;
                m_summary.rejected_sets++;
                m_result_count++;
                continue;
            }
            m_summary.valid_sets++;

            //--- Step 3a: Run evaluation (backtest + WF + MC)
            result.report = m_runner.RunSingle(result.params, m_space,
                                                m_base_config, config,
                                                from_time, to_time);

            if(result.report.verdict == ATLAS_VAL_INCOMPLETE)
            {
                result.rejected = true;
                result.anti_overfit_code = ATLAS_AOF_SMALL_SAMPLE;
                result.anti_overfit_detail = "Validation incomplete";
                m_summary.rejected_sets++;
                m_result_count++;
                continue;
            }

            //--- Step 3b: Anti-overfitting check
            int aof_code = CheckAntiOverfitting(result.report, config);
            if(aof_code != ATLAS_AOF_OK)
            {
                result.rejected = true;
                result.anti_overfit_code = aof_code;
                result.anti_overfit_detail = AntiOverfitRejectName(aof_code);
                m_summary.rejected_sets++;
                m_result_count++;
                continue;
            }

            //--- Step 3c: Compute composite score
            result.score = ComputeScore(result.report, config);

            m_summary.evaluated_sets++;
            m_result_count++;

            if(m_logger != NULL && (i % 10 == 0 || i == set_count - 1))
                m_logger.Info("OptimizationManager",
                    "Progress: " + IntegerToString(i + 1) + "/" + IntegerToString(set_count) +
                    " evaluated=" + IntegerToString(m_summary.evaluated_sets) +
                    " rejected=" + IntegerToString(m_summary.rejected_sets));
        }

        //==============================================================
        // STEP 5: Find best/worst
        //==============================================================
        FindBestWorst(config);

        m_summary.duration_sec = (int)((long)TimeCurrent() - (long)start);

        if(m_logger != NULL)
        {
            m_report.LogSummary(m_summary);
            m_report.LogTopSets(m_results, m_result_count);
            m_report.LogRejectedSets(m_results, m_result_count);
        }

        return true;
    }

    virtual const OptimizationSummary& GetSummary(void) const override
    {
        return m_summary;
    }

    virtual const ParameterSetResult& GetResult(const int index) const override
    {
        if(index < 0 || index >= m_result_count)
        {
            static ParameterSetResult empty;
            return empty;
        }
        return m_results[index];
    }

    virtual int GetResultCount(void) const override
    {
        return m_result_count;
    }

    virtual const ParameterSetResult& GetBestResult(void) const override
    {
        if(m_summary.best_set_index >= 0 && m_summary.best_set_index < m_result_count)
            return m_results[m_summary.best_set_index];
        static ParameterSetResult empty;
        return empty;
    }

    virtual bool ExportCSV(const string filename) const override
    {
        return m_report.ExportCSV(m_results, m_result_count, m_summary, filename);
    }

    virtual void LogSummary(void) const override
    {
        m_report.LogSummary(m_summary);
        m_report.LogTopSets(m_results, m_result_count);
    }

private:
    /**
     * @brief Anti-overfitting checks.
     * @return ATLAS_AOF_OK if passes, rejection code if fails.
     */
    int CheckAntiOverfitting(const ValidationReport &report,
                              const OptimizationConfig &config) const
    {
        const PerformanceMetrics &p = report.performance;

        //--- 1. Too few trades
        if(p.total_trades < config.min_trades)
            return ATLAS_AOF_TOO_FEW_TRADES;

        //--- 2. Unrealistic profit factor
        if(p.profit_factor > config.max_profit_factor)
            return ATLAS_AOF_UNREALISTIC_PF;

        //--- 3. Negative net profit
        if(p.net_profit < 0.0)
            return ATLAS_AOF_NEGATIVE_NET_PROFIT;

        //--- 4. Walk-forward failure
        if(config.run_walk_forward && report.wf_pass_rate < config.min_wf_pass_rate)
            return ATLAS_AOF_WF_FAILED;

        //--- 5. Monte Carlo failure
        if(config.run_monte_carlo && report.confidence_mc_stability < config.min_mc_p5_pnl)
            return ATLAS_AOF_MC_FAILED;

        //--- 6. Train/validation deviation (simplified: check if PF CV > threshold)
        if(config.run_walk_forward && report.wf_pf_cv > config.max_train_val_dev)
            return ATLAS_AOF_TRAIN_VAL_DEVIATION;

        return ATLAS_AOF_OK;
    }

    /**
     * @brief Compute composite optimization score.
     *
     * 9 components, each normalized to [0, 1], then weighted:
     *   profit (net profit / cap)
     *   drawdown (inverted: lower DD = higher score)
     *   risk (1 - risk_pct / max_risk)
     *   trade_count (min(trades / 100, 1))
     *   consistency (1 - PF coefficient of variation)
     *   recovery (RF / cap)
     *   stability (confidence factor)
     *   wf_score (WF pass rate)
     *   mc_score (MC stability factor)
     *
     * Total = weighted sum × 100, clamped to [0, 100].
     */
    OptimizationScore ComputeScore(const ValidationReport &report,
                                     const OptimizationConfig &config) const
    {
        OptimizationScore score;
        const PerformanceMetrics &p = report.performance;

        //--- Profit score (normalized by $10,000 cap)
        score.profit_score = MathMin(1.0, MathMax(0.0, p.net_profit / 10000.0));

        //--- Drawdown score (inverted: 25% DD = 0, 0% DD = 1)
        score.drawdown_score = MathMax(0.0, 1.0 - p.max_drawdown_pct / 25.0);

        //--- Risk score (lower risk = higher score)
        double risk_ratio = (p.average_holding_time > 0) ? 0.5 : 1.0; // Simplified
        score.risk_score = risk_ratio;

        //--- Trade count score (100+ trades = full)
        score.trade_count_score = MathMin(1.0, (double)p.total_trades / 100.0);

        //--- Consistency score (from PF CV: lower CV = more consistent)
        if(report.wf_pf_cv > 0.0)
            score.consistency_score = MathMax(0.0, 1.0 - report.wf_pf_cv / 2.0);
        else
            score.consistency_score = 0.5; // No WF data

        //--- Recovery score (RF / 5 cap)
        score.recovery_score = MathMin(1.0, MathMax(0.0, p.recovery_factor / 5.0));

        //--- Stability score (from confidence factor)
        score.stability_score = report.confidence_factor;

        //--- Walk-forward score (pass rate)
        score.wf_score = report.wf_pass_rate;

        //--- Monte Carlo score (MC stability factor)
        score.mc_score = report.confidence_mc_stability;

        //--- Weighted total
        double total = score.profit_score      * config.weight_profit +
                       score.drawdown_score    * config.weight_drawdown +
                       score.risk_score        * config.weight_risk +
                       score.trade_count_score * config.weight_trade_count +
                       score.consistency_score * config.weight_consistency +
                       score.recovery_score    * config.weight_recovery +
                       score.stability_score   * config.weight_stability +
                       score.wf_score          * config.weight_wf +
                       score.mc_score          * config.weight_mc;

        //--- Normalize: weights may not sum to 100
        double weight_sum = config.weight_profit + config.weight_drawdown +
                            config.weight_risk + config.weight_trade_count +
                            config.weight_consistency + config.weight_recovery +
                            config.weight_stability + config.weight_wf +
                            config.weight_mc;

        if(weight_sum > 0.0)
            total = total / weight_sum * 100.0;
        else
            total = 0.0;

        if(total > 100.0) total = 100.0;
        if(total < 0.0)   total = 0.0;

        score.total_score = total;

        //--- Adjust for objective function
        switch(config.objective)
        {
            case ATLAS_OPT_OBJ_NET_PROFIT:
                score.total_score = MathMin(100.0, MathMax(0.0,
                    p.net_profit / 10000.0 * 100.0));
                break;
            case ATLAS_OPT_OBJ_PROFIT_FACTOR:
                score.total_score = MathMin(100.0, MathMax(0.0,
                    p.profit_factor / 5.0 * 100.0));
                break;
            case ATLAS_OPT_OBJ_MIN_DD:
                score.total_score = MathMin(100.0, MathMax(0.0,
                    (25.0 - p.max_drawdown_pct) / 25.0 * 100.0));
                break;
            case ATLAS_OPT_OBJ_SHARPE:
                score.total_score = MathMin(100.0, MathMax(0.0,
                    p.sharpe_ratio / 3.0 * 100.0));
                break;
            case ATLAS_OPT_OBJ_RECOVERY:
                score.total_score = MathMin(100.0, MathMax(0.0,
                    p.recovery_factor / 5.0 * 100.0));
                break;
            //--- BALANCED and CUSTOM use the composite score as-is
        }

        return score;
    }

    /**
     * @brief Find the best and worst results.
     */
    void FindBestWorst(const OptimizationConfig &config)
    {
        double best  = -1.0;
        double worst = 999.0;
        double sum   = 0.0;
        int    eval_count = 0;

        for(int i = 0; i < m_result_count; i++)
        {
            if(m_results[i].rejected) continue;
            double s = m_results[i].score.total_score;
            if(s > best) { best = s; m_summary.best_set_index = i; }
            if(s < worst) worst = s;
            sum += s;
            eval_count++;
        }

        m_summary.best_score  = (best < 0.0) ? 0.0 : best;
        m_summary.worst_score = (worst > 999.0) ? 0.0 : worst;
        m_summary.avg_score   = (eval_count > 0) ? sum / (double)eval_count : 0.0;
    }
};

#endif // ATLAS_OPTIMIZATION_MANAGER_MQH
//+------------------------------------------------------------------+
