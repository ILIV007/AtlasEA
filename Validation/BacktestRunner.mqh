//+------------------------------------------------------------------+
//|                    Validation/BacktestRunner.mqh                 |
//|       AtlasEA v1.0 Step 5 - Historical Backtest Runner           |
//+------------------------------------------------------------------+
#ifndef ATLAS_BACKTEST_RUNNER_MQH
#define ATLAS_BACKTEST_RUNNER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "PerformanceAnalyzer.mqh"
#include "EquityAnalyzer.mqh"
#include "RiskAnalyzer.mqh"

/**
 * @struct BacktestConfig
 * @brief Configuration for a backtest run.
 */
struct BacktestConfig
{
    datetime from_time;          ///< Backtest start time
    datetime to_time;            ///< Backtest end time
    double   initial_equity;     ///< Starting equity
    string   symbol;             ///< Symbol to backtest
    int      timeframe_minutes;  ///< Timeframe in minutes

    BacktestConfig(void)
    {
        from_time         = 0;
        to_time           = 0;
        initial_equity    = 10000.0;
        symbol            = "";
        timeframe_minutes = 60;
    }
};

/**
 * @class BacktestRunner
 * @brief Runs full historical backtests and collects trade records.
 *
 * SOLE RESPONSIBILITY: run a backtest over a historical period,
 * collect all trade records, and produce a ValidationReport.
 *
 * Integration:
 *   - Uses existing Replay engine to replay historical market data.
 *   - Uses existing StrategyEngine to evaluate strategies.
 *   - Uses existing RiskEngine, ExecutionEngine, TradeLifecycleManager.
 *   - Collects closed trade records for analysis.
 *
 * NOTE: The actual replay is performed by the caller (CoreEngine or
 * ValidationManager). The BacktestRunner receives the trade records
 * that were collected during the replay and produces the report.
 * This design avoids duplicating the replay infrastructure.
 *
 * Performance: O(N) where N = number of trades. No heap allocation.
 */
class BacktestRunner
{
private:
    ILogger             *m_logger;
    PerformanceAnalyzer  m_perf_analyzer;
    EquityAnalyzer       m_equity_analyzer;
    RiskAnalyzer         m_risk_analyzer;
    BacktestConfig       m_config;

public:
    BacktestRunner(void) { m_logger = NULL; }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_perf_analyzer.SetLogger(logger);
        m_equity_analyzer.SetLogger(logger);
        m_risk_analyzer.SetLogger(logger);
    }

    void SetConfig(const BacktestConfig &config) { m_config = config; }

    /**
     * @brief Run analysis on collected trade records.
     *
     * The caller collects trade records during a replay and passes
     * them to this method. The runner analyzes them and produces
     * a complete ValidationReport.
     *
     * @param trades Array of closed trade records.
     * @param count Number of trades.
     * @param criteria Pass/fail criteria.
     * @param run_name Name for the report.
     * @return ValidationReport with all metrics + pass/fail.
     */
    ValidationReport Run(const TradeRecord &trades[], const int count,
                          const PassFailCriteria &criteria,
                          const string run_name)
    {
        ValidationReport report;
        report.run_type   = ATLAS_VAL_RUN_BACKTEST;
        report.run_name   = run_name;
        report.criteria   = criteria;

        datetime start = TimeCurrent();

        if(m_logger != NULL)
            m_logger.Info("BacktestRunner",
                "Starting backtest: " + run_name +
                " trades=" + IntegerToString(count) +
                " equity=" + DoubleToString(m_config.initial_equity, 2));

        //--- Analyze performance
        report.performance = m_perf_analyzer.Analyze(trades, count,
                                                      m_config.initial_equity);

        //--- Analyze equity curve
        report.equity = m_equity_analyzer.Analyze(trades, count,
                                                   m_config.initial_equity);

        //--- Analyze risk
        report.risk = m_risk_analyzer.Analyze(trades, count,
                                               m_config.initial_equity);

        //--- Evaluate pass/fail
        EvaluatePassFail(report);

        //--- Compute validation score
        report.validation_score = ComputeScore(report);

        //--- Duration
        report.duration_sec = (int)((long)TimeCurrent() - (long)start);

        if(m_logger != NULL)
            m_logger.Info("BacktestRunner",
                "Backtest complete: " + run_name +
                " verdict=" + (report.verdict == ATLAS_VAL_PASS ? "PASS" : "FAIL") +
                " score=" + DoubleToString(report.validation_score, 1) +
                " PF=" + DoubleToString(report.performance.profit_factor, 2) +
                " DD=" + DoubleToString(report.performance.max_drawdown_pct, 1) + "%" +
                " WR=" + DoubleToString(report.performance.win_rate * 100.0, 1) + "%" +
                " trades=" + IntegerToString(report.performance.total_trades));

        return report;
    }

