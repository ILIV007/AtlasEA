//+------------------------------------------------------------------+
//|                     Trading/TradeLifecycle.mqh                   |
//|       AtlasEA v0.2.0 - Trade Lifecycle Orchestrator              |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_LIFECYCLE_MQH
#define ATLAS_TRADE_LIFECYCLE_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/IPositionStore.mqh"
#include "TradeSignal.mqh"
#include "TradeContext.mqh"
#include "TradeValidator.mqh"
#include "TradeEntryManager.mqh"
#include "PositionManager.mqh"
#include "TradeExitManager.mqh"
#include "TradeStatistics.mqh"

/**
 * @brief Maximum concurrent trades tracked by the lifecycle.
 * Trades that are closed are kept in the statistics; only active
 * trades occupy slots in the lifecycle's array.
 */
#define ATLAS_MAX_ACTIVE_TRADES 32

/**
 * @class TradeLifecycle
 * @brief Orchestrates the complete trade lifecycle.
 *
 * The lifecycle is the SINGLE ENTRY POINT for all trading activity.
 * Every trade passes through exactly the same deterministic pipeline:
 *
 *   Signal Generated
 *     ↓
 *   Signal Validation          (TradeValidator)
 *     ↓
 *   Risk Validation            (IRiskEvaluator via TradeEntryManager)
 *     ↓
 *   Position Size Calculation  (IRiskEvaluator decides volume)
 *     ↓
 *   Entry Decision              (IOrderBuilder builds the order)
 *     ↓
 *   Order Submission            (IBrokerAdapter sends the order)
 *     ↓
 *   Fill Monitoring             (lifecycle records fills)
 *     ↓
 *   Position Management         (PositionManager: BE, trailing, partial)
 *     ↓
 *   Exit Decision               (TradeExitManager evaluates reasons)
 *     ↓
 *   Position Close              (IBrokerAdapter closes position)
 *     ↓
 *   Statistics Update           (TradeStatistics records outcome)
 *
 * DETERMINISM: the pipeline is strictly ordered. No phase can be
 * skipped. No phase can run out of order. Every trade follows the
 * same path.
 *
 * INTEGRATION: the lifecycle uses ONLY existing interfaces:
 *   - ILogger for logging
 *   - IEventBus for event emission
 *   - IBrokerAdapter for order dispatch and position queries
 *   - IRiskEvaluator for risk decisions (existing RiskEngine — UNCHANGED)
 *   - IOrderBuilder for order construction (existing ExecutionEngine — UNCHANGED)
 *   - IContextStore for shared state
 *   - IPositionStore for position reconciliation
 *
 * NO MT5 API calls. NO strategy logic. NO indicator logic. NO AI.
 *
 * Memory: fixed-size array of ATLAS_MAX_ACTIVE_TRADES TradeContext
 * structs (~64 KB). No dynamic allocation on the hot path.
 */
class TradeLifecycle
{
private:
    //=== Dependencies (injected, NOT owned) ===
    ILogger        *m_logger;
    IEventBus      *m_event_bus;
    IBrokerAdapter *m_broker;
    IRiskEvaluator *m_risk;
    IOrderBuilder  *m_execution;
    IContextStore  *m_context;
    IPositionStore *m_position_store;

    //=== Components (owned, stack-allocated) ===
    TradeValidator    m_validator;
    TradeEntryManager m_entry_manager;
    PositionManager   m_position_manager;
    TradeExitManager  m_exit_manager;
    TradeStatistics   m_statistics;

    //=== Active trades (fixed-size array) ===
    TradeContext m_trades[ATLAS_MAX_ACTIVE_TRADES];
    int          m_trade_count;

    //=== State ===
    bool m_initialized;

    /**
     * @brief Find a free slot in the trades array.
     * @return Index of free slot, or -1 if full.
     */
    int FindFreeSlot(void) const
    {
        for(int i = 0; i < ATLAS_MAX_ACTIVE_TRADES; i++)
        {
            if(m_trades[i].current_phase == ATLAS_TRADE_PHASE_SIGNAL_GENERATED &&
               StringLen(m_trades[i].trade_id) == 0)
                return i;
        }
        return -1;
    }

