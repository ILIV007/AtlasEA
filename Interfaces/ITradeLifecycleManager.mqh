//+------------------------------------------------------------------+
//|               Interfaces/ITradeLifecycleManager.mqh              |
//|       AtlasEA v1.0 Step 2 - Trade Lifecycle Manager Interface    |
//+------------------------------------------------------------------+
#ifndef ATLAS_ITRADE_LIFECYCLE_MANAGER_MQH
#define ATLAS_ITRADE_LIFECYCLE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Trailing stop mode codes.
 */
#define ATLAS_TRAIL_OFF          0   ///< Trailing disabled
#define ATLAS_TRAIL_CLASSIC      1   ///< Fixed distance trailing
#define ATLAS_TRAIL_ATR          2   ///< ATR-based trailing distance
#define ATLAS_TRAIL_STEP         3   ///< Step trailing (move in increments)
#define ATLAS_TRAIL_DYNAMIC      4   ///< Dynamic (profit-scaled distance)
#define ATLAS_TRAIL_VOLATILITY   5   ///< Volatility-adjusted trailing

/**
 * @brief Exit reason codes for the Trade Lifecycle Manager.
 * Extends the ATLAS_EXIT_* codes from Trading/TradeExitManager.mqh
 * with additional lifecycle-specific reasons.
 */
#define ATLAS_TLM_EXIT_NONE            0
#define ATLAS_TLM_EXIT_TRAILING        1   ///< Trailing stop hit
#define ATLAS_TLM_EXIT_BREAK_EVEN      2   ///< Break-even stop hit
#define ATLAS_TLM_EXIT_TIME_EXIT       3   ///< Time-based exit (duration/bars)
#define ATLAS_TLM_EXIT_SESSION_CLOSE   4   ///< Session close exit
#define ATLAS_TLM_EXIT_WEEKEND_CLOSE   5   ///< Weekend close
#define ATLAS_TLM_EXIT_HOLIDAY_CLOSE   6   ///< Holiday close
#define ATLAS_TLM_EXIT_PROFIT_LOCK     7   ///< Profit lock triggered close
#define ATLAS_TLM_EXIT_PARTIAL_COMPLETE 8  ///< Position fully closed via partials
#define ATLAS_TLM_EXIT_EMERGENCY       9   ///< Emergency exit (kill switch, DD, etc.)
#define ATLAS_TLM_EXIT_SCALE_OUT      10   ///< Scale-out exit completed
#define ATLAS_TLM_EXIT_MANUAL         11   ///< Manual close

/**
 * @brief Maximum partial close levels per position.
 */
#define ATLAS_TLM_MAX_PARTIAL_LEVELS 4

/**
 * @brief Maximum profit lock levels per position.
 */
#define ATLAS_TLM_MAX_PROFIT_LOCK_LEVELS 4

/**
 * @struct PartialCloseLevel
 * @brief A single partial close level (RR-based or percentage-based).
 */
struct PartialCloseLevel
{
    double trigger_rr;       ///< Trigger at this R:R ratio (0 = use trigger_pct)
    double trigger_pct;      ///< Trigger at this profit % (0 = use trigger_rr)
    double close_fraction;   ///< Fraction of position to close [0.01, 1.0]
    bool   executed;         ///< Has this level been executed?

    PartialCloseLevel(void)
    {
        trigger_rr     = 0.0;
        trigger_pct    = 0.0;
        close_fraction = 0.50;
        executed       = false;
    }
};

/**
 * @struct ProfitLockLevel
 * @brief A profit lock level — move SL to entry when RR reaches this level.
 */
struct ProfitLockLevel
{
    double trigger_rr;   ///< Lock profit at this R:R ratio
    double lock_fraction;///< Fraction of profit to lock (0 = breakeven, 1 = full)
    bool   executed;     ///< Has this lock been applied?

    ProfitLockLevel(void)
    {
        trigger_rr   = 1.0;
        lock_fraction = 0.0;  ///< Breakeven
        executed     = false;
    }
};

