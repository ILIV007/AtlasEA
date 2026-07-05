//+------------------------------------------------------------------+
//|                   Validation/MonteCarloRunner.mqh                |
//|       AtlasEA v1.0 Step 5 - Monte Carlo Simulation Runner         |
//+------------------------------------------------------------------+
#ifndef ATLAS_MONTECARLO_RUNNER_MQH
#define ATLAS_MONTECARLO_RUNNER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "PerformanceAnalyzer.mqh"

/**
 * @struct MonteCarloConfig
 * @brief Configuration for Monte Carlo simulation.
 */
struct MonteCarloConfig
{
    int    simulation_count;     ///< Number of simulations
    ulong  seed;                 ///< Random seed (deterministic)
    bool   shuffle_trades;       ///< Shuffle trade order
    bool   vary_spread;          ///< Vary spread
    bool   vary_slippage;        ///< Vary slippage
    bool   vary_delay;           ///< Vary execution delay
    double spread_var_pct;       ///< Spread variation ±%
    double slippage_var_points;  ///< Slippage variation ±points
    double delay_var_ms;         ///< Delay variation ±ms
    double initial_equity;       ///< Starting equity

    MonteCarloConfig(void)
    {
        simulation_count    = 1000;
        seed                 = 12345;
        shuffle_trades      = true;
        vary_spread         = false;
        vary_slippage       = true;
        vary_delay          = false;
        spread_var_pct      = 20.0;
        slippage_var_points = 2.0;
        delay_var_ms        = 100.0;
        initial_equity      = 10000.0;
    }
};

/**
 * @struct MonteCarloResult
 * @brief Result of a single Monte Carlo simulation.
 */
struct MonteCarloResult
{
    double net_profit;           ///< Final net profit
    double max_drawdown;         ///< Max drawdown
    double max_drawdown_pct;     ///< Max drawdown %
    double profit_factor;        ///< Profit factor
    double win_rate;             ///< Win rate
    double sharpe_ratio;         ///< Sharpe ratio
    int    total_trades;         ///< Total trades

    MonteCarloResult(void)
    {
        net_profit       = 0.0;
        max_drawdown     = 0.0;
        max_drawdown_pct = 0.0;
        profit_factor    = 0.0;
        win_rate         = 0.0;
        sharpe_ratio     = 0.0;
        total_trades     = 0;
    }
};

/**
 * @struct MonteCarloConfidenceInterval
 * @brief Confidence interval for a metric.
 */
struct MonteCarloConfidenceInterval
{
    double p5;                   ///< 5th percentile
    double p25;                  ///< 25th percentile
    double p50;                  ///< 50th percentile (median)
    double p75;                  ///< 75th percentile
    double p95;                  ///< 95th percentile
    double mean;                 ///< Mean
    double std_dev;              ///< Standard deviation
    double min;                  ///< Minimum
    double max;                  ///< Maximum

    MonteCarloConfidenceInterval(void)
    {
        p5 = 0.0; p25 = 0.0; p50 = 0.0; p75 = 0.0; p95 = 0.0;
        mean = 0.0; std_dev = 0.0; min = 0.0; max = 0.0;
    }
};

/**
 * @class MonteCarloRunner
 * @brief Runs Monte Carlo simulations on trade records.
 *
 * SOLE RESPONSIBILITY: run deterministic Monte Carlo simulations by
 * shuffling trade order and/or varying spread, slippage, and delay.
 *
 * Determinism: uses a configurable random seed. Same seed → same results.
 *
 * Shuffling:
 *   - Trade order: reorders the sequence of trades
 *   - Spread variation: adjusts each trade's PnL by ±spread_var_pct
 *   - Slippage variation: adjusts each trade's PnL by ±slippage_var_points
 *   - Delay variation: adjusts each trade's PnL by ±delay cost
 *
 * Confidence intervals: computes p5, p25, p50, p75, p95, mean, std_dev,
 * min, max for each key metric across all simulations.
 *
 * Performance: O(S × N) where S = simulations, N = trades. No heap.
 */
