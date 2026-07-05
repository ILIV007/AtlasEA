//+------------------------------------------------------------------+
//|                    Validation/ValidationManager.mqh              |
//|       AtlasEA v1.0 Step 5 - Validation Manager (Orchestrator)    |
//+------------------------------------------------------------------+
#ifndef ATLAS_VALIDATION_MANAGER_MQH
#define ATLAS_VALIDATION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"
#include "DatasetFingerprint.mqh"
#include "QualityGate.mqh"
#include "ValidationScoringEngine.mqh"
#include "ConfidenceRating.mqh"
#include "WalkForwardSummary.mqh"
#include "ValidationCache.mqh"
#include "PerformanceAnalyzer.mqh"
#include "EquityAnalyzer.mqh"
#include "RiskAnalyzer.mqh"
#include "BacktestRunner.mqh"
#include "WalkForwardRunner.mqh"
#include "MonteCarloRunner.mqh"

/**
 * @class ValidationManager
 * @brief The ONLY component that orchestrates validation runs.
 *
 * Implements IValidationManager. Coordinates backtest, walk-forward,
 * and Monte Carlo analysis. Produces deterministic reports.
 *
 * v2 (Step 5.5) improvements:
 *   - Uses ValidationConfig for all thresholds (no hard-coded values)
 *   - Schema/report versioning embedded in every report
 *   - Scoring delegated to ValidationScoringEngine (4 profiles)
 *   - Quality gate runs before validation (early reject)
 *   - DatasetFingerprint for provenance + cache lookup
 *   - Confidence rating (LOW/MEDIUM/HIGH/VERY_HIGH)
 *   - Walk-forward summary (Stable/Weak/Unstable/Overfitted)
 *   - Validation cache (skip recomputation if fingerprint + config match)
 *   - ValidationManager is an orchestrator only — no scoring logic
 *
 * INTEGRATION:
 *   - Uses existing Testing framework, Replay engine, and Metrics.
 *   - Does not duplicate functionality.
 *   - Trade records are collected by the caller (CoreEngine) during
 *     replay and passed to the ValidationManager for analysis.
 *
 * Performance: O(N) for backtest, O(S×N) for walk-forward/MC.
 * No heap allocation in hot path.
 */
class ValidationManager : public IValidationManager
{
private:
    ILogger           *m_logger;
    bool               m_initialized;
    ValidationConfig   m_val_config;     ///< v2: full validation config
    PassFailCriteria   m_criteria;       ///< Derived from val_config

    //--- Owned analyzers/runners (stack-allocated)
    PerformanceAnalyzer m_perf_analyzer;
    EquityAnalyzer      m_equity_analyzer;
    RiskAnalyzer        m_risk_analyzer;
    BacktestRunner      m_backtest_runner;
    WalkForwardRunner   m_walkforward_runner;
    MonteCarloRunner    m_montecarlo_runner;

    //--- v2: New components (stack-allocated)
    QualityGate         m_quality_gate;
    ValidationCache     m_cache;

    //--- Last report
    ValidationReport    m_last_report;

    //--- Trade records (collected by caller, stored for analysis)
    TradeRecord         m_trades[ATLAS_VAL_MAX_TRADES];
    int                 m_trade_count;

    //--- Dataset metadata
    string              m_symbol;
    int                 m_timeframe_minutes;
    string              m_replay_id;

    /**
     * @brief Sync PassFailCriteria from ValidationConfig.
     */
    void SyncCriteria(void)
    {
        m_criteria.min_profit_factor      = m_val_config.min_profit_factor;
        m_criteria.max_drawdown_pct       = m_val_config.max_drawdown_pct;
        m_criteria.min_win_rate           = m_val_config.min_win_rate;
        m_criteria.min_trade_count        = m_val_config.min_trade_count;
        m_criteria.max_exposure_pct       = m_val_config.max_exposure_pct;
        m_criteria.min_net_profit         = m_val_config.min_net_profit;
        m_criteria.min_sharpe_ratio       = m_val_config.min_sharpe_ratio;
        m_criteria.max_consecutive_losses = m_val_config.max_consecutive_losses;
    }

    /**
     * @brief Populate fingerprint fields in the report.
     */
    void PopulateFingerprint(ValidationReport &report,
                              const DatasetFingerprint &fp)
    {
        report.fingerprint_symbol      = fp.symbol;
        report.fingerprint_trade_count = fp.trade_count;
        report.fingerprint_data_from   = fp.data_from;
        report.fingerprint_data_to     = fp.data_to;
        report.fingerprint_hash        = fp.dataset_hash;
    }

