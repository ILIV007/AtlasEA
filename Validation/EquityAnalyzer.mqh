//+------------------------------------------------------------------+
//|                    Validation/EquityAnalyzer.mqh                 |
//|       AtlasEA v1.0 Step 5 - Equity Curve Analyzer                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_EQUITY_ANALYZER_MQH
#define ATLAS_EQUITY_ANALYZER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"

/**
 * @class EquityAnalyzer
 * @brief Analyzes the equity curve, balance curve, drawdown curve,
 *        recovery curve, and returns.
 *
 * SOLE RESPONSIBILITY: compute equity curve analysis from trade records.
 * Does NOT run backtests or access the broker.
 *
 * Outputs:
 *   - Equity curve (timestamp + equity + balance + drawdown)
 *   - Initial / final / peak / trough equity
 *   - Total return %
 *   - Max drawdown, max DD %
 *   - Recovery factor
 *   - Daily returns (last 100)
 *   - Monthly returns (last 36)
 *   - Average / best / worst daily and monthly returns
 *
 * Performance: O(N) where N = number of trades. No heap allocation.
 */
class EquityAnalyzer
{
private:
    ILogger *m_logger;

public:
    EquityAnalyzer(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Analyze trades and build the equity curve.
     * @param trades Array of trade records.
     * @param count Number of trades.
     * @param initial_equity Starting equity.
     * @return EquityAnalysis struct.
     */
    EquityAnalysis Analyze(const TradeRecord &trades[], const int count,
                            const double initial_equity)
    {
        EquityAnalysis ea;
        if(count <= 0 || initial_equity <= 0.0) return ea;

        ea.initial_equity = initial_equity;
        ea.peak_equity    = initial_equity;
        ea.trough_equity  = initial_equity;

        double running_balance = initial_equity;
        double peak = initial_equity;
        double max_dd = 0.0;
        double max_dd_pct = 0.0;

        //--- Build equity curve
        int curve_idx = 0;
        for(int i = 0; i < count && curve_idx < ATLAS_VAL_MAX_CURVE_PTS; i++)
        {
            const TradeRecord &t = trades[i];
            running_balance += t.realized_pnl;

            double equity = running_balance; // Balance = equity (no floating in backtest)
            double dd = (peak > equity) ? (peak - equity) : 0.0;
            double dd_pct = (peak > 0.0) ? (dd / peak) * 100.0 : 0.0;

            ea.curve[curve_idx].timestamp   = t.close_time;
            ea.curve[curve_idx].equity      = equity;
            ea.curve[curve_idx].balance     = running_balance;
            ea.curve[curve_idx].drawdown    = dd;
            ea.curve[curve_idx].drawdown_pct = dd_pct;
            curve_idx++;

            if(equity > ea.peak_equity) ea.peak_equity = equity;
            if(equity < ea.trough_equity) ea.trough_equity = equity;
            if(equity > peak) peak = equity;
            if(dd > max_dd) { max_dd = dd; max_dd_pct = dd_pct; }
        }
        ea.curve_point_count = curve_idx;
        ea.final_equity      = running_balance;
        ea.max_drawdown      = max_dd;
        ea.max_drawdown_pct  = max_dd_pct;
        ea.total_return_pct  = ((running_balance - initial_equity) / initial_equity) * 100.0;
        ea.recovery_factor   = (max_dd > 0.0) ? (running_balance - initial_equity) / max_dd
                                              : (running_balance > initial_equity ? 999.0 : 0.0);

        //--- Compute daily and monthly returns
        ComputeReturns(ea, trades, count, initial_equity);

        return ea;
    }

private:
    /**
     * @brief Compute daily and monthly returns from trades.
     */
    void ComputeReturns(EquityAnalysis &ea, const TradeRecord &trades[],
                        const int count, const double initial_equity)
    {
        if(count <= 0) return;

        //--- Daily returns: group by day, compute PnL per day
        //--- Since trades may span multiple days, we approximate by
        //--- computing the return for each trade relative to initial equity
        //--- and then grouping by day.

        double daily_pnl[100];
        datetime daily_dates[100];
        int daily_count = 0;

        for(int i = 0; i < count && daily_count < 100; i++)
        {
            const TradeRecord &t = trades[i];
            if(t.close_time <= 0) continue;

            //--- Get the day (truncate to day)
            MqlDateTime dt;
            TimeToStruct(t.close_time, dt);
            dt.hour = 0; dt.min = 0; dt.sec = 0;
            datetime day = StructToTime(dt);

            //--- Check if this day already exists
            int found = -1;
            for(int j = 0; j < daily_count; j++)
            {
                MqlDateTime dtj;
                TimeToStruct(daily_dates[j], dtj);
                MqlDateTime dtc;
                TimeToStruct(day, dtc);
                if(dtj.year == dtc.year && dtj.mon == dtc.mon && dtj.day == dtc.day)
                {
                    found = j;
                    break;
                }
            }

            if(found >= 0)
            {
                daily_pnl[found] += t.realized_pnl;
            }
            else
            {
                daily_pnl[daily_count] = t.realized_pnl;
                daily_dates[daily_count] = day;
                daily_count++;
            }
        }

        //--- Convert to returns
        ea.daily_return_count = daily_count;
        ea.avg_daily_return = 0.0;
        ea.best_daily_return = 0.0;
        ea.worst_daily_return = 0.0;

        for(int i = 0; i < daily_count; i++)
        {
            double ret = (initial_equity > 0.0) ? daily_pnl[i] / initial_equity * 100.0 : 0.0;
            ea.daily_returns[i] = ret;
            ea.avg_daily_return += ret;
            if(ret > ea.best_daily_return) ea.best_daily_return = ret;
            if(ret < ea.worst_daily_return) ea.worst_daily_return = ret;
        }
        if(daily_count > 0) ea.avg_daily_return /= (double)daily_count;

        //--- Monthly returns: group by month
        double monthly_pnl[36];
        datetime monthly_dates[36];
        int monthly_count = 0;

        for(int i = 0; i < daily_count && monthly_count < 36; i++)
        {
            MqlDateTime dt;
            TimeToStruct(daily_dates[i], dt);

            //--- Check if this month already exists
            int found = -1;
            for(int j = 0; j < monthly_count; j++)
            {
                MqlDateTime dtj;
                TimeToStruct(monthly_dates[j], dtj);
                if(dtj.year == dt.year && dtj.mon == dt.mon)
                {
                    found = j;
                    break;
                }
            }

            if(found >= 0)
            {
                monthly_pnl[found] += daily_pnl[i];
            }
            else
            {
                monthly_pnl[monthly_count] = daily_pnl[i];
                monthly_dates[monthly_count] = daily_dates[i];
                monthly_count++;
            }
        }

        ea.monthly_return_count = monthly_count;
        ea.avg_monthly_return = 0.0;
        ea.best_monthly_return = 0.0;
        ea.worst_monthly_return = 0.0;

        for(int i = 0; i < monthly_count; i++)
        {
            double ret = (initial_equity > 0.0) ? monthly_pnl[i] / initial_equity * 100.0 : 0.0;
            ea.monthly_returns[i] = ret;
            ea.avg_monthly_return += ret;
            if(ret > ea.best_monthly_return) ea.best_monthly_return = ret;
            if(ret < ea.worst_monthly_return) ea.worst_monthly_return = ret;
        }
        if(monthly_count > 0) ea.avg_monthly_return /= (double)monthly_count;
    }
};

#endif // ATLAS_EQUITY_ANALYZER_MQH
//+------------------------------------------------------------------+