class MonteCarloRunner
{
private:
    ILogger           *m_logger;
    MonteCarloConfig   m_config;
    PerformanceAnalyzer m_perf_analyzer;

    //--- Deterministic pseudo-random number generator (LCG)
    ulong m_rng_state;

    /**
     * @brief Seed the RNG.
     */
    void SeedRNG(const ulong seed) { m_rng_state = seed; }

    /**
     * @brief Generate a deterministic pseudo-random number [0, 1).
     * Uses a Linear Congruential Generator (LCG).
     */
    double Random(void)
    {
        //--- LCG parameters (same as glibc)
        m_rng_state = (m_rng_state * 1103515245 + 12345) & 0x7FFFFFFF;
        return (double)m_rng_state / (double)0x7FFFFFFF;
    }

    /**
     * @brief Generate a random number in [min, max].
     */
    double RandomRange(const double min_val, const double max_val)
    {
        return min_val + Random() * (max_val - min_val);
    }

    /**
     * @brief Shuffle an array of trade indices (Fisher-Yates).
     */
    void ShuffleIndices(int &indices[], const int count)
    {
        for(int i = count - 1; i > 0; i--)
        {
            int j = (int)(Random() * (double)(i + 1));
            if(j > i) j = i;
            int temp = indices[i];
            indices[i] = indices[j];
            indices[j] = temp;
        }
    }

public:
    MonteCarloRunner(void) { m_logger = NULL; m_rng_state = 0; }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_perf_analyzer.SetLogger(logger);
    }

    void SetConfig(const MonteCarloConfig &config) { m_config = config; }

    /**
     * @brief Run Monte Carlo simulations on trade records.
     *
     * @param trades Original trade records (baseline).
     * @param count Number of trades.
     * @param criteria Pass/fail criteria (for final report).
     * @return ValidationReport with confidence intervals.
     */
    ValidationReport Run(const TradeRecord &trades[], const int count,
                          const PassFailCriteria &criteria)
    {
        ValidationReport report;
        report.run_type         = ATLAS_VAL_RUN_MONTECARLO;
        report.run_name         = "Monte Carlo Simulation";
        report.criteria         = criteria;
        report.simulation_count = (m_config.simulation_count < ATLAS_VAL_MAX_SIMS)
                                  ? m_config.simulation_count : ATLAS_VAL_MAX_SIMS;

        if(count <= 0)
        {
            report.verdict = ATLAS_VAL_INCOMPLETE;
            return report;
        }

        if(m_logger != NULL)
            m_logger.Info("MonteCarloRunner",
                "Starting MC: " + IntegerToString(report.simulation_count) +
                " simulations, seed=" + IntegerToString((long)m_config.seed) +
                " trades=" + IntegerToString(count));

        //--- Arrays to collect results from all simulations
        MonteCarloResult results[ATLAS_VAL_MAX_SIMS];
        int sim_count = report.simulation_count;

        //--- Seed the RNG
        SeedRNG(m_config.seed);

        //--- Run simulations
        for(int sim = 0; sim < sim_count; sim++)
        {
            results[sim] = RunSingleSimulation(trades, count, sim);
        }

        //--- Compute confidence intervals
        MonteCarloConfidenceInterval ci_pnl = ComputeCI(results, sim_count, 0); // net_profit
        MonteCarloConfidenceInterval ci_dd  = ComputeCI(results, sim_count, 1); // max_dd_pct
        MonteCarloConfidenceInterval ci_pf  = ComputeCI(results, sim_count, 2); // profit_factor
        MonteCarloConfidenceInterval ci_wr  = ComputeCI(results, sim_count, 3); // win_rate

        //--- Use the baseline (original) performance for the report
        report.performance = m_perf_analyzer.Analyze(trades, count, m_config.initial_equity);

        //--- Compute validation score from baseline
        //--- (simplified — reuses BacktestRunner scoring logic)
        report.validation_score = ComputeMCScore(report.performance, ci_pnl, ci_dd);

        //--- Verdict: pass if p5 (5th percentile) of net profit > 0
        //--- AND p95 (95th percentile) of max DD < criteria max
        report.verdict = ATLAS_VAL_PASS;
        report.criteria_checked = 2;
        if(ci_pnl.p5 < 0.0)
        {
            report.verdict = ATLAS_VAL_FAIL;
            report.criteria_failed++;
            if(report.fail_reason_count < 16)
            {
                report.fail_reasons[report.fail_reason_count] =
                    "MC 5th percentile net profit " + DoubleToString(ci_pnl.p5, 2) + " < 0";
                report.fail_reason_count++;
            }
        }
        else report.criteria_passed++;

        if(ci_dd.p95 > criteria.max_drawdown_pct && criteria.max_drawdown_pct > 0.0)
        {
            report.verdict = ATLAS_VAL_FAIL;
            report.criteria_failed++;
            if(report.fail_reason_count < 16)
            {
                report.fail_reasons[report.fail_reason_count] =
                    "MC 95th percentile max DD " + DoubleToString(ci_dd.p95, 1) +
                    "% > max " + DoubleToString(criteria.max_drawdown_pct, 1) + "%";
                report.fail_reason_count++;
            }
        }
        else report.criteria_passed++;

        if(m_logger != NULL)
            m_logger.Info("MonteCarloRunner",
                "MC complete: verdict=" + (report.verdict == ATLAS_VAL_PASS ? "PASS" : "FAIL") +
                " PnL p5=" + DoubleToString(ci_pnl.p5, 2) +
                " p50=" + DoubleToString(ci_pnl.p50, 2) +
                " p95=" + DoubleToString(ci_pnl.p95, 2) +
                " DD p95=" + DoubleToString(ci_dd.p95, 1) + "%");

        return report;
    }

