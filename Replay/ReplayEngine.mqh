//+------------------------------------------------------------------+
//|                     Replay/ReplayEngine.mqh                     |
//|       AtlasEA v0.1.23.0 - Deterministic Event Replay Engine    |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_ENGINE_MQH
#define ATLAS_REPLAY_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/IReplayEngine.mqh"
#include "../Interfaces/IReplayClock.mqh"
#include "../Interfaces/IReplayStatistics.mqh"
#include "../Interfaces/IEventStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Events/EventMetadata.mqh"
#include "../Events/EventVersioning.mqh"
#include "ReplaySession.mqh"
#include "ReplayCursor.mqh"
#include "ReplayClock.mqh"
#include "ReplayStatistics.mqh"
#include "ReplayValidator.mqh"

/**
 * @class ReplayEngine
 * @brief Concrete implementation of IReplayEngine.
 *
 * Deterministic event replay engine.
 *
 * Capabilities:
 *   - Load events from IEventStore by sequence range
 *   - Validate loaded events (continuity, timestamps, duplicates)
 *   - Replay at variable speed (1x, 10x, 100x, MAX, STEP)
 *   - Pause / Resume / Stop
 *   - JumpTo (seek to arbitrary sequence)
 *   - StepForward (manual single-event advance)
 *   - Virtual clock (replaces TimeCurrent during replay)
 *   - Statistics collection
 *
 * The replay engine does NOT call MT5 APIs. It works entirely from
 * persisted events. The callback delivers events to the caller
 * (typically CoreEngine), which processes them as if they were live.
 *
 * CoreEngine does not know whether events come from Live or Replay.
 */
class ReplayEngine : public IReplayEngine
{
private:
    ILogger           *m_logger;
    IEventStore       *m_store;
    ReplaySession      m_session;
    ReplayStatistics   m_stats;
    ReplayValidator    m_validator;

    ReplayEventCallback m_callback;
    void               *m_callback_data;

    int                 m_current_speed;
    ReplayResult        m_last_result;

    /// @brief Load events from the store into the session.
    bool LoadFromStore(const long from_seq, const long to_seq)
    {
        if(m_store == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("ReplayEngine", "LoadFromStore: no event store");
            return false;
        }

        m_session.Transition(ATLAS_REPLAY_STATE_LOADING);

        //--- Read events from the store
        SourcedEvent events[ATLAS_REPLAY_CURSOR_MAX];
        int loaded = 0;

        //--- Read events in the sequence range
        for(long seq = from_seq; seq <= to_seq && loaded < ATLAS_REPLAY_CURSOR_MAX; seq++)
        {
            SourcedEvent sourced;
            if(m_store.ReadSourced(seq, sourced))
            {
                //--- Upgrade if needed
                EventVersioning::Upgrade(sourced);
                events[loaded] = sourced;
                loaded++;
            }
        }

        if(loaded == 0)
        {
            if(m_logger != NULL)
                m_logger.Error("ReplayEngine", "LoadFromStore: no events in range");
            m_session.Transition(ATLAS_REPLAY_STATE_FAILED);
            return false;
        }

        //--- Validate
        ReplayValidationReport vreport = m_validator.Validate(events, loaded);
        if(!vreport.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("ReplayEngine",
                    "LoadFromStore: validation failed (" + IntegerToString(vreport.error_count) + " errors)");
            m_session.Transition(ATLAS_REPLAY_STATE_FAILED);
            return false;
        }

        //--- Initialize session
        if(!m_session.Initialize(events, loaded))
        {
            m_session.Transition(ATLAS_REPLAY_STATE_FAILED);
            return false;
        }

        //--- Set statistics total
        m_stats.SetTotal(loaded);
        m_stats.Start();

        m_session.Transition(ATLAS_REPLAY_STATE_READY);

        if(m_logger != NULL)
            m_logger.Info("ReplayEngine",
                "Loaded " + IntegerToString(loaded) + " events [" +
                IntegerToString(from_seq) + ".." + IntegerToString(to_seq) + "]");

        return true;
    }

