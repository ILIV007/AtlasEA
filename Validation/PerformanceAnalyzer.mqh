//+------------------------------------------------------------------+
//|                  Validation/PerformanceAnalyzer.mqh              |
//|       AtlasEA v1.0 Step 5 - Performance Metrics Analyzer          |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERFORMANCE_ANALYZER_MQH
#define ATLAS_PERFORMANCE_ANALYZER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"

/**
 * @class PerformanceAnalyzer
 * @brief Computes all 19 backtest performance metrics from trade records.
 *
 * SOLE RESPONSIBILITY: compute performance metrics from a list of
 * closed trades. Does NOT run backtests or access the broker.
 *
 * Metrics computed:
 *   1. Total trades, winning, losing, breakeven
 *   2. Win rate, loss rate
 *   3. Net profit, gross profit, gross loss
 *   4. Largest win, largest loss
 *   5. Average win, average loss
 *   6. Profit factor, recovery factor
 *   7. Expected payoff, payoff ratio
 *   8. Sharpe ratio, Sortino ratio (annualized)
 *   9. Max drawdown, max DD %, average DD, max DD duration
 *  10. Max consecutive losses, max consecutive wins
 *  11. Average holding time, average R:R
 *
 * Performance: O(N) where N = number of trades. No heap allocation.
 */