private:
    /**
     * @brief Run a single Monte Carlo simulation.
     */
    MonteCarloResult RunSingleSimulation(const TradeRecord &trades[], const int count,
                                          const int sim_idx)
    {
        MonteCarloResult result;
        result.total_trades = count;

        //--- Create shuffled indices if needed
        int indices[ATLAS_VAL_MAX_TRADES];
        for(int i = 0; i < count && i < ATLAS_VAL_MAX_TRADES; i++)
            indices[i] = i;

        if(m_config.shuffle_trades)
            ShuffleIndices(indices, count);

        //--- Simulate the equity curve
        double equity = m_config.initial_equity;
        double peak = equity;
        double max_dd = 0.0;
        double max_dd_pct = 0.0;
        double gross_profit = 0.0;
        double gross_loss = 0.0;
        int wins = 0;

        for(int i = 0; i < count; i++)
        {
            int idx = (m_config.shuffle_trades) ? indices[i] : i;
            double pnl = trades[idx].realized_pnl;

            //--- Apply spread variation
            if(m_config.vary_spread && m_config.spread_var_pct > 0.0)
            {
                double spread_adj = RandomRange(-m_config.spread_var_pct, m_config.spread_var_pct);
                pnl += pnl * (spread_adj / 100.0);
            }

            //--- Apply slippage variation
            if(m_config.vary_slippage && m_config.slippage_var_points > 0.0)
            {
                double slippage_adj = RandomRange(-m_config.slippage_var_points, m_config.slippage_var_points);
                pnl -= slippage_adj * trades[idx].volume; // Approximate cost
            }

            //--- Apply delay variation (simplified: small random cost)
            if(m_config.vary_delay && m_config.delay_var_ms > 0.0)
            {
                double delay_cost = Random() * m_config.delay_var_ms * 0.001; // Small cost
                pnl -= delay_cost;
            }

            equity += pnl;

            if(pnl > 0.0) { gross_profit += pnl; wins++; }
            else if(pnl < 0.0) gross_loss += pnl;

            if(equity > peak) peak = equity;
            double dd = peak - equity;
            double dd_pct = (peak > 0.0) ? (dd / peak) * 100.0 : 0.0;
            if(dd > max_dd) { max_dd = dd; max_dd_pct = dd_pct; }
        }

        result.net_profit       = equity - m_config.initial_equity;
        result.max_drawdown     = max_dd;
        result.max_drawdown_pct = max_dd_pct;
        result.profit_factor    = (gross_loss < 0.0)
            ? gross_profit / MathAbs(gross_loss)
            : (gross_profit > 0.0 ? 999.0 : 0.0);
        result.win_rate         = (count > 0) ? (double)wins / (double)count : 0.0;
        result.sharpe_ratio     = 0.0; // Simplified

        return result;
    }

    /**
     * @brief Compute confidence interval for a specific metric.
     * @param metric 0=net_profit, 1=max_dd_pct, 2=profit_factor, 3=win_rate
     */
    MonteCarloConfidenceInterval ComputeCI(const MonteCarloResult &results[],
                                            const int count, const int metric)
    {
        MonteCarloConfidenceInterval ci;
        if(count <= 0) return ci;

        //--- Extract values
        double values[ATLAS_VAL_MAX_SIMS];
        for(int i = 0; i < count; i++)
        {
            switch(metric)
            {
                case 0: values[i] = results[i].net_profit; break;
                case 1: values[i] = results[i].max_drawdown_pct; break;
                case 2: values[i] = results[i].profit_factor; break;
                case 3: values[i] = results[i].win_rate; break;
                default: values[i] = 0.0; break;
            }
        }

        //--- Sort (simple bubble sort — count is small enough for typical use)
        for(int i = 0; i < count - 1; i++)
            for(int j = i + 1; j < count; j++)
                if(values[j] < values[i])
                {
                    double tmp = values[i];
                    values[i] = values[j];
                    values[j] = tmp;
                }

        //--- Percentiles
        ci.min = values[0];
        ci.max = values[count - 1];
        ci.p5  = values[(int)(count * 0.05)];
        ci.p25 = values[(int)(count * 0.25)];
        ci.p50 = values[(int)(count * 0.50)];
        ci.p75 = values[(int)(count * 0.75)];
        ci.p95 = values[(int)(count * 0.95)];

        //--- Mean
        double sum = 0.0;
        for(int i = 0; i < count; i++) sum += values[i];
        ci.mean = sum / (double)count;

        //--- Std dev
        double sq_sum = 0.0;
        for(int i = 0; i < count; i++)
        {
            double diff = values[i] - ci.mean;
            sq_sum += diff * diff;
        }
        ci.std_dev = (count > 1) ? MathSqrt(sq_sum / (double)(count - 1)) : 0.0;

        return ci;
    }

    /**
     * @brief Compute a Monte Carlo validation score.
     */
    double ComputeMCScore(const PerformanceMetrics &p,
                           const MonteCarloConfidenceInterval &ci_pnl,
                           const MonteCarloConfidenceInterval &ci_dd) const
    {
        double score = 0.0;

        //--- PnL robustness (0-40 points): p5 > 0 = full score
        if(ci_pnl.p5 > 0.0) score += 40.0;
        else if(ci_pnl.p50 > 0.0) score += 20.0;

        //--- DD robustness (0-30 points): p95 < 25% = full score
        if(ci_dd.p95 < 25.0) score += 30.0;
        else if(ci_dd.p50 < 15.0) score += 15.0;

        //--- Profit factor (0-15 points)
        score += MathMin(15.0, p.profit_factor / 3.0 * 15.0);

        //--- Win rate (0-15 points)
        score += p.win_rate * 15.0;

        if(score > 100.0) score = 100.0;
        if(score < 0.0) score = 0.0;
        return score;
    }
};

#endif // ATLAS_MONTECARLO_RUNNER_MQH
//+------------------------------------------------------------------+
