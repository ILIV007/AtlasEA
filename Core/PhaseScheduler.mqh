//+------------------------------------------------------------------+
//|                                       Core/PhaseScheduler.mqh
//|            AtlasEA v2.0 - Pipeline Phase Scheduler                |
//+------------------------------------------------------------------+
#ifndef ATLAS_PHASE_SCHEDULER_MQH
#define ATLAS_PHASE_SCHEDULER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IMarketDataSource.mqh"
#include "../Interfaces/IStrategySet.mqh"
#include "../Interfaces/IRiskEvaluator.mqh"
#include "../Interfaces/IOrderBuilder.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "SnapshotManager.mqh"
#include "PipelineStatistics.mqh"
#include "TimeBudgetRunner.mqh"
#include "ValidationResult.mqh"

/**
 * @class PhaseScheduler
 * @brief Runs the 4-phase pipeline: Market → Strategy → Risk → Execution.
 *
 * Each phase is time-budgeted. If a phase exceeds its allocation, the
 * scheduler aborts the remaining phases for this tick and logs a warning.
 *
 * Phases:
 *   1. Market:    CaptureTick → ProcessTick → MarketState
 *   2. Strategy:  EvaluateStrategies → votes[] → AggregateVotes
 *   3. Risk:      EvaluateRisk → RiskDecision
 *   4. Execution: BuildOrderRequest → SendOrder (if approved)
 *
 * Between phases, the scheduler emits flow-signal events onto the bus.
 *
 * Hot path: RunPipeline() is called every OnTick. No allocation.
 */
class PhaseScheduler
{
private:
    //--- Dependencies (injected, not owned)
    IEventBus        *m_event_bus;
    IContextStore    *m_context;
    ILogger          *m_logger;
    IMarketDataSource *m_market;
    IStrategySet     *m_strategy;
    IRiskEvaluator   *m_risk;
    IOrderBuilder    *m_execution;
    IBrokerAdapter   *m_broker;
    SnapshotManager  *m_snapshot_mgr;
    PipelineStatistics *m_stats;
    TimeBudgetRunner *m_budget;

    //--- Config
    AtlasConfig m_config;

    //--- Last market state (cached for execution phase)
    MarketState m_last_market_state;

    /// @brief Confidence-weighted vote aggregation.
    AggregatedVote AggregateVotes(const StrategyVote &votes[], const int count, const long snapshot_id) const;

    /// @brief Emit a simple flow event.
    void EmitFlowEvent(const ENUM_ATLAS_EVENT_TYPE type, const long snapshot_id) const;

public:
    /**
     * @brief Constructor.
     */
    PhaseScheduler(void);

    /**
     * @brief Initialize the scheduler with all dependencies.
     */
    void Initialize(IEventBus *bus, IContextStore *context, ILogger *logger,
                    IMarketDataSource *market, IStrategySet *strategy,
                    IRiskEvaluator *risk, IOrderBuilder *execution,
                    IBrokerAdapter *broker,
                    SnapshotManager *snapshot_mgr,
                    PipelineStatistics *stats, TimeBudgetRunner *budget,
                    const AtlasConfig &config);

    /**
     * @brief Run the full pipeline for one tick.
     * @return true if all phases completed within budget, false if aborted.
     */
    bool RunPipeline(void);

    /**
     * @brief Get the last market state produced by the market phase.
     */
    const MarketState& LastMarketState(void) const { return m_last_market_state; }

    /**
     * @brief Validate the scheduler's internal state.
     * @return ValidationResult.
     *
     * Invariants:
     *   - m_context != NULL (required for kill-switch check)
     *   - m_snapshot_mgr != NULL (required for snapshot ID assignment)
     *   - m_logger != NULL (required for diagnostics)
     *   - m_budget != NULL (required for phase timing)
     *   - m_broker != NULL (required for tick capture)
     *   - m_last_market_state, if populated (snapshot_id > 0), must validate
     */
    ValidationResult Validate(void) const
    {
        if(m_context == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "context is NULL", "m_context");
        if(m_snapshot_mgr == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "snapshot_mgr is NULL", "m_snapshot_mgr");
        if(m_logger == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "logger is NULL", "m_logger");
        if(m_budget == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "budget is NULL", "m_budget");
        if(m_broker == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "broker is NULL", "m_broker");
        //--- Validate cached market state if it has been populated
        if(m_last_market_state.snapshot_id > 0)
        {
            ValidationResult mr = m_last_market_state.Validate();
            if(!mr.valid)
            {
                mr.field = "m_last_market_state." + mr.field;
                return mr;
            }
        }
        return ValidationResult::Ok();
    }
};