class PerformanceAnalyzer
{
private:
    ILogger *m_logger;

public:
    PerformanceAnalyzer(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Analyze a list of trades and compute all metrics.
     * @param trades Array of trade records.
     * @param count Number of trades.
     * @param initial_equity Starting equity (for drawdown calc).
     * @return PerformanceMetrics struct.
     */
    PerformanceMetrics Analyze(const TradeRecord &trades[], const int count,
                                const double initial_equity)
    {
        PerformanceMetrics m;
        if(count <= 0) return m;

        //=== Trade counts ===
        m.total_trades = count;
        double sum_pnl = 0.0;
        double sum_win_pnl = 0.0;
        double sum_loss_pnl = 0.0;
        double sum_rr = 0.0;
        double sum_holding = 0.0;
        double max_win = 0.0;
        double max_loss = 0.0;

        //--- Drawdown tracking
        double peak = initial_equity;
        double max_dd = 0.0;
        double max_dd_pct = 0.0;
        double sum_dd = 0.0;
        int dd_count = 0;
        datetime dd_start = 0;
        double max_dd_duration = 0.0;

        //--- Streak tracking
        int current_win_streak = 0;
        int current_loss_streak = 0;
        int max_win_streak = 0;
        int max_loss_streak = 0;

        //--- For Sharpe/Sortino: collect per-trade returns
        double returns[ATLAS_VAL_MAX_TRADES];
        int return_count = 0;

        for(int i = 0; i < count && i < ATLAS_VAL_MAX_TRADES; i++)
        {
            const TradeRecord &t = trades[i];
            sum_pnl += t.realized_pnl;
            sum_rr  += t.rr_ratio;
            sum_holding += (double)t.holding_time_sec;

            if(t.realized_pnl > 0.0)
            {
                m.winning_trades++;
                sum_win_pnl += t.realized_pnl;
                if(t.realized_pnl > max_win) max_win = t.realized_pnl;

                current_win_streak++;
                current_loss_streak = 0;
                if(current_win_streak > max_win_streak)
                    max_win_streak = current_win_streak;
            }
            else if(t.realized_pnl < 0.0)
            {
                m.losing_trades++;
                sum_loss_pnl += t.realized_pnl;
                if(t.realized_pnl < max_loss) max_loss = t.realized_pnl;

                current_loss_streak++;
                current_win_streak = 0;
                if(current_loss_streak > max_loss_streak)
                    max_loss_streak = current_loss_streak;
            }
            else
            {
                m.breakeven_trades++;
                current_win_streak = 0;
                current_loss_streak = 0;
            }

            //--- Drawdown calculation (equity curve)
            double current_equity = initial_equity + sum_pnl;
            if(current_equity > peak)
            {
                peak = current_equity;
                dd_start = t.close_time;
            }
            else
            {
                double dd = peak - current_equity;
                double dd_pct = (peak > 0.0) ? (dd / peak) * 100.0 : 0.0;
                if(dd > max_dd) { max_dd = dd; max_dd_pct = dd_pct; }
                if(dd > 0.0)
                {
                    sum_dd += dd;
                    dd_count++;
                    double duration = (double)((long)t.close_time - (long)dd_start);
                    if(duration > max_dd_duration) max_dd_duration = duration;
                }
            }

            //--- Per-trade return for Sharpe/Sortino
            if(initial_equity > 0.0)
            {
                returns[return_count] = t.realized_pnl / initial_equity;
                return_count++;
            }
        }

        //=== Rates ===
        m.win_rate  = (m.total_trades > 0) ? (double)m.winning_trades / (double)m.total_trades : 0.0;
        m.loss_rate = (m.total_trades > 0) ? (double)m.losing_trades / (double)m.total_trades : 0.0;

        //=== PnL ===
        m.net_profit   = sum_pnl;
        m.gross_profit = sum_win_pnl;
        m.gross_loss   = sum_loss_pnl;
        m.largest_win  = max_win;
        m.largest_loss = max_loss;
        m.average_win  = (m.winning_trades > 0) ? sum_win_pnl / (double)m.winning_trades : 0.0;
        m.average_loss = (m.losing_trades > 0) ? sum_loss_pnl / (double)m.losing_trades : 0.0;

        //=== Ratios ===
        m.profit_factor   = (sum_loss_pnl < 0.0) ? sum_win_pnl / MathAbs(sum_loss_pnl)
                                                  : (sum_win_pnl > 0.0 ? 999.0 : 0.0);
        m.recovery_factor = (max_dd > 0.0) ? sum_pnl / max_dd : (sum_pnl > 0.0 ? 999.0 : 0.0);
        m.expected_payoff = sum_pnl / (double)m.total_trades;
        m.payoff_ratio    = (m.average_loss < 0.0) ? m.average_win / MathAbs(m.average_loss)
                                                    : (m.average_win > 0.0 ? 999.0 : 0.0);

        //=== Drawdown ===
        m.max_drawdown          = max_dd;
        m.max_drawdown_pct      = max_dd_pct;
        m.average_drawdown      = (dd_count > 0) ? sum_dd / (double)dd_count : 0.0;
        m.max_drawdown_duration = max_dd_duration;

        //=== Streaks ===
        m.max_consecutive_losses = max_loss_streak;
        m.max_consecutive_wins   = max_win_streak;

        //=== Time ===
        m.average_holding_time = sum_holding / (double)m.total_trades;
        m.average_rr           = sum_rr / (double)m.total_trades;

        //=== Sharpe & Sortino (annualized) ===
        ComputeSharpeSortino(m, returns, return_count);

        return m;
    }

private:
    /**
     * @brief Compute Sharpe and Sortino ratios from per-trade returns.
     *
     * Sharpe = (mean_return / std_dev) × sqrt(trades_per_year)
     * Sortino = (mean_return / downside_std_dev) × sqrt(trades_per_year)
     *
     * Assumptions:
     *   - trades_per_year = 252 (daily trading assumption)
     *   - risk_free_rate = 0
     */
    void ComputeSharpeSortino(PerformanceMetrics &m, const double &returns[],
                               const int count)
    {
        if(count < 2)
        {
            m.sharpe_ratio  = 0.0;
            m.sortino_ratio = 0.0;
            return;
        }

        //--- Mean return
        double sum = 0.0;
        for(int i = 0; i < count; i++) sum += returns[i];
        double mean = sum / (double)count;

        //--- Standard deviation
        double sq_sum = 0.0;
        for(int i = 0; i < count; i++)
        {
            double diff = returns[i] - mean;
            sq_sum += diff * diff;
        }
        double std_dev = MathSqrt(sq_sum / (double)(count - 1));

        //--- Downside deviation (Sortino)
        double downside_sq = 0.0;
        int downside_count = 0;
        for(int i = 0; i < count; i++)
        {
            if(returns[i] < 0.0)
            {
                downside_sq += returns[i] * returns[i];
                downside_count++;
            }
        }
        double downside_std = (downside_count > 0)
            ? MathSqrt(downside_sq / (double)downside_count) : 0.0;

        //--- Annualize (assume 252 trading days, ~1 trade per day)
        double annualization = MathSqrt(252.0);

        m.sharpe_ratio  = (std_dev > 0.0) ? (mean / std_dev) * annualization : 0.0;
        m.sortino_ratio = (downside_std > 0.0) ? (mean / downside_std) * annualization : 0.0;
    }
};

#endif // ATLAS_PERFORMANCE_ANALYZER_MQH
//+------------------------------------------------------------------+