    /**
     * @brief Find a trade by position ID.
     */
    int FindByPositionId(const string position_id) const
    {
        if(StringLen(position_id) == 0) return -1;
        for(int i = 0; i < m_trade_count; i++)
        {
            if(m_trades[i].position_id == position_id &&
               m_trades[i].HasOpenPosition())
                return i;
        }
        return -1;
    }

    /**
     * @brief Find a trade by request ID (for fill matching).
     */
    int FindByRequestId(const string request_id) const
    {
        if(StringLen(request_id) == 0) return -1;
        for(int i = 0; i < m_trade_count; i++)
        {
            if(m_trades[i].order.request_id == request_id &&
               !m_trades[i].fill_received)
                return i;
        }
        return -1;
    }

    /**
     * @brief Emit a trade-related event.
     */
    void EmitTradeEvent(const ENUM_ATLAS_EVENT_TYPE type, const string source,
                        const long snapshot_id)
    {
        if(m_event_bus == NULL) return;
        AtlasEvent ev;
        ev.type          = type;
        ev.source_module = source;
        ev.timestamp     = TimeCurrent();
        ev.snapshot_id   = snapshot_id;
        ev.payload_size  = 0;
        m_event_bus.EmitEvent(ev);
    }

    /**
     * @brief Close a position via the broker.
     * @return true if close order was sent.
     */
    bool ClosePosition(TradeContext &ctx, const double exit_price)
    {
        if(m_broker == NULL) return false;

        //--- Build a close order: invert the direction
        OrderRequest close_req;
        close_req.request_id  = "CLS_" + ctx.order.request_id;
        close_req.decision_id = ctx.decision.decision_id;
        close_req.symbol      = ctx.order.symbol;
        close_req.order_type  = ctx.order.order_type;
        close_req.direction   = -ctx.signal.direction; // Invert
        close_req.volume      = ctx.filled_volume - ctx.partial_closed_volume;
        close_req.entry_price = exit_price; // 0 = market
        close_req.stop_loss   = 0.0;
        close_req.take_profit = 0.0;
        close_req.magic_number = ctx.order.magic_number;
        close_req.snapshot_id = ctx.signal.snapshot_id;
        close_req.comment     = "Exit: " + TradeExitManager::ExitReasonName(ctx.exit_reason);

        bool sent = m_broker.SendOrder(close_req);
        if(sent && m_context != NULL)
            m_context.IncrementOrdersSent();

        return sent;
    }

    /**
     * @brief Finalize a closed trade: compute outcome and record stats.
     */
    void FinalizeClosedTrade(TradeContext &ctx, const double close_price)
    {
        ctx.exit_price         = close_price;
        ctx.position_close_time = TimeCurrent();
        ctx.holding_time_sec   = ctx.GetHoldingTime();

        //--- Compute realized PnL
        //--- PnL = (close_price - fill_price) * direction * volume * contract_size
        //--- We don't have contract_size here; use raw price difference * volume
        //--- The broker/account level PnL will be reconciled separately.
        double price_diff = (close_price - ctx.fill_price) * ctx.signal.direction;
        ctx.realized_pnl  = price_diff * (ctx.filled_volume - ctx.partial_closed_volume);
        ctx.realized_pips = price_diff;

        //--- Determine outcome
        if(ctx.realized_pnl > 0.0)
            ctx.outcome = ATLAS_TRADE_OUTCOME_WIN;
        else if(ctx.realized_pnl < 0.0)
            ctx.outcome = ATLAS_TRADE_OUTCOME_LOSS;
        else
            ctx.outcome = ATLAS_TRADE_OUTCOME_BREAKEVEN;

        ctx.TransitionTo(ATLAS_TRADE_PHASE_POSITION_CLOSED);

        //--- Record in statistics
        m_statistics.RecordClosedTrade(ctx);

        ctx.TransitionTo(ATLAS_TRADE_PHASE_STATS_UPDATED);

        if(m_logger != NULL)
            m_logger.Info("TradeLifecycle",
                "Trade " + ctx.trade_id + " CLOSED: " +
                TradeExitManager::ExitReasonName(ctx.exit_reason) +
                " pnl=" + DoubleToString(ctx.realized_pnl, 2) +
                " hold=" + IntegerToString((long)ctx.holding_time_sec) + "s");

        EmitTradeEvent(EV_TRADE_EXECUTED, "TradeLifecycle", ctx.signal.snapshot_id);
    }

public:
    /**
     * @brief Constructor.
     */
    TradeLifecycle(void)
    {
        m_logger        = NULL;
        m_event_bus     = NULL;
        m_broker        = NULL;
        m_risk          = NULL;
        m_execution     = NULL;
        m_context       = NULL;
        m_position_store = NULL;
        m_trade_count   = 0;
        m_initialized   = false;
    }

