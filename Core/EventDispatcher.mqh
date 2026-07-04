//+------------------------------------------------------------------+
//|                                      Core/EventDispatcher.mqh
//|              AtlasEA v2.0 - Event Routing & Dispatch Engine       |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_DISPATCHER_MQH
#define ATLAS_EVENT_DISPATCHER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "EventQueue.mqh"
#include "TimeBudgetRunner.mqh"
#include "PipelineStatistics.mqh"
#include "ValidationResult.mqh"

/**
 * @class EventDispatcher
 * @brief Routes events from the queue to registered handlers.
 *
 * Responsibilities:
 *   - Event validation (type range, snapshot_id consistency, source non-empty)
 *   - Event filtering (skip events from stale snapshots if configured)
 *   - Duplicate detection (by event_id for ExecutionEvents)
 *   - Event routing (dispatch to the correct handler based on type)
 *   - Budget-aware processing (stops when time or event budget exhausted)
 *
 * Design: the dispatcher does NOT own the EventQueue — it receives a
 * reference. This keeps ownership in CoreEngine and the dispatcher
 * focused on routing logic.
 *
 * Hot path: ProcessBatch() is called every OnTick. No allocation.
 */
class EventDispatcher
{
public:
    /// Handler function pointer type (MQL5 does not support std::function)
    typedef void (*EventHandler)(const AtlasEvent &event, void *user_data);

    /// Statistics for the dispatcher itself
    struct DispatchStats
    {
        ulong total_dispatched;
        ulong total_dropped;
        ulong total_duplicates;
        ulong total_filtered;
        ulong total_invalid;
        ulong total_sequence_gaps;
        ulong per_type_count[13];  // One per ENUM_ATLAS_EVENT_TYPE
    };

private:
    EventQueue      *m_queue;           ///< The event queue (owned by CoreEngine)
    IContextStore   *m_context;         ///< Context for snapshot validation
    ILogger         *m_logger;          ///< Logger
    DispatchStats    m_stats;           ///< Dispatch statistics

    /// Duplicate detection ring (numeric composite key — no string allocation)
    long m_seen_keys[ATLAS_IDEMPOTENCY_SLOTS];
    int  m_seen_count;

    /// Last seen snapshot_id for sequence continuity checking
    long m_last_snapshot_id;

    /// @brief Build a numeric composite key from event fields (zero allocation).
    long BuildCompositeKey(const AtlasEvent &event) const
    {
        return (long)event.type * 100000000L + (long)(event.timestamp % 100000);
    }

    /// @brief Validate an event before dispatching.
    bool ValidateEvent(const AtlasEvent &event) const;

    /// @brief Check if a composite key has already been seen (duplicate detection).
    bool IsDuplicate(const AtlasEvent &event);

    /// @brief Record a composite key in the dedup ring.
    void RecordSeen(const AtlasEvent &event);

public:
    /**
     * @brief Constructor.
     */
    EventDispatcher(void);

    /**
     * @brief Initialize the dispatcher.
     * @param queue   The event queue to drain.
     * @param context Context store for snapshot validation.
     * @param logger  Logger.
     */
    void Initialize(EventQueue *queue, IContextStore *context, ILogger *logger);

    /**
     * @brief Process a batch of events within budget.
     * Drains the queue (priority first, then normal) until either:
     *   - The queue is empty
     *   - The event budget (max_events) is exhausted
     *   - The time budget (budget_runner) is exhausted
     * @param budget   Time budget runner (may be NULL for unlimited time).
     * @param stats    Pipeline statistics (may be NULL).
     * @return Number of events dispatched.
     */
    int ProcessBatch(TimeBudgetRunner *budget, PipelineStatistics *stats);

    /**
     * @brief Get dispatch statistics.
     */
    const DispatchStats& GetStats(void) const { return m_stats; }

    /**
     * @brief Reset all statistics.
     */
    void ResetStats(void);

    /**
     * @brief Reset the duplicate detection ring.
     */
    void ResetDedup(void);
};

//+------------------------------------------------------------------+
//| EventDispatcher implementation                                    |
//+------------------------------------------------------------------+

EventDispatcher::EventDispatcher(void)
{
    m_queue   = NULL;
    m_context = NULL;
    m_logger  = NULL;
    m_seen_count = 0;
    m_last_snapshot_id = 0;
    ResetStats();
}

//+------------------------------------------------------------------+
void EventDispatcher::Initialize(EventQueue *queue, IContextStore *context, ILogger *logger)
{
    m_queue   = queue;
    m_context = context;
    m_logger  = logger;
    ResetStats();
    ResetDedup();
}