private:
    /**
     * @brief Evaluate pass/fail criteria.
     */
    void EvaluatePassFail(ValidationReport &report)
    {
        const PerformanceMetrics &p = report.performance;
        const RiskAnalysis &r = report.risk;
        const PassFailCriteria &c = report.criteria;

        report.criteria_checked = 0;
        report.criteria_passed  = 0;
        report.criteria_failed  = 0;
        report.fail_reason_count = 0;

        //--- Min profit factor
        if(c.min_profit_factor > 0.0)
        {
            report.criteria_checked++;
            if(p.profit_factor >= c.min_profit_factor)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Profit factor " +
                    DoubleToString(p.profit_factor, 2) +
                    " < min " + DoubleToString(c.min_profit_factor, 2));
            }
        }

        //--- Max drawdown
        if(c.max_drawdown_pct > 0.0)
        {
            report.criteria_checked++;
            if(p.max_drawdown_pct <= c.max_drawdown_pct)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Max drawdown " +
                    DoubleToString(p.max_drawdown_pct, 1) + "% > max " +
                    DoubleToString(c.max_drawdown_pct, 1) + "%");
            }
        }

        //--- Min win rate
        if(c.min_win_rate > 0.0)
        {
            report.criteria_checked++;
            if(p.win_rate >= c.min_win_rate)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Win rate " +
                    DoubleToString(p.win_rate * 100.0, 1) + "% < min " +
                    DoubleToString(c.min_win_rate * 100.0, 1) + "%");
            }
        }

        //--- Min trade count
        if(c.min_trade_count > 0)
        {
            report.criteria_checked++;
            if(p.total_trades >= c.min_trade_count)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Trade count " +
                    IntegerToString(p.total_trades) + " < min " +
                    IntegerToString(c.min_trade_count));
            }
        }

        //--- Max exposure
        if(c.max_exposure_pct > 0.0)
        {
            report.criteria_checked++;
            if(r.max_exposure_pct <= c.max_exposure_pct)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Max exposure " +
                    DoubleToString(r.max_exposure_pct, 1) + "% > max " +
                    DoubleToString(c.max_exposure_pct, 1) + "%");
            }
        }

        //--- Min net profit
        if(c.min_net_profit > 0.0 || c.min_net_profit == 0.0)
        {
            report.criteria_checked++;
            if(p.net_profit >= c.min_net_profit)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Net profit " +
                    DoubleToString(p.net_profit, 2) + " < min " +
                    DoubleToString(c.min_net_profit, 2));
            }
        }

        //--- Min Sharpe ratio
        if(c.min_sharpe_ratio > 0.0)
        {
            report.criteria_checked++;
            if(p.sharpe_ratio >= c.min_sharpe_ratio)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Sharpe ratio " +
                    DoubleToString(p.sharpe_ratio, 2) + " < min " +
                    DoubleToString(c.min_sharpe_ratio, 2));
            }
        }

        //--- Max consecutive losses
        if(c.max_consecutive_losses > 0)
        {
            report.criteria_checked++;
            if(p.max_consecutive_losses <= c.max_consecutive_losses)
                report.criteria_passed++;
            else
            {
                report.criteria_failed++;
                AddFailReason(report, "Consecutive losses " +
                    IntegerToString(p.max_consecutive_losses) + " > max " +
                    IntegerToString(c.max_consecutive_losses));
            }
        }

        //--- Final verdict
        report.verdict = (report.criteria_failed > 0) ? ATLAS_VAL_FAIL : ATLAS_VAL_PASS;
    }

    /**
     * @brief Compute a validation score [0, 100].
     *
     * Score is a weighted combination of:
     *   - Profit factor (25%)
     *   - Win rate (15%)
     *   - Drawdown (20%, inverted — lower DD = higher score)
     *   - Sharpe ratio (20%)
     *   - Recovery factor (10%)
     *   - Trade count adequacy (10%)
     */
    double ComputeScore(const ValidationReport &report) const
    {
        const PerformanceMetrics &p = report.performance;
        double score = 0.0;

        //--- Profit factor (0-25 points, capped at PF=3.0)
        score += MathMin(25.0, p.profit_factor / 3.0 * 25.0);

        //--- Win rate (0-15 points)
        score += p.win_rate * 15.0;

        //--- Drawdown (0-20 points, lower DD = higher score, 25% DD = 0)
        if(p.max_drawdown_pct < 25.0)
            score += (25.0 - p.max_drawdown_pct) / 25.0 * 20.0;

        //--- Sharpe ratio (0-20 points, capped at 2.0)
        score += MathMin(20.0, MathMax(0.0, p.sharpe_ratio) / 2.0 * 20.0);

        //--- Recovery factor (0-10 points, capped at 5.0)
        score += MathMin(10.0, MathMax(0.0, p.recovery_factor) / 5.0 * 10.0);

        //--- Trade count adequacy (0-10 points, 30+ trades = full)
        if(p.total_trades >= 30)
            score += 10.0;
        else
            score += (double)p.total_trades / 30.0 * 10.0;

        if(score > 100.0) score = 100.0;
        if(score < 0.0) score = 0.0;
        return score;
    }

    void AddFailReason(ValidationReport &report, const string reason) const
    {
        if(report.fail_reason_count < 16)
        {
            report.fail_reasons[report.fail_reason_count] = reason;
            report.fail_reason_count++;
        }
    }
};

#endif // ATLAS_BACKTEST_RUNNER_MQH
//+------------------------------------------------------------------+