    /**
     * @brief Populate scoring breakdown in the report.
     */
    void PopulateScoring(ValidationReport &report,
                          const ScoreBreakdown &score)
    {
        report.validation_score    = score.total_score;
        report.scoring_profile     = m_val_config.scoring_profile;
        report.score_profit_factor = score.profit_factor_score;
        report.score_win_rate      = score.win_rate_score;
        report.score_drawdown      = score.drawdown_score;
        report.score_sharpe        = score.sharpe_score;
        report.score_recovery      = score.recovery_score;
        report.score_trade_count   = score.trade_count_score;
        report.score_sortino       = score.sortino_score;
    }

    /**
     * @brief Populate confidence fields in the report.
     */
    void PopulateConfidence(ValidationReport &report,
                             const ConfidenceFactors &factors)
    {
        report.confidence_level          = ConfidenceRating::Classify(factors.overall_factor);
        report.confidence_factor         = factors.overall_factor;
        report.confidence_trade_count    = factors.trade_count_factor;
        report.confidence_wf_stability   = factors.wf_stability_factor;
        report.confidence_mc_stability   = factors.mc_stability_factor;
        report.confidence_dd_consistency = factors.dd_consistency_factor;
    }

public:
    /**
     * @brief Constructor.
     */
    ValidationManager(void)
    {
        m_logger            = NULL;
        m_initialized       = false;
        m_trade_count       = 0;
        m_timeframe_minutes = 60;
        m_replay_id         = "";
        m_symbol            = "";
        SyncCriteria();
    }

    /**
     * @brief Set the logger (wires to all sub-components).
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_perf_analyzer.SetLogger(logger);
        m_equity_analyzer.SetLogger(logger);
        m_risk_analyzer.SetLogger(logger);
        m_backtest_runner.SetLogger(logger);
        m_walkforward_runner.SetLogger(logger);
        m_montecarlo_runner.SetLogger(logger);
        m_quality_gate.SetLogger(logger);
        m_cache.SetLogger(logger);
    }

    /**
     * @brief Set dataset metadata (for fingerprint generation).
     */
    void SetDatasetMetadata(const string symbol, const int timeframe_minutes,
                             const string replay_id)
    {
        m_symbol            = symbol;
        m_timeframe_minutes = timeframe_minutes;
        m_replay_id         = replay_id;
    }

    //=== Trade record collection (called by CoreEngine during replay) ===

    void AddTrade(const TradeRecord &trade)
    {
        if(m_trade_count >= ATLAS_VAL_MAX_TRADES) return;
        m_trades[m_trade_count] = trade;
        m_trade_count++;
    }

    void ClearTrades(void)
    {
        m_trade_count = 0;
    }

    int GetTradeCount(void) const { return m_trade_count; }

