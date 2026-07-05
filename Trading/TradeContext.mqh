//+------------------------------------------------------------------+
//|                      Trading/TradeContext.mqh                    |
//|       AtlasEA v0.2.0 - Per-Trade State Container                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_CONTEXT_MQH
#define ATLAS_TRADE_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "TradeSignal.mqh"

/**
 * @brief Trade lifecycle phases.
 * Every trade passes through these phases in strict order.
 */
#define ATLAS_TRADE_PHASE_SIGNAL_GENERATED   0
#define ATLAS_TRADE_PHASE_SIGNAL_VALIDATED   1
#define ATLAS_TRADE_PHASE_RISK_VALIDATED     2
#define ATLAS_TRADE_PHASE_SIZE_CALCULATED    3
#define ATLAS_TRADE_PHASE_ENTRY_DECIDED      4
#define ATLAS_TRADE_PHASE_ORDER_SUBMITTED    5
#define ATLAS_TRADE_PHASE_FILL_MONITORED     6
#define ATLAS_TRADE_PHASE_POSITION_MANAGED   7
#define ATLAS_TRADE_PHASE_EXIT_DECIDED       8
#define ATLAS_TRADE_PHASE_POSITION_CLOSED    9
#define ATLAS_TRADE_PHASE_STATS_UPDATED     10

/**
 * @brief Trade outcome codes.
 */
#define ATLAS_TRADE_OUTCOME_NONE      0
#define ATLAS_TRADE_OUTCOME_WIN       1
#define ATLAS_TRADE_OUTCOME_LOSS      2
#define ATLAS_TRADE_OUTCOME_BREAKEVEN 3
#define ATLAS_TRADE_OUTCOME_CANCELLED 4

/**
 * @struct TradeContext
 * @brief Mutable state container tracking one trade through the lifecycle.
 *
 * A TradeContext is created when a signal is accepted into the lifecycle
 * and destroyed when the trade is closed and statistics are updated.
 * It carries the trade's identity, the original signal, the risk decision,
 * the order request, the fill result, the position state, and the exit
 * result — all in one container.
 *
 * The context is NOT thread-safe (MQL5 is single-threaded).
 * The context does NOT own any dynamic memory — all fields are values
 * or fixed-size arrays.
 *
 * Memory: ~2 KB per context (dominated by string fields).
 */
struct TradeContext
{
    //=== Identity ===
    string   trade_id;            ///< Unique trade ID (e.g., "TRD_12345")
    long     sequence;            ///< Monotonic sequence number
    datetime created_at;          ///< When this context was created
    datetime updated_at;          ///< Last modification time
    int      current_phase;       ///< ATLAS_TRADE_PHASE_*

    //=== Original signal (immutable copy) ===
    TradeSignal signal;

    //=== Risk decision ===
    RiskDecision decision;
    bool         decision_valid;

    //=== Order ===
    OrderRequest order;
    bool         order_built;
    bool         order_sent;
    bool         order_filled;

    //=== Fill ===
    ExecutionEvent fill;
    bool           fill_received;

    //=== Position management ===
    string   position_id;         ///< Broker position ticket as string
    double   filled_volume;       ///< Actual filled volume
    double   fill_price;          ///< Actual fill price
    double   current_sl;          ///< Current SL (may move with trailing/BE)
    double   current_tp;          ///< Current TP (rarely changes)
    double   break_even_price;    ///< Price at which BE is activated
    double   trailing_stop;       ///< Current trailing stop level
    bool     break_even_active;   ///< Has BE been applied?
    bool     trailing_active;     ///< Has trailing stop been applied?
    int      partial_closes;      ///< Number of partial closes executed
    double   partial_closed_volume; ///< Total volume closed via partial closes
    datetime position_open_time;  ///< When the position was opened
    datetime position_close_time; ///< When the position was closed

    //=== Exit ===
    int      exit_reason;         ///< ATLAS_EXIT_* (from TradeExitManager)
    string   exit_detail;         ///< Human-readable exit detail
    double   exit_price;          ///< Price at which the position was closed
    double   realized_pnl;        ///< Realized PnL for this trade
    double   realized_pips;       ///< Realized PnL in pips
    int      outcome;             ///< ATLAS_TRADE_OUTCOME_*

    //=== Statistics ===
    ulong    holding_time_sec;    ///< Position holding time in seconds

    /**
     * @brief Default constructor — initializes to empty state.
     */
    TradeContext(void)
    {
        trade_id         = "";
        sequence         = 0;
        created_at       = 0;
        updated_at       = 0;
        current_phase    = ATLAS_TRADE_PHASE_SIGNAL_GENERATED;

        decision_valid   = false;
        order_built      = false;
        order_sent       = false;
        order_filled     = false;

        fill_received    = false;

        position_id      = "";
        filled_volume    = 0.0;
        fill_price       = 0.0;
        current_sl       = 0.0;
        current_tp       = 0.0;
        break_even_price = 0.0;
        trailing_stop    = 0.0;
        break_even_active  = false;
        trailing_active    = false;
        partial_closes     = 0;
        partial_closed_volume = 0.0;
        position_open_time  = 0;
        position_close_time = 0;

        exit_reason      = 0;
        exit_detail      = "";
        exit_price       = 0.0;
        realized_pnl     = 0.0;
        realized_pips    = 0.0;
        outcome          = ATLAS_TRADE_OUTCOME_NONE;

        holding_time_sec = 0;
    }

    /**
     * @brief Transition to a new phase.
     * @param new_phase The phase to transition to.
     * @return true if the transition is valid (forward only).
     */
    bool TransitionTo(const int new_phase)
    {
        //--- Phases must advance forward (no going back)
        if(new_phase < current_phase) return false;
        if(new_phase == current_phase) return true; // idempotent

        current_phase = new_phase;
        updated_at    = TimeCurrent();
        return true;
    }

    /**
     * @brief Check if the trade is in a terminal phase.
     * @return true if the trade is closed (no further processing).
     */
    bool IsTerminal(void) const
    {
        return current_phase == ATLAS_TRADE_PHASE_POSITION_CLOSED ||
               current_phase == ATLAS_TRADE_PHASE_STATS_UPDATED;
    }

    /**
     * @brief Check if the trade has an open position.
     * @return true if the position is currently open.
     */
    bool HasOpenPosition(void) const
    {
        return order_filled && !IsTerminal() &&
               current_phase >= ATLAS_TRADE_PHASE_POSITION_MANAGED &&
               current_phase < ATLAS_TRADE_PHASE_POSITION_CLOSED;
    }

    /**
     * @brief Get the holding time in seconds (if position is open or closed).
     * @return Holding time, or 0 if not yet opened.
     */
    ulong GetHoldingTime(void) const
    {
        if(position_open_time == 0) return 0;
        datetime end = (position_close_time > 0) ? position_close_time : TimeCurrent();
        return (ulong)((long)end - (long)position_open_time);
    }
};

#endif // ATLAS_TRADE_CONTEXT_MQH
//+------------------------------------------------------------------+
