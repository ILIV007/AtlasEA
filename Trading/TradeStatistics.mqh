//+------------------------------------------------------------------+
//|                    Trading/TradeStatistics.mqh                   |
//|       AtlasEA v0.2.0 - Trade Statistics Collector                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_STATISTICS_MQH
#define ATLAS_TRADE_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "TradeContext.mqh"

/**
 * @struct TradeStatisticsSnapshot
 * @brief Immutable snapshot of trade statistics at a point in time.
 *
 * Used for reporting and diagnostics. Captured via TradeStatistics.GetSnapshot().
 */
struct TradeStatisticsSnapshot
{
    //--- Counters ---
    int    total_trades;       ///< Total closed trades
    int    winning_trades;     ///< Trades with realized_pnl > 0
    int    losing_trades;      ///< Trades with realized_pnl < 0
    int    breakeven_trades;   ///< Trades with realized_pnl == 0

    //--- Win rate ---
    double win_rate;           ///< winning_trades / total_trades (0..1)

    //--- PnL ---
    double total_pnl;          ///< Sum of all realized PnL
    double gross_profit;       ///< Sum of winning PnL
    double gross_loss;         ///< Sum of losing PnL (negative)
    double average_win;        ///< Gross profit / winning trades
    double average_loss;       ///< Gross loss / losing trades
    double largest_win;        ///< Single largest winning PnL
    double largest_loss;       ///< Single largest losing PnL (negative)

    //--- Ratios ---
    double profit_factor;      ///< gross_profit / abs(gross_loss)
    double expectancy;         ///< Expected PnL per trade
    double payoff_ratio;       ///< average_win / abs(average_loss)

    //--- Time ---
    ulong  total_holding_time; ///< Sum of all holding times (seconds)
    double average_holding_time; ///< Average holding time per trade (seconds)

    //--- Exit reason distribution ---
    int    exits_by_sl;        ///< Stop loss exits
    int    exits_by_tp;        ///< Take profit exits
    int    exits_by_trailing;  ///< Trailing exits
    int    exits_by_be;        ///< Break-even exits
    int    exits_by_time;      ///< Time exits
    int    exits_by_emergency; ///< Emergency exits
    int    exits_by_strategy;  ///< Strategy exits
    int    exits_by_manual;    ///< Manual exits
    int    exits_by_max_hold;  ///< Max holding time exits

    /**
     * @brief Default constructor — zero everything.
     */
    TradeStatisticsSnapshot(void)
    {
        total_trades       = 0;
        winning_trades     = 0;
        losing_trades      = 0;
        breakeven_trades   = 0;
        win_rate           = 0.0;
        total_pnl          = 0.0;
        gross_profit       = 0.0;
        gross_loss         = 0.0;
        average_win        = 0.0;
        average_loss       = 0.0;
        largest_win        = 0.0;
        largest_loss       = 0.0;
        profit_factor      = 0.0;
        expectancy         = 0.0;
        payoff_ratio       = 0.0;
        total_holding_time = 0;
        average_holding_time = 0.0;
        exits_by_sl        = 0;
        exits_by_tp        = 0;
        exits_by_trailing  = 0;
        exits_by_be        = 0;
        exits_by_time      = 0;
        exits_by_emergency = 0;
        exits_by_strategy  = 0;
        exits_by_manual    = 0;
        exits_by_max_hold  = 0;
    }
};

/**
 * @class TradeStatistics
 * @brief Collects and computes trade statistics.
 *
 * SOLE RESPONSIBILITY: accumulate statistics from closed trades and
 * compute aggregate metrics.
 *
 * The statistics collector does NOT:
 *   - Decide entries or exits
 *   - Access the broker
 *   - Modify trade contexts
 *
 * It receives closed TradeContexts via RecordClosedTrade() and
 * maintains running totals. A snapshot can be taken at any time via
 * GetSnapshot().
 *
 * Memory: ~256 bytes (counters + accumulators). No dynamic allocation.
 */
