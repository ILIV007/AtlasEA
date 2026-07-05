//+------------------------------------------------------------------+
//|                      Validation/RiskAnalyzer.mqh                 |
//|       AtlasEA v1.0 Step 5 - Risk Analyzer                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_ANALYZER_MQH
#define ATLAS_RISK_ANALYZER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"

/**
 * @class RiskAnalyzer
 * @brief Analyzes risk metrics from trade records.
 *
 * SOLE RESPONSIBILITY: compute risk analysis from trade records.
 *
 * Outputs:
 *   - Max/avg exposure %
 *   - Max/avg margin usage %
 *   - Max daily loss, max weekly loss
 *   - Max/avg position size
 *   - R:R distribution (histogram)
 *   - Max loss streak + total PnL during streak
 *
 * Performance: O(N) where N = number of trades. No heap allocation.
 */
class RiskAnalyzer
{
private:
    ILogger *m_logger;

public:
    RiskAnalyzer(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Analyze trades and compute risk metrics.
     * @param trades Array of trade records.
     * @param count Number of trades.
     * @param initial_equity Starting equity (for exposure calc).
     * @return RiskAnalysis struct.
     */
    RiskAnalysis Analyze(const TradeRecord &trades[], const int count,
                          const double initial_equity)
    {
        RiskAnalysis ra;
        if(count <= 0 || initial_equity <= 0.0) return ra;

        //--- Initialize R:R bucket labels
        ra.rr_bucket_labels[0] = -3.0;
        ra.rr_bucket_labels[1] = -2.0;
        ra.rr_bucket_labels[2] = -1.0;
        ra.rr_bucket_labels[3] = -0.5;
        ra.rr_bucket_labels[4] =  0.0;
        ra.rr_bucket_labels[5] =  0.5;
        ra.rr_bucket_labels[6] =  1.0;
        ra.rr_bucket_labels[7] =  2.0;
        ra.rr_bucket_labels[8] =  3.0;
        ra.rr_bucket_labels[9] =  5.0;

        double sum_exposure = 0.0;
        double sum_margin = 0.0;
        double sum_volume = 0.0;
        double max_volume = 0.0;

        //--- Loss streak tracking
        int current_loss_streak = 0;
        int max_loss_streak = 0;
        double current_streak_pnl = 0.0;
        double max_streak_pnl = 0.0;

        //--- Daily loss tracking
        double daily_pnl[100];
        datetime daily_dates[100];
        int daily_count = 0;

        //--- Weekly loss tracking
        double weekly_pnl[52];
        datetime weekly_dates[52];
        int weekly_count = 0;

        for(int i = 0; i < count; i++)
        {
            const TradeRecord &t = trades[i];

            //--- Position size
            sum_volume += t.volume;
            if(t.volume > max_volume) max_volume = t.volume;

            //--- Exposure (approximate: volume × price / equity)
            double notional = t.volume * t.entry_price * 100000.0; // Assume 100k contract
            double exposure_pct = (notional / initial_equity) * 100.0;
            sum_exposure += exposure_pct;
            if(exposure_pct > ra.max_exposure_pct) ra.max_exposure_pct = exposure_pct;

            //--- Margin usage (approximate: notional / leverage / equity)
            double margin = notional / 100.0; // Assume 1:100 leverage
            double margin_pct = (margin / initial_equity) * 100.0;
            sum_margin += margin_pct;
            if(margin_pct > ra.max_margin_usage_pct) ra.max_margin_usage_pct = margin_pct;

            //--- R:R distribution
            int bucket = GetRRBucket(t.rr_ratio);
            if(bucket >= 0 && bucket < 10) ra.rr_buckets[bucket]++;

            //--- Loss streak
            if(t.realized_pnl < 0.0)
            {
                current_loss_streak++;
                current_streak_pnl += t.realized_pnl;
                if(current_loss_streak > max_loss_streak)
                {
                    max_loss_streak = current_loss_streak;
                    max_streak_pnl = current_streak_pnl;
                }
            }
            else
            {
                current_loss_streak = 0;
                current_streak_pnl = 0.0;
            }

            //--- Daily PnL accumulation
            AccumulatePeriod(daily_pnl, daily_dates, daily_count, 100,
                             t.close_time, t.realized_pnl, true);

            //--- Weekly PnL accumulation
            AccumulatePeriod(weekly_pnl, weekly_dates, weekly_count, 52,
                             t.close_time, t.realized_pnl, false);
        }

        //--- Averages
        ra.avg_exposure_pct     = (count > 0) ? sum_exposure / (double)count : 0.0;
        ra.avg_margin_usage_pct = (count > 0) ? sum_margin / (double)count : 0.0;
        ra.max_position_size    = max_volume;
        ra.avg_position_size    = (count > 0) ? sum_volume / (double)count : 0.0;
        ra.max_loss_streak      = max_loss_streak;
        ra.max_loss_streak_pnl  = max_streak_pnl;

        //--- Max daily loss
        for(int i = 0; i < daily_count; i++)
        {
            if(daily_pnl[i] < ra.max_daily_loss)
                ra.max_daily_loss = daily_pnl[i];
        }

        //--- Max weekly loss
        for(int i = 0; i < weekly_count; i++)
        {
            if(weekly_pnl[i] < ra.max_weekly_loss)
                ra.max_weekly_loss = weekly_pnl[i];
        }

        return ra;
    }

private:
    /**
     * @brief Get the R:R bucket index for a given R:R ratio.
     */
    int GetRRBucket(const double rr) const
    {
        if(rr < -2.0) return 0;
        if(rr < -1.5) return 1;
        if(rr < -0.75) return 2;
        if(rr < -0.25) return 3;
        if(rr < 0.25) return 4;
        if(rr < 0.75) return 5;
        if(rr < 1.5) return 6;
        if(rr < 2.5) return 7;
        if(rr < 4.0) return 8;
        return 9;
    }

    /**
     * @brief Accumulate PnL into daily or weekly buckets.
     */
    void AccumulatePeriod(double &pnl_arr[], datetime &date_arr[],
                           int &count, const int max_count,
                           const datetime timestamp, const double pnl,
                           const bool daily)
    {
        if(timestamp <= 0) return;
        MqlDateTime dt;
        TimeToStruct(timestamp, dt);

        if(daily)
        {
            dt.hour = 0; dt.min = 0; dt.sec = 0;
        }
        else
        {
            //--- Weekly: truncate to start of week (Monday)
            dt.hour = 0; dt.min = 0; dt.sec = 0;
        }
        datetime period = StructToTime(dt);

        //--- Check if this period already exists
        for(int j = 0; j < count; j++)
        {
            if(daily)
            {
                MqlDateTime dtj, dtc;
                TimeToStruct(date_arr[j], dtj);
                TimeToStruct(period, dtc);
                if(dtj.year == dtc.year && dtj.mon == dtc.mon && dtj.day == dtc.day)
                {
                    pnl_arr[j] += pnl;
                    return;
                }
            }
            else
            {
                //--- Weekly: same year + same week number
                MqlDateTime dtj;
                TimeToStruct(date_arr[j], dtj);
                if(dtj.year == dt.year)
                {
                    int week_j = (dtj.day - 1) / 7 + 1;
                    int week_c = (dt.day - 1) / 7 + 1;
                    if(week_j == week_c)
                    {
                        pnl_arr[j] += pnl;
                        return;
                    }
                }
            }
        }

        if(count < max_count)
        {
            pnl_arr[count] = pnl;
            date_arr[count] = period;
            count++;
        }
    }
};

#endif // ATLAS_RISK_ANALYZER_MQH
//+------------------------------------------------------------------+
