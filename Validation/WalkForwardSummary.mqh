//+------------------------------------------------------------------+
//|                   Validation/WalkForwardSummary.mqh              |
//|       AtlasEA v1.0 Step 5.5 - Walk-Forward Summary               |
//+------------------------------------------------------------------+
#ifndef ATLAS_WALKFORWARD_SUMMARY_MQH
#define ATLAS_WALKFORWARD_SUMMARY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"

/**
 * @struct WalkForwardSummaryData
 * @brief Aggregated data from all walk-forward segments.
 */
struct WalkForwardSummaryData
{
    int    total_segments;          ///< Total number of segments
    int    passing_segments;        ///< Segments that passed
    int    failing_segments;        ///< Segments that failed
    double pass_rate;               ///< passing / total [0, 1]

    double avg_profit_factor;       ///< Average PF across segments
    double std_profit_factor;       ///< Std dev of PF across segments
    double min_profit_factor;       ///< Min PF
    double max_profit_factor;       ///< Max PF

    double avg_net_profit;          ///< Average net profit
    double std_net_profit;          ///< Std dev of net profit
    double min_net_profit;          ///< Min net profit
    double max_net_profit;          ///< Max net profit

    double avg_max_drawdown_pct;    ///< Average max DD %
    double max_max_drawdown_pct;    ///< Worst (largest) max DD %

    double avg_win_rate;            ///< Average win rate
    double pf_coefficient_variation; ///< CV of PF (std/avg) — lower = more stable

    int    classification;          ///< ATLAS_WF_STABLE / WEAK / UNSTABLE / OVERFITTED
    string classification_name;     ///< Human-readable classification

    WalkForwardSummaryData(void)
    {
        total_segments     = 0;
        passing_segments   = 0;
        failing_segments   = 0;
        pass_rate          = 0.0;
        avg_profit_factor  = 0.0;
        std_profit_factor  = 0.0;
        min_profit_factor  = 0.0;
        max_profit_factor  = 0.0;
        avg_net_profit     = 0.0;
        std_net_profit     = 0.0;
        min_net_profit     = 0.0;
        max_net_profit     = 0.0;
        avg_max_drawdown_pct = 0.0;
        max_max_drawdown_pct = 0.0;
        avg_win_rate       = 0.0;
        pf_coefficient_variation = 0.0;
        classification    = ATLAS_WF_WEAK;
        classification_name = "Weak";
    }
};

/**
 * @class WalkForwardSummary
 * @brief Classifies walk-forward results as Stable / Weak / Unstable / Overfitted.
 *
 * SOLE RESPONSIBILITY: aggregate segment results and classify the
 * walk-forward analysis.
 *
 * Classification logic:
 *
 *   STABLE:
 *     - pass_rate >= 75%
 *     - PF coefficient of variation < 0.3 (consistent PF across segments)
 *     - All segments have positive net profit
 *     - max_drawdown_pct < 2× average
 *
 *   WEAK:
 *     - pass_rate >= 50%
 *     - PF coefficient of variation < 0.5
 *     - At least 50% of segments have positive net profit
 *
 *   UNSTABLE:
 *     - pass_rate >= 25%
 *     - PF coefficient of variation >= 0.5 (inconsistent)
 *     - OR net profit changes sign frequently
 *
 *   OVERFITTED:
 *     - pass_rate < 25%
 *     - OR PF coefficient of variation >= 1.0 (wildly inconsistent)
 *     - OR negative average net profit despite high PF in some segments
 *
 * Performance: O(S) where S = segments. No allocation.
 */
