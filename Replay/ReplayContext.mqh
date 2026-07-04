//+------------------------------------------------------------------+
//|                    Replay/ReplayContext.mqh                     |
//|       AtlasEA v0.1.24.0 - Replay Execution Context              |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_CONTEXT_MQH
#define ATLAS_REPLAY_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IExecutionContext.mqh"
#include "../Interfaces/IReplayClock.mqh"
#include "ReplayClock.mqh"

/**
 * @class ReplayContext
 * @brief Replay execution context — deterministic event playback.
 *
 * - Uses virtual clock (ReplayClock) instead of system clock
 * - Orders are NOT allowed (replay is read-only)
 * - Events come from ReplayEngine, not from the broker
 *
 * CoreEngine receives this context and queries GetCurrentTime()
 * instead of calling TimeCurrent() directly.
 */
class ReplayContext : public IExecutionContext
{
private:
    ReplayClock *m_clock;

public:
    /**
     * @brief Constructor.
     * @param clock Pointer to the replay clock (must outlive this context).
     */
    ReplayContext(ReplayClock *clock = NULL)
    {
        m_clock = clock;
    }

    /**
     * @brief Set the replay clock.
     */
    void SetClock(ReplayClock *clock) { m_clock = clock; }

    virtual int GetMode(void) const override { return ATLAS_EXEC_MODE_REPLAY; }

    virtual datetime GetCurrentTime(void) const override
    {
        if(m_clock != NULL)
            return m_clock.Now();
        return TimeCurrent();  //--- Fallback to system clock
    }

    virtual bool IsLive(void) const override { return false; }
    virtual bool IsReplay(void) const override { return true; }
    virtual bool CanSendOrders(void) const override { return false; }  //--- Replay is read-only
    virtual string GetModeName(void) const override { return "Replay"; }
};

#endif // ATLAS_REPLAY_CONTEXT_MQH
//+------------------------------------------------------------------+