    //=== IValidationManager implementation ===

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("ValidationManager",
            "Initialized v2 (schema=" + IntegerToString(m_val_config.schema_version) +
            " profile=" + ScoringProfileName(m_val_config.scoring_profile) + ")");
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        m_initialized = false;
        ClearTrades();
        m_cache.Clear();
        if(m_logger != NULL)
            m_logger.Info("ValidationManager", "Shutdown complete");
    }

    virtual void SetCriteria(const PassFailCriteria &criteria) override
    {
        m_criteria = criteria;
    }

    virtual void SetValidationConfig(const ValidationConfig &config) override
    {
        m_val_config = config;
        SyncCriteria();
    }

    virtual void SetScoringProfile(const int profile) override
    {
        m_val_config.scoring_profile = profile;
    }

    virtual ValidationReport RunBacktest(const datetime from_time,
                                          const datetime to_time) override
    {
        if(!m_initialized)
        {
            m_last_report.verdict = ATLAS_VAL_INCOMPLETE;
            return m_last_report;
        }

        //--- v2: Generate fingerprint
        DatasetFingerprint fp = FingerprintGenerator::Generate(
            m_trades, m_trade_count, m_symbol, m_timeframe_minutes, m_replay_id);

        //--- v2: Check cache
        if(ValidationCache::IsEnabled(m_val_config))
        {
            double cached_score;
            int cached_conf, cached_verdict;
            if(m_cache.TryGet(fp, m_val_config, cached_score, cached_conf, cached_verdict))
            {
                m_last_report.verdict            = cached_verdict;
                m_last_report.run_type           = ATLAS_VAL_RUN_BACKTEST;
                m_last_report.run_name           = "Full Backtest (cached)";
                m_last_report.validation_score   = cached_score;
                m_last_report.confidence_level   = cached_conf;
                m_last_report.cache_hit          = true;
                m_last_report.schema_version     = m_val_config.schema_version;
                m_last_report.report_version     = m_val_config.report_version;
                PopulateFingerprint(m_last_report, fp);
                if(m_logger != NULL)
                    m_logger.Info("ValidationManager",
                        "Cache hit — skipping recomputation");
                return m_last_report;
            }
        }

        //--- v2: Quality gate
        QualityGateResult qg = m_quality_gate.Check(m_trades, m_trade_count, m_val_config);
        if(!qg.Passed())
        {
            m_last_report.verdict       = ATLAS_VAL_INCOMPLETE;
            m_last_report.run_name      = "Backtest (quality gate failed)";
            m_last_report.fail_reason_count = 1;
            m_last_report.fail_reasons[0] = "Quality gate: " + qg.detail;
            m_last_report.schema_version = m_val_config.schema_version;
            m_last_report.report_version = m_val_config.report_version;
            PopulateFingerprint(m_last_report, fp);
            return m_last_report;
        }

        //--- Run backtest (uses BacktestRunner which delegates to analyzers)
        BacktestConfig bc;
        bc.from_time      = from_time;
        bc.to_time        = to_time;
        bc.initial_equity = 10000.0;
        m_backtest_runner.SetConfig(bc);

        m_last_report = m_backtest_runner.Run(m_trades, m_trade_count,
                                               m_criteria, "Full Backtest");

        //--- v2: Schema versioning
        m_last_report.schema_version = m_val_config.schema_version;
        m_last_report.report_version = m_val_config.report_version;

        //--- v2: Fingerprint
        PopulateFingerprint(m_last_report, fp);

        //--- v2: Scoring (delegated to ValidationScoringEngine)
        ScoreBreakdown score = ValidationScoringEngine::Compute(
            m_last_report.performance, m_val_config);
        PopulateScoring(m_last_report, score);

        //--- v2: Confidence rating
        ConfidenceFactors factors = ConfidenceRating::ComputeFactors(
            m_last_report, 0.0, 0.0, 10000.0);
        PopulateConfidence(m_last_report, factors);

        //--- v2: Cache the result
        if(ValidationCache::IsEnabled(m_val_config))
        {
            m_cache.Put(fp, m_val_config,
                        m_last_report.validation_score,
                        m_last_report.confidence_level,
                        m_last_report.verdict);
        }

        return m_last_report;
    }

    virtual ValidationReport RunWalkForward(const datetime from_time,
                                              const datetime to_time,
                                              const int train_bars,
                                              const int validate_bars,
                                              const bool expanding) override
    {
        if(!m_initialized)
        {
            m_last_report.verdict = ATLAS_VAL_INCOMPLETE;
            return m_last_report;
        }

        WalkForwardConfig wfc;
        wfc.from_time      = from_time;
        wfc.to_time        = to_time;
        wfc.train_bars     = train_bars;
        wfc.validate_bars  = validate_bars;
        wfc.expanding      = expanding;
        wfc.initial_equity = 10000.0;
        m_walkforward_runner.SetConfig(wfc);

        int seg_count = m_walkforward_runner.PlanSegments();
        if(seg_count <= 0)
        {
            m_last_report.verdict = ATLAS_VAL_INCOMPLETE;
            m_last_report.run_name = "WalkForward (no segments)";
            return m_last_report;
        }

        ValidationReport seg_reports[ATLAS_VAL_MAX_SEGMENTS];
        for(int i = 0; i < seg_count; i++)
        {
            seg_reports[i] = m_walkforward_runner.RunSegment(i, m_trades,
                                                              m_trade_count,
                                                              m_criteria);
        }

        m_last_report = m_walkforward_runner.Aggregate(seg_reports, seg_count,
                                                        m_criteria);

        //--- v2: Walk-forward summary classification
        WalkForwardSummaryData wf_summary = WalkForwardSummary::Compute(
            seg_reports, seg_count);
        m_last_report.wf_classification = wf_summary.classification;
        m_last_report.wf_pass_rate      = wf_summary.pass_rate;
        m_last_report.wf_pf_cv          = wf_summary.pf_coefficient_variation;

        //--- v2: Schema + scoring + confidence
        m_last_report.schema_version = m_val_config.schema_version;
        m_last_report.report_version = m_val_config.report_version;
        ScoreBreakdown score = ValidationScoringEngine::Compute(
            m_last_report.performance, m_val_config);
        PopulateScoring(m_last_report, score);
        ConfidenceFactors factors = ConfidenceRating::ComputeFactors(
            m_last_report, wf_summary.pass_rate, 0.0, 10000.0);
        PopulateConfidence(m_last_report, factors);

        return m_last_report;
    }

    virtual ValidationReport RunMonteCarlo(const int simulation_count,
                                             const ulong seed,
                                             const bool shuffle_trades,
                                             const bool vary_spread,
                                             const bool vary_slippage,
                                             const bool vary_delay) override
    {
        if(!m_initialized)
        {
            m_last_report.verdict = ATLAS_VAL_INCOMPLETE;
            return m_last_report;
        }

        MonteCarloConfig mcc;
        mcc.simulation_count = simulation_count;
        mcc.seed             = seed;
        mcc.shuffle_trades   = shuffle_trades;
        mcc.vary_spread      = vary_spread;
        mcc.vary_slippage    = vary_slippage;
        mcc.vary_delay       = vary_delay;
        mcc.initial_equity   = 10000.0;
        m_montecarlo_runner.SetConfig(mcc);

        m_last_report = m_montecarlo_runner.Run(m_trades, m_trade_count, m_criteria);

        //--- v2: Schema + scoring + confidence
        m_last_report.schema_version = m_val_config.schema_version;
        m_last_report.report_version = m_val_config.report_version;
        ScoreBreakdown score = ValidationScoringEngine::Compute(
            m_last_report.performance, m_val_config);
        PopulateScoring(m_last_report, score);
        ConfidenceFactors factors = ConfidenceRating::ComputeFactors(
            m_last_report, 0.0, 0.0, 10000.0);
        PopulateConfidence(m_last_report, factors);

        return m_last_report;
    }

    virtual const ValidationReport& GetLastReport(void) const override
    {
        return m_last_report;
    }

    virtual bool ExportCSV(const string filename) const override
    {
        if(m_logger == NULL) return false;

        int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
        if(handle == INVALID_HANDLE)
        {
            m_logger.Error("ValidationManager", "Cannot open CSV: " + filename);
            return false;
        }

        //--- v2: Schema version header
        FileWrite(handle, "Schema Version", m_last_report.schema_version);
        FileWrite(handle, "Report Version", m_last_report.report_version);

        //--- v2: Fingerprint
        FileWrite(handle, "Fingerprint Symbol", m_last_report.fingerprint_symbol);
        FileWrite(handle, "Fingerprint Trade Count", m_last_report.fingerprint_trade_count);
        FileWrite(handle, "Fingerprint Hash", IntegerToString((long)m_last_report.fingerprint_hash));

        //--- v2: Cache
        FileWrite(handle, "Cache Hit", m_last_report.cache_hit ? "YES" : "NO");

        //--- Performance metrics
        const PerformanceMetrics &p = m_last_report.performance;
        FileWrite(handle, "Total Trades", p.total_trades);
        FileWrite(handle, "Winning Trades", p.winning_trades);
        FileWrite(handle, "Losing Trades", p.losing_trades);
        FileWrite(handle, "Win Rate", DoubleToString(p.win_rate * 100.0, 2) + "%");
        FileWrite(handle, "Net Profit", DoubleToString(p.net_profit, 2));
        FileWrite(handle, "Gross Profit", DoubleToString(p.gross_profit, 2));
        FileWrite(handle, "Gross Loss", DoubleToString(p.gross_loss, 2));
        FileWrite(handle, "Profit Factor", DoubleToString(p.profit_factor, 4));
        FileWrite(handle, "Recovery Factor", DoubleToString(p.recovery_factor, 4));
        FileWrite(handle, "Sharpe Ratio", DoubleToString(p.sharpe_ratio, 4));
        FileWrite(handle, "Sortino Ratio", DoubleToString(p.sortino_ratio, 4));
        FileWrite(handle, "Max Drawdown %", DoubleToString(p.max_drawdown_pct, 2) + "%");
        FileWrite(handle, "Max Consecutive Losses", p.max_consecutive_losses);
        FileWrite(handle, "Max Consecutive Wins", p.max_consecutive_wins);
        FileWrite(handle, "Average RR", DoubleToString(p.average_rr, 4));

        //--- v2: Scoring breakdown
        FileWrite(handle, "Scoring Profile", ScoringProfileName(m_last_report.scoring_profile));
        FileWrite(handle, "Validation Score", DoubleToString(m_last_report.validation_score, 1));
        FileWrite(handle, "Score PF Component", DoubleToString(m_last_report.score_profit_factor, 1));
        FileWrite(handle, "Score WR Component", DoubleToString(m_last_report.score_win_rate, 1));
        FileWrite(handle, "Score DD Component", DoubleToString(m_last_report.score_drawdown, 1));
        FileWrite(handle, "Score Sharpe Component", DoubleToString(m_last_report.score_sharpe, 1));
        FileWrite(handle, "Score Recovery Component", DoubleToString(m_last_report.score_recovery, 1));
        FileWrite(handle, "Score Trade Count Component", DoubleToString(m_last_report.score_trade_count, 1));
        FileWrite(handle, "Score Sortino Component", DoubleToString(m_last_report.score_sortino, 1));

        //--- v2: Confidence
        FileWrite(handle, "Confidence Level", ConfidenceLevelName(m_last_report.confidence_level));
        FileWrite(handle, "Confidence Factor", DoubleToString(m_last_report.confidence_factor * 100.0, 1) + "%");

        //--- v2: Walk-forward
        FileWrite(handle, "WF Classification", WalkForwardClassificationName(m_last_report.wf_classification));
        FileWrite(handle, "WF Pass Rate", DoubleToString(m_last_report.wf_pass_rate * 100.0, 1) + "%");
        FileWrite(handle, "WF PF CV", DoubleToString(m_last_report.wf_pf_cv, 3));

        //--- Verdict
        FileWrite(handle, "Verdict",
            m_last_report.verdict == ATLAS_VAL_PASS ? "PASS" :
            m_last_report.verdict == ATLAS_VAL_FAIL ? "FAIL" : "INCOMPLETE");

        FileClose(handle);

        if(m_logger != NULL)
            m_logger.Info("ValidationManager", "CSV exported to " + filename);
        return true;
    }

    virtual void LogReport(void) const override
    {
        if(m_logger == NULL) return;

        const PerformanceMetrics &p = m_last_report.performance;

        string verdict_str = (m_last_report.verdict == ATLAS_VAL_PASS) ? "PASS" :
                             (m_last_report.verdict == ATLAS_VAL_FAIL) ? "FAIL" : "INCOMPLETE";

        m_logger.Info("ValidationManager",
            "=== Validation Report v" + IntegerToString(m_last_report.report_version) +
            " (schema v" + IntegerToString(m_last_report.schema_version) + "): " +
            m_last_report.run_name + " ===");
        m_logger.Info("ValidationManager",
            "Verdict: " + verdict_str +
            " Score: " + DoubleToString(m_last_report.validation_score, 1) + "/100" +
            " [" + ScoringProfileName(m_last_report.scoring_profile) + "]" +
            " Confidence: " + ConfidenceLevelName(m_last_report.confidence_level) +
            " (" + DoubleToString(m_last_report.confidence_factor * 100.0, 0) + "%)" +
            (m_last_report.cache_hit ? " [CACHED]" : ""));
        m_logger.Info("ValidationManager",
            "Fingerprint: " + m_last_report.fingerprint_symbol +
            " hash=" + IntegerToString((long)m_last_report.fingerprint_hash) +
            " trades=" + IntegerToString(m_last_report.fingerprint_trade_count));
        m_logger.Info("ValidationManager",
            "Trades: " + IntegerToString(p.total_trades) +
            " W:" + IntegerToString(p.winning_trades) +
            " L:" + IntegerToString(p.losing_trades) +
            " WR:" + DoubleToString(p.win_rate * 100.0, 1) + "%" +
            " PF:" + DoubleToString(p.profit_factor, 2) +
            " Sharpe:" + DoubleToString(p.sharpe_ratio, 2) +
            " MaxDD:" + DoubleToString(p.max_drawdown_pct, 1) + "%");

        if(m_last_report.segment_count > 0)
        {
            m_logger.Info("ValidationManager",
                "Walk-Forward: " + WalkForwardClassificationName(m_last_report.wf_classification) +
                " pass_rate=" + DoubleToString(m_last_report.wf_pass_rate * 100.0, 0) + "%" +
                " PF_cv=" + DoubleToString(m_last_report.wf_pf_cv, 2) +
                " segments=" + IntegerToString(m_last_report.segment_count));
        }

        for(int i = 0; i < m_last_report.fail_reason_count; i++)
        {
            m_logger.Warn("ValidationManager",
                "FAIL: " + m_last_report.fail_reasons[i]);
        }
    }
};

#endif // ATLAS_VALIDATION_MANAGER_MQH
//+------------------------------------------------------------------+
