//+------------------------------------------------------------------+
//|                    Trading/TradeExitManager.mqh                  |
//|       AtlasEA v0.2.0 - Trade Exit Manager                        |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_EXIT_MANAGER_MQH
#define ATLAS_TRADE_EXIT_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"
#include "TradeContext.mqh"
#include "PositionManager.mqh"

/**
 * @brief Exit reason codes.
 * Every trade that closes gets exactly one exit reason.
 */
#define ATLAS_EXIT_NONE              0
#define ATLAS_EXIT_STOP_LOSS         1   ///< Price hit the stop loss
#define ATLAS_EXIT_TAKE_PROFIT       2   ///< Price hit the take profit
#define ATLAS_EXIT_TRAILING          3   ///< Trailing stop was hit
#define ATLAS_EXIT_BREAK_EVEN        4   ///< Break-even stop was hit
#define ATLAS_EXIT_TIME_EXIT         5   ///< Time-based exit (market close, session end)
#define ATLAS_EXIT_EMERGENCY         6   ///< Emergency exit (kill switch, margin call)
#define ATLAS_EXIT_STRATEGY          7   ///< Strategy signaled exit
#define ATLAS_EXIT_MANUAL            8   ///< Operator manually closed
#define ATLAS_EXIT_MAX_HOLDING_TIME  9   ///< Maximum holding time exceeded
#define ATLAS_EXIT_SIGNAL_INVALID    10  ///< Signal was invalid before entry

/**
 * @struct ExitEvaluation
 * @brief Result of evaluating whether a position should exit.
 */
struct ExitEvaluation
{
    bool   should_exit;      ///< True if the position should be closed
    int    reason;           ///< ATLAS_EXIT_* (if should_exit is true)
    double exit_price;       ///< Suggested exit price (0 = market)
    string detail;           ///< Human-readable detail

    /**
     * @brief Default constructor — no exit.
     */
    ExitEvaluation(void)
    {
        should_exit = false;
        reason      = ATLAS_EXIT_NONE;
        exit_price  = 0.0;
        detail      = "";
    }
};

/**
 * @class TradeExitManager
 * @brief Evaluates whether open positions should be closed.
 *
 * SOLE RESPONSIBILITY: determine IF and WHY a position should exit.
 * It does NOT execute the close — the lifecycle does that.
 *
 * Exit reasons (checked in priority order):
 *   1. EMERGENCY: kill switch is active → close immediately
 *   2. STOP_LOSS: current price has hit the stop loss
 *   3. TAKE_PROFIT: current price has hit the take profit
 *   4. TRAILING: trailing stop was hit (after PositionManager moved SL)
 *   5. BREAK_EVEN: break-even stop was hit
 *   6. MAX_HOLDING_TIME: position held longer than maximum
 *   7. TIME_EXIT: time-based exit (e.g., session end, configurable)
 *   8. STRATEGY: strategy signaled an exit (via flag on context)
 *   9. MANUAL: operator requested manual close (via flag on context)
 *
 * The ExitManager checks market conditions and context flags to
 * determine the exit reason. It returns an ExitEvaluation that the
 * lifecycle uses to execute the close.
 *
 * Memory: ~128 bytes (logger + config).
 */
class TradeExitManager
{
private:
    ILogger *m_logger;

