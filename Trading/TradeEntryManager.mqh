//+------------------------------------------------------------------+
//|                  Trading/TradeEntryManager.mqh                   |
//|       AtlasEA v0.2.0 - Trade Entry Manager                       |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_ENTRY_MANAGER_MQH
#define ATLAS_TRADE_ENTRY_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "TradeSignal.mqh"
#include "TradeContext.mqh"

/**
 * @class TradeEntryManager
 * @brief Converts validated trade signals into executable orders.
 *
 * SOLE RESPONSIBILITY: transform a validated TradeSignal + RiskDecision
 * into an OrderRequest, then submit it via the broker.
 *
 * The entry manager is the BRIDGE between the Trading layer and the
 * existing Execution layer:
 *   - It receives a TradeSignal (Trading layer DTO)
 *   - It calls IRiskEvaluator to get a RiskDecision (existing risk pipeline)
 *   - It calls IOrderBuilder to build an OrderRequest (existing execution)
 *   - It calls IBrokerAdapter.SendOrder to submit (existing broker layer)
 *
 * The entry manager does NOT:
 *   - Validate the signal (that's TradeValidator's job)
 *   - Manage the position after entry (that's PositionManager's job)
 *   - Decide exits (that's TradeExitManager's job)
 *
 * Pipeline (BuildAndSubmitEntry):
 *   1. Check that the signal has been validated (phase >= VALIDATED)
 *   2. Call IRiskEvaluator.EvaluateRisk to get a RiskDecision
 *   3. If decision is APPROVED, call IOrderBuilder.BuildOrderRequest
 *   4. If order built, call IBrokerAdapter.SendOrder
 *   5. Update the TradeContext with results
 *
 * Memory: stateless beyond injected pointers. ~128 bytes.
 */
class TradeEntryManager
{
private:
    ILogger        *m_logger;
    IRiskEvaluator *m_risk;
    IOrderBuilder  *m_execution;
    IBrokerAdapter *m_broker;
    IContextStore  *m_context;

    //--- Entry counters (monotonic, for ID generation)
    int m_entry_counter;

    /**
     * @brief Generate a unique trade ID.
     */
    string GenerateTradeId(void)
    {
        m_entry_counter++;
        return "TRD_" + IntegerToString((long)TimeCurrent()) + "_" +
               IntegerToString(m_entry_counter);
    }

public:
    /**
     * @brief Constructor.
     */
    TradeEntryManager(void)
    {
        m_logger   = NULL;
        m_risk     = NULL;
        m_execution = NULL;
        m_broker   = NULL;
        m_context  = NULL;
        m_entry_counter = 0;
    }

    /**
     * @brief Set all dependencies.
     */
    void SetDependencies(ILogger *logger,
                         IRiskEvaluator *risk,
                         IOrderBuilder *execution,
                         IBrokerAdapter *broker,
                         IContextStore *context)
    {
        m_logger    = logger;
        m_risk      = risk;
        m_execution = execution;
        m_broker    = broker;
        m_context   = context;
    }

    /**
     * @brief Build an AggregatedVote from a TradeSignal for risk evaluation.
     *
     * The existing IRiskEvaluator expects an AggregatedVote. This method
     * converts the TradeSignal into the vote format the risk engine
     * already understands.
     *
     * @param signal The validated trade signal.
     * @return AggregatedVote ready for risk evaluation.
     */
    AggregatedVote BuildVoteFromSignal(const TradeSignal &signal)
    {
        AggregatedVote vote;
        vote.aggregation_id = signal.signal_id;
        vote.direction      = signal.direction;
        vote.confidence     = signal.confidence;
        vote.snapshot_id    = signal.snapshot_id;
        vote.vote_count     = 1;

        //--- Fill the single vote
        vote.votes[0].strategy_id      = signal.strategy_id;
        vote.votes[0].strategy_version = signal.strategy_version;
        vote.votes[0].direction        = signal.direction;
        vote.votes[0].confidence       = signal.confidence;
        vote.votes[0].suggested_volume = 0.0;  // Let risk engine decide
        vote.votes[0].suggested_entry  = signal.entry_price;
        vote.votes[0].suggested_sl     = signal.stop_loss;
        vote.votes[0].suggested_tp     = signal.take_profit;
        vote.votes[0].snapshot_id      = signal.snapshot_id;
        vote.votes[0].vote_time        = signal.timestamp;

        return vote;
    }