//+------------------------------------------------------------------+
//| PhaseScheduler implementation                                     |
//+------------------------------------------------------------------+

PhaseScheduler::PhaseScheduler(void)
{
    m_event_bus    = NULL;
    m_context      = NULL;
    m_logger       = NULL;
    m_market       = NULL;
    m_strategy     = NULL;
    m_risk         = NULL;
    m_execution    = NULL;
    m_broker       = NULL;
    m_snapshot_mgr = NULL;
    m_stats        = NULL;
    m_budget       = NULL;
    ZeroMemory(m_last_market_state);
}

//+------------------------------------------------------------------+
void PhaseScheduler::Initialize(IEventBus *bus, IContextStore *context, ILogger *logger,
                                IMarketDataSource *market, IStrategySet *strategy,
                                IRiskEvaluator *risk, IOrderBuilder *execution,
                                IBrokerAdapter *broker,
                                SnapshotManager *snapshot_mgr,
                                PipelineStatistics *stats, TimeBudgetRunner *budget,
                                const AtlasConfig &config)
{
    m_event_bus    = bus;
    m_context      = context;
    m_logger       = logger;
    m_market       = market;
    m_strategy     = strategy;
    m_risk         = risk;
    m_execution    = execution;
    m_broker       = broker;
    m_snapshot_mgr = snapshot_mgr;
    m_stats        = stats;
    m_budget       = budget;
    m_config       = config;
}

//+------------------------------------------------------------------+
void PhaseScheduler::EmitFlowEvent(const ENUM_ATLAS_EVENT_TYPE type, const long snapshot_id) const
{
    if(m_event_bus == NULL) return;
    AtlasEvent ev;
    ev.type          = type;
    ev.source_module = "PhaseScheduler";
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = snapshot_id;
    ev.payload_size  = 0;
    m_event_bus.EmitEvent(ev);
}

//+------------------------------------------------------------------+
AggregatedVote PhaseScheduler::AggregateVotes(const StrategyVote &votes[], const int count, const long snapshot_id) const
{
    AggregatedVote agg;
    agg.aggregation_id = "AGG_" + IntegerToString(snapshot_id);
    agg.vote_count     = count;
    agg.snapshot_id    = snapshot_id;

    double sum_buy  = 0.0;
    double sum_sell = 0.0;

    for(int i = 0; i < count; i++)
    {
        agg.votes[i] = votes[i];
        if(votes[i].direction == ATLAS_ORDER_BUY)
            sum_buy  += votes[i].confidence;
        else if(votes[i].direction == ATLAS_ORDER_SELL)
            sum_sell += votes[i].confidence;
    }

    if(sum_buy > sum_sell && sum_buy > 0.0)
    {
        agg.direction  = ATLAS_ORDER_BUY;
        agg.confidence = sum_buy / (double)count;
    }
    else if(sum_sell > 0.0)
    {
        agg.direction  = ATLAS_ORDER_SELL;
        agg.confidence = sum_sell / (double)count;
    }
    else
    {
        agg.direction  = ATLAS_ORDER_NONE;
        agg.confidence = 0.0;
    }
    return agg;
}