    //--- Config ---
    bool   m_time_exit_enabled;
    int    m_time_exit_hour;        ///< Hour of day to close (server time, 0-23)
    bool   m_close_before_weekend;  ///< Close all positions before weekend
    int    m_weekend_close_hour;   ///< Friday close hour

public:
    /**
     * @brief Constructor with defaults.
     */
    TradeExitManager(void)
    {
        m_logger              = NULL;
        m_time_exit_enabled   = false;
        m_time_exit_hour      = 22;  // 22:00 server time
        m_close_before_weekend = true;
        m_weekend_close_hour  = 20;  // Friday 20:00
        m_max_hold_sec        = 0;   // Disabled by default
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Configure time-based exit.
     */
    void SetTimeExit(const bool enabled, const int hour)
    {
        m_time_exit_enabled = enabled;
        m_time_exit_hour    = hour;
    }

    /**
     * @brief Configure weekend close.
     */
    void SetWeekendClose(const bool enabled, const int friday_hour)
    {
        m_close_before_weekend = enabled;
        m_weekend_close_hour   = friday_hour;
    }

    /**
     * @brief Evaluate whether a position should exit.
     *
     * Checks all exit conditions in priority order. Returns on the
     * FIRST matching condition.
     *
     * @param ctx The trade context (must have an open position).
     * @param market Current market state.
     * @param kill_switch_active Whether the kill switch is active.
     * @return ExitEvaluation.
     */
    ExitEvaluation Evaluate(const TradeContext &ctx,
                             const MarketState &market,
                             const bool kill_switch_active)
    {
        ExitEvaluation result;

        if(!ctx.HasOpenPosition())
            return result;

        //=== Priority 1: EMERGENCY (kill switch) ===
        if(kill_switch_active)
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_EMERGENCY;
            result.exit_price  = 0.0; // market
            result.detail      = "Kill switch active — emergency exit";
            return result;
        }

        //=== Priority 2: STOP_LOSS ===
        if(IsStopLossHit(ctx, market))
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_STOP_LOSS;
            result.exit_price  = ctx.current_sl;
            result.detail      = "Stop loss hit at " +
                                 DoubleToString(ctx.current_sl, 5);
            return result;
        }

        //=== Priority 3: TAKE_PROFIT ===
        if(IsTakeProfitHit(ctx, market))
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_TAKE_PROFIT;
            result.exit_price  = ctx.current_tp;
            result.detail      = "Take profit hit at " +
                                 DoubleToString(ctx.current_tp, 5);
            return result;
        }

        //=== Priority 4: TRAILING / BREAK_EVEN stop hit ===
        //--- If the current SL was moved by trailing or BE, and price
        //--- hits it, classify accordingly.
        if(ctx.trailing_active && IsStopLossHit(ctx, market))
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_TRAILING;
            result.exit_price  = ctx.current_sl;
            result.detail      = "Trailing stop hit at " +
                                 DoubleToString(ctx.current_sl, 5);
            return result;
        }
        if(ctx.break_even_active && !ctx.trailing_active && IsStopLossHit(ctx, market))
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_BREAK_EVEN;
            result.exit_price  = ctx.current_sl;
            result.detail      = "Break-even stop hit at " +
                                 DoubleToString(ctx.current_sl, 5);
            return result;
        }

        //=== Priority 5: MAX_HOLDING_TIME ===
        //--- Checked by PositionManager; if it returned MAX_HOLD_EXIT,
        //--- the lifecycle sets this. Also check here directly.
        ulong hold_time = ctx.GetHoldingTime();
        if(m_max_hold_sec > 0 && hold_time >= (ulong)m_max_hold_sec)
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_MAX_HOLDING_TIME;
            result.exit_price  = 0.0; // market
            result.detail      = "Max holding time: " +
                                 IntegerToString((long)hold_time) + "s";
            return result;
        }

        //=== Priority 6: TIME_EXIT (session end) ===
        if(m_time_exit_enabled && IsTimeExit())
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_TIME_EXIT;
            result.exit_price  = 0.0; // market
            result.detail      = "Time exit at hour " +
                                 IntegerToString(m_time_exit_hour);
            return result;
        }

        //=== Priority 7: WEEKEND close ===
        if(m_close_before_weekend && IsWeekendCloseTime())
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_TIME_EXIT;
            result.exit_price  = 0.0; // market
            result.detail      = "Weekend close (Friday " +
                                 IntegerToString(m_weekend_close_hour) + ":00)";
            return result;
        }

        //=== Priority 8: STRATEGY exit ===
        //--- The lifecycle can set a flag on the context to signal
        //--- a strategy-driven exit. This is checked via a method
        //--- the lifecycle calls before Evaluate.
        //--- (Handled by the lifecycle calling EvaluateStrategyExit)

        //=== Priority 9: MANUAL close ===
        //--- (Handled by the lifecycle calling EvaluateManualExit)

        return result; // No exit
    }

    /**
     * @brief Check if the strategy has requested an exit.
     *
     * The lifecycle can call this to check for a strategy-driven exit.
     * A strategy signals exit by setting the context's exit_detail
     * field to a non-empty string before calling this method.
     *
     * @param ctx The trade context.
     * @return ExitEvaluation with STRATEGY reason if requested.
     */
    ExitEvaluation EvaluateStrategyExit(const TradeContext &ctx) const
    {
        ExitEvaluation result;
        //--- The lifecycle sets a flag; here we check the comment field
        //--- for a "STRATEGY_EXIT:" prefix.
        if(StringLen(ctx.exit_detail) > 0 &&
           StringFind(ctx.exit_detail, "STRATEGY_EXIT:") == 0)
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_STRATEGY;
            result.exit_price  = 0.0; // market
            result.detail      = StringSubstr(ctx.exit_detail, 14);
        }
        return result;
    }

    /**
     * @brief Check if a manual close has been requested.
     *
     * @param ctx The trade context.
     * @return ExitEvaluation with MANUAL reason if requested.
     */
    ExitEvaluation EvaluateManualExit(const TradeContext &ctx) const
    {
        ExitEvaluation result;
        if(StringLen(ctx.exit_detail) > 0 &&
           StringFind(ctx.exit_detail, "MANUAL_CLOSE:") == 0)
        {
            result.should_exit = true;
            result.reason      = ATLAS_EXIT_MANUAL;
            result.exit_price  = 0.0; // market
            result.detail      = StringSubstr(ctx.exit_detail, 13);
        }
        return result;
    }

    /**
     * @brief Create an emergency exit evaluation.
     * Used when the kill switch is triggered externally.
     */
    static ExitEvaluation CreateEmergencyExit(const string reason)
    {
        ExitEvaluation result;
        result.should_exit = true;
        result.reason      = ATLAS_EXIT_EMERGENCY;
        result.exit_price  = 0.0;
        result.detail      = "Emergency: " + reason;
        return result;
    }

    /**
     * @brief Get the name of an exit reason.
     */
    static string ExitReasonName(const int reason)
    {
        switch(reason)
        {
            case ATLAS_EXIT_NONE:             return "NONE";
            case ATLAS_EXIT_STOP_LOSS:        return "STOP_LOSS";
            case ATLAS_EXIT_TAKE_PROFIT:      return "TAKE_PROFIT";
            case ATLAS_EXIT_TRAILING:         return "TRAILING";
            case ATLAS_EXIT_BREAK_EVEN:       return "BREAK_EVEN";
            case ATLAS_EXIT_TIME_EXIT:        return "TIME_EXIT";
            case ATLAS_EXIT_EMERGENCY:        return "EMERGENCY";
            case ATLAS_EXIT_STRATEGY:         return "STRATEGY";
            case ATLAS_EXIT_MANUAL:           return "MANUAL";
            case ATLAS_EXIT_MAX_HOLDING_TIME: return "MAX_HOLDING_TIME";
            case ATLAS_EXIT_SIGNAL_INVALID:   return "SIGNAL_INVALID";
        }
        return "UNKNOWN";
    }

