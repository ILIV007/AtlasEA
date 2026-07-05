//+------------------------------------------------------------------+
//|                   Validation/ValidationConfig.mqh                |
//|       AtlasEA v1.0 Step 5.5 - Validation Configuration            |
//+------------------------------------------------------------------+
#ifndef ATLAS_VALIDATION_CONFIG_MQH
#define ATLAS_VALIDATION_CONFIG_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Schema version for the validation data structures.
 * Increment when any struct layout changes. Future code must
 * remain backward compatible with older schema versions.
 */
#define ATLAS_VALIDATION_SCHEMA_VERSION   2

/**
 * @brief Report version for the ValidationReport struct.
 * Increment when ValidationReport fields change.
 */
#define ATLAS_VALIDATION_REPORT_VERSION   2

/**
 * @brief Scoring profile codes.
 */
#define ATLAS_SCORING_BALANCED         0
#define ATLAS_SCORING_CONSERVATIVE     1
#define ATLAS_SCORING_AGGRESSIVE       2
#define ATLAS_SCORING_INSTITUTIONAL    3

/**
 * @brief Confidence level codes.
 */
#define ATLAS_CONFIDENCE_LOW          0
#define ATLAS_CONFIDENCE_MEDIUM       1
#define ATLAS_CONFIDENCE_HIGH         2
#define ATLAS_CONFIDENCE_VERY_HIGH    3

/**
 * @brief Walk-forward classification codes.
 */
#define ATLAS_WF_STABLE              0
#define ATLAS_WF_WEAK                1
#define ATLAS_WF_UNSTABLE            2
#define ATLAS_WF_OVERFITTED          3

/**
 * @struct ValidationConfig
 * @brief All configurable validation thresholds.
 *
 * Replaces the hard-coded PassFailCriteria with a fully configurable
 * struct. Every threshold can be set to 0 to skip that check.
 */
struct ValidationConfig
{
    //=== Pass/Fail thresholds (0 = skip check) ===
    double min_profit_factor;        ///< Min profit factor
    double max_drawdown_pct;         ///< Max drawdown %
    double min_win_rate;             ///< Min win rate [0..1]
    int    min_trade_count;          ///< Min trade count
    double max_exposure_pct;         ///< Max exposure %
    double min_net_profit;           ///< Min net profit
    double min_sharpe_ratio;         ///< Min Sharpe ratio
    double min_sortino_ratio;        ///< Min Sortino ratio
    int    max_consecutive_losses;   ///< Max consecutive losses
    double min_recovery_factor;      ///< Min recovery factor

    //=== Scoring profile ===
    int    scoring_profile;          ///< ATLAS_SCORING_*

    //=== Quality gate thresholds ===
    int    min_dataset_size;         ///< Min trades required to run
    int    max_missing_data_pct;     ///< Max % of missing timestamps
    int    max_duplicate_trades;     ///< Max duplicate trade IDs allowed
    int    min_history_bars;         ///< Min history bars required

    //=== Cache ===
    bool   enable_cache;             ///< Enable validation cache

    //=== Schema ===
    int    schema_version;           ///< Schema version for this config
    int    report_version;           ///< Report version for this config

    ValidationConfig(void)
    {
        //--- Pass/fail (sensible defaults)
        min_profit_factor       = 1.2;
        max_drawdown_pct        = 25.0;
        min_win_rate            = 0.35;
        min_trade_count         = 30;
        max_exposure_pct        = 25.0;
        min_net_profit          = 0.0;
        min_sharpe_ratio        = 0.5;
        min_sortino_ratio       = 0.3;
        max_consecutive_losses  = 6;
        min_recovery_factor     = 1.0;

        //--- Scoring
        scoring_profile         = ATLAS_SCORING_BALANCED;

        //--- Quality gate
        min_dataset_size        = 10;
        max_missing_data_pct    = 5;
        max_duplicate_trades    = 0;
        min_history_bars        = 100;

        //--- Cache
        enable_cache            = true;

        //--- Schema
        schema_version          = ATLAS_VALIDATION_SCHEMA_VERSION;
        report_version          = ATLAS_VALIDATION_REPORT_VERSION;
    }
};

/**
 * @struct ScoringWeights
 * @brief Weights for each scoring component.
 * All weights should sum to 100 (percentage).
 */
struct ScoringWeights
{
    double profit_factor_weight;    ///< Weight for PF component
    double win_rate_weight;         ///< Weight for win rate component
    double drawdown_weight;         ///< Weight for drawdown component
    double sharpe_weight;           ///< Weight for Sharpe ratio component
    double recovery_weight;         ///< Weight for recovery factor component
    double trade_count_weight;      ///< Weight for trade count adequacy
    double sortino_weight;          ///< Weight for Sortino ratio component

