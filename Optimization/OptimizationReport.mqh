//+------------------------------------------------------------------+
//|                    Optimization/OptimizationReport.mqh           |
//|       AtlasEA v1.0 Step 6 - Optimization Report                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_OPTIMIZATION_REPORT_MQH
#define ATLAS_OPTIMIZATION_REPORT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IOptimizationManager.mqh"

/**
 * @class OptimizationReport
 * @brief Generates optimization reports: top sets, worst sets, rejected sets,
 *        summary, and CSV export.
 *
 * SOLE RESPONSIBILITY: format and output optimization results.
 * Does NOT run optimization or compute scores.
 *
 * Performance: O(N) for sorting + formatting. No allocation.
 */
class OptimizationReport
{
private:
    ILogger *m_logger;

    /**
     * @brief Simple insertion sort to find top N results by score.
     * O(N × TOP) — efficient when TOP << N.
     */
    void FindTopN(const ParameterSetResult &results[], const int count,
                  int &indices[], const int top_count) const
    {
        for(int i = 0; i < top_count; i++) indices[i] = -1;

        for(int i = 0; i < count; i++)
        {
            if(results[i].rejected) continue;
            double score = results[i].score.total_score;

            //--- Find insertion position
            int pos = top_count;
            for(int j = 0; j < top_count; j++)
            {
                if(indices[j] < 0) { pos = j; break; }
                if(score > results[indices[j]].score.total_score) { pos = j; break; }
            }

            if(pos < top_count)
            {
                //--- Shift down
                for(int j = top_count - 1; j > pos; j--)
                    indices[j] = indices[j - 1];
                indices[pos] = i;
            }
        }
    }