    /// @brief Process the current event (invoke callback + update stats).
    void ProcessCurrentEvent(void)
    {
        SourcedEvent current;
        if(!m_session.GetCursor().Current(current))
            return;

        //--- Advance the virtual clock
        m_session.GetClock().AdvanceTo(current.event.timestamp);

        //--- Calculate scaled delay
        datetime prev_ts = m_session.GetPrevTimestamp();
        int delay_ms = m_session.GetClock().GetScaledDelayMs(prev_ts, current.event.timestamp);

        //--- Apply delay (except MAX and STEP modes)
        if(delay_ms > 0 && m_current_speed != ATLAS_REPLAY_MAX && m_current_speed != ATLAS_REPLAY_STEP)
        {
            ulong start = GetTickCount64();
            Sleep(delay_ms);
            double actual_latency = (double)(GetTickCount64() - start);
            m_stats.RecordEvent(actual_latency);
        }
        else
        {
            m_stats.RecordEvent(0.001);  //--- Near-zero latency
        }

        //--- Record drift
        m_stats.RecordDrift(m_session.GetClock().GetDriftMs());

        //--- Invoke callback
        if(m_callback != NULL)
            m_callback(current.event, m_callback_data);

        //--- Update session position
        m_session.UpdatePosition(current.metadata.sequence);
        m_session.SetPrevTimestamp(current.event.timestamp);
    }

public:
    /**
     * @brief Constructor.
     */
    ReplayEngine(void)
    {
        m_logger        = NULL;
        m_store         = NULL;
        m_callback      = NULL;
        m_callback_data = NULL;
        m_current_speed = ATLAS_REPLAY_MAX;

        m_last_result.success        = false;
        m_last_result.events_replayed = 0;
        m_last_result.events_skipped  = 0;
        m_last_result.duration_ms    = 0.0;
        m_last_result.avg_speed      = 0.0;
        m_last_result.failure_reason = "";
    }

    /**
     * @brief Set dependencies.
     * @param store Event store to read from.
     * @param logger Logger.
     */
    void SetDependencies(IEventStore *store, ILogger *logger)
    {
        m_store  = store;
        m_logger = logger;
        m_session.SetLogger(logger);
        m_stats.SetLogger(logger);
        m_validator.SetLogger(logger);
    }

    /**
     * @brief Validate runtime invariants of the ReplayEngine.
     *
     * Contract:
     *   - m_store MUST be non-NULL (the engine cannot load events
     *     without an event store).
     *   - m_logger MUST be non-NULL (required for diagnostics).
     *   - Delegates to m_session.Validate() (ReplayStatistics has no
     *     Validate() method, so it is not delegated).
     *
     * @return ValidationResult::Ok() on success, Fail() on first violation.
     */
    ValidationResult Validate(void) const
    {
        if(m_store == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "Event store is NULL",
                "m_store");

        if(m_logger == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "Logger is NULL",
                "m_logger");

        //--- Delegate to the session (ReplayStatistics exposes no Validate()).
        ValidationResult session_result = m_session.Validate();
        if(!session_result.valid)
            return session_result;

        return ValidationResult::Ok();
    }

    //=== IReplayEngine implementation ===

    virtual bool LoadEvents(const long from_sequence, const long to_sequence) override
    {
        m_session.Reset();
        m_stats.Reset();

        return LoadFromStore(from_sequence, to_sequence);
    }

