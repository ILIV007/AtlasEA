//+------------------------------------------------------------------+
//|                      Validation/QualityGate.mqh                  |
//|       AtlasEA v1.0 Step 5.5 - Quality Gate (Pre-Validation)      |
//+------------------------------------------------------------------+
#ifndef ATLAS_QUALITY_GATE_MQH
#define ATLAS_QUALITY_GATE_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"

/**
 * @brief Quality gate check result codes.
 */
#define ATLAS_QG_PASS                 0   ///< All checks passed
#define ATLAS_QG_FAIL_DATASET_SIZE    1   ///< Too few trades
#define ATLAS_QG_FAIL_DATE_RANGE      2   ///< Invalid or insufficient date range
#define ATLAS_QG_FAIL_MISSING_DATA    3   ///< Missing timestamps detected
#define ATLAS_QG_FAIL_DUPLICATE       4   ///< Duplicate trade IDs detected
#define ATLAS_QG_FAIL_INVALID_TIME    5   ///< Invalid timestamps (zero, future, reversed)
#define ATLAS_QG_FAIL_INSUFFICIENT    6   ///< Insufficient history bars
#define ATLAS_QG_FAIL_CORRUPTED       7   ///< Corrupted data (NaN, invalid prices)

/**
 * @struct QualityGateResult
 * @brief Result of the quality gate check.
 */
struct QualityGateResult
{
    int    verdict;             ///< ATLAS_QG_PASS or ATLAS_QG_FAIL_*
    string detail;             ///< Human-readable detail
    int    trade_count;        ///< Actual trade count
    int    missing_count;      ///< Number of missing timestamps
    int    duplicate_count;    ///< Number of duplicate trade IDs
    int    invalid_time_count; ///< Number of invalid timestamps
    int    corrupted_count;    ///< Number of corrupted records
    datetime earliest_time;    ///< Earliest valid timestamp
    datetime latest_time;      ///< Latest valid timestamp

    QualityGateResult(void)
    {
        verdict            = ATLAS_QG_PASS;
        detail             = "";
        trade_count        = 0;
        missing_count      = 0;
        duplicate_count    = 0;
        invalid_time_count = 0;
        corrupted_count    = 0;
        earliest_time      = 0;
        latest_time        = 0;
    }

    bool Passed(void) const { return verdict == ATLAS_QG_PASS; }
};

/**
 * @class QualityGate
 * @brief Pre-validation quality checks.
 *
 * SOLE RESPONSIBILITY: verify dataset quality BEFORE running validation.
 * Rejects early if quality requirements fail, saving computation time.
 *
 * Checks (in order):
 *   1. Dataset size: trade_count >= min_dataset_size
 *   2. Date range: from < to, range > 0
 *   3. Missing data: trades with zero timestamps
 *   4. Invalid timestamps: zero, future, or reversed (close < open)
 *   5. Duplicate trades: same trade_id appearing more than once
 *   6. Corrupted data: NaN PnL, invalid prices, zero volume
 *   7. Insufficient history: range too short for meaningful analysis
 *
 * Performance: O(N) where N = number of trades. No heap allocation.
 */