    /**
     * @brief Find worst N results by score.
     */
    void FindWorstN(const ParameterSetResult &results[], const int count,
                    int &indices[], const int worst_count) const
    {
        for(int i = 0; i < worst_count; i++) indices[i] = -1;

        for(int i = 0; i < count; i++)
        {
            if(results[i].rejected) continue;
            double score = results[i].score.total_score;

            int pos = worst_count;
            for(int j = 0; j < worst_count; j++)
            {
                if(indices[j] < 0) { pos = j; break; }
                if(score < results[indices[j]].score.total_score) { pos = j; break; }
            }

            if(pos < worst_count)
            {
                for(int j = worst_count - 1; j > pos; j--)
                    indices[j] = indices[j - 1];
                indices[pos] = i;
            }
        }
    }

public:
    OptimizationReport(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Log the top 10 parameter sets.
     */
    void LogTopSets(const ParameterSetResult &results[], const int count) const
    {
        if(m_logger == NULL || count <= 0) return;

        int top[ATLAS_OPT_TOP_COUNT];
        FindTopN(results, count, top, ATLAS_OPT_TOP_COUNT);

        m_logger.Info("OptimizationReport",
            "=== TOP " + IntegerToString(ATLAS_OPT_TOP_COUNT) + " Parameter Sets ===");

        for(int i = 0; i < ATLAS_OPT_TOP_COUNT; i++)
        {
            if(top[i] < 0) break;
            const ParameterSetResult &r = results[top[i]];
            const PerformanceMetrics &p = r.report.performance;

            m_logger.Info("OptimizationReport",
                "#" + IntegerToString(i + 1) +
                " Set=" + IntegerToString(r.params.set_index) +
                " Score=" + DoubleToString(r.score.total_score, 1) +
                " PF=" + DoubleToString(p.profit_factor, 2) +
                " DD=" + DoubleToString(p.max_drawdown_pct, 1) + "%" +
                " WR=" + DoubleToString(p.win_rate * 100.0, 1) + "%" +
                " Trades=" + IntegerToString(p.total_trades) +
                " Net=" + DoubleToString(p.net_profit, 2) +
                " Sharpe=" + DoubleToString(p.sharpe_ratio, 2));
        }
    }

    /**
     * @brief Log the worst parameter sets.
     */
    void LogWorstSets(const ParameterSetResult &results[], const int count) const
    {
        if(m_logger == NULL || count <= 0) return;

        int worst[5];
        FindWorstN(results, count, worst, 5);

        m_logger.Info("OptimizationReport",
            "=== WORST 5 Parameter Sets ===");

        for(int i = 0; i < 5; i++)
        {
            if(worst[i] < 0) break;
            const ParameterSetResult &r = results[worst[i]];
            const PerformanceMetrics &p = r.report.performance;

            m_logger.Info("OptimizationReport",
                "#" + IntegerToString(i + 1) +
                " Set=" + IntegerToString(r.params.set_index) +
                " Score=" + DoubleToString(r.score.total_score, 1) +
                " PF=" + DoubleToString(p.profit_factor, 2) +
                " DD=" + DoubleToString(p.max_drawdown_pct, 1) + "%" +
                " Net=" + DoubleToString(p.net_profit, 2));
        }
    }

    /**
     * @brief Log rejected parameter sets with reasons.
     */
    void LogRejectedSets(const ParameterSetResult &results[], const int count) const
    {
        if(m_logger == NULL || count <= 0) return;

        m_logger.Info("OptimizationReport",
            "=== REJECTED Parameter Sets ===");

        int logged = 0;
        for(int i = 0; i < count && logged < 20; i++)
        {
            const ParameterSetResult &r = results[i];
            if(!r.rejected) continue;

            string reason = "";
            if(!r.params.valid)
                reason = "Validation: " + ParamValidationRejectName(r.params.validation_code) +
                         " " + r.params.validation_detail;
            else if(r.anti_overfit_code != ATLAS_AOF_OK)
                reason = "AntiOverfit: " + AntiOverfitRejectName(r.anti_overfit_code) +
                         " " + r.anti_overfit_detail;

            m_logger.Info("OptimizationReport",
                "Set=" + IntegerToString(r.params.set_index) +
                " REJECTED: " + reason);
            logged++;
        }

        if(logged == 0)
            m_logger.Info("OptimizationReport", "No rejected sets.");
    }

    /**
     * @brief Log the optimization summary.
     */
    void LogSummary(const OptimizationSummary &summary) const
    {
        if(m_logger == NULL) return;

        m_logger.Info("OptimizationReport",
            "=== OPTIMIZATION SUMMARY ===");
        m_logger.Info("OptimizationReport",
            "Search: " + OptimizationSearchModeName(summary.search_mode) +
            " Objective: " + OptimizationObjectiveName(summary.objective) +
            " Seed: " + IntegerToString((long)summary.random_seed) +
            " Duration: " + IntegerToString(summary.duration_sec) + "s");
        m_logger.Info("OptimizationReport",
            "Sets: total=" + IntegerToString(summary.total_sets) +
            " valid=" + IntegerToString(summary.valid_sets) +
            " evaluated=" + IntegerToString(summary.evaluated_sets) +
            " rejected=" + IntegerToString(summary.rejected_sets));
        m_logger.Info("OptimizationReport",
            "Best: set=" + IntegerToString(summary.best_set_index) +
            " score=" + DoubleToString(summary.best_score, 1) +
            " avg=" + DoubleToString(summary.avg_score, 1) +
            " worst=" + DoubleToString(summary.worst_score, 1));
    }

    /**
     * @brief Export the full optimization report as CSV.
     */
    bool ExportCSV(const ParameterSetResult &results[], const int count,
                   const OptimizationSummary &summary,
                   const string filename) const
    {
        int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
        if(handle == INVALID_HANDLE) return false;

        //--- Header
        FileWrite(handle,
            "Set", "Rejected", "Score",
            "Total Trades", "Win Rate", "Net Profit", "Profit Factor",
            "Max DD %", "Sharpe", "Recovery", "Sortino",
            "WF Pass Rate", "WF Classification", "MC P5 PnL",
            "Anti-Overfit", "Validation Code",
            "Profit Score", "DD Score", "Risk Score", "TC Score",
            "Consistency Score", "Recovery Score", "Stability Score",
            "WF Score", "MC Score");

        for(int i = 0; i < count; i++)
        {
            const ParameterSetResult &r = results[i];
            const PerformanceMetrics &p = r.report.performance;

            FileWrite(handle,
                IntegerToString(r.params.set_index),
                r.rejected ? "YES" : "NO",
                DoubleToString(r.score.total_score, 2),
                IntegerToString(p.total_trades),
                DoubleToString(p.win_rate * 100.0, 2),
                DoubleToString(p.net_profit, 2),
                DoubleToString(p.profit_factor, 4),
                DoubleToString(p.max_drawdown_pct, 2),
                DoubleToString(p.sharpe_ratio, 4),
                DoubleToString(p.recovery_factor, 4),
                DoubleToString(p.sortino_ratio, 4),
                DoubleToString(r.report.wf_pass_rate * 100.0, 1),
                WalkForwardClassificationName(r.report.wf_classification),
                DoubleToString(r.report.confidence_mc_stability * 100.0, 1),
                r.rejected ? AntiOverfitRejectName(r.anti_overfit_code) : "OK",
                r.params.valid ? "OK" : ParamValidationRejectName(r.params.validation_code),
                DoubleToString(r.score.profit_score, 2),
                DoubleToString(r.score.drawdown_score, 2),
                DoubleToString(r.score.risk_score, 2),
                DoubleToString(r.score.trade_count_score, 2),
                DoubleToString(r.score.consistency_score, 2),
                DoubleToString(r.score.recovery_score, 2),
                DoubleToString(r.score.stability_score, 2),
                DoubleToString(r.score.wf_score, 2),
                DoubleToString(r.score.mc_score, 2));
        }

        FileClose(handle);
        return true;
    }
};

#endif // ATLAS_OPTIMIZATION_REPORT_MQH
//+------------------------------------------------------------------+