    /**
     * @brief Evaluate risk for a trade signal.
     *
     * Calls the existing IRiskEvaluator with a vote built from the signal.
     * Does NOT submit any order — just gets the risk decision.
     *
     * @param ctx The trade context (must be in VALIDATED phase).
     * @return true if risk approved, false if rejected.
     */
    bool EvaluateRisk(TradeContext &ctx)
    {
        if(m_risk == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager", "EvaluateRisk: risk evaluator is NULL");
            return false;
        }

        //--- Build vote from signal
        AggregatedVote vote = BuildVoteFromSignal(ctx.signal);

        //--- Evaluate risk (existing pipeline — kill switch, exposure, etc.)
        ctx.decision = m_risk.EvaluateRisk(vote);
        ctx.decision_valid = true;

        //--- Transition phase
        ctx.TransitionTo(ATLAS_TRADE_PHASE_RISK_VALIDATED);

        if(ctx.decision.status != ATLAS_DECISION_APPROVED)
        {
            if(m_logger != NULL)
                m_logger.Info("TradeEntryManager",
                    "Trade " + ctx.trade_id + " REJECTED by risk: " +
                    ctx.decision.rejection_reason);
            return false;
        }

        //--- Validate the decision structurally (Design by Contract)
        ValidationResult dvalid = ctx.decision.Validate();
        if(!dvalid.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "Trade " + ctx.trade_id + " decision invalid: " + dvalid.Summary());
            ctx.decision.status = ATLAS_DECISION_REJECTED;
            ctx.decision.rejection_reason = "Decision invariant: " + dvalid.Summary();
            return false;
        }

        if(m_logger != NULL)
            m_logger.Debug("TradeEntryManager",
                "Trade " + ctx.trade_id + " risk APPROVED vol=" +
                DoubleToString(ctx.decision.approved_volume, 2));