class QualityGate
{
private:
    ILogger *m_logger;

public:
    QualityGate(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Run all quality checks on the dataset.
     * @param trades Array of trade records.
     * @param count Number of trades.
     * @param config Validation configuration (thresholds).
     * @return QualityGateResult.
     */
    QualityGateResult Check(const TradeRecord &trades[], const int count,
                             const ValidationConfig &config)
    {
        QualityGateResult result;
        result.trade_count = count;

        if(count <= 0)
        {
            result.verdict = ATLAS_QG_FAIL_DATASET_SIZE;
            result.detail  = "No trades in dataset";
            LogResult(result);
            return result;
        }

        //=== 1. Dataset size ===
        if(config.min_dataset_size > 0 && count < config.min_dataset_size)
        {
            result.verdict = ATLAS_QG_FAIL_DATASET_SIZE;
            result.detail  = "Trade count " + IntegerToString(count) +
                             " < min " + IntegerToString(config.min_dataset_size);
            LogResult(result);
            return result;
        }

        //=== 2-6. Scan all trades for issues ===
        datetime earliest = 0;
        datetime latest = 0;

        for(int i = 0; i < count; i++)
        {
            const TradeRecord &t = trades[i];

            //--- Track time range
            if(t.open_time > 0)
            {
                if(earliest == 0 || t.open_time < earliest) earliest = t.open_time;
                if(t.open_time > latest) latest = t.open_time;
            }
            if(t.close_time > 0)
            {
                if(t.close_time > latest) latest = t.close_time;
            }

            //--- 3. Missing data: zero timestamps
            if(t.open_time == 0 || t.close_time == 0)
                result.missing_count++;

            //--- 4. Invalid timestamps: future or reversed
            if(t.open_time > TimeCurrent() + 86400) // More than 1 day in the future
                result.invalid_time_count++;
            if(t.close_time > 0 && t.open_time > 0 && t.close_time < t.open_time)
                result.invalid_time_count++;

            //--- 5. Duplicate trade IDs
            if(StringLen(t.trade_id) > 0)
            {
                for(int j = i + 1; j < count && j < i + 50; j++) // Bounded search
                {
                    if(trades[j].trade_id == t.trade_id)
                    {
                        result.duplicate_count++;
                        break;
                    }
                }
            }

            //--- 6. Corrupted data
            if(!MathIsValidNumber(t.realized_pnl) ||
               !MathIsValidNumber(t.entry_price) ||
               !MathIsValidNumber(t.exit_price) ||
               t.volume <= 0.0)
                result.corrupted_count++;
        }

        result.earliest_time = earliest;
        result.latest_time   = latest;

        //=== Check missing data ===
        if(config.max_missing_data_pct > 0)
        {
            int missing_pct = (int)((double)result.missing_count / (double)count * 100.0);
            if(missing_pct > config.max_missing_data_pct)
            {
                result.verdict = ATLAS_QG_FAIL_MISSING_DATA;
                result.detail  = "Missing data " + IntegerToString(missing_pct) +
                                 "% > max " + IntegerToString(config.max_missing_data_pct) + "%";
                LogResult(result);
                return result;
            }
        }

        //=== Check duplicates ===
        if(config.max_duplicate_trades >= 0 &&
           result.duplicate_count > config.max_duplicate_trades)
        {
            result.verdict = ATLAS_QG_FAIL_DUPLICATE;
            result.detail  = "Duplicate trades " + IntegerToString(result.duplicate_count) +
                             " > max " + IntegerToString(config.max_duplicate_trades);
            LogResult(result);
            return result;
        }

        //=== Check invalid timestamps ===
        if(result.invalid_time_count > 0)
        {
            result.verdict = ATLAS_QG_FAIL_INVALID_TIME;
            result.detail  = "Invalid timestamps: " + IntegerToString(result.invalid_time_count);
            LogResult(result);
            return result;
        }

        //=== Check corrupted data ===
        if(result.corrupted_count > 0)
        {
            result.verdict = ATLAS_QG_FAIL_CORRUPTED;
            result.detail  = "Corrupted records: " + IntegerToString(result.corrupted_count);
            LogResult(result);
            return result;
        }

        //=== 7. Insufficient history ===
        if(config.min_history_bars > 0 && earliest > 0 && latest > 0)
        {
            long range_sec = (long)latest - (long)earliest;
            long bar_sec = 3600; // Assume 1-hour bars
            long bars = range_sec / bar_sec;
            if(bars < config.min_history_bars)
            {
                result.verdict = ATLAS_QG_FAIL_INSUFFICIENT;
                result.detail  = "History " + IntegerToString((int)bars) + " bars < min " +
                                 IntegerToString(config.min_history_bars) + " bars";
                LogResult(result);
                return result;
            }
        }

        //=== 2. Date range check (final) ===
        if(earliest >= latest)
        {
            result.verdict = ATLAS_QG_FAIL_DATE_RANGE;
            result.detail  = "Invalid date range: from >= to";
            LogResult(result);
            return result;
        }

        //=== All checks passed ===
        result.verdict = ATLAS_QG_PASS;
        result.detail  = "All quality checks passed";
        LogResult(result);
        return result;
    }

private:
    void LogResult(const QualityGateResult &result)
    {
        if(m_logger == NULL) return;
        if(result.Passed())
            m_logger.Debug("QualityGate", result.detail +
                           " (trades=" + IntegerToString(result.trade_count) + ")");
        else
            m_logger.Warn("QualityGate",
                "REJECTED: " + result.detail +
                " [code=" + IntegerToString(result.verdict) + "]");
    }
};

#endif // ATLAS_QUALITY_GATE_MQH
//+------------------------------------------------------------------+
