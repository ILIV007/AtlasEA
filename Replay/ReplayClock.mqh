//+------------------------------------------------------------------+
//|                      Replay/ReplayClock.mqh                     |
//|       AtlasEA v0.1.23.0 - Virtual Replay Clock                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_CLOCK_MQH
#define ATLAS_REPLAY_CLOCK_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IReplayClock.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class ReplayClock
 * @brief Concrete implementation of IReplayClock.
 *
 * Virtual clock that replaces TimeCurrent() during replay.
 * Advances based on replayed event timestamps, not real time.
 *
 * Speed scaling:
 *   - 1X: events played at real-time intervals
 *   - 10X: intervals divided by 10
 *   - 100X: intervals divided by 100
 *   - MAX: no delay between events
 *   - STEP: manual advance (no automatic progression)
 *
 * The clock tracks:
 *   - Virtual time (from events)
 *   - Real time (wall clock)
 *   - Synchronization drift (virtual vs real)
 */
class ReplayClock : public IReplayClock
{
private:
    datetime m_virtual_time;    ///< Current virtual time (from events)
    ulong    m_real_start_ms;   ///< Real wall-clock at replay start
    datetime m_virtual_start;   ///< Virtual time at replay start
    int      m_speed;           ///< Current speed code
    bool     m_paused;          ///< Is the clock paused?
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     */
    ReplayClock(void)
    {
        m_virtual_time    = 0;
        m_real_start_ms   = 0;
        m_virtual_start   = 0;
        m_speed           = ATLAS_REPLAY_MAX;
        m_paused          = false;
        m_logger          = NULL;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Initialize the clock with a starting virtual time.
     */
    void Initialize(const datetime start_time)
    {
        m_virtual_time  = start_time;
        m_virtual_start = start_time;
        m_real_start_ms = GetTickCount64();
        m_paused        = false;
        //--- Reset speed to default so a re-Initialize() does not carry
        //    over the previous session's speed setting.
        m_speed         = ATLAS_REPLAY_MAX;

        if(m_logger != NULL)
            m_logger.Info("ReplayClock",
                "Initialized: virtual_start=" + TimeToString(start_time, TIME_DATE | TIME_SECONDS));
    }

    //=== IReplayClock implementation ===

    virtual datetime Now(void) const override
    {
        return m_virtual_time;
    }

    virtual ulong NowMs(void) const override
    {
        return (ulong)((long)m_virtual_time * 1000);
    }

    virtual void AdvanceTo(const datetime target) override
    {
        if(m_paused) return;
        if(target > m_virtual_time)
            m_virtual_time = target;
    }

    virtual void AdvanceBy(const long seconds) override
    {
        if(m_paused) return;
        m_virtual_time = (datetime)((long)m_virtual_time + seconds);
    }

    virtual void Pause(void) override
    {
        m_paused = true;
        if(m_logger != NULL)
            m_logger.Debug("ReplayClock", "Paused");
    }

    virtual void Resume(void) override
    {
        m_paused = false;
        if(m_logger != NULL)
            m_logger.Debug("ReplayClock", "Resumed");
    }

    virtual void ScaleSpeed(const int speed_code) override
    {
        m_speed = speed_code;
        if(m_logger != NULL)
            m_logger.Debug("ReplayClock", "Speed set to " + IntegerToString(speed_code));
    }

    virtual bool IsPaused(void) const override { return m_paused; }
    virtual int GetSpeed(void) const override { return m_speed; }

    /**
     * @brief Get the delay (in ms) between the previous and current event,
     *        scaled by the current speed.
     */
    int GetScaledDelayMs(const datetime prev_ts, const datetime curr_ts) const
    {
        if(m_paused) return 0;
        if(m_speed == ATLAS_REPLAY_MAX) return 0;
        if(m_speed == ATLAS_REPLAY_STEP) return 0;

        long delta_sec = (long)curr_ts - (long)prev_ts;
        if(delta_sec <= 0) return 0;

        long delay_ms = delta_sec * 1000;

        switch(m_speed)
        {
            case ATLAS_REPLAY_10X:  delay_ms /= 10;  break;
            case ATLAS_REPLAY_100X: delay_ms /= 100; break;
            case ATLAS_REPLAY_1X:   break;
        }

        if(delay_ms > 5000) delay_ms = 5000;  ///< Cap at 5 seconds
        return (int)delay_ms;
    }

    /**
     * @brief Get synchronization drift (virtual time elapsed vs real time elapsed).
     */
    double GetDriftMs(void) const
    {
        if(m_real_start_ms == 0) return 0.0;
        ulong real_elapsed_ms = GetTickCount64() - m_real_start_ms;
        long virtual_elapsed_sec = (long)m_virtual_time - (long)m_virtual_start;
        double virtual_elapsed_ms = (double)virtual_elapsed_sec * 1000.0;
        return virtual_elapsed_ms - (double)real_elapsed_ms;
    }

    /**
     * @brief Reset the clock.
     */
    void Reset(void)
    {
        m_virtual_time  = 0;
        m_real_start_ms = 0;
        m_virtual_start = 0;
        m_paused        = false;
        m_speed         = ATLAS_REPLAY_MAX;
    }
};

#endif // ATLAS_REPLAY_CLOCK_MQH
//+------------------------------------------------------------------+