/**
 * @struct PositionAction
 * @brief An action to be taken on a position.
 *
 * The EvaluatePosition() method returns this struct. The caller
 * (typically the heartbeat/tick handler) executes the action.
 */
struct PositionAction
{
    int    action_type;     ///< ATLAS_TLM_ACTION_*
    double new_sl;          ///< New SL (for SL modifications)
    double new_tp;          ///< New TP (for TP modifications)
    double close_volume;    ///< Volume to close (for partial/scale-out)
    int    exit_reason;     ///< ATLAS_TLM_EXIT_* (for full closes)
    string detail;          ///< Human-readable detail

    PositionAction(void)
    {
        action_type  = 0;
        new_sl       = 0.0;
        new_tp       = 0.0;
        close_volume = 0.0;
        exit_reason  = ATLAS_TLM_EXIT_NONE;
        detail       = "";
    }
};

/**
 * @brief Action type codes.
 */
#define ATLAS_TLM_ACTION_NONE           0   ///< No action needed
#define ATLAS_TLM_ACTION_MODIFY_SL      1   ///< Modify stop loss only
#define ATLAS_TLM_ACTION_MODIFY_TP      2   ///< Modify take profit only
#define ATLAS_TLM_ACTION_MODIFY_SLTP    3   ///< Modify both SL and TP
#define ATLAS_TLM_ACTION_PARTIAL_CLOSE  4   ///< Partial close
#define ATLAS_TLM_ACTION_FULL_CLOSE     5   ///< Full close (exit)
#define ATLAS_TLM_ACTION_EMERGENCY_CLOSE 6  ///< Emergency close

/**
 * @struct TradeLifecycleStats
 * @brief Statistics for the Trade Lifecycle Manager.
 */
struct TradeLifecycleStats
{
    ulong trailing_updates;         ///< Total trailing stop updates
    ulong breakeven_activations;    ///< Total break-even activations
    ulong partial_closes;           ///< Total partial close executions
    ulong profit_locks;             ///< Total profit lock activations
    ulong full_closes;              ///< Total full position closes
    ulong emergency_closes;         ///< Total emergency closes
    ulong sl_modifications;         ///< Total SL modifications
    ulong tp_modifications;         ///< Total TP modifications

    double sum_holding_time_sec;    ///< Sum of holding times (for average)
    double max_holding_time_sec;    ///< Maximum holding time
    ulong  closed_count;            ///< Number of closed positions (for average)

    double sum_rr;                  ///< Sum of R:R at exit (for average)
    int    exit_counts[12];         ///< Exit reason distribution

    TradeLifecycleStats(void)
    {
        trailing_updates      = 0;
        breakeven_activations = 0;
        partial_closes        = 0;
        profit_locks          = 0;
        full_closes           = 0;
        emergency_closes      = 0;
        sl_modifications      = 0;
        tp_modifications      = 0;
        sum_holding_time_sec  = 0.0;
        max_holding_time_sec  = 0.0;
        closed_count          = 0;
        sum_rr                = 0.0;
        for(int i = 0; i < 12; i++) exit_counts[i] = 0;
    }

    double AverageHoldingTime(void) const
    {
        return (closed_count > 0) ? sum_holding_time_sec / (double)closed_count : 0.0;
    }
    double AverageRR(void) const
    {
        return (closed_count > 0) ? sum_rr / (double)closed_count : 0.0;
    }
};

/**
 * @class ITradeLifecycleManager
 * @brief The ONLY interface through which any module may modify or close
 *        existing open positions.
 *
 * Implemented by TradeLifecycleManager (Infrastructure/). Consumed by
 * CoreEngine (OnTimer/heartbeat) and by the kill switch handler.
 *
 * Contract:
 *   - ExecutionEngine opens trades; TradeLifecycleManager modifies/closes.
 *   - Never opens new positions.
 *   - Only manages already-open trades.
 *   - TradeManager owns the position mirror; TradeLifecycleManager
 *     receives read-only snapshots.
 *
 * Thread safety: MQL5 single-threaded — no synchronization needed.
 */