class TradeStatistics
{
private:
    ILogger *m_logger;

    //--- Running counters ---
    int    m_total_trades;
    int    m_winning_trades;
    int    m_losing_trades;
    int    m_breakeven_trades;

    //--- Running PnL accumulators ---
    double m_total_pnl;
    double m_gross_profit;
    double m_gross_loss;
    double m_largest_win;
    double m_largest_loss;

    //--- Running time accumulator ---
    ulong  m_total_holding_time;

    //--- Exit reason counters ---
    int    m_exits[11]; // Indexed by ATLAS_EXIT_* (0..10)

public:
    /**
     * @brief Constructor.
     */
    TradeStatistics(void)
    {
        m_logger = NULL;
        Reset();
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Reset all statistics to zero.
     */
    void Reset(void)
    {
        m_total_trades     = 0;
        m_winning_trades   = 0;
        m_losing_trades    = 0;
        m_breakeven_trades = 0;
        m_total_pnl        = 0.0;
        m_gross_profit     = 0.0;
        m_gross_loss       = 0.0;
        m_largest_win      = 0.0;
        m_largest_loss     = 0.0;
        m_total_holding_time = 0;
        for(int i = 0; i < 11; i++) m_exits[i] = 0;
    }

    /**
     * @brief Record a closed trade.
     *
     * Extracts the PnL, holding time, and exit reason from the context
     * and accumulates them into the running statistics.
     *
     * @param ctx The closed trade context.
     */
    void RecordClosedTrade(const TradeContext &ctx)
    {
        m_total_trades++;

        //--- PnL classification
        double pnl = ctx.realized_pnl;
        m_total_pnl += pnl;

        if(pnl > 0.0)
        {
            m_winning_trades++;
            m_gross_profit += pnl;
            if(pnl > m_largest_win) m_largest_win = pnl;
        }
        else if(pnl < 0.0)
        {
            m_losing_trades++;
            m_gross_loss += pnl;
            if(pnl < m_largest_loss) m_largest_loss = pnl;
        }
        else
        {
            m_breakeven_trades++;
        }

        //--- Holding time
        m_total_holding_time += ctx.holding_time_sec;

        //--- Exit reason
        int reason = ctx.exit_reason;
        if(reason >= 0 && reason <= 10)
            m_exits[reason]++;

        if(m_logger != NULL)
            m_logger.Debug("TradeStatistics",
                "Recorded trade " + ctx.trade_id +
                " pnl=" + DoubleToString(pnl, 2) +
                " hold=" + IntegerToString((long)ctx.holding_time_sec) + "s" +
                " exit=" + IntegerToString(reason));
    }

    /**
     * @brief Get a snapshot of all current statistics.
     * @return TradeStatisticsSnapshot.
     */
    TradeStatisticsSnapshot GetSnapshot(void) const
    {
        TradeStatisticsSnapshot snap;

        snap.total_trades       = m_total_trades;
        snap.winning_trades     = m_winning_trades;
        snap.losing_trades      = m_losing_trades;
        snap.breakeven_trades   = m_breakeven_trades;

        //--- Win rate
        snap.win_rate = (m_total_trades > 0)
                        ? (double)m_winning_trades / (double)m_total_trades
                        : 0.0;

        //--- PnL
        snap.total_pnl    = m_total_pnl;
        snap.gross_profit = m_gross_profit;
        snap.gross_loss   = m_gross_loss;
        snap.largest_win  = m_largest_win;
        snap.largest_loss = m_largest_loss;

        //--- Averages
        snap.average_win  = (m_winning_trades > 0)
                            ? m_gross_profit / (double)m_winning_trades
                            : 0.0;
        snap.average_loss = (m_losing_trades > 0)
                            ? m_gross_loss / (double)m_losing_trades
                            : 0.0;

        //--- Ratios
        snap.profit_factor = (m_gross_loss < 0.0)
                             ? m_gross_profit / MathAbs(m_gross_loss)
                             : (m_gross_profit > 0.0 ? 999.0 : 0.0);
        snap.payoff_ratio  = (snap.average_loss < 0.0)
                             ? snap.average_win / MathAbs(snap.average_loss)
                             : (snap.average_win > 0.0 ? 999.0 : 0.0);

        //--- Expectancy: (win_rate * avg_win) + (loss_rate * avg_loss)
        double loss_rate = (m_total_trades > 0)
                           ? (double)m_losing_trades / (double)m_total_trades
                           : 0.0;
        snap.expectancy = (snap.win_rate * snap.average_win) +
                          (loss_rate * snap.average_loss);

        //--- Time
        snap.total_holding_time = m_total_holding_time;
        snap.average_holding_time = (m_total_trades > 0)
                                    ? (double)m_total_holding_time / (double)m_total_trades
                                    : 0.0;

        //--- Exit reasons
        snap.exits_by_sl        = m_exits[ATLAS_EXIT_STOP_LOSS];
        snap.exits_by_tp        = m_exits[ATLAS_EXIT_TAKE_PROFIT];
        snap.exits_by_trailing  = m_exits[ATLAS_EXIT_TRAILING];
        snap.exits_by_be        = m_exits[ATLAS_EXIT_BREAK_EVEN];
        snap.exits_by_time      = m_exits[ATLAS_EXIT_TIME_EXIT];
        snap.exits_by_emergency = m_exits[ATLAS_EXIT_EMERGENCY];
        snap.exits_by_strategy  = m_exits[ATLAS_EXIT_STRATEGY];
        snap.exits_by_manual    = m_exits[ATLAS_EXIT_MANUAL];
        snap.exits_by_max_hold  = m_exits[ATLAS_EXIT_MAX_HOLDING_TIME];

        return snap;
    }

    /**
     * @brief Log the current statistics summary.
     */
    void LogSummary(void) const
    {
        if(m_logger == NULL) return;

        TradeStatisticsSnapshot s = GetSnapshot();
        m_logger.Info("TradeStatistics",
            "Trades=" + IntegerToString(s.total_trades) +
            " W=" + IntegerToString(s.winning_trades) +
            " L=" + IntegerToString(s.losing_trades) +
            " BE=" + IntegerToString(s.breakeven_trades) +
            " WR=" + DoubleToString(s.win_rate * 100.0, 1) + "%" +
            " PF=" + DoubleToString(s.profit_factor, 2) +
            " Exp=" + DoubleToString(s.expectancy, 2) +
            " TotalPnL=" + DoubleToString(s.total_pnl, 2) +
            " AvgHold=" + DoubleToString(s.average_holding_time, 0) + "s" +
            " Best=" + DoubleToString(s.largest_win, 2) +
            " Worst=" + DoubleToString(s.largest_loss, 2));
    }

    //=== Direct accessors (for diagnostics) ===

    int    TotalTrades(void)     const { return m_total_trades; }
    int    WinningTrades(void)   const { return m_winning_trades; }
    int    LosingTrades(void)    const { return m_losing_trades; }
    double TotalPnl(void)        const { return m_total_pnl; }
    double ProfitFactor(void)    const { return GetSnapshot().profit_factor; }
    double Expectancy(void)      const { return GetSnapshot().expectancy; }
    double WinRate(void)         const { return GetSnapshot().win_rate; }
    double AverageWin(void)      const { return GetSnapshot().average_win; }
    double AverageLoss(void)     const { return GetSnapshot().average_loss; }
    double LargestWin(void)      const { return m_largest_win; }
    double LargestLoss(void)     const { return m_largest_loss; }
    ulong  TotalHoldingTime(void) const { return m_total_holding_time; }
    double AverageHoldingTime(void) const { return GetSnapshot().average_holding_time; }
};

#endif // ATLAS_TRADE_STATISTICS_MQH
//+------------------------------------------------------------------+
