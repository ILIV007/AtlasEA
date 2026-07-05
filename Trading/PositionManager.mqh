//+------------------------------------------------------------------+
//|                    Trading/PositionManager.mqh                   |
//|       AtlasEA v0.2.0 - Position Management                       |
//+------------------------------------------------------------------+
#ifndef ATLAS_POSITION_MANAGER_MQH
#define ATLAS_POSITION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"
#include "TradeContext.mqh"

/**
 * @brief Position management action codes.
 * Returned by EvaluateManagement to indicate what action (if any)
 * should be taken on a position.
 */
#define ATLAS_POS_ACTION_NONE             0
#define ATLAS_POS_ACTION_MOVE_BREAK_EVEN  1
#define ATLAS_POS_ACTION_TRAIL_STOP       2
#define ATLAS_POS_ACTION_PARTIAL_CLOSE    3
#define ATLAS_POS_ACTION_TIME_EXIT        4
#define ATLAS_POS_ACTION_MAX_HOLD_EXIT    5

/**
 * @struct PositionManagementConfig
 * @brief Configuration for position management features.
 *
 * All features are opt-in. Setting enabled=false for a feature
 * disables it completely.
 */
struct PositionManagementConfig
{
    //--- Break-even ---
    bool   be_enabled;          ///< Enable break-even
    double be_trigger_atr_mult; ///< Move SL to BE when price moves N * ATR in favor
    double be_buffer_points;    ///< Buffer points above entry for BE SL

    //--- Trailing stop ---
    bool   ts_enabled;          ///< Enable trailing stop
    double ts_atr_mult;         ///< Trail at N * ATR distance
    double ts_min_profit_atr;   ///< Don't trail until N * ATR in profit

    //--- Partial close ---
    bool   pc_enabled;          ///< Enable partial close
    double pc_trigger_atr_mult; ///< Close partial at N * ATR in profit
    double pc_close_fraction;   ///< Fraction of position to close (0..1)
    int    pc_max_closes;       ///< Max number of partial closes per trade

    //--- Maximum holding time ---
    bool   mh_enabled;          ///< Enable max holding time
    int    mh_max_hold_sec;     ///< Maximum holding time in seconds

    /**
     * @brief Default constructor with sensible defaults.
     */
    PositionManagementConfig(void)
    {
        be_enabled         = true;
        be_trigger_atr_mult = 1.0;
        be_buffer_points   = 5.0;

        ts_enabled         = true;
        ts_atr_mult        = 2.0;
        ts_min_profit_atr  = 1.0;

        pc_enabled         = false;
        pc_trigger_atr_mult = 2.0;
        pc_close_fraction  = 0.50;
        pc_max_closes      = 1;

        mh_enabled         = false;
        mh_max_hold_sec    = 86400; // 24 hours
    }
};

/**
 * @struct PositionManagementAction
 * @brief The result of evaluating position management for one trade.
 */
struct PositionManagementAction
{
    int    action;           ///< ATLAS_POS_ACTION_*
    double new_sl;           ///< New SL price (for BE/trailing)
    double close_volume;     ///< Volume to close (for partial close)
    string detail;           ///< Human-readable detail

    /**
     * @brief Default constructor — no action.
     */
    PositionManagementAction(void)
    {
        action        = ATLAS_POS_ACTION_NONE;
        new_sl        = 0.0;
        close_volume  = 0.0;
        detail        = "";
    }
};

/**
 * @class PositionManager
 * @brief Manages open positions: break-even, trailing stop, partial close, aging.
 *
 * SOLE RESPONSIBILITY: evaluate each open position against management
 * rules and determine what action (if any) should be taken.
 *
 * The PositionManager does NOT:
 *   - Execute trades (it returns actions; the lifecycle executes them)
 *   - Decide entry or exit reasons
 *   - Call the broker directly (the lifecycle does that based on actions)
 *
 * Management features (all configurable, all opt-in):
 *   1. Break-even: when price moves N*ATR in favor, move SL to entry + buffer
 *   2. Trailing stop: trail SL at N*ATR distance behind current price
 *   3. Partial close: close a fraction of the position at N*ATR profit
 *   4. Position aging: track holding time
 *   5. Maximum holding time: signal exit if held too long
 *
 * Memory: ~200 bytes (config + logger).
 */