    virtual bool Play(const int speed) override
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_READY &&
           m_session.GetState() != ATLAS_REPLAY_STATE_PAUSED)
        {
            if(m_logger != NULL)
                m_logger.Warn("ReplayEngine", "Play: not in READY/PAUSED state");
            return false;
        }

        m_current_speed = speed;
        m_session.SetSpeed(speed);
        m_session.Transition(ATLAS_REPLAY_STATE_RUNNING);

        if(m_logger != NULL)
            m_logger.Info("ReplayEngine",
                "Play started: speed=" + IntegerToString(speed) +
                " events=" + IntegerToString(m_session.GetInfo().loaded_events));

        //--- If resuming from pause, don't reset cursor
        if(m_session.GetCursor().Position() < 0)
            m_session.GetCursor().Next();

        return true;
    }

    virtual bool Pause(void) override
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_RUNNING)
            return false;

        m_session.Transition(ATLAS_REPLAY_STATE_PAUSED);
        m_session.GetClock().Pause();

        if(m_logger != NULL)
            m_logger.Info("ReplayEngine", "Paused at sequence " +
                         IntegerToString(m_session.GetInfo().current_sequence));
        return true;
    }

    virtual bool Resume(void) override
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_PAUSED)
            return false;

        m_session.Transition(ATLAS_REPLAY_STATE_RUNNING);
        m_session.GetClock().Resume();

        if(m_logger != NULL)
            m_logger.Info("ReplayEngine", "Resumed");
        return true;
    }

    virtual bool Stop(void) override
    {
        if(m_session.GetState() == ATLAS_REPLAY_STATE_IDLE ||
           m_session.GetState() == ATLAS_REPLAY_STATE_STOPPED)
            return false;

        m_session.Transition(ATLAS_REPLAY_STATE_STOPPED);
        m_session.EndSession();

        //--- Finalize statistics
        m_stats.UpdateProgress();
        ReplayStats stats = m_stats.GetStats();

        m_last_result.success        = true;
        m_last_result.events_replayed = stats.events_replayed;
        m_last_result.events_skipped  = stats.events_skipped;
        m_last_result.duration_ms    = stats.replay_duration_ms;
        m_last_result.avg_speed      = stats.avg_replay_speed;
        m_last_result.failure_reason = "";

        if(m_logger != NULL)
        {
            m_logger.Info("ReplayEngine", "Stopped at sequence " +
                         IntegerToString(m_session.GetInfo().current_sequence));
            m_stats.LogStats();
        }

        return true;
    }

    virtual bool JumpTo(const long sequence) override
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_READY &&
           m_session.GetState() != ATLAS_REPLAY_STATE_PAUSED &&
           m_session.GetState() != ATLAS_REPLAY_STATE_RUNNING)
            return false;

        bool found = m_session.GetCursor().SeekBySequence(sequence);
        if(!found)
        {
            if(m_logger != NULL)
                m_logger.Warn("ReplayEngine",
                    "JumpTo: sequence " + IntegerToString(sequence) + " not found");
            return false;
        }

        //--- Update session position
        SourcedEvent current;
        if(m_session.GetCursor().Current(current))
        {
            m_session.UpdatePosition(current.metadata.sequence);
            m_session.SetPrevTimestamp(current.event.timestamp);
            m_session.GetClock().AdvanceTo(current.event.timestamp);
        }

        if(m_logger != NULL)
            m_logger.Info("ReplayEngine", "Jumped to sequence " + IntegerToString(sequence));
        return true;
    }

    virtual bool StepForward(void) override
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_RUNNING &&
           m_session.GetState() != ATLAS_REPLAY_STATE_PAUSED)
            return false;

        //--- Force STEP mode for this call
        int prev_speed = m_current_speed;
        m_current_speed = ATLAS_REPLAY_STEP;

        if(!m_session.GetCursor().Next())
        {
            //--- End of events
            m_session.Transition(ATLAS_REPLAY_STATE_COMPLETED);
            m_session.EndSession();
            m_current_speed = prev_speed;
            return false;
        }

        ProcessCurrentEvent();
        m_current_speed = prev_speed;
        return true;
    }

    /**
     * @brief Process the next event (called in a loop by the caller).
     * This is the main replay tick — called from OnTimer or a dedicated loop.
     * @return true if an event was processed, false if replay is complete/paused/stopped.
     */
    bool ProcessNext(void)
    {
        if(m_session.GetState() != ATLAS_REPLAY_STATE_RUNNING)
            return false;

        //--- Advance cursor
        if(!m_session.GetCursor().Next())
        {
            //--- End of events
            m_session.Transition(ATLAS_REPLAY_STATE_COMPLETED);
            m_session.EndSession();

            m_stats.UpdateProgress();
            ReplayStats stats = m_stats.GetStats();
            m_last_result.success        = true;
            m_last_result.events_replayed = stats.events_replayed;
            m_last_result.events_skipped  = stats.events_skipped;
            m_last_result.duration_ms    = stats.replay_duration_ms;
            m_last_result.avg_speed      = stats.avg_replay_speed;

            if(m_logger != NULL)
            {
                m_logger.Info("ReplayEngine", "Replay completed: " +
                             IntegerToString((long)stats.events_replayed) + " events in " +
                             DoubleToString(stats.replay_duration_ms, 1) + "ms");
                m_stats.LogStats();
            }
            return false;
        }

        ProcessCurrentEvent();
        return true;
    }

    virtual int GetState(void) const override
    {
        return m_session.GetState();
    }

    virtual long GetCurrentSequence(void) const override
    {
        return m_session.GetInfo().current_sequence;
    }

    virtual long GetLoadedCount(void) const override
    {
        return m_session.GetInfo().loaded_events;
    }

    virtual const ReplayResult& GetLastResult(void) const override
    {
        return m_last_result;
    }

    virtual void SetCallback(ReplayEventCallback callback, void *user_data) override
    {
        m_callback      = callback;
        m_callback_data = user_data;
    }

    virtual void SetSpeed(const int speed) override
    {
        m_current_speed = speed;
        m_session.SetSpeed(speed);
    }

    //=== Extended API ===

    /**
     * @brief Get the virtual clock.
     */
    ReplayClock& GetClock(void) { return m_session.GetClock(); }

    /**
     * @brief Get the statistics.
     */
    ReplayStatistics& GetStatistics(void) { return m_stats; }

    /**
     * @brief Get the session info.
     */
    const ReplaySessionInfo& GetSessionInfo(void) const { return m_session.GetInfo(); }

    /**
     * @brief Get the validator.
     */
    ReplayValidator& GetValidator(void) { return m_validator; }
};

#endif // ATLAS_REPLAY_ENGINE_MQH
//+------------------------------------------------------------------+