    /**
     * @brief Set all dependencies.
     *
     * Must be called before Initialize().
     */
    void SetDependencies(ILogger *logger,
                         IEventBus *event_bus,
                         IBrokerAdapter *broker,
                         IRiskEvaluator *risk,
                         IOrderBuilder *execution,
                         IContextStore *context,
                         IPositionStore *position_store)
    {
        m_logger         = logger;
        m_event_bus      = event_bus;
        m_broker         = broker;
        m_risk           = risk;
        m_execution      = execution;
        m_context        = context;
        m_position_store = position_store;

        //--- Wire logger to all components
        m_validator.SetLogger(logger);
        m_entry_manager.SetDependencies(logger, risk, execution, broker, context);
        m_position_manager.SetLogger(logger);
        m_exit_manager.SetLogger(logger);
        m_statistics.SetLogger(logger);
    }

    /**
     * @brief Configure position management.
     */
    void SetPositionManagementConfig(const PositionManagementConfig &config)
    {
        m_position_manager.SetConfig(config);
        m_exit_manager.SetMaxHoldSec(config.mh_enabled ? config.mh_max_hold_sec : 0);
    }

    /**
     * @brief Configure exit manager.
     */
    void SetExitConfig(const bool time_exit_enabled, const int time_exit_hour,
                       const bool weekend_close, const int friday_hour)
    {
        m_exit_manager.SetTimeExit(time_exit_enabled, time_exit_hour);
        m_exit_manager.SetWeekendClose(weekend_close, friday_hour);
    }

    /**
     * @brief Initialize the lifecycle.
     */
    bool Initialize(void)
    {
        if(m_logger == NULL)
            return false;
        m_initialized = true;
        m_logger.Info("TradeLifecycle", "Initialized. Max active trades=" +
                      IntegerToString(ATLAS_MAX_ACTIVE_TRADES));
        return true;
    }

    /**
     * @brief Shutdown the lifecycle.
     */
    void Shutdown(void)
    {
        if(!m_initialized) return;
        m_statistics.LogSummary();
        m_trade_count = 0;
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("TradeLifecycle", "Shutdown complete");
    }

    //=== Pipeline entry point ===

    /**
     * @brief Process a trade signal through the lifecycle.
     *
     * This is the MAIN ENTRY POINT. A strategy (or manual operator)
     * calls this with a TradeSignal. The lifecycle runs the signal
     * through validation, risk, entry, and order submission.
     *
     * Fill monitoring, position management, and exit happen in
     * subsequent calls to ProcessFill(), ManagePositions(), and
     * EvaluateExits() (typically called from OnTick/OnTimer/OnTrade).
     *
     * @param signal The trade signal to process.
     * @param market Current market state.
     * @return true if the signal was accepted and an order was submitted.
     */
    bool ProcessSignal(const TradeSignal &signal, const MarketState &market)
    {
        if(!m_initialized) return false;

        //==============================================================
        // PHASE 1: SIGNAL VALIDATION
        //==============================================================
        ValidationResult validation = m_validator.Validate(signal);
        if(!validation.valid)
        {
            if(m_logger != NULL)
                m_logger.Warn("TradeLifecycle",
                    "Signal rejected (validation): " + validation.Summary());
            return false;
        }

        //--- Find a free slot
        int slot = FindFreeSlot();
        if(slot < 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("TradeLifecycle",
                    "No free trade slots (max " +
                    IntegerToString(ATLAS_MAX_ACTIVE_TRADES) + ")");
            return false;
        }

        //--- Create the trade context
        m_trades[slot] = m_entry_manager.CreateContext(signal);
        m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_SIGNAL_VALIDATED);
        m_trade_count++;

        if(m_logger != NULL)
            m_logger.Info("TradeLifecycle",
                "Signal accepted: " + signal.signal_id +
                " → trade " + m_trades[slot].trade_id);

        EmitTradeEvent(EV_ORDER_REQUESTED, "TradeLifecycle", signal.snapshot_id);

