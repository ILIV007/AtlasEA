//+------------------------------------------------------------------+
//|                                      Core/TimeBudgetRunner.mqh
//|            AtlasEA v2.0 - Tick Time Budget Controller             |
//+------------------------------------------------------------------+
#ifndef ATLAS_TIME_BUDGET_RUNNER_MQH
#define ATLAS_TIME_BUDGET_RUNNER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class TimeBudgetRunner
 * @brief Enforces per-tick time budget and event count limits.
 *
 * The EA must complete OnTick() within max_ms_per_tick (default 50ms)
 * and process at most max_events_per_tick events (default 8).
 *
 * This class provides:
 *   - StartTick(): record the tick start timestamp
 *   - HasTimeRemaining(): check if budget remains
 *   - HasEventBudget(): check if more events can be processed
 *   - ElapsedMs(): current elapsed time since tick start
 *   - RemainingMs(): remaining budget
 *
 * Thread model: MQL5 single-threaded; uses GetTickCount64() for monotonic ms.
 * No Sleep() or blocking — if budget is exhausted, remaining events defer.
 */
class TimeBudgetRunner
{
private:
    ulong   m_tick_start_ms;        ///< Tick start timestamp (ms)
    ulong   m_max_ms_per_tick;      ///< Budget per tick
    int     m_max_events_per_tick;  ///< Event budget per tick
    int     m_events_processed;     ///< Events processed this tick
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     */
    TimeBudgetRunner(void);

    /**
     * @brief Initialize the budget runner.
     * @param logger         Logger.
     * @param max_ms         Max milliseconds per tick.
     * @param max_events     Max events per tick.
     */
    void Initialize(ILogger *logger, const ulong max_ms, const int max_events);

    /**
     * @brief Mark the start of a tick. Resets event counter.
     */
    void StartTick(void);

    /**
     * @brief Record that one event was processed.
     */
    void RecordEvent(void);

    /**
     * @brief Check if time budget remains.
     * @return true if ElapsedMs() < max_ms_per_tick.
     */
    bool HasTimeRemaining(void) const;

    /**
     * @brief Check if event budget remains.
     * @return true if events_processed < max_events_per_tick.
     */
    bool HasEventBudget(void) const;

    /**
     * @brief Check if both budgets remain (convenience).
     * @return true if both time and event budgets remain.
     */
    bool CanContinue(void) const;

    /**
     * @brief Elapsed milliseconds since StartTick().
     */
    ulong ElapsedMs(void) const;

    /**
     * @brief Remaining milliseconds in the budget.
     */
    ulong RemainingMs(void) const;

    /// @brief Max ms per tick.
    ulong MaxMsPerTick(void) const { return m_max_ms_per_tick; }

    /// @brief Max events per tick.
    int   MaxEventsPerTick(void) const { return m_max_events_per_tick; }

    /// @brief Events processed so far this tick.
    int   EventsProcessed(void) const { return m_events_processed; }

    /// @brief true if the last tick exceeded the budget.
    bool   LastTickOverrun(void) const { return ElapsedMs() > m_max_ms_per_tick; }
};

//+------------------------------------------------------------------+
//| TimeBudgetRunner implementation                                   |
//+------------------------------------------------------------------+

TimeBudgetRunner::TimeBudgetRunner(void)
{
    m_tick_start_ms       = 0;
    m_max_ms_per_tick     = ATLAS_MAX_MS_PER_TICK;
    m_max_events_per_tick = ATLAS_MAX_EVENTS_PER_TICK;
    m_events_processed    = 0;
    m_logger              = NULL;
}

//+------------------------------------------------------------------+
void TimeBudgetRunner::Initialize(ILogger *logger, const ulong max_ms, const int max_events)
{
    m_logger              = logger;
    m_max_ms_per_tick     = (max_ms > 0) ? max_ms : ATLAS_MAX_MS_PER_TICK;
    m_max_events_per_tick = (max_events > 0) ? max_events : ATLAS_MAX_EVENTS_PER_TICK;
}

//+------------------------------------------------------------------+
void TimeBudgetRunner::StartTick(void)
{
    m_tick_start_ms    = GetTickCount64();
    m_events_processed = 0;
}

//+------------------------------------------------------------------+
void TimeBudgetRunner::RecordEvent(void)
{
    m_events_processed++;
}

//+------------------------------------------------------------------+
bool TimeBudgetRunner::HasTimeRemaining(void) const
{
    return ElapsedMs() < m_max_ms_per_tick;
}

//+------------------------------------------------------------------+
bool TimeBudgetRunner::HasEventBudget(void) const
{
    return m_events_processed < m_max_events_per_tick;
}

//+------------------------------------------------------------------+
bool TimeBudgetRunner::CanContinue(void) const
{
    return HasTimeRemaining() && HasEventBudget();
}

//+------------------------------------------------------------------+
ulong TimeBudgetRunner::ElapsedMs(void) const
{
    if(m_tick_start_ms == 0) return 0;
    return GetTickCount64() - m_tick_start_ms;
}

//+------------------------------------------------------------------+
ulong TimeBudgetRunner::RemainingMs(void) const
{
    ulong elapsed = ElapsedMs();
    if(elapsed >= m_max_ms_per_tick) return 0;
    return m_max_ms_per_tick - elapsed;
}

#endif // ATLAS_TIME_BUDGET_RUNNER_MQH
//+------------------------------------------------------------------+
