//+------------------------------------------------------------------+
//|                   Validation/WalkForwardRunner.mqh               |
//|       AtlasEA v1.0 Step 5 - Walk-Forward Analysis Runner          |
//+------------------------------------------------------------------+
#ifndef ATLAS_WALKFORWARD_RUNNER_MQH
#define ATLAS_WALKFORWARD_RUNNER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "BacktestRunner.mqh"

/**
 * @struct WalkForwardConfig
 * @brief Configuration for walk-forward analysis.
 */
struct WalkForwardConfig
{
    datetime from_time;          ///< Overall start time
    datetime to_time;            ///< Overall end time
    int      train_bars;         ///< Training window size (bars)
    int      validate_bars;      ///< Validation window size (bars)
    bool     expanding;          ///< Expanding (true) or rolling (false) windows
    double   initial_equity;     ///< Starting equity

    WalkForwardConfig(void)
    {
        from_time      = 0;
        to_time        = 0;
        train_bars     = 500;
        validate_bars  = 250;
        expanding      = false;
        initial_equity = 10000.0;
    }
};

/**
 * @struct WalkForwardSegment
 * @brief Results for a single walk-forward segment.
 */
struct WalkForwardSegment
{
    int      segment_number;     ///< Segment index
    datetime train_start;        ///< Training period start
    datetime train_end;          ///< Training period end
    datetime validate_start;     ///< Validation period start
    datetime validate_end;       ///< Validation period end
    int      trade_count;        ///< Trades in validation period
    double   net_profit;         ///< Net profit in validation
    double   profit_factor;      ///< PF in validation
    double   max_drawdown_pct;   ///< Max DD % in validation
    double   win_rate;           ///< Win rate in validation
    int      verdict;            ///< ATLAS_VAL_PASS / FAIL

    WalkForwardSegment(void)
    {
        segment_number   = 0;
        train_start      = 0;
        train_end        = 0;
        validate_start   = 0;
        validate_end     = 0;
        trade_count      = 0;
        net_profit       = 0.0;
        profit_factor    = 0.0;
        max_drawdown_pct = 0.0;
        win_rate         = 0.0;
        verdict          = ATLAS_VAL_INCOMPLETE;
    }
};

/**
 * @class WalkForwardRunner
 * @brief Runs walk-forward analysis with rolling or expanding windows.
 *
 * SOLE RESPONSIBILITY: divide the historical period into training +
 * validation segments, run a backtest for each validation segment,
 * and aggregate the results.
 *
 * The actual trade collection is done by the caller (CoreEngine or
 * ValidationManager). The WalkForwardRunner receives the trade records
 * for each segment and produces segment reports + an aggregated report.
 *
 * Window types:
 *   - Rolling: each segment has the same train_bars + validate_bars
 *   - Expanding: the training window grows, validation stays fixed
 *
 * Performance: O(S × N) where S = segments, N = trades per segment.
 */
class WalkForwardRunner
{
private:
    ILogger          *m_logger;
    WalkForwardConfig m_config;
    BacktestRunner    m_backtest_runner;

