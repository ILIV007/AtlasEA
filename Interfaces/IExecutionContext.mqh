//+------------------------------------------------------------------+
//|                   Interfaces/IExecutionContext.mqh              |
//|       AtlasEA v0.1.24.0 - Execution Context Interface           |
//+------------------------------------------------------------------+
#ifndef ATLAS_IEXECUTION_CONTEXT_MQH
#define ATLAS_IEXECUTION_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Execution mode codes.
 */
#define ATLAS_EXEC_MODE_LIVE    0
#define ATLAS_EXEC_MODE_REPLAY  1
#define ATLAS_EXEC_MODE_BACKTEST 2

/**
 * @class IExecutionContext
 * @brief Abstraction layer for execution mode.
 *
 * CoreEngine consumes this interface — it does NOT know whether
 * the system is running in Live mode, Replay mode, or Backtest mode.
 *
 * LiveContext:
 *   - Captures real ticks from broker
 *   - Uses system clock (TimeCurrent)
 *   - Sends real orders
 *
 * ReplayContext:
 *   - Delivers events from ReplayEngine
 *   - Uses virtual clock (ReplayClock)
 *   - Does NOT send orders (replay is read-only)
 *
 * This abstraction enables:
 *   - Time Travel Debugging (replay past sessions)
 *   - Backtesting (replay historical data)
 *   - Regression Testing (replay + compare)
 *   - AI Dataset Generation (replay + record)
 */
class IExecutionContext
{
public:
    /// @brief Get the current execution mode.
    virtual int GetMode(void) const = 0;

    /// @brief Get the current virtual time (from clock).
    virtual datetime GetCurrentTime(void) const = 0;

    /// @brief Is this a live execution?
    virtual bool IsLive(void) const = 0;

    /// @brief Is this a replay execution?
    virtual bool IsReplay(void) const = 0;

    /// @brief Are orders allowed in this context?
    virtual bool CanSendOrders(void) const = 0;

    /// @brief Get a human-readable mode name.
    virtual string GetModeName(void) const = 0;

    virtual ~IExecutionContext(void) {}
};

#endif // ATLAS_IEXECUTION_CONTEXT_MQH
//+------------------------------------------------------------------+
