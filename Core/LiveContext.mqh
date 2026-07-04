//+------------------------------------------------------------------+
//|                      Core/LiveContext.mqh                       |
//|       AtlasEA v0.1.24.0 - Live Execution Context                |
//+------------------------------------------------------------------+
#ifndef ATLAS_LIVE_CONTEXT_MQH
#define ATLAS_LIVE_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IExecutionContext.mqh"

/**
 * @class LiveContext
 * @brief Live execution context — real-time trading.
 *
 * - Uses system clock (TimeCurrent)
 * - Orders are allowed
 * - Ticks come from the broker
 *
 * This is the default context for production trading.
 */
class LiveContext : public IExecutionContext
{
public:
    virtual int GetMode(void) const override { return ATLAS_EXEC_MODE_LIVE; }
    virtual datetime GetCurrentTime(void) const override { return TimeCurrent(); }
    virtual bool IsLive(void) const override { return true; }
    virtual bool IsReplay(void) const override { return false; }
    virtual bool CanSendOrders(void) const override { return true; }
    virtual string GetModeName(void) const override { return "Live"; }
};

#endif // ATLAS_LIVE_CONTEXT_MQH
//+------------------------------------------------------------------+
