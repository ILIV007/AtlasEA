//+------------------------------------------------------------------+
//|                     Replay/ReplaySession.mqh                    |
//|       AtlasEA v0.1.23.0 - Replay Session                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_SESSION_MQH
#define ATLAS_REPLAY_SESSION_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/IReplayEngine.mqh"
#include "../Interfaces/ILogger.mqh"
#include "ReplayCursor.mqh"
#include "ReplayClock.mqh"

/**
 * @struct ReplaySessionInfo
 * @brief Metadata about a replay session.
 */
struct ReplaySessionInfo
{
    string   session_id;         ///< Unique session ID
    datetime start_time;         ///< When the session started (wall clock)
    datetime end_time;           ///< When the session ended
    int      replay_speed;      ///< Speed code
    long     current_sequence;   ///< Current sequence position
    long     loaded_events;      ///< Total events loaded
    int      replay_state;       ///< ATLAS_REPLAY_STATE_*
    datetime first_event_time;   ///< Timestamp of first event
    datetime last_event_time;    ///< Timestamp of last event
    long     first_sequence;     ///< First sequence number
    long     last_sequence;      ///< Last sequence number

    /**
     * @brief Default constructor.
     */
    ReplaySessionInfo(void)
    {
        session_id        = "";
        start_time        = 0;
        end_time          = 0;
        replay_speed      = ATLAS_REPLAY_MAX;
        current_sequence  = 0;
        loaded_events     = 0;
        replay_state      = ATLAS_REPLAY_STATE_IDLE;
        first_event_time  = 0;
        last_event_time   = 0;
        first_sequence    = 0;
        last_sequence     = 0;
    }
};

/**
 * @class ReplaySession
 * @brief Manages a single replay session.
 *
 * A session encapsulates:
 *   - A loaded set of events (via ReplayCursor)
 *   - A virtual clock (ReplayClock)
 *   - Session metadata (ID, start/end time, speed, state)
 *   - Replay state transitions
 *
 * The session is the core data structure for replay. The ReplayEngine
 * drives the session by calling cursor.Next() and clock.AdvanceTo().
 */
class ReplaySession
{
private:
    ReplaySessionInfo m_info;
    ReplayCursor      m_cursor;
    ReplayClock       m_clock;
    ILogger          *m_logger;
    datetime          m_prev_timestamp;