        return true;
    }

    /**
     * @brief Build an order request from the approved risk decision.
     *
     * Calls the existing IOrderBuilder to construct a normalized,
     * broker-ready OrderRequest.
     *
     * @param ctx The trade context (must have an approved decision).
     * @param market Current market state (for bid/ask).
     * @return true if order was built successfully.
     */
    bool BuildOrder(TradeContext &ctx, const MarketState &market)
    {
        if(m_execution == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager", "BuildOrder: execution is NULL");
            return false;
        }

        if(!ctx.decision_valid || ctx.decision.status != ATLAS_DECISION_APPROVED)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "BuildOrder: trade " + ctx.trade_id + " has no approved decision");
            return false;
        }

        //--- Build the order (existing pipeline — normalization, stops level)
        if(!m_execution.BuildOrderRequest(ctx.decision, market, ctx.order))
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "Trade " + ctx.trade_id + " order build FAILED");
            return false;
        }

        //--- Validate the order structurally
        ValidationResult ovalid = ctx.order.Validate();
        if(!ovalid.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "Trade " + ctx.trade_id + " order invalid: " + ovalid.Summary());
            return false;
        }

        ctx.order_built = true;
        ctx.TransitionTo(ATLAS_TRADE_PHASE_ENTRY_DECIDED);

        if(m_logger != NULL)
            m_logger.Debug("TradeEntryManager",
                "Trade " + ctx.trade_id + " order built: " + ctx.order.request_id);

        return true;
    }

    /**
     * @brief Submit the order to the broker.
     *
     * @param ctx The trade context (must have a built order).
     * @return true if the order was sent (fill status determined later).
     */
    bool SubmitOrder(TradeContext &ctx)
    {
        if(m_broker == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager", "SubmitOrder: broker is NULL");
            return false;
        }

        if(!ctx.order_built)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "SubmitOrder: trade " + ctx.trade_id + " has no built order");
            return false;
        }

        //--- Mark idempotency: this decision has been processed
        if(m_context != NULL)
            m_context.MarkDecisionProcessed(ctx.decision.decision_id);

        //--- Submit to broker
        bool sent = m_broker.SendOrder(ctx.order);
        ctx.order_sent = sent;

        if(!sent)
        {
            if(m_logger != NULL)
                m_logger.Error("TradeEntryManager",
                    "Trade " + ctx.trade_id + " order NOT sent by broker");
            return false;
        }

        //--- Increment context telemetry
        if(m_context != NULL)
            m_context.IncrementOrdersSent();

        ctx.TransitionTo(ATLAS_TRADE_PHASE_ORDER_SUBMITTED);

        if(m_logger != NULL)
            m_logger.Info("TradeEntryManager",
                "Trade " + ctx.trade_id + " order submitted: " + ctx.order.request_id);

        return true;
    }

    /**
     * @brief Record a fill event for this trade.
     *
     * Called by the lifecycle when a fill is received (from OnTrade
     * callback or broker reconciliation).
     *
     * @param ctx The trade context.
     * @param fill The execution event from the broker.
     */
    void RecordFill(TradeContext &ctx, const ExecutionEvent &fill)
    {
        ctx.fill          = fill;
        ctx.fill_received = true;

        if(fill.fill_status == ATLAS_FILL_FILLED ||
           fill.fill_status == ATLAS_FILL_PARTIAL)
        {
            ctx.order_filled   = true;
            ctx.filled_volume  = fill.filled_volume;
            ctx.fill_price     = fill.fill_price;
            ctx.current_sl     = ctx.order.stop_loss;
            ctx.current_tp     = ctx.order.take_profit;
            ctx.position_open_time = fill.execution_time;

            //--- Set break-even trigger price (midpoint between entry and TP)
            double tp_dist = MathAbs(ctx.order.take_profit - ctx.fill_price);
            ctx.break_even_price = ctx.fill_price + (tp_dist * 0.5 * ctx.signal.direction);

            ctx.TransitionTo(ATLAS_TRADE_PHASE_FILL_MONITORED);

            if(m_logger != NULL)
                m_logger.Info("TradeEntryManager",
                    "Trade " + ctx.trade_id + " FILLED at " +
                    DoubleToString(ctx.fill_price, 5) +
                    " vol=" + DoubleToString(ctx.filled_volume, 2));
        }
        else
        {
            //--- Rejected or timeout
            ctx.TransitionTo(ATLAS_TRADE_PHASE_POSITION_CLOSED);
            ctx.outcome = ATLAS_TRADE_OUTCOME_CANCELLED;
            ctx.exit_reason = 0; // No exit reason — never entered
            ctx.exit_detail = "Order " + FillStatusName(fill.fill_status);

            if(m_logger != NULL)
                m_logger.Warn("TradeEntryManager",
                    "Trade " + ctx.trade_id + " NOT filled: " +
                    FillStatusName(fill.fill_status));
        }
    }

    /**
     * @brief Initialize a new trade context from a validated signal.
     *
     * @param signal The validated signal.
     * @return A new TradeContext ready for risk evaluation.
     */
    TradeContext CreateContext(const TradeSignal &signal)
    {
        TradeContext ctx;
        ctx.trade_id    = GenerateTradeId();
        ctx.sequence    = m_entry_counter;
        ctx.created_at  = TimeCurrent();
        ctx.updated_at  = TimeCurrent();
        ctx.signal      = signal;
        ctx.current_phase = ATLAS_TRADE_PHASE_SIGNAL_VALIDATED;
        return ctx;
    }

    /**
     * @brief Get the fill status as a string.
     */
    static string FillStatusName(const int status)
    {
        switch(status)
        {
            case ATLAS_FILL_PENDING:  return "PENDING";
            case ATLAS_FILL_FILLED:   return "FILLED";
            case ATLAS_FILL_PARTIAL:  return "PARTIAL";
            case ATLAS_FILL_REJECTED: return "REJECTED";
            case ATLAS_FILL_TIMEOUT:  return "TIMEOUT";
        }
        return "UNKNOWN";
    }
};

#endif // ATLAS_TRADE_ENTRY_MANAGER_MQH
//+------------------------------------------------------------------+