        //==============================================================
        // PHASE 2: RISK VALIDATION + PHASE 3: POSITION SIZE CALCULATION
        //==============================================================
        if(!m_entry_manager.EvaluateRisk(m_trades[slot]))
        {
            //--- Risk rejected — close the trade context immediately
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_POSITION_CLOSED);
            m_trades[slot].outcome = ATLAS_TRADE_OUTCOME_CANCELLED;
            m_trades[slot].exit_reason = ATLAS_EXIT_SIGNAL_INVALID;
            m_trades[slot].exit_detail = "Risk rejected: " + m_trades[slot].decision.rejection_reason;
            m_statistics.RecordClosedTrade(m_trades[slot]);
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_STATS_UPDATED);
            m_trade_count--;
            return false;
        }

        //==============================================================
        // PHASE 4: ENTRY DECISION (build the order)
        //==============================================================
        if(!m_entry_manager.BuildOrder(m_trades[slot], market))
        {
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_POSITION_CLOSED);
            m_trades[slot].outcome = ATLAS_TRADE_OUTCOME_CANCELLED;
            m_trades[slot].exit_reason = ATLAS_EXIT_SIGNAL_INVALID;
            m_trades[slot].exit_detail = "Order build failed";
            m_statistics.RecordClosedTrade(m_trades[slot]);
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_STATS_UPDATED);
            m_trade_count--;
            return false;
        }

        //==============================================================
        // PHASE 5: ORDER SUBMISSION
        //==============================================================
        if(!m_entry_manager.SubmitOrder(m_trades[slot]))
        {
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_POSITION_CLOSED);
            m_trades[slot].outcome = ATLAS_TRADE_OUTCOME_CANCELLED;
            m_trades[slot].exit_reason = ATLAS_EXIT_SIGNAL_INVALID;
            m_trades[slot].exit_detail = "Order submission failed";
            m_statistics.RecordClosedTrade(m_trades[slot]);
            m_trades[slot].TransitionTo(ATLAS_TRADE_PHASE_STATS_UPDATED);
            m_trade_count--;
            return false;
        }

        //--- Order submitted — fill monitoring happens via ProcessFill()
        return true;
    }

    //=== Fill monitoring ===

    /**
     * @brief Process a fill event from the broker.
     *
     * Called when a fill is received (from OnTrade callback or broker
     * reconciliation). Matches the fill to an active trade by request_id.
     *
     * @param fill The execution event.
     */
    void ProcessFill(const ExecutionEvent &fill)
    {
        if(!m_initialized) return;

        int idx = FindByRequestId(fill.request_id);
        if(idx < 0)
        {
            if(m_logger != NULL)
                m_logger.Debug("TradeLifecycle",
                    "Fill for unknown request: " + fill.request_id);
            return;
        }

        m_entry_manager.RecordFill(m_trades[idx], fill);

        if(m_trades[idx].order_filled)
        {
            m_trades[idx].TransitionTo(ATLAS_TRADE_PHASE_POSITION_MANAGED);
            EmitTradeEvent(EV_TRADE_EXECUTED, "TradeLifecycle",
                           m_trades[idx].signal.snapshot_id);
        }
        else
        {
            //--- Not filled (rejected/timeout) — finalize as cancelled
            m_statistics.RecordClosedTrade(m_trades[idx]);
            m_trades[idx].TransitionTo(ATLAS_TRADE_PHASE_STATS_UPDATED);
            m_trade_count--;
        }
    }

    //=== Position management ===

    /**
     * @brief Manage all open positions.
     *
     * Called on each tick (or heartbeat). Evaluates break-even, trailing
     * stop, and partial close for every open position. Executes the
     * recommended action if any.
     *
     * @param market Current market state.
     */
    void ManagePositions(const MarketState &market)
    {
        if(!m_initialized) return;

        for(int i = 0; i < ATLAS_MAX_ACTIVE_TRADES; i++)
        {
            if(!m_trades[i].HasOpenPosition()) continue;

            PositionManagementAction action =
                m_position_manager.Evaluate(m_trades[i], market);

            if(action.action == ATLAS_POS_ACTION_NONE) continue;

            //--- Execute the action
            switch(action.action)
            {
                case ATLAS_POS_ACTION_MOVE_BREAK_EVEN:
                    m_trades[i].current_sl       = action.new_sl;
                    m_trades[i].break_even_active = true;
                    if(m_logger != NULL)
                        m_logger.Debug("TradeLifecycle",
                            "Trade " + m_trades[i].trade_id +
                            " BE activated: SL=" + DoubleToString(action.new_sl, 5));
                    break;

                case ATLAS_POS_ACTION_TRAIL_STOP:
                    m_trades[i].current_sl      = action.new_sl;
                    m_trades[i].trailing_active = true;
                    if(m_logger != NULL)
                        m_logger.Debug("TradeLifecycle",
                            "Trade " + m_trades[i].trade_id +
                            " trailing: SL=" + DoubleToString(action.new_sl, 5));
                    break;

                case ATLAS_POS_ACTION_PARTIAL_CLOSE:
                {
                    //--- Execute partial close via broker
                    double close_vol = action.close_volume;
                    if(close_vol > 0.0 && m_broker != NULL)
                    {
                        //--- Build a partial close order
                        OrderRequest pc_req;
                        pc_req.request_id  = "PC_" + m_trades[i].order.request_id +
                                             "_" + IntegerToString(m_trades[i].partial_closes + 1);
                        pc_req.decision_id = m_trades[i].decision.decision_id;
                        pc_req.symbol      = m_trades[i].order.symbol;
                        pc_req.direction   = -m_trades[i].signal.direction;
                        pc_req.volume      = close_vol;
                        pc_req.entry_price = 0.0;
                        pc_req.stop_loss   = 0.0;
                        pc_req.take_profit = 0.0;
                        pc_req.magic_number = m_trades[i].order.magic_number;
                        pc_req.snapshot_id = m_trades[i].signal.snapshot_id;
                        pc_req.comment     = "Partial close";

                        if(m_broker.SendOrder(pc_req))
                        {
                            m_trades[i].partial_closes++;
                            m_trades[i].partial_closed_volume += close_vol;
                            if(m_context != NULL)
                                m_context.IncrementOrdersSent();
                            if(m_logger != NULL)
                                m_logger.Info("TradeLifecycle",
                                    "Trade " + m_trades[i].trade_id +
                                    " partial close #" + IntegerToString(m_trades[i].partial_closes) +
                                    " vol=" + DoubleToString(close_vol, 2));
                        }
                    }
                    break;
                }

                case ATLAS_POS_ACTION_MAX_HOLD_EXIT:
                    //--- Set the exit reason and let EvaluateExits handle the close
                    m_trades[i].exit_reason = ATLAS_EXIT_MAX_HOLDING_TIME;
                    m_trades[i].exit_detail = action.detail;
                    break;
            }
        }
    }

    //=== Exit evaluation ===

    /**
     * @brief Evaluate exits for all open positions.
     *
     * Called on each tick (or heartbeat). Checks all exit conditions
     * for every open position. Closes positions that should exit.
     *
     * @param market Current market state.
     */
    void EvaluateExits(const MarketState &market)
    {
        if(!m_initialized) return;

        bool kill_switch = (m_context != NULL) ? m_context.IsKillSwitchActive() : false;

        for(int i = 0; i < ATLAS_MAX_ACTIVE_TRADES; i++)
        {
            if(!m_trades[i].HasOpenPosition()) continue;

            //--- Evaluate standard exits (SL, TP, trailing, BE, time, emergency)
            ExitEvaluation eval = m_exit_manager.Evaluate(m_trades[i], market, kill_switch);

            //--- If no standard exit, check strategy and manual exits
            if(!eval.should_exit)
                eval = m_exit_manager.EvaluateStrategyExit(m_trades[i]);
            if(!eval.should_exit)
                eval = m_exit_manager.EvaluateManualExit(m_trades[i]);

            if(!eval.should_exit) continue;

            //--- Set exit info and close
            m_trades[i].exit_reason = eval.reason;
            m_trades[i].exit_detail = eval.detail;
            m_trades[i].TransitionTo(ATLAS_TRADE_PHASE_EXIT_DECIDED);

            //--- Determine exit price
            double exit_price = eval.exit_price;
            if(exit_price <= 0.0)
            {
                //--- Market close: use current bid/ask
                exit_price = (m_trades[i].signal.direction == ATLAS_ORDER_BUY)
                             ? market.bid : market.ask;
            }

            //--- Close the position
            if(ClosePosition(m_trades[i], exit_price))
            {
                FinalizeClosedTrade(m_trades[i], exit_price);
                m_trade_count--;
            }
            else
            {
                if(m_logger != NULL)
                    m_logger.Error("TradeLifecycle",
                        "Trade " + m_trades[i].trade_id +
                        " close FAILED — will retry next tick");
            }
        }
    }

    //=== Emergency ===

    /**
     * @brief Emergency close all open positions.
     *
     * Called when the kill switch is triggered. Closes all positions
     * immediately at market.
     *
     * @param reason Emergency reason.
     */
    void EmergencyCloseAll(const string reason)
    {
        if(!m_initialized) return;

        if(m_logger != NULL)
            m_logger.Fatal("TradeLifecycle",
                "EMERGENCY CLOSE ALL: " + reason);

        if(m_broker != NULL)
            m_broker.CloseAllPositionsForMagic("Emergency: " + reason);

        //--- Mark all open trades as emergency-exited
        for(int i = 0; i < ATLAS_MAX_ACTIVE_TRADES; i++)
        {
            if(!m_trades[i].HasOpenPosition()) continue;

            m_trades[i].exit_reason = ATLAS_EXIT_EMERGENCY;
            m_trades[i].exit_detail = "Emergency: " + reason;
            m_trades[i].TransitionTo(ATLAS_TRADE_PHASE_EXIT_DECIDED);

            //--- Use last known fill price as exit (will be reconciled)
            double exit_price = m_trades[i].fill_price; // Placeholder
            FinalizeClosedTrade(m_trades[i], exit_price);
            m_trade_count--;
        }
    }

    //=== Reconciliation ===

    /**
     * @brief Reconcile with broker positions.
     *
     * Called from OnTrade or heartbeat. Updates the lifecycle's view
     * of which positions are still open. Positions that are no longer
     * at the broker are considered closed.
     *
     * @param snap Broker position snapshot.
     */
    void ReconcilePositions(const PositionSnapshotEvent &snap)
    {
        if(!m_initialized) return;

        //--- For each open trade, check if its position still exists at broker
        for(int i = 0; i < ATLAS_MAX_ACTIVE_TRADES; i++)
        {
            if(!m_trades[i].HasOpenPosition()) continue;
            if(StringLen(m_trades[i].position_id) == 0) continue;

            bool found = false;
            for(int j = 0; j < snap.count; j++)
            {
                if(snap.broker_positions[j].position_id == m_trades[i].position_id)
                {
                    found = true;
                    //--- Update PnL from broker
                    m_trades[i].realized_pnl = snap.broker_positions[j].pnl;
                    break;
                }
            }

            if(!found)
            {
                //--- Position is gone — it was closed externally
                //--- Reconcile the close
                double exit_price = m_trades[i].fill_price; // Placeholder
                if(m_trades[i].exit_reason == ATLAS_EXIT_NONE)
                {
                    m_trades[i].exit_reason = ATLAS_EXIT_MANUAL;
                    m_trades[i].exit_detail = "Closed externally (broker reconcile)";
                }
                FinalizeClosedTrade(m_trades[i], exit_price);
                m_trade_count--;
            }
        }
    }

    //=== Diagnostics ===

    /**
     * @brief Get the number of currently active trades.
     */
    int ActiveTradeCount(void) const { return m_trade_count; }

    /**
     * @brief Get the statistics snapshot.
     */
    TradeStatisticsSnapshot GetStatistics(void) const
    {
        return m_statistics.GetSnapshot();
    }

    /**
     * @brief Log the current statistics summary.
     */
    void LogStatistics(void) const
    {
        m_statistics.LogSummary();
    }

    /**
     * @brief Get the trade validator (for configuration).
     */
    TradeValidator& GetValidator(void) { return m_validator; }

    /**
     * @brief Get the position manager (for configuration).
     */
    PositionManager& GetPositionManager(void) { return m_position_manager; }

    /**
     * @brief Get the exit manager (for configuration).
     */
    TradeExitManager& GetExitManager(void) { return m_exit_manager; }

    /**
     * @brief Get the entry manager (for configuration).
     */
    TradeEntryManager& GetEntryManager(void) { return m_entry_manager; }

    /**
     * @brief Get the statistics collector (for direct access).
     */
    TradeStatistics& GetStatisticsCollector(void) { return m_statistics; }
};

#endif // ATLAS_TRADE_LIFECYCLE_MQH
//+------------------------------------------------------------------+
