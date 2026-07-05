//+------------------------------------------------------------------+
//|                Validation/ValidationScoringEngine.mqh            |
//|       AtlasEA v1.0 Step 5.5 - Validation Scoring Engine           |
//+------------------------------------------------------------------+
#ifndef ATLAS_VALIDATION_SCORING_ENGINE_MQH
#define ATLAS_VALIDATION_SCORING_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"

/**
 * @struct ScoreBreakdown
 * @brief Breakdown of the validation score by component.
 */
struct ScoreBreakdown
{
    double profit_factor_score;   ///< Score from profit factor [0, weight]
    double win_rate_score;        ///< Score from win rate
    double drawdown_score;        ///< Score from drawdown (inverted)
    double sharpe_score;          ///< Score from Sharpe ratio
    double recovery_score;        ///< Score from recovery factor
    double trade_count_score;     ///< Score from trade count adequacy
    double sortino_score;         ///< Score from Sortino ratio
    double total_score;           ///< Total [0, 100]
    string profile_name;          ///< Scoring profile used

    ScoreBreakdown(void)
    {
        profit_factor_score = 0.0;
        win_rate_score      = 0.0;
        drawdown_score      = 0.0;
        sharpe_score        = 0.0;
        recovery_score      = 0.0;
        trade_count_score   = 0.0;
        sortino_score       = 0.0;
        total_score         = 0.0;
        profile_name        = "";
    }
};

/**
 * @class ValidationScoringEngine
 * @brief Computes composite validation scores using configurable profiles.
 *
 * SOLE RESPONSIBILITY: compute a validation score [0, 100] from
 * performance metrics using a configurable scoring profile.
 *
 * The ValidationManager does NOT contain scoring logic. It delegates
 * to this component.
 *
 * Scoring profiles:
 *   - BALANCED:      equal emphasis on all metrics
 *   - CONSERVATIVE:  heavy emphasis on drawdown + Sharpe (risk-averse)
 *   - AGGRESSIVE:    heavy emphasis on profit factor + recovery (return-focused)
 *   - INSTITUTIONAL: very strict drawdown, high Sharpe, more trades needed
 *
 * Performance: O(1), no allocation.
 */
class ValidationScoringEngine
{
public:
    /**
     * @brief Compute the validation score.
     * @param metrics Performance metrics.
     * @param config Validation configuration (selects scoring profile).
     * @return ScoreBreakdown with total [0, 100] + component breakdown.
     */
    static ScoreBreakdown Compute(const PerformanceMetrics &metrics,
                                   const ValidationConfig &config)
    {
        ScoreBreakdown score;
        ScoringWeights w = GetScoringWeights(config.scoring_profile);
        score.profile_name = ScoringProfileName(config.scoring_profile);

        //--- Profit factor (normalized to [0, 1] by PF cap)
        if(w.pf_cap > 0.0)
        {
            double pf_norm = MathMin(1.0, MathMax(0.0, metrics.profit_factor / w.pf_cap));
            score.profit_factor_score = pf_norm * w.profit_factor_weight;
        }

        //--- Win rate (already [0, 1])
        score.win_rate_score = metrics.win_rate * w.win_rate_weight;

        //--- Drawdown (inverted: lower DD = higher score)
        if(w.dd_threshold > 0.0)
        {
            double dd_norm = MathMax(0.0, 1.0 - (metrics.max_drawdown_pct / w.dd_threshold));
            score.drawdown_score = dd_norm * w.drawdown_weight;
        }

        //--- Sharpe ratio (normalized to [0, 1] by Sharpe cap)
        if(w.sharpe_cap > 0.0)
        {
            double sharpe_norm = MathMin(1.0, MathMax(0.0, metrics.sharpe_ratio / w.sharpe_cap));
            score.sharpe_score = sharpe_norm * w.sharpe_weight;
        }

        //--- Recovery factor (normalized to [0, 1] by RF cap)
        if(w.recovery_cap > 0.0)
        {
            double rf_norm = MathMin(1.0, MathMax(0.0, metrics.recovery_factor / w.recovery_cap));
            score.recovery_score = rf_norm * w.recovery_weight;
        }

        //--- Trade count adequacy (0..1, full at trade_count_full)
        if(w.trade_count_full > 0)
        {
            double tc_norm = MathMin(1.0, (double)metrics.total_trades / (double)w.trade_count_full);
            score.trade_count_score = tc_norm * w.trade_count_weight;
        }

        //--- Sortino ratio (normalized to [0, 1] by Sortino cap)
        if(w.sortino_cap > 0.0)
        {
            double sortino_norm = MathMin(1.0, MathMax(0.0, metrics.sortino_ratio / w.sortino_cap));
            score.sortino_score = sortino_norm * w.sortino_weight;
        }

        //--- Total
        score.total_score = score.profit_factor_score +
                            score.win_rate_score +
                            score.drawdown_score +
                            score.sharpe_score +
                            score.recovery_score +
                            score.trade_count_score +
                            score.sortino_score;

        //--- Clamp to [0, 100]
        if(score.total_score > 100.0) score.total_score = 100.0;
        if(score.total_score < 0.0)   score.total_score = 0.0;

        return score;
    }

    /**
     * @brief Get a text summary of the score breakdown.
     */
    static string Summary(const ScoreBreakdown &s)
    {
        return "Score=" + DoubleToString(s.total_score, 1) + "/100" +
               " [" + s.profile_name + "]" +
               " PF=" + DoubleToString(s.profit_factor_score, 1) +
               " WR=" + DoubleToString(s.win_rate_score, 1) +
               " DD=" + DoubleToString(s.drawdown_score, 1) +
               " Sh=" + DoubleToString(s.sharpe_score, 1) +
               " RF=" + DoubleToString(s.recovery_score, 1) +
               " TC=" + DoubleToString(s.trade_count_score, 1) +
               " So=" + DoubleToString(s.sortino_score, 1);
    }
};

#endif // ATLAS_VALIDATION_SCORING_ENGINE_MQH
//+------------------------------------------------------------------+