class WalkForwardSummary
{
public:
    /**
     * @brief Compute the walk-forward summary from segment reports.
     * @param segment_reports Array of segment ValidationReports.
     * @param segment_count Number of segments.
     * @return WalkForwardSummaryData with classification.
     */
    static WalkForwardSummaryData Compute(const ValidationReport &segment_reports[],
                                           const int segment_count)
    {
        WalkForwardSummaryData s;
        s.total_segments = segment_count;

        if(segment_count <= 0)
        {
            s.classification = ATLAS_WF_UNSTABLE;
            s.classification_name = WalkForwardClassificationName(ATLAS_WF_UNSTABLE);
            return s;
        }

        //--- Aggregate
        double sum_pf = 0.0;
        double sum_pf_sq = 0.0;
        double sum_pnl = 0.0;
        double sum_pnl_sq = 0.0;
        double sum_dd = 0.0;
        double sum_wr = 0.0;
        double max_dd = 0.0;
        double min_pf = 999.0;
        double max_pf = 0.0;
        double min_pnl = 0.0;
        double max_pnl = 0.0;
        int positive_pnl_count = 0;

        for(int i = 0; i < segment_count; i++)
        {
            const PerformanceMetrics &p = segment_reports[i].performance;
            double pf = p.profit_factor;
            double pnl = p.net_profit;
            double dd = p.max_drawdown_pct;
            double wr = p.win_rate;

            sum_pf += pf;
            sum_pf_sq += pf * pf;
            sum_pnl += pnl;
            sum_pnl_sq += pnl * pnl;
            sum_dd += dd;
            sum_wr += wr;

            if(dd > max_dd) max_dd = dd;
            if(pf < min_pf) min_pf = pf;
            if(pf > max_pf) max_pf = pf;
            if(pnl < min_pnl) min_pnl = pnl;
            if(pnl > max_pnl) max_pnl = pnl;
            if(pnl > 0.0) positive_pnl_count++;

            if(segment_reports[i].verdict == ATLAS_VAL_PASS)
                s.passing_segments++;
            else
                s.failing_segments++;
        }

        //--- Compute averages
        s.pass_rate            = (double)s.passing_segments / (double)segment_count;
        s.avg_profit_factor    = sum_pf / (double)segment_count;
        s.avg_net_profit       = sum_pnl / (double)segment_count;
        s.avg_max_drawdown_pct = sum_dd / (double)segment_count;
        s.avg_win_rate         = sum_wr / (double)segment_count;
        s.min_profit_factor    = min_pf;
        s.max_profit_factor    = max_pf;
        s.min_net_profit       = min_pnl;
        s.max_net_profit       = max_pnl;
        s.max_max_drawdown_pct = max_dd;

        //--- Standard deviations
        if(segment_count > 1)
        {
            double pf_mean = s.avg_profit_factor;
            s.std_profit_factor = MathSqrt(
                (sum_pf_sq - pf_mean * pf_mean * segment_count) / (double)(segment_count - 1));

            double pnl_mean = s.avg_net_profit;
            s.std_net_profit = MathSqrt(
                (sum_pnl_sq - pnl_mean * pnl_mean * segment_count) / (double)(segment_count - 1));
        }

        //--- Coefficient of variation (CV = std / mean)
        if(s.avg_profit_factor > 0.0)
            s.pf_coefficient_variation = s.std_profit_factor / s.avg_profit_factor;
        else
            s.pf_coefficient_variation = 999.0;

        //--- Classify
        double positive_pnl_rate = (double)positive_pnl_count / (double)segment_count;

        if(s.pass_rate >= 0.75 &&
           s.pf_coefficient_variation < 0.3 &&
           positive_pnl_rate >= 1.0 &&
           s.max_max_drawdown_pct < 2.0 * s.avg_max_drawdown_pct)
        {
            s.classification = ATLAS_WF_STABLE;
        }
        else if(s.pass_rate >= 0.50 &&
                s.pf_coefficient_variation < 0.5 &&
                positive_pnl_rate >= 0.50)
        {
            s.classification = ATLAS_WF_WEAK;
        }
        else if(s.pass_rate < 0.25 ||
                s.pf_coefficient_variation >= 1.0 ||
                (s.avg_net_profit < 0.0 && s.max_profit_factor > 2.0))
        {
            s.classification = ATLAS_WF_OVERFITTED;
        }
        else
        {
            s.classification = ATLAS_WF_UNSTABLE;
        }

        s.classification_name = WalkForwardClassificationName(s.classification);
        return s;
    }

    /**
     * @brief Get a text summary.
     */
    static string Summary(const WalkForwardSummaryData &s)
    {
        return "WF: " + s.classification_name +
               " (pass_rate=" + DoubleToString(s.pass_rate * 100.0, 0) + "%" +
               " PF_avg=" + DoubleToString(s.avg_profit_factor, 2) +
               " PF_cv=" + DoubleToString(s.pf_coefficient_variation, 2) +
               " segments=" + IntegerToString(s.total_segments) + ")";
    }
};

#endif // ATLAS_WALKFORWARD_SUMMARY_MQH
//+------------------------------------------------------------------+