    //--- Caps for normalization
    double pf_cap;                  ///< PF value that gives full score
    double sharpe_cap;              ///< Sharpe value that gives full score
    double recovery_cap;            ///< RF value that gives full score
    double sortino_cap;             ///< Sortino value that gives full score
    double dd_threshold;            ///< DD % that gives zero score
    int    trade_count_full;        ///< Trade count that gives full score

    ScoringWeights(void)
    {
        profit_factor_weight  = 20.0;
        win_rate_weight       = 15.0;
        drawdown_weight       = 20.0;
        sharpe_weight         = 15.0;
        recovery_weight       = 10.0;
        trade_count_weight    = 10.0;
        sortino_weight        = 10.0;

        pf_cap         = 3.0;
        sharpe_cap     = 2.0;
        recovery_cap   = 5.0;
        sortino_cap    = 3.0;
        dd_threshold   = 25.0;
        trade_count_full = 30;
    }
};

/**
 * @brief Get the scoring weights for a profile.
 */
ScoringWeights GetScoringWeights(const int profile)
{
    ScoringWeights w;
    switch(profile)
    {
        case ATLAS_SCORING_BALANCED:
            //--- Default weights (already set)
            break;

        case ATLAS_SCORING_CONSERVATIVE:
            w.profit_factor_weight  = 15.0;
            w.win_rate_weight       = 10.0;
            w.drawdown_weight       = 30.0;  // Emphasize low drawdown
            w.sharpe_weight         = 20.0;
            w.recovery_weight       = 10.0;
            w.trade_count_weight    = 10.0;
            w.sortino_weight        = 5.0;
            w.dd_threshold          = 15.0;  // Stricter DD
            break;

        case ATLAS_SCORING_AGGRESSIVE:
            w.profit_factor_weight  = 30.0;  // Emphasize PF
            w.win_rate_weight       = 10.0;
            w.drawdown_weight       = 10.0;
            w.sharpe_weight         = 15.0;
            w.recovery_weight       = 15.0;  // Emphasize recovery
            w.trade_count_weight    = 10.0;
            w.sortino_weight        = 10.0;
            w.dd_threshold          = 40.0;  // Allow higher DD
            w.pf_cap                = 5.0;
            w.recovery_cap          = 10.0;
            break;

        case ATLAS_SCORING_INSTITUTIONAL:
            w.profit_factor_weight  = 15.0;
            w.win_rate_weight       = 10.0;
            w.drawdown_weight       = 25.0;  // Low DD is critical
            w.sharpe_weight         = 25.0;  // Risk-adjusted is critical
            w.recovery_weight       = 10.0;
            w.trade_count_weight    = 5.0;
            w.sortino_weight        = 10.0;
            w.dd_threshold          = 10.0;  // Very strict
            w.sharpe_cap            = 3.0;
            w.min_sortino_ratio     = 0.0;   // (not used here, just example)
            w.trade_count_full      = 100;   // Need more trades
            break;
    }
    return w;
}

/**
 * @brief Get the name of a scoring profile.
 */
string ScoringProfileName(const int profile)
{
    switch(profile)
    {
        case ATLAS_SCORING_BALANCED:      return "Balanced";
        case ATLAS_SCORING_CONSERVATIVE:  return "Conservative";
        case ATLAS_SCORING_AGGRESSIVE:    return "Aggressive";
        case ATLAS_SCORING_INSTITUTIONAL: return "Institutional";
    }
    return "Unknown";
}

/**
 * @brief Get the name of a confidence level.
 */
string ConfidenceLevelName(const int level)
{
    switch(level)
    {
        case ATLAS_CONFIDENCE_LOW:       return "LOW";
        case ATLAS_CONFIDENCE_MEDIUM:    return "MEDIUM";
        case ATLAS_CONFIDENCE_HIGH:      return "HIGH";
        case ATLAS_CONFIDENCE_VERY_HIGH: return "VERY_HIGH";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of a walk-forward classification.
 */
string WalkForwardClassificationName(const int classification)
{
    switch(classification)
    {
        case ATLAS_WF_STABLE:    return "Stable";
        case ATLAS_WF_WEAK:      return "Weak";
        case ATLAS_WF_UNSTABLE:  return "Unstable";
        case ATLAS_WF_OVERFITTED: return "Overfitted";
    }
    return "Unknown";
}

#endif // ATLAS_VALIDATION_CONFIG_MQH
//+------------------------------------------------------------------+
