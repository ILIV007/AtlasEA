//+------------------------------------------------------------------+
//|               StrategySDK/StrategyLifecycle.mqh                |
//|       AtlasEA v0.1.17.0 - Strategy Lifecycle Helper              |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_LIFECYCLE_MQH
#define ATLAS_STRATEGY_LIFECYCLE_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Strategy lifecycle states.
 */
#define ATLAS_LIFECYCLE_UNINITIALIZED  0
#define ATLAS_LIFECYCLE_INITIALIZED    1
#define ATLAS_LIFECYCLE_ACTIVE         2
#define ATLAS_LIFECYCLE_PAUSED         3
#define ATLAS_LIFECYCLE_FAILED         4
#define ATLAS_LIFECYCLE_SHUTDOWN       5

/**
 * @class StrategyLifecycle
 * @brief Tracks the lifecycle state of a strategy plugin.
 *
 * This is a helper for the PluginManager. It records the current state
 * and enforces valid transitions.
 */
class StrategyLifecycle
{
private:
    int m_state;
    int m_failure_count;
    datetime m_last_transition;

public:
    /**
     * @brief Constructor.
     */
    StrategyLifecycle(void)
    {
        m_state            = ATLAS_LIFECYCLE_UNINITIALIZED;
        m_failure_count    = 0;
        m_last_transition  = 0;
    }

    /**
     * @brief Transition to INITIALIZED.
     */
    bool ToInitialized(void)
    {
        if(m_state != ATLAS_LIFECYCLE_UNINITIALIZED) return false;
        m_state = ATLAS_LIFECYCLE_INITIALIZED;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Transition to ACTIVE.
     */
    bool ToActive(void)
    {
        if(m_state != ATLAS_LIFECYCLE_INITIALIZED &&
           m_state != ATLAS_LIFECYCLE_PAUSED) return false;
        m_state = ATLAS_LIFECYCLE_ACTIVE;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Transition to PAUSED.
     */
    bool ToPaused(void)
    {
        if(m_state != ATLAS_LIFECYCLE_ACTIVE) return false;
        m_state = ATLAS_LIFECYCLE_PAUSED;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Transition to FAILED.
     */
    bool ToFailed(void)
    {
        m_state = ATLAS_LIFECYCLE_FAILED;
        m_failure_count++;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Transition to SHUTDOWN.
     */
    bool ToShutdown(void)
    {
        m_state = ATLAS_LIFECYCLE_SHUTDOWN;
        m_last_transition = TimeCurrent();
        return true;
    }

    /**
     * @brief Reset to UNINITIALIZED.
     */
    void Reset(void)
    {
        m_state = ATLAS_LIFECYCLE_UNINITIALIZED;
        m_failure_count = 0;
        m_last_transition = 0;
    }

    //=== Queries ===
    int GetState(void) const { return m_state; }
    int GetFailureCount(void) const { return m_failure_count; }
    datetime GetLastTransition(void) const { return m_last_transition; }

    bool IsUninitialized(void) const { return m_state == ATLAS_LIFECYCLE_UNINITIALIZED; }
    bool IsInitialized(void) const   { return m_state == ATLAS_LIFECYCLE_INITIALIZED; }
    bool IsActive(void) const        { return m_state == ATLAS_LIFECYCLE_ACTIVE; }
    bool IsPaused(void) const        { return m_state == ATLAS_LIFECYCLE_PAUSED; }
    bool IsFailed(void) const        { return m_state == ATLAS_LIFECYCLE_FAILED; }
    bool IsShutdown(void) const      { return m_state == ATLAS_LIFECYCLE_SHUTDOWN; }
};

#endif // ATLAS_STRATEGY_LIFECYCLE_MQH
//+------------------------------------------------------------------+