    WalkForwardSegment m_segments[ATLAS_VAL_MAX_SEGMENTS];
    int                m_segment_count;

public:
    WalkForwardRunner(void) { m_logger = NULL; m_segment_count = 0; }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_backtest_runner.SetLogger(logger);
    }

    void SetConfig(const WalkForwardConfig &config) { m_config = config; }

    /**
     * @brief Plan the walk-forward segments.
     *
     * Computes the train/validate time windows for each segment based
     * on the configuration. Called before running the segments.
     *
     * @return Number of segments planned.
     */
    int PlanSegments(void)
    {
        m_segment_count = 0;
        if(m_config.train_bars <= 0 || m_config.validate_bars <= 0) return 0;

        //--- Estimate total bars in the period
        long total_sec = (long)m_config.to_time - (long)m_config.from_time;
        long bar_sec = 3600; // Assume 1-hour bars
        long total_bars = total_sec / bar_sec;
        long min_bars = m_config.train_bars + m_config.validate_bars;

        if(total_bars < min_bars) return 0;

        //--- Calculate how many segments fit
        long train = m_config.train_bars;
        long validate = m_config.validate_bars;
        long current_start = 0;

        while(current_start + train + validate <= total_bars &&
              m_segment_count < ATLAS_VAL_MAX_SEGMENTS)
        {
            WalkForwardSegment seg;
            seg.segment_number = m_segment_count + 1;

            long train_start_bar = current_start;
            long train_end_bar = current_start + train;
            long val_start_bar = train_end_bar;
            long val_end_bar = val_start_bar + validate;

            seg.train_start = (datetime)((long)m_config.from_time + train_start_bar * bar_sec);
            seg.train_end   = (datetime)((long)m_config.from_time + train_end_bar * bar_sec);
            seg.validate_start = (datetime)((long)m_config.from_time + val_start_bar * bar_sec);
            seg.validate_end   = (datetime)((long)m_config.from_time + val_end_bar * bar_sec);

            m_segments[m_segment_count] = seg;
            m_segment_count++;

            //--- Advance
            if(m_config.expanding)
            {
                //--- Expanding: train grows, validation slides forward
                current_start += validate;
                train += validate; // Train window expands
            }
            else
            {
                //--- Rolling: both windows slide forward
                current_start += validate;
            }
        }

        if(m_logger != NULL)
            m_logger.Info("WalkForwardRunner",
                "Planned " + IntegerToString(m_segment_count) + " segments" +
                " (" + (m_config.expanding ? "expanding" : "rolling") + ")" +
                " train=" + IntegerToString(m_config.train_bars) + " bars" +
                " validate=" + IntegerToString(m_config.validate_bars) + " bars");

        return m_segment_count;
    }

    /**
     * @brief Run analysis for a specific segment.
     *
     * @param segment_idx Segment index (0-based).
     * @param trades Trade records for this segment's validation period.
     * @param count Number of trades.
     * @param criteria Pass/fail criteria.
     * @return ValidationReport for this segment.
     */
    ValidationReport RunSegment(const int segment_idx,
                                 const TradeRecord &trades[], const int count,
                                 const PassFailCriteria &criteria)
    {
        ValidationReport report;
        if(segment_idx < 0 || segment_idx >= m_segment_count) return report;

        report.run_type  = ATLAS_VAL_RUN_WALKFORWARD;
        report.run_name  = "WalkForward Segment " + IntegerToString(segment_idx + 1);
        report.criteria  = criteria;
        report.segment_count = m_segment_count;

        BacktestConfig bc;
        bc.from_time      = m_segments[segment_idx].validate_start;
        bc.to_time        = m_segments[segment_idx].validate_end;
        bc.initial_equity = m_config.initial_equity;
        m_backtest_runner.SetConfig(bc);

        report = m_backtest_runner.Run(trades, count, criteria, report.run_name);
        report.run_type     = ATLAS_VAL_RUN_WALKFORWARD;
        report.segment_count = m_segment_count;

        //--- Record segment summary
        m_segments[segment_idx].trade_count      = report.performance.total_trades;
        m_segments[segment_idx].net_profit       = report.performance.net_profit;
        m_segments[segment_idx].profit_factor    = report.performance.profit_factor;
        m_segments[segment_idx].max_drawdown_pct = report.performance.max_drawdown_pct;
        m_segments[segment_idx].win_rate         = report.performance.win_rate;
        m_segments[segment_idx].verdict          = report.verdict;

        return report;
    }

    /**
     * @brief Aggregate all segment results into a final report.
     *
     * @param segment_reports Array of segment ValidationReports.
     * @param segment_count Number of segments.
     * @param criteria Pass/fail criteria.
     * @return Aggregated ValidationReport.
     */
    ValidationReport Aggregate(const ValidationReport &segment_reports[],
                                const int segment_count,
                                const PassFailCriteria &criteria)
    {
        ValidationReport agg;
        agg.run_type      = ATLAS_VAL_RUN_WALKFORWARD;
        agg.run_name      = "WalkForward Aggregated";
        agg.criteria      = criteria;
        agg.segment_count = segment_count;

        if(segment_count <= 0)
        {
            agg.verdict = ATLAS_VAL_INCOMPLETE;
            return agg;
        }

        //--- Sum metrics across segments
        int total_trades = 0;
        double total_pnl = 0.0;
        int passing_segments = 0;

        for(int i = 0; i < segment_count; i++)
        {
            total_trades += segment_reports[i].performance.total_trades;
            total_pnl += segment_reports[i].performance.net_profit;
            if(segment_reports[i].verdict == ATLAS_VAL_PASS)
                passing_segments++;
        }

        agg.performance.total_trades = total_trades;
        agg.performance.net_profit   = total_pnl;

        //--- A walk-forward passes if >= 60% of segments pass
        double pass_rate = (double)passing_segments / (double)segment_count;
        agg.verdict = (pass_rate >= 0.60) ? ATLAS_VAL_PASS : ATLAS_VAL_FAIL;
        agg.criteria_checked = segment_count;
        agg.criteria_passed  = passing_segments;
        agg.criteria_failed  = segment_count - passing_segments;
        agg.validation_score = pass_rate * 100.0;

        if(m_logger != NULL)
            m_logger.Info("WalkForwardRunner",
                "Aggregated: " + IntegerToString(passing_segments) + "/" +
                IntegerToString(segment_count) + " segments passed" +
                " verdict=" + (agg.verdict == ATLAS_VAL_PASS ? "PASS" : "FAIL") +
                " score=" + DoubleToString(agg.validation_score, 1));

        return agg;
    }

    /**
     * @brief Get a segment summary.
     */
    const WalkForwardSegment& GetSegment(const int idx) const
    {
        if(idx < 0 || idx >= m_segment_count)
        {
            static WalkForwardSegment empty;
            return empty;
        }
        return m_segments[idx];
    }

    /**
     * @brief Get the number of planned segments.
     */
    int GetSegmentCount(void) const { return m_segment_count; }
};

#endif // ATLAS_WALKFORWARD_RUNNER_MQH
//+------------------------------------------------------------------+
