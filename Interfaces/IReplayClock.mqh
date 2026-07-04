//+------------------------------------------------------------------+
//|                    Interfaces/IReplayClock.mqh                  |
//|       AtlasEA v0.1.23.0 - Virtual Replay Clock Interface        |
//+------------------------------------------------------------------+
#ifndef ATLAS_IREPLAY_CLOCK_MQH
#define ATLAS_IREPLAY_CLOCK_MQH

#include "../Config/Settings.mqh"

/**
 * @class IReplayClock
 * @brief Virtual clock for deterministic replay.
 *
 * During replay, this clock replaces the system clock.
 * It advances based on replayed event timestamps, not real time.
 *
 * CoreEngine queries this clock instead of TimeCurrent() during replay.
 */
class IReplayClock
{
public:
    /// @brief Get the current virtual time.
    virtual datetime Now(void) const = 0;

    /// @brief Get the current virtual time in milliseconds.
    virtual ulong NowMs(void) const = 0;

    /// @brief Advance the clock to a specific time.
    virtual void AdvanceTo(const datetime target) = 0;

    /// @brief Advance the clock by a delta.
    virtual void AdvanceBy(const long seconds) = 0;

    /// @brief Pause the clock.
    virtual void Pause(void) = 0;

    /// @brief Resume the clock.
    virtual void Resume(void) = 0;

    /// @brief Scale the replay speed.
    virtual void ScaleSpeed(const int speed_code) = 0;

    /// @brief Is the clock paused?
    virtual bool IsPaused(void) const = 0;

    /// @brief Get the replay speed.
    virtual int GetSpeed(void) const = 0;

    virtual ~IReplayClock(void) {}
};

#endif // ATLAS_IREPLAY_CLOCK_MQH
//+------------------------------------------------------------------+
