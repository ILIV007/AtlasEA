//+------------------------------------------------------------------+
//|                                        Interfaces/IContextStore.mqh
//|                          AtlasEA v2.0 - Context Store Interface   |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONTEXT_STORE_MQH
#define ATLAS_ICONTEXT_STORE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Single read+write interface for the shared mutable context.
 *
 * Implemented by AtlasContext (Core). Consumed by engines and infra modules
 * so they depend on Interfaces/ rather than Core/.
 *
 * Design decision: one fat interface instead of 5 narrow ones (pragmatic MQL5 approach).
 * ContextGuardian enforces single-writer at runtime; this interface exposes the full surface.
 */
class IContextStore
{
public:
    //--- Identity / time ---
    virtual long     GetSnapshotId(void) const = 0;
    virtual void     SetSnapshotId(long id) = 0;
    virtual datetime GetTickTime(void) const = 0;
    virtual void     SetTickTime(datetime t) = 0;

    //--- Daily risk stats ---
    virtual double   GetDailyStartEquity(void) const = 0;
    virtual void     SetDailyStartEquity(double v) = 0;
    virtual double   GetDailyPeakEquity(void) const = 0;
    virtual void     UpdateDailyPeakEquity(double v) = 0;
    virtual double   GetDailyDrawdownPct(void) const = 0;
    virtual void     SetDailyDrawdownPct(double v) = 0;
    virtual double   GetDailyRealizedPnl(void) const = 0;
    virtual void     SetDailyRealizedPnl(double v) = 0;
    virtual int      GetDailyTradeCount(void) const = 0;
    virtual void     IncrementDailyTradeCount(void) = 0;
    virtual int      GetDailyLossCount(void) const = 0;
    virtual void     IncrementDailyLossCount(void) = 0;
    virtual datetime GetTradingDayStart(void) const = 0;
    virtual void     SetTradingDayStart(datetime t) = 0;

    //--- Exposure ---
    virtual double   GetCurrentExposurePct(void) const = 0;
    virtual void     SetCurrentExposurePct(double v) = 0;
    virtual double   GetTotalFloatingPnl(void) const = 0;
    virtual void     SetTotalFloatingPnl(double v) = 0;

    //--- Kill switch ---
    virtual bool     IsKillSwitchActive(void) const = 0;
    virtual string   GetKillSwitchReason(void) const = 0;
    virtual datetime GetKillSwitchTime(void) const = 0;
    virtual void     ActivateKillSwitch(const string reason) = 0;
    virtual void     DeactivateKillSwitch(void) = 0;

    //--- Risk state ---
    virtual int      GetConsecutiveLosses(void) const = 0;
    virtual void     SetConsecutiveLosses(int v) = 0;
    virtual datetime GetLastTradeTime(void) const = 0;
    virtual void     SetLastTradeTime(datetime t) = 0;
    virtual datetime GetCooldownUntil(void) const = 0;
    virtual void     SetCooldownUntil(datetime t) = 0;

    //--- Position mirror ---
    virtual int      GetPositionCount(void) const = 0;
    virtual void     GetPosition(const int index, PositionState &out) const = 0;
    virtual void     SetPositions(const PositionState &src[], const int count) = 0;
    virtual void     ClearPositions(void) = 0;

    //--- Idempotency ---
    virtual bool     IsDecisionProcessed(const string decision_id) const = 0;
    virtual void     MarkDecisionProcessed(const string decision_id) = 0;

    //--- Telemetry ---
    virtual ulong    GetTotalTicksProcessed(void) const = 0;
    virtual void     IncrementTicksProcessed(void) = 0;
    virtual ulong    GetTotalEventsEmitted(void) const = 0;
    virtual void     IncrementEventsEmitted(void) = 0;
    virtual ulong    GetTotalOrdersSent(void) const = 0;
    virtual void     IncrementOrdersSent(void) = 0;
    virtual ulong    GetTotalOrdersFilled(void) const = 0;
    virtual void     IncrementOrdersFilled(void) = 0;

    //--- Context versioning ---
    virtual ulong    GetContextVersion(void) const = 0;
    virtual void     IncrementContextVersion(void) = 0;

    //--- Reset ---
    virtual void     ResetDaily(void) = 0;
    virtual void     ResetAll(void) = 0;

    virtual ~IContextStore(void) {}
};

#endif // ATLAS_ICONTEXT_STORE_MQH
//+------------------------------------------------------------------+