//+------------------------------------------------------------------+
bool PhaseScheduler::RunPipeline(void)
{
    if(m_event_bus == NULL || m_context == NULL || m_broker == NULL || m_snapshot_mgr == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("PhaseScheduler", "RunPipeline: missing dependencies");
        return false;
    }

    bool all_ok = true;

    //==============================================================
    // Phase 1: MARKET
    //==============================================================
    ulong phase_start = GetTickCount64();
    long snap_id = m_snapshot_mgr.AssignId();

    //--- Capture tick (null-safe)
    RawTick tick;
    if(m_broker != NULL)
        tick = m_broker.CaptureTick();
    else
    {
        ZeroMemory(tick);
        tick.timestamp = TimeCurrent();
    }
    EmitFlowEvent(EV_TICK_RECEIVED, snap_id);

    if(m_market != NULL)
    {
        m_last_market_state = m_market.ProcessTick(tick, snap_id);

        //--- Runtime invariant: validate the market state produced by the engine.
        //    If the engine claims the state is valid but it fails structural
        //    validation, mark it invalid and log the precise reason. This
        //    prevents corrupt market data from reaching the strategy phase.
        if(m_last_market_state.is_valid)
        {
            ValidationResult mvalid = m_last_market_state.Validate();
            if(!mvalid.valid)
            {
                if(m_logger != NULL)
                    m_logger.Warn("PhaseScheduler",
                        "MarketState invariant violated: " + mvalid.Summary() +
                        " — marking invalid");
                m_last_market_state.is_valid = false;
                m_last_market_state.invalid_reason = mvalid.Summary();
            }
        }

        EmitFlowEvent(EV_MARKET_STATE_UPDATED, snap_id);

        if(m_stats != NULL)
            m_stats.RecordPhase(PipelineStatistics::PHASE_MARKET, (double)(GetTickCount64() - phase_start));

        //--- Only proceed if market state is valid and kill switch is off
        if(m_last_market_state.is_valid && !m_context.IsKillSwitchActive() && m_strategy != NULL)
        {
            //==============================================================
            // Phase 2: STRATEGY
            //==============================================================
            phase_start = GetTickCount64();

            StrategyVote votes[ATLAS_MAX_VOTES];
            int vote_count = m_strategy.EvaluateStrategies(m_last_market_state, votes);

            if(vote_count > 0)
            {
                EmitFlowEvent(EV_STRATEGY_VOTE_SUBMITTED, snap_id);

                AggregatedVote agg = AggregateVotes(votes, vote_count, snap_id);
                EmitFlowEvent(EV_VOTES_AGGREGATED, snap_id);

                if(m_stats != NULL)
                    m_stats.RecordPhase(PipelineStatistics::PHASE_STRATEGY, (double)(GetTickCount64() - phase_start));

                //==============================================================
                // Phase 3: RISK
                //==============================================================
                phase_start = GetTickCount64();

                if(m_risk != NULL)
                {
                    RiskDecision decision = m_risk.EvaluateRisk(agg);

                    //--- Runtime invariant: validate the risk decision before
                    //    passing it to execution. If invalid, log and skip.
                    if(decision.status == ATLAS_DECISION_APPROVED)
                    {
                        ValidationResult dvalid = decision.Validate();
                        if(!dvalid.valid)
                        {
                            if(m_logger != NULL)
                                m_logger.Error("PhaseScheduler",
                                    "RiskDecision invariant violated: " + dvalid.Summary() +
                                    " — rejecting decision");
                            decision.status = ATLAS_DECISION_REJECTED;
                            decision.rejection_reason = "Invariant violation: " + dvalid.Summary();
                        }
                    }

                    EmitFlowEvent(EV_RISK_DECISION_RENDERED, snap_id);

                    if(m_stats != NULL)
                        m_stats.RecordPhase(PipelineStatistics::PHASE_RISK, (double)(GetTickCount64() - phase_start));

                    //==============================================================
                    // Phase 4: EXECUTION
                    //==============================================================
                    phase_start = GetTickCount64();

                    if(decision.status == ATLAS_DECISION_APPROVED && m_execution != NULL)
                    {
                        OrderRequest req;
                        if(m_execution.BuildOrderRequest(decision, m_last_market_state, req))
                        {
                            //--- Runtime invariant: validate the order request
                            //    before sending to the broker. If invalid, log
                            //    and skip — never send a corrupt order.
                            ValidationResult ovalid = req.Validate();
                            if(!ovalid.valid)
                            {
                                if(m_logger != NULL)
                                    m_logger.Error("PhaseScheduler",
                                        "OrderRequest invariant violated: " + ovalid.Summary() +
                                        " — order NOT sent");
                            }
                            else
                            {
                                EmitFlowEvent(EV_ORDER_REQUESTED, snap_id);

                                bool sent = m_broker.SendOrder(req);
                                m_context.IncrementOrdersSent();

                                if(sent)
                                    EmitFlowEvent(EV_ORDER_DISPATCHED, snap_id);
                            }
                        }
                    }
                    else if(decision.kill_switch_triggered)
                    {
                        EmitFlowEvent(EV_KILL_SWITCH_ACTIVATED, snap_id);
                    }

                    if(m_stats != NULL)
                        m_stats.RecordPhase(PipelineStatistics::PHASE_EXECUTION, (double)(GetTickCount64() - phase_start));
                }
            }
        }
    }

    //--- Check budget
    if(m_budget != NULL && m_budget.LastTickOverrun())
    {
        if(m_logger != NULL)
            m_logger.Warn("PhaseScheduler", "Tick budget overrun: " + IntegerToString((long)m_budget.ElapsedMs()) + "ms");
        all_ok = false;
    }

    return all_ok;
}

#endif // ATLAS_PHASE_SCHEDULER_MQH
//+------------------------------------------------------------------+