class ITradeLifecycleManager
{
public:
    /**
     * @brief Evaluate all open positions and return actions for each.
     *
     * Called on each heartbeat (or tick). Iterates all positions from
     * the snapshot, evaluates each against the configured management
     * features (break-even, trailing, partial close, profit lock, time
     * exit, emergency exit), and returns the actions to take.
     *
     * The caller executes the actions via the broker adapter.
     *
     * @param snapshot  Read-only broker position snapshot.
     * @param market    Current market state.
     * @param context   Context store (for kill switch, drawdown).
     * @param broker    Broker adapter (for executing actions).
     * @return Number of actions executed.
     */
    virtual int ManagePositions(const PositionSnapshotEvent &snapshot,
                                 const MarketState &market,
                                 class IContextStore *context,
                                 class IBrokerAdapter *broker) = 0;

    /**
     * @brief Emergency close all positions immediately.
     * @param broker  Broker adapter.
     * @param reason  Emergency reason.
     * @return Number of positions closed.
     */
    virtual int EmergencyCloseAll(class IBrokerAdapter *broker,
                                   const string reason) = 0;

    /**
     * @brief Get the current statistics.
     */
    virtual TradeLifecycleStats GetStats(void) const = 0;

    /**
     * @brief Reset daily statistics.
     */
    virtual void ResetDaily(void) = 0;

    /**
     * @brief Reset all statistics.
     */
    virtual void ResetAll(void) = 0;

    /**
     * @brief Log the current statistics.
     */
    virtual void LogStats(void) const = 0;

    /**
     * @brief Initialize the manager.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the manager.
     */
    virtual void Shutdown(void) = 0;

    virtual ~ITradeLifecycleManager(void) {}
};

/**
 * @brief Get the name of a trailing mode.
 */
string TrailingModeName(const int mode)
{
    switch(mode)
    {
        case ATLAS_TRAIL_OFF:         return "OFF";
        case ATLAS_TRAIL_CLASSIC:     return "CLASSIC";
        case ATLAS_TRAIL_ATR:         return "ATR";
        case ATLAS_TRAIL_STEP:        return "STEP";
        case ATLAS_TRAIL_DYNAMIC:     return "DYNAMIC";
        case ATLAS_TRAIL_VOLATILITY:  return "VOLATILITY";
    }
    return "UNKNOWN";
}

/**
 * @brief Get the name of an exit reason.
 */
string TradeLifecycleExitName(const int reason)
{
    switch(reason)
    {
        case ATLAS_TLM_EXIT_NONE:             return "NONE";
        case ATLAS_TLM_EXIT_TRAILING:         return "TRAILING";
        case ATLAS_TLM_EXIT_BREAK_EVEN:       return "BREAK_EVEN";
        case ATLAS_TLM_EXIT_TIME_EXIT:        return "TIME_EXIT";
        case ATLAS_TLM_EXIT_SESSION_CLOSE:    return "SESSION_CLOSE";
        case ATLAS_TLM_EXIT_WEEKEND_CLOSE:    return "WEEKEND_CLOSE";
        case ATLAS_TLM_EXIT_HOLIDAY_CLOSE:    return "HOLIDAY_CLOSE";
        case ATLAS_TLM_EXIT_PROFIT_LOCK:      return "PROFIT_LOCK";
        case ATLAS_TLM_EXIT_PARTIAL_COMPLETE: return "PARTIAL_COMPLETE";
        case ATLAS_TLM_EXIT_EMERGENCY:        return "EMERGENCY";
        case ATLAS_TLM_EXIT_SCALE_OUT:        return "SCALE_OUT";
        case ATLAS_TLM_EXIT_MANUAL:           return "MANUAL";
    }
    return "UNKNOWN";
}

#endif // ATLAS_ITRADE_LIFECYCLE_MANAGER_MQH
//+------------------------------------------------------------------+