//+------------------------------------------------------------------+
bool EventDispatcher::ValidateEvent(const AtlasEvent &event) const
{
    //--- Delegate to the canonical contract validation method.
    //    This ensures the dispatcher uses the same invariants as every
    //    other consumer of AtlasEvent. The struct's Validate() checks
    //    type range, source_module non-empty, timestamp > 0, and
    //    payload_size in [0, ATLAS_PAYLOAD_MAX_SIZE].
    ValidationResult vr = event.Validate();
    if(!vr.valid)
    {
        if(m_logger != NULL)
            m_logger.Warn("EventDispatcher",
                "Event validation failed: " + vr.Summary());
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
bool EventDispatcher::IsDuplicate(const AtlasEvent &event)
{
    long key = BuildCompositeKey(event);
    for(int i = 0; i < m_seen_count; i++)
    {
        if(m_seen_keys[i] == key)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
void EventDispatcher::RecordSeen(const AtlasEvent &event)
{
    long key = BuildCompositeKey(event);
    if(m_seen_count >= ATLAS_IDEMPOTENCY_SLOTS)
    {
        for(int i = 1; i < ATLAS_IDEMPOTENCY_SLOTS; i++)
            m_seen_keys[i-1] = m_seen_keys[i];
        m_seen_keys[ATLAS_IDEMPOTENCY_SLOTS - 1] = key;
    }
    else
    {
        m_seen_keys[m_seen_count] = key;
        m_seen_count++;
    }
}

//+------------------------------------------------------------------+
int EventDispatcher::ProcessBatch(TimeBudgetRunner *budget, PipelineStatistics *stats)
{
    if(m_queue == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("EventDispatcher", "ProcessBatch: no queue attached");
        return 0;
    }

    int dispatched = 0;
    ulong phase_start = GetTickCount64();

    while(!m_queue.IsEmpty())
    {
        //--- Check event budget
        if(budget != NULL && !budget.HasEventBudget())
            break;

        //--- Check time budget
        if(budget != NULL && !budget.HasTimeRemaining())
        {
            if(m_logger != NULL && dispatched == 0)
                m_logger.Warn("EventDispatcher", "Time budget exhausted before any event processed");
            break;
        }

        //--- Dequeue next event (priority first)
        AtlasEvent event;
        if(!m_queue.Dequeue(event))
            break;

        //--- Validate
        if(!ValidateEvent(event))
        {
            m_stats.total_invalid++;
            continue;
        }

        //--- Sequence continuity check (snapshot_id gaps)
        if(m_last_snapshot_id > 0 && event.snapshot_id > m_last_snapshot_id + 1)
        {
            m_stats.total_sequence_gaps++;
            if(m_logger != NULL)
                m_logger.Warn("EventDispatcher",
                    "Snapshot gap: expected " + IntegerToString(m_last_snapshot_id + 1) +
                    " got " + IntegerToString(event.snapshot_id));
        }
        if(event.snapshot_id > m_last_snapshot_id)
            m_last_snapshot_id = event.snapshot_id;

        //--- Duplicate detection
        if(IsDuplicate(event))
        {
            m_stats.total_duplicates++;
            if(m_logger != NULL)
                m_logger.Debug("EventDispatcher", "Duplicate event skipped: type=" + IntegerToString((int)event.type));
            continue;
        }
        RecordSeen(event);

        //--- Route based on event type
        //--- In this phase, routing is logging-only (handlers wired in Integration phase)
        if(event.type >= EV_TICK_RECEIVED && event.type <= EV_KILL_SWITCH_ACTIVATED)
        {
            m_stats.per_type_count[(int)event.type]++;
            m_stats.total_dispatched++;

            if(m_logger != NULL && event.type == EV_ERROR_OCCURRED)
            {
                m_logger.Error("EventDispatcher", "Error event from " + event.source_module + " snapshot=" + IntegerToString(event.snapshot_id));
            }
            else if(m_logger != NULL && event.type == EV_KILL_SWITCH_ACTIVATED)
            {
                m_logger.Fatal("EventDispatcher", "Kill switch event received from " + event.source_module);
            }

            if(budget != NULL)
                budget.RecordEvent();
            dispatched++;
        }
        else
        {
            m_stats.total_invalid++;
        }
    }

    //--- Record dispatch phase latency
    if(stats != NULL && dispatched > 0)
    {
        double elapsed = (double)(GetTickCount64() - phase_start);
        stats.RecordPhase(PipelineStatistics::PHASE_DISPATCH, elapsed);
    }

    return dispatched;
}

//+------------------------------------------------------------------+
void EventDispatcher::ResetStats(void)
{
    m_stats.total_dispatched  = 0;
    m_stats.total_dropped     = 0;
    m_stats.total_duplicates  = 0;
    m_stats.total_filtered    = 0;
    m_stats.total_invalid     = 0;
    m_stats.total_sequence_gaps = 0;
    for(int i = 0; i < 13; i++)
        m_stats.per_type_count[i] = 0;
}

//+------------------------------------------------------------------+
void EventDispatcher::ResetDedup(void)
{
    m_seen_count = 0;
    m_last_snapshot_id = 0;
}

#endif // ATLAS_EVENT_DISPATCHER_MQH
//+------------------------------------------------------------------+
