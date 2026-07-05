//+------------------------------------------------------------------+
//|                    Optimization/OptimizationRunner.mqh           |
//|       AtlasEA v1.0 Step 6 - Optimization Runner                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_OPTIMIZATION_RUNNER_MQH
#define ATLAS_OPTIMIZATION_RUNNER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IOptimizationManager.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ParameterSpace.mqh"

/**
 * @class OptimizationRunner
 * @brief Runs validation (backtest + walk-forward + Monte Carlo) for
 *        each parameter set.
 *
 * SOLE RESPONSIBILITY: apply a parameter set to the config, run the
 * validation framework, and collect the results.
 *
 * INTEGRATION:
 *   - Reuses the Validation Framework (IValidationManager).
 *   - No duplicated calculations.
 *   - Does NOT compute scores or anti-overfitting checks (that's
 *     OptimizationManager's job).
 *
 * Performance: O(N × V) where N = parameter sets, V = validation time.
 * No heap allocation.
 */
class OptimizationRunner
{
private:
    ILogger             *m_logger;
    IValidationManager  *m_validation;

public:
    OptimizationRunner(void) { m_logger = NULL; m_validation = NULL; }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the validation manager to use for backtests.
     * The caller must have collected trade records before calling Run.
     */
    void SetValidationManager(IValidationManager *val) { m_validation = val; }

    /**
     * @brief Run validation for a single parameter set.
     *
     * @param params The parameter set to evaluate.
     * @param space The parameter space (for ApplyToConfig).
     * @param config The base AtlasConfig (will be modified per param set).
     * @param opt_config Optimization configuration (controls WF/MC).
     * @param from_time Backtest start time.
     * @param to_time Backtest end time.
     * @return ValidationReport for this parameter set.
     */
    ValidationReport RunSingle(const ParameterSet &params,
                                const ParameterSpace &space,
                                AtlasConfig &config,
                                const OptimizationConfig &opt_config,
                                const datetime from_time,
                                const datetime to_time)
    {
        //--- Apply parameter set to config
        space.ApplyToConfig(params, config);

        if(m_validation == NULL)
        {
            ValidationReport empty;
            empty.verdict = ATLAS_VAL_INCOMPLETE;
            return empty;
        }

        //--- Update validation config from the modified AtlasConfig
        ValidationConfig val_config;
        m_validation.SetValidationConfig(val_config);
        m_validation.SetCriteria(val_config);

        //--- Run backtest
        ValidationReport report = m_validation.RunBacktest(from_time, to_time);

        //--- Optionally run walk-forward
        if(opt_config.run_walk_forward && report.verdict != ATLAS_VAL_INCOMPLETE)
        {
            ValidationReport wf_report = m_validation.RunWalkForward(
                from_time, to_time,
                opt_config.wf_train_bars, opt_config.wf_validate_bars,
                opt_config.wf_expanding);

            //--- Merge WF data into the report
            report.wf_classification = wf_report.wf_classification;
            report.wf_pass_rate      = wf_report.wf_pass_rate;
            report.wf_pf_cv          = wf_report.wf_pf_cv;
            report.segment_count     = wf_report.segment_count;
        }

        //--- Optionally run Monte Carlo
        if(opt_config.run_monte_carlo && report.verdict != ATLAS_VAL_INCOMPLETE)
        {
            ValidationReport mc_report = m_validation.RunMonteCarlo(
                opt_config.mc_simulations, opt_config.mc_seed,
                true, false, true, false);

            //--- Merge MC data into the report
            report.simulation_count = mc_report.simulation_count;
        }

        return report;
    }
};

#endif // ATLAS_OPTIMIZATION_RUNNER_MQH
//+------------------------------------------------------------------+