    /// @brief Generate a unique session ID (deterministic — uses counter, not MathRand).
    int m_session_counter;
    string GenerateSessionId(void)
    {
        m_session_counter++;
        return "REPLAY_" + IntegerToString((long)TimeCurrent()) + "_" +
               IntegerToString(m_session_counter);
    }

public:
    /**
     * @brief Constructor.
     */
    ReplaySession(void)
    {
        m_logger         = NULL;
        m_prev_timestamp = 0;
        m_session_counter = 0;
    }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_cursor.SetLogger(logger);
        m_clock.SetLogger(logger);
    }

    /**
     * @brief Initialize the session with loaded events.
     * @param events Array of sourced events.
     * @param count Number of events.
     */
    bool Initialize(const SourcedEvent &events[], const int count)
    {
        if(count <= 0)
        {
            if(m_logger != NULL)
                m_logger.Error("ReplaySession", "Initialize: no events");
            m_info.replay_state = ATLAS_REPLAY_STATE_FAILED;
            return false;
        }

        m_cursor.Load(events, count);

        m_info.session_id       = GenerateSessionId();
        m_info.start_time       = TimeCurrent();
        m_info.loaded_events    = count;
        m_info.replay_state     = ATLAS_REPLAY_STATE_READY;
        m_info.first_sequence   = m_cursor.FirstSequence();
        m_info.last_sequence    = m_cursor.LastSequence();
        m_info.first_event_time = m_cursor.FirstTimestamp();
        m_info.last_event_time  = m_cursor.LastTimestamp();
        m_info.current_sequence = m_info.first_sequence;

        //--- Initialize the clock to the first event's timestamp
        m_clock.Initialize(m_info.first_event_time);

        if(m_logger != NULL)
            m_logger.Info("ReplaySession",
                "Initialized: " + IntegerToString(count) + " events, " +
                "seq [" + IntegerToString(m_info.first_sequence) + ".." +
                IntegerToString(m_info.last_sequence) + "], " +
                "session=" + m_info.session_id);

        return true;
    }

    /**
     * @brief Get the cursor.
     */
    ReplayCursor& GetCursor(void) { return m_cursor; }

    /**
     * @brief Get the clock.
     */
    ReplayClock& GetClock(void) { return m_clock; }

    /**
     * @brief Get the session info.
     */
    const ReplaySessionInfo& GetInfo(void) const { return m_info; }

    /**
     * @brief Set the replay speed.
     */
    void SetSpeed(const int speed)
    {
        m_info.replay_speed = speed;
        m_clock.ScaleSpeed(speed);
    }

    /**
     * @brief Transition to a new state.
     */
    bool Transition(const int new_state)
    {
        //--- Validate transition
        switch(m_info.replay_state)
        {
            case ATLAS_REPLAY_STATE_IDLE:
            case ATLAS_REPLAY_STATE_LOADING:
                if(new_state != ATLAS_REPLAY_STATE_READY &&
                   new_state != ATLAS_REPLAY_STATE_FAILED) return false;
                break;

            case ATLAS_REPLAY_STATE_READY:
                if(new_state != ATLAS_REPLAY_STATE_RUNNING &&
                   new_state != ATLAS_REPLAY_STATE_STOPPED) return false;
                break;

            case ATLAS_REPLAY_STATE_RUNNING:
                if(new_state != ATLAS_REPLAY_STATE_PAUSED &&
                   new_state != ATLAS_REPLAY_STATE_STOPPED &&
                   new_state != ATLAS_REPLAY_STATE_COMPLETED) return false;
                break;

            case ATLAS_REPLAY_STATE_PAUSED:
                if(new_state != ATLAS_REPLAY_STATE_RUNNING &&
                   new_state != ATLAS_REPLAY_STATE_STOPPED) return false;
                break;

            case ATLAS_REPLAY_STATE_STOPPED:
            case ATLAS_REPLAY_STATE_COMPLETED:
            case ATLAS_REPLAY_STATE_FAILED:
                if(new_state != ATLAS_REPLAY_STATE_IDLE) return false;
                break;
        }

        m_info.replay_state = new_state;
        return true;
    }

    /**
     * @brief Update the current sequence position.
     */
    void UpdatePosition(const long sequence)
    {
        m_info.current_sequence = sequence;
    }

    /**
     * @brief Mark the session as ended and release loaded event state.
     *
     * Records the end time, then releases the cursor's loaded events
     * and resets the virtual clock. The session info (metadata) is
     * preserved so callers can still read final statistics after
     * EndSession() returns.
     */
    void EndSession(void)
    {
        m_info.end_time = TimeCurrent();

        //--- Release loaded events from the cursor (the heavy data).
        //    The info struct (metadata) is preserved for post-stop reporting.
        m_cursor.Clear();
        m_clock.Reset();
        m_prev_timestamp = 0;
    }

    /**
     * @brief Get the previous event timestamp (for speed scaling).
     */
    datetime GetPrevTimestamp(void) const { return m_prev_timestamp; }

    /**
     * @brief Set the previous event timestamp.
     */
    void SetPrevTimestamp(const datetime ts) { m_prev_timestamp = ts; }

    /**
     * @brief Reset the session to idle.
     */
    void Reset(void)
    {
        m_cursor.Clear();
        m_clock.Reset();
        m_info = ReplaySessionInfo();
        m_prev_timestamp = 0;
    }

    int GetState(void) const { return m_info.replay_state; }
    bool IsRunning(void) const { return m_info.replay_state == ATLAS_REPLAY_STATE_RUNNING; }
    bool IsPaused(void) const { return m_info.replay_state == ATLAS_REPLAY_STATE_PAUSED; }
    bool IsCompleted(void) const { return m_info.replay_state == ATLAS_REPLAY_STATE_COMPLETED; }

    /**
     * @brief Validate runtime invariants of the replay session.
     *
     * Contract:
     *   - If the session has been initialized (replay_state != IDLE),
     *     m_info.session_id MUST be non-empty.
     *   - m_info.replay_state MUST be a valid ATLAS_REPLAY_STATE_* enum
     *     value (0=IDLE, 1=LOADING, 2=READY, 3=RUNNING, 4=PAUSED,
     *     5=STOPPED, 6=COMPLETED, 7=FAILED).
     *   - m_info.loaded_events >= 0.
     *   - m_info.first_sequence >= 0.
     *   - If loaded_events > 0, last_sequence >= first_sequence.
     *   - If loaded_events > 0, current_sequence in
     *     [first_sequence, last_sequence].
     *
     * Pre-init (IDLE, no events loaded) is explicitly valid.
     *
     * @return ValidationResult::Ok() on success, Fail() on first violation.
     */
    ValidationResult Validate(void) const
    {
        //--- replay_state must be a known enum value
        if(m_info.replay_state < ATLAS_REPLAY_STATE_IDLE ||
           m_info.replay_state > ATLAS_REPLAY_STATE_FAILED)
            return ValidationResult::Fail(ATLAS_V_INVALID_ENUM,
                "replay_state out of range [0..7]",
                "m_info.replay_state");

        //--- Pre-init (IDLE) is unconditionally valid.
        //    The session may legitimately have an empty session_id and
        //    zeroed counters before Initialize() is called.
        bool initialized = (m_info.replay_state != ATLAS_REPLAY_STATE_IDLE);
        if(!initialized)
            return ValidationResult::Ok();

        //--- session_id required once initialized
        if(m_info.session_id == "")
            return ValidationResult::Fail(ATLAS_V_EMPTY_FIELD,
                "session_id is empty after Initialize",
                "m_info.session_id");

        //--- counters must be non-negative
        if(m_info.loaded_events < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "loaded_events must be >= 0",
                "m_info.loaded_events");

        if(m_info.first_sequence < 0)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "first_sequence must be >= 0",
                "m_info.first_sequence");

        //--- monotonicity: last >= first (only when events were loaded)
        if(m_info.loaded_events > 0)
        {
            if(m_info.last_sequence < m_info.first_sequence)
                return ValidationResult::Fail(ATLAS_V_MONOTONICITY,
                    "last_sequence < first_sequence",
                    "m_info.last_sequence");

            //--- current_sequence must lie within [first, last]
            if(m_info.current_sequence < m_info.first_sequence ||
               m_info.current_sequence > m_info.last_sequence)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "current_sequence outside [first_sequence, last_sequence]",
                    "m_info.current_sequence");
        }

        return ValidationResult::Ok();
    }
};

#endif // ATLAS_REPLAY_SESSION_MQH
//+------------------------------------------------------------------+
