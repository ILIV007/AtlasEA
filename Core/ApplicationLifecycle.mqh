//+------------------------------------------------------------------+
//|                  Core/ApplicationLifecycle.mqh                  |
//|       AtlasEA v0.1.21.0 - Application Lifecycle State Machine   |
//+------------------------------------------------------------------+
#ifndef ATLAS_APPLICATION_LIFECYCLE_MQH
#define ATLAS_APPLICATION_LIFECYCLE_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Application lifecycle states.
 */
#define ATLAS_LIFECYCLE_CREATED        0
#define ATLAS_LIFECYCLE_BOOTSTRAPPING  1
#define ATLAS_LIFECYCLE_INITIALIZING   2
#define ATLAS_LIFECYCLE_RUNNING        3
#define ATLAS_LIFECYCLE_STOPPING       4
#define ATLAS_LIFECYCLE_STOPPED        5
#define ATLAS_LIFECYCLE_FAILED         6

/**
 * @class ApplicationLifecycle
 * @brief Tracks and validates application lifecycle state transitions.
 *
 * State machine:
 *   CREATED → BOOTSTRAPPING → INITIALIZING → RUNNING → STOPPING → STOPPED
 *                    ↓              ↓             ↓
 *                 FAILED        FAILED        FAILED
 *
 * From FAILED, only a full reset (→ CREATED) is allowed.
 * From STOPPED, only a full reset (→ CREATED) is allowed.
 */
class ApplicationLifecycle
{
private:
    int      m_state;
    datetime m_last_transition;
    string   m_failure_reason;

    /// @brief Check if a transition is valid.
    bool IsValidTransition(const int from, const int to) const
    {
        //--- CREATED → BOOTSTRAPPING
        if(from == ATLAS_LIFECYCLE_CREATED && to == ATLAS_LIFECYCLE_BOOTSTRAPPING)
            return true;

        //--- BOOTSTRAPPING → INITIALIZING
        if(from == ATLAS_LIFECYCLE_BOOTSTRAPPING && to == ATLAS_LIFECYCLE_INITIALIZING)
            return true;

        //--- INITIALIZING → RUNNING
        if(from == ATLAS_LIFECYCLE_INITIALIZING && to == ATLAS_LIFECYCLE_RUNNING)
            return true;

        //--- RUNNING → STOPPING
        if(from == ATLAS_LIFECYCLE_RUNNING && to == ATLAS_LIFECYCLE_STOPPING)
            return true;

        //--- STOPPING → STOPPED
        if(from == ATLAS_LIFECYCLE_STOPPING && to == ATLAS_LIFECYCLE_STOPPED)
            return true;

        //--- Any active state → FAILED
        if(from >= ATLAS_LIFECYCLE_BOOTSTRAPPING && from <= ATLAS_LIFECYCLE_RUNNING &&
           to == ATLAS_LIFECYCLE_FAILED)
            return true;

        //--- FAILED → CREATED (reset)
        if(from == ATLAS_LIFECYCLE_FAILED && to == ATLAS_LIFECYCLE_CREATED)
            return true;

        //--- STOPPED → CREATED (reset for restart)
        if(from == ATLAS_LIFECYCLE_STOPPED && to == ATLAS_LIFECYCLE_CREATED)
            return true;

        return false;
    }

    /// @brief Get state name string.
    string StateName(const int state) const
    {
        switch(state)
        {
            case ATLAS_LIFECYCLE_CREATED:       return "CREATED";
            case ATLAS_LIFECYCLE_BOOTSTRAPPING: return "BOOTSTRAPPING";
            case ATLAS_LIFECYCLE_INITIALIZING:  return "INITIALIZING";
            case ATLAS_LIFECYCLE_RUNNING:       return "RUNNING";
            case ATLAS_LIFECYCLE_STOPPING:      return "STOPPING";
            case ATLAS_LIFECYCLE_STOPPED:       return "STOPPED";
            case ATLAS_LIFECYCLE_FAILED:        return "FAILED";
        }
        return "UNKNOWN";
    }

public:
    /**
     * @brief Constructor — starts in CREATED state.
     */
    ApplicationLifecycle(void)
    {
        m_state           = ATLAS_LIFECYCLE_CREATED;
        m_last_transition = 0;
        m_failure_reason  = "";
    }

    /**
     * @brief Transition to a new state.
     * @return true if the transition is valid and was applied.
     */
    bool Transition(const int new_state)
    {
        if(!IsValidTransition(m_state, new_state))
            return false;

        m_state           = new_state;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Transition to FAILED with a reason.
     */
    bool Fail(const string reason)
    {
        if(!Transition(ATLAS_LIFECYCLE_FAILED))
            return false;
        m_failure_reason = reason;
        return true;
    }

    /**
     * @brief Reset to CREATED state.
     */
    void Reset(void)
    {
        m_state           = ATLAS_LIFECYCLE_CREATED;
        m_last_transition = 0;
        m_failure_reason  = "";
    }

    //=== Queries ===
    int GetState(void) const { return m_state; }
    string GetStateName(void) const { return StateName(m_state); }
    datetime GetLastTransition(void) const { return m_last_transition; }
    string GetFailureReason(void) const { return m_failure_reason; }

    bool IsCreated(void) const       { return m_state == ATLAS_LIFECYCLE_CREATED; }
    bool IsBootstrapping(void) const { return m_state == ATLAS_LIFECYCLE_BOOTSTRAPPING; }
    bool IsInitializing(void) const  { return m_state == ATLAS_LIFECYCLE_INITIALIZING; }
    bool IsRunning(void) const       { return m_state == ATLAS_LIFECYCLE_RUNNING; }
    bool IsStopping(void) const      { return m_state == ATLAS_LIFECYCLE_STOPPING; }
    bool IsStopped(void) const       { return m_state == ATLAS_LIFECYCLE_STOPPED; }
    bool IsFailed(void) const        { return m_state == ATLAS_LIFECYCLE_FAILED; }
};

#endif // ATLAS_APPLICATION_LIFECYCLE_MQH
//+------------------------------------------------------------------+