private:
    int m_max_hold_sec;  ///< Mirror of PositionManager's max hold (set by lifecycle)

public:
    /**
     * @brief Set the maximum holding time (called by lifecycle from config).
     */
    void SetMaxHoldSec(const int sec) { m_max_hold_sec = sec; }

private:
    /**
     * @brief Check if the stop loss has been hit.
     */
    bool IsStopLossHit(const TradeContext &ctx, const MarketState &market) const
    {
        if(ctx.current_sl <= 0.0) return false;
        if(ctx.signal.direction == ATLAS_ORDER_BUY)
            return market.bid <= ctx.current_sl;
        else
            return market.ask >= ctx.current_sl;
    }

    /**
     * @brief Check if the take profit has been hit.
     */
    bool IsTakeProfitHit(const TradeContext &ctx, const MarketState &market) const
    {
        if(ctx.current_tp <= 0.0) return false;
        if(ctx.signal.direction == ATLAS_ORDER_BUY)
            return market.bid >= ctx.current_tp;
        else
            return market.ask <= ctx.current_tp;
    }

    /**
     * @brief Check if the current time is the time-exit hour.
     */
    bool IsTimeExit(void) const
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        return dt.hour == m_time_exit_hour;
    }

    /**
     * @brief Check if it's Friday at or after the weekend close hour.
     */
    bool IsWeekendCloseTime(void) const
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        //--- Friday = 5
        return dt.day_of_week == 5 && dt.hour >= m_weekend_close_hour;
    }
};

#endif // ATLAS_TRADE_EXIT_MANAGER_MQH
//+------------------------------------------------------------------+
