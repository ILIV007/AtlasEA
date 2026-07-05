//+------------------------------------------------------------------+
//|                   Validation/ConfidenceRating.mqh                |
//|       AtlasEA v1.0 Step 5.5 - Confidence Rating                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIDENCE_RATING_MQH
#define ATLAS_CONFIDENCE_RATING_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"

/**
 * @struct ConfidenceFactors
 * @brief Individual factors that contribute to the confidence rating.
 */
struct ConfidenceFactors
{
    double trade_count_factor;      ///< [0, 1] based on trade count
    double wf_stability_factor;     ///< [0, 1] based on walk-forward stability
    double mc_stability_factor;     ///< [0, 1] based on Monte Carlo stability
    double dd_consistency_factor;   ///< [0, 1] based on drawdown consistency
    double overall_factor;          ///< Weighted average [0, 1]

    ConfidenceFactors(void)
    {
        trade_count_factor    = 0.0;
        wf_stability_factor   = 0.0;
        mc_stability_factor   = 0.0;
        dd_consistency_factor = 0.0;
        overall_factor        = 0.0;
    }
};

/**
 * @class ConfidenceRating
 * @brief Computes a confidence rating for a validation report.
 *
 * SOLE RESPONSIBILITY: compute a confidence level (LOW / MEDIUM / HIGH /
 * VERY_HIGH) based on multiple stability factors.
 *
 * Factors:
 *   1. Trade count: more trades = higher confidence
 *      < 20 trades → 0.1
 *      20-50 → 0.4
 *      50-100 → 0.7
 *      100-200 → 0.9
 *      > 200 → 1.0
 *
 *   2. Walk-forward stability: more segments passing = higher confidence
 *      (0 segments → 0.5, 100% pass → 1.0, < 50% pass → 0.2)
 *
 *   3. Monte Carlo stability: narrower confidence intervals = higher
 *      p5 of net profit > 0 → 1.0, p5 < -10% of initial → 0.1
 *
 *   4. Drawdown consistency: lower max DD relative to average DD = higher
 *      max_dd / avg_dd < 2 → 1.0, > 10 → 0.1
 *
 * Overall = weighted average of all factors.
 *
 * Rating:
 *   overall < 0.30 → LOW
 *   0.30-0.55    → MEDIUM
 *   0.55-0.80    → HIGH
 *   > 0.80       → VERY_HIGH
 *
 * Performance: O(1), no allocation.
 */
class ConfidenceRating
{
public:
    /**
     * @brief Compute confidence rating from a validation report.
     * @param report The validation report (must have performance metrics).
     * @param wf_pass_rate Walk-forward pass rate [0, 1] (0 = no WF run).
     * @param mc_p5_pnl Monte Carlo p5 of net profit (0 = no MC run).
     * @param initial_equity Initial equity (for MC normalization).
     * @return Confidence level code (ATLAS_CONFIDENCE_*).
     */
    static int Compute(const ValidationReport &report,
                        const double wf_pass_rate,
                        const double mc_p5_pnl,
                        const double initial_equity)
    {
        ConfidenceFactors f = ComputeFactors(report, wf_pass_rate,
                                              mc_p5_pnl, initial_equity);
        return Classify(f.overall_factor);
    }

    /**
     * @brief Compute individual confidence factors.
     */
    static ConfidenceFactors ComputeFactors(const ValidationReport &report,
                                              const double wf_pass_rate,
                                              const double mc_p5_pnl,
                                              const double initial_equity)
    {
        ConfidenceFactors f;
        const PerformanceMetrics &p = report.performance;

        //=== 1. Trade count factor ===
        int tc = p.total_trades;
        if(tc < 20)       f.trade_count_factor = 0.1;
        else if(tc < 50)  f.trade_count_factor = 0.4;
        else if(tc < 100) f.trade_count_factor = 0.7;
        else if(tc < 200) f.trade_count_factor = 0.9;
        else              f.trade_count_factor = 1.0;

        //=== 2. Walk-forward stability factor ===
        if(wf_pass_rate > 0.0)
        {
            if(wf_pass_rate >= 0.80)      f.wf_stability_factor = 1.0;
            else if(wf_pass_rate >= 0.60) f.wf_stability_factor = 0.8;
            else if(wf_pass_rate >= 0.40) f.wf_stability_factor = 0.5;
            else                          f.wf_stability_factor = 0.2;
        }
        else
        {
            //--- No walk-forward run → neutral
            f.wf_stability_factor = 0.5;
        }

        //=== 3. Monte Carlo stability factor ===
        if(mc_p5_pnl != 0.0 || report.simulation_count > 0)
        {
            //--- MC was run; check p5 of net profit
            if(initial_equity > 0.0)
            {
                double p5_pct = mc_p5_pnl / initial_equity * 100.0;
                if(p5_pct > 5.0)       f.mc_stability_factor = 1.0;
                else if(p5_pct > 0.0)  f.mc_stability_factor = 0.8;
                else if(p5_pct > -5.0) f.mc_stability_factor = 0.4;
                else                   f.mc_stability_factor = 0.1;
            }
            else
            {
                f.mc_stability_factor = (mc_p5_pnl > 0.0) ? 0.8 : 0.3;
            }
        }
        else
        {
            //--- No MC run → neutral
            f.mc_stability_factor = 0.5;
        }

        //=== 4. Drawdown consistency factor ===
        if(p.average_drawdown > 0.0 && p.max_drawdown > 0.0)
        {
            double ratio = p.max_drawdown / p.average_drawdown;
            if(ratio < 2.0)       f.dd_consistency_factor = 1.0;
            else if(ratio < 5.0)  f.dd_consistency_factor = 0.7;
            else if(ratio < 10.0) f.dd_consistency_factor = 0.4;
            else                  f.dd_consistency_factor = 0.1;
        }
        else
        {
            //--- No drawdown data → neutral
            f.dd_consistency_factor = 0.5;
        }

        //=== Overall (weighted average) ===
        f.overall_factor = f.trade_count_factor    * 0.30 +
                           f.wf_stability_factor   * 0.25 +
                           f.mc_stability_factor   * 0.25 +
                           f.dd_consistency_factor * 0.20;

        if(f.overall_factor > 1.0) f.overall_factor = 1.0;
        if(f.overall_factor < 0.0) f.overall_factor = 0.0;

        return f;
    }

    /**
     * @brief Classify an overall factor into a confidence level.
     */
    static int Classify(const double overall_factor)
    {
        if(overall_factor >= 0.80) return ATLAS_CONFIDENCE_VERY_HIGH;
        if(overall_factor >= 0.55) return ATLAS_CONFIDENCE_HIGH;
        if(overall_factor >= 0.30) return ATLAS_CONFIDENCE_MEDIUM;
        return ATLAS_CONFIDENCE_LOW;
    }

    /**
     * @brief Get a text summary of the confidence factors.
     */
    static string Summary(const ConfidenceFactors &f)
    {
        return "Confidence: " + ConfidenceLevelName(Classify(f.overall_factor)) +
               " (overall=" + DoubleToString(f.overall_factor * 100.0, 0) + "%" +
               " TC=" + DoubleToString(f.trade_count_factor * 100.0, 0) + "%" +
               " WF=" + DoubleToString(f.wf_stability_factor * 100.0, 0) + "%" +
               " MC=" + DoubleToString(f.mc_stability_factor * 100.0, 0) + "%" +
               " DD=" + DoubleToString(f.dd_consistency_factor * 100.0, 0) + "%)";
    }
};

#endif // ATLAS_CONFIDENCE_RATING_MQH
//+------------------------------------------------------------------+