class PositionManager
{
private:
    ILogger                    *m_logger;
    PositionManagementConfig    m_config;

public:
    /**
     * @brief Constructor.
     */
    PositionManager(void)
    {
        m_logger = NULL;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the management configuration.
     */
    void SetConfig(const PositionManagementConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const PositionManagementConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Evaluate position management for a trade.
     *
     * Checks all enabled management features and returns the FIRST
     * action that should be taken (priority: max hold > partial close >
     * trailing > break-even).
     *
     * @param ctx The trade context (must have an open position).
     * @param market Current market state.
     * @return PositionManagementAction.
     */
    PositionManagementAction Evaluate(const TradeContext &ctx,
                                       const MarketState &market)
    {
        PositionManagementAction action;

        if(!ctx.HasOpenPosition())
        {
            action.detail = "No open position";
            return action;
        }

        //--- Priority 1: Maximum holding time
        if(m_config.mh_enabled)
        {
            ulong hold_time = ctx.GetHoldingTime();
            if(hold_time >= (ulong)m_config.mh_max_hold_sec)
            {
                action.action = ATLAS_POS_ACTION_MAX_HOLD_EXIT;
                action.detail = "Max holding time reached: " +
                                IntegerToString((long)hold_time) + "s";
                return action;
            }
        }

        //--- Priority 2: Partial close
        if(m_config.pc_enabled && ctx.partial_closes < m_config.pc_max_closes)
        {
            double profit_atr = ComputeProfitInAtr(ctx, market);
            if(profit_atr >= m_config.pc_trigger_atr_mult)
            {
                action.action        = ATLAS_POS_ACTION_PARTIAL_CLOSE;
                action.close_volume  = ctx.filled_volume * m_config.pc_close_fraction;
                action.detail        = "Partial close at " +
                                       DoubleToString(profit_atr, 1) + " ATR profit";
                return action;
            }
        }

        //--- Priority 3: Trailing stop
        if(m_config.ts_enabled && !ctx.trailing_active)
        {
            double profit_atr = ComputeProfitInAtr(ctx, market);
            if(profit_atr >= m_config.ts_min_profit_atr)
            {
                double new_sl = ComputeTrailingStop(ctx, market);
                if(ShouldMoveStop(ctx, new_sl, true))
                {
                    action.action = ATLAS_POS_ACTION_TRAIL_STOP;
                    action.new_sl = new_sl;
                    action.detail = "Trailing stop activated at " +
                                   DoubleToString(profit_atr, 1) + " ATR";
                    return action;
                }
            }
        }
        //--- Continue trailing if already active
        else if(m_config.ts_enabled && ctx.trailing_active)
        {
            double new_sl = ComputeTrailingStop(ctx, market);
            if(ShouldMoveStop(ctx, new_sl, true))
            {
                action.action = ATLAS_POS_ACTION_TRAIL_STOP;
                action.new_sl = new_sl;
                action.detail = "Trailing stop updated";
                return action;
            }
        }

        //--- Priority 4: Break-even
        if(m_config.be_enabled && !ctx.break_even_active)
        {
            double profit_atr = ComputeProfitInAtr(ctx, market);
            if(profit_atr >= m_config.be_trigger_atr_mult)
            {
                double be_sl = ComputeBreakEvenStop(ctx, market);
                if(ShouldMoveStop(ctx, be_sl, false))
                {
                    action.action = ATLAS_POS_ACTION_MOVE_BREAK_EVEN;
                    action.new_sl = be_sl;
                    action.detail = "Break-even at " +
                                   DoubleToString(profit_atr, 1) + " ATR profit";
                    return action;
                }
            }
        }

        return action;
    }

    /**
     * @brief Get the holding time for a trade.
     * @param ctx The trade context.
     * @return Holding time in seconds (0 if not open).
     */
    ulong GetHoldingTime(const TradeContext &ctx) const
    {
        return ctx.GetHoldingTime();
    }

    /**
     * @brief Check if a trade has exceeded its maximum holding time.
     */
    bool IsMaxHoldExceeded(const TradeContext &ctx) const
    {
        if(!m_config.mh_enabled) return false;
        return ctx.GetHoldingTime() >= (ulong)m_config.mh_max_hold_sec;
    }

private:
    /**
     * @brief Compute the current profit in ATR units.
     * @return Profit in ATR multiples (positive = in profit).
     */
    double ComputeProfitInAtr(const TradeContext &ctx,
                               const MarketState &market) const
    {
        if(market.atr_14 <= 0.0) return 0.0;
        double price = (market.bid + market.ask) / 2.0;
        double profit = (price - ctx.fill_price) * ctx.signal.direction;
        return profit / market.atr_14;
    }

    /**
     * @brief Compute the break-even stop loss price.
     */
    double ComputeBreakEvenStop(const TradeContext &ctx,
                                 const MarketState &market) const
    {
        double point = (market.point > 0.0) ? market.point : 0.00001;
        double buffer = m_config.be_buffer_points * point;
        //--- BE SL = entry + buffer (in direction of trade)
        return ctx.fill_price + (buffer * ctx.signal.direction);
    }

    /**
     * @brief Compute the trailing stop loss price.
     */
    double ComputeTrailingStop(const TradeContext &ctx,
                                const MarketState &market) const
    {
        if(market.atr_14 <= 0.0) return ctx.current_sl;
        double trail_dist = m_config.ts_atr_mult * market.atr_14;
        double price = (ctx.signal.direction == ATLAS_ORDER_BUY)
                       ? market.bid : market.ask;
        //--- For BUY: SL = price - trail_dist; for SELL: SL = price + trail_dist
        return price - (trail_dist * ctx.signal.direction);
    }

    /**
     * @brief Check if the stop should be moved to the new value.
     *
     * For trailing (tightening only): the new SL must be BETTER than
     * the current SL (closer to current price, locking in more profit).
     * For break-even: any move is acceptable (first activation).
     *
     * @param ctx The trade context.
     * @param new_sl The proposed new SL.
     * @param is_trailing True if this is a trailing stop update.
     */
    bool ShouldMoveStop(const TradeContext &ctx, double new_sl,
                         bool is_trailing) const
    {
        if(new_sl <= 0.0) return false;
        if(!MathIsValidNumber(new_sl)) return false;

        if(!is_trailing) return true; // BE first activation

        //--- Trailing: only move if it tightens (improves) the stop
        if(ctx.signal.direction == ATLAS_ORDER_BUY)
        {
            //--- BUY: new SL must be higher than current
            return new_sl > ctx.current_sl;
        }
        else
        {
            //--- SELL: new SL must be lower than current
            return new_sl < ctx.current_sl;
        }
    }
};

#endif // ATLAS_POSITION_MANAGER_MQH
//+------------------------------------------------------------------+
