//+------------------------------------------------------------------+
//|                                           Core/AtlasContext.mqh
//|                  AtlasEA v2.0 - Shared Mutable Context State      |
//+------------------------------------------------------------------+
#ifndef ATLAS_ATLAS_CONTEXT_MQH
#define ATLAS_ATLAS_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IContextStore.mqh"

/**
 * @class AtlasContext
 * @brief The single mutable shared state of the EA.
 *
 * Implements IContextStore so engines and infra modules depend on the
 * interface (Interfaces/) rather than this concrete class (Core/).
 *
 * All writes go through ContextGuardian (single-writer rule).
 * The context has a version counter that increments on every mutation,
 * enabling optimistic concurrency checks and snapshot correlation.
 *
 * Memory: all arrays are fixed-size (no dynamic allocation).
 * Thread safety: MQL5 single-threaded — no locks needed.
 */
class AtlasContext : public IContextStore
{
private:
    //--- Identity / time
    long     m_snapshot_id;
    datetime m_tick_time;
    datetime m_trading_day_start;

    //--- Daily risk stats
    double   m_daily_start_equity;
    double   m_daily_peak_equity;
    double   m_daily_drawdown_pct;
    double   m_daily_realized_pnl;
    int      m_daily_trade_count;
    int      m_daily_loss_count;

    //--- Exposure
    double   m_current_exposure_pct;
    double   m_total_floating_pnl;

    //--- Kill switch (non-bypassable once triggered)
    bool     m_kill_switch_active;
    string   m_kill_switch_reason;
    datetime m_kill_switch_time;

    //--- Risk state
    int      m_consecutive_losses;
    datetime m_last_trade_time;
    datetime m_cooldown_until;

    //--- Position mirror
    PositionState m_positions[ATLAS_MAX_POSITIONS];
    int           m_position_count;

    //--- Telemetry
    ulong    m_total_ticks_processed;
    ulong    m_total_events_emitted;
    ulong    m_total_orders_sent;
    ulong    m_total_orders_filled;

    //--- Context versioning
    ulong    m_context_version;

    //--- Idempotency ring (decision_id dedup)
    string   m_processed_decisions[ATLAS_IDEMPOTENCY_SLOTS];
    int      m_processed_count;

public:
    /**
     * @brief Constructor — initializes all fields to safe defaults.
     */
    AtlasContext(void);

    /**
     * @brief Destructor — no dynamic resources to release.
     */
    ~AtlasContext(void) {}

    //=== IContextStore implementation ===

    //--- Identity / time ---
    virtual long     GetSnapshotId(void) const override { return m_snapshot_id; }
    virtual void     SetSnapshotId(long id) override { m_snapshot_id = id; IncrementContextVersion(); }
    virtual datetime GetTickTime(void) const override { return m_tick_time; }
    virtual void     SetTickTime(datetime t) override { m_tick_time = t; }

    //--- Daily risk stats ---
    virtual double   GetDailyStartEquity(void) const override { return m_daily_start_equity; }
    virtual void     SetDailyStartEquity(double v) override { m_daily_start_equity = v; IncrementContextVersion(); }
    virtual double   GetDailyPeakEquity(void) const override { return m_daily_peak_equity; }
    virtual void     UpdateDailyPeakEquity(double v) override { if(v > m_daily_peak_equity) { m_daily_peak_equity = v; IncrementContextVersion(); } }
    virtual double   GetDailyDrawdownPct(void) const override { return m_daily_drawdown_pct; }
    virtual void     SetDailyDrawdownPct(double v) override { m_daily_drawdown_pct = v; IncrementContextVersion(); }
    virtual double   GetDailyRealizedPnl(void) const override { return m_daily_realized_pnl; }
    virtual void     SetDailyRealizedPnl(double v) override { m_daily_realized_pnl = v; IncrementContextVersion(); }
    virtual int      GetDailyTradeCount(void) const override { return m_daily_trade_count; }
    virtual void     IncrementDailyTradeCount(void) override { m_daily_trade_count++; IncrementContextVersion(); }
    virtual int      GetDailyLossCount(void) const override { return m_daily_loss_count; }
    virtual void     IncrementDailyLossCount(void) override { m_daily_loss_count++; IncrementContextVersion(); }
    virtual datetime GetTradingDayStart(void) const override { return m_trading_day_start; }
    virtual void     SetTradingDayStart(datetime t) override { m_trading_day_start = t; IncrementContextVersion(); }

    //--- Exposure ---
    virtual double   GetCurrentExposurePct(void) const override { return m_current_exposure_pct; }
    virtual void     SetCurrentExposurePct(double v) override { m_current_exposure_pct = v; IncrementContextVersion(); }
    virtual double   GetTotalFloatingPnl(void) const override { return m_total_floating_pnl; }
    virtual void     SetTotalFloatingPnl(double v) override { m_total_floating_pnl = v; IncrementContextVersion(); }

    //--- Kill switch ---
    virtual bool     IsKillSwitchActive(void) const override { return m_kill_switch_active; }
    virtual string   GetKillSwitchReason(void) const override { return m_kill_switch_reason; }
    virtual datetime GetKillSwitchTime(void) const override { return m_kill_switch_time; }
    virtual void     ActivateKillSwitch(const string reason) override;
    virtual void     DeactivateKillSwitch(void) override;

    //--- Risk state ---
    virtual int      GetConsecutiveLosses(void) const override { return m_consecutive_losses; }
    virtual void     SetConsecutiveLosses(int v) override { m_consecutive_losses = v; IncrementContextVersion(); }
    virtual datetime GetLastTradeTime(void) const override { return m_last_trade_time; }
    virtual void     SetLastTradeTime(datetime t) override { m_last_trade_time = t; IncrementContextVersion(); }
    virtual datetime GetCooldownUntil(void) const override { return m_cooldown_until; }
    virtual void     SetCooldownUntil(datetime t) override { m_cooldown_until = t; IncrementContextVersion(); }

    //--- Position mirror ---
    virtual int      GetPositionCount(void) const override { return m_position_count; }
    virtual void     GetPosition(const int index, PositionState &out) const override;
    virtual void     SetPositions(const PositionState &src[], const int count) override;
    virtual void     ClearPositions(void) override { m_position_count = 0; IncrementContextVersion(); }

    //--- Idempotency ---
    virtual bool     IsDecisionProcessed(const string decision_id) const override;
    virtual void     MarkDecisionProcessed(const string decision_id) override;

    //--- Telemetry ---
    virtual ulong    GetTotalTicksProcessed(void) const override { return m_total_ticks_processed; }
    virtual void     IncrementTicksProcessed(void) override { m_total_ticks_processed++; }
    virtual ulong    GetTotalEventsEmitted(void) const override { return m_total_events_emitted; }
    virtual void     IncrementEventsEmitted(void) override { m_total_events_emitted++; }
    virtual ulong    GetTotalOrdersSent(void) const override { return m_total_orders_sent; }
    virtual void     IncrementOrdersSent(void) override { m_total_orders_sent++; IncrementContextVersion(); }
    virtual ulong    GetTotalOrdersFilled(void) const override { return m_total_orders_filled; }
    virtual void     IncrementOrdersFilled(void) override { m_total_orders_filled++; IncrementContextVersion(); }

    //--- Context versioning ---
    virtual ulong    GetContextVersion(void) const override { return m_context_version; }
    virtual void     IncrementContextVersion(void) override { m_context_version++; }

    //--- Reset ---
    virtual void     ResetDaily(void) override;
    virtual void     ResetAll(void) override;
};

//+------------------------------------------------------------------+
//| AtlasContext implementation                                      |
//+------------------------------------------------------------------+

AtlasContext::AtlasContext(void)
{
    m_snapshot_id           = 0;
    m_tick_time             = 0;
    m_trading_day_start     = 0;

    m_daily_start_equity    = 0.0;
    m_daily_peak_equity     = 0.0;
    m_daily_drawdown_pct    = 0.0;
    m_daily_realized_pnl    = 0.0;
    m_daily_trade_count     = 0;
    m_daily_loss_count      = 0;

    m_current_exposure_pct  = 0.0;
    m_total_floating_pnl    = 0.0;

    m_kill_switch_active    = false;
    m_kill_switch_reason    = "";
    m_kill_switch_time      = 0;

    m_consecutive_losses    = 0;
    m_last_trade_time       = 0;
    m_cooldown_until        = 0;

    m_position_count        = 0;

    m_total_ticks_processed = 0;
    m_total_events_emitted  = 0;
    m_total_orders_sent     = 0;
    m_total_orders_filled   = 0;

    m_context_version       = 0;
    m_processed_count       = 0;
}

//+------------------------------------------------------------------+
void AtlasContext::ActivateKillSwitch(const string reason)
{
    if(m_kill_switch_active) return;
    m_kill_switch_active = true;
    m_kill_switch_reason = reason;
    m_kill_switch_time   = TimeCurrent();
    IncrementContextVersion();
}

//+------------------------------------------------------------------+
void AtlasContext::DeactivateKillSwitch(void)
{
    m_kill_switch_active = false;
    m_kill_switch_reason = "";
    m_kill_switch_time   = 0;
    IncrementContextVersion();
}

//+------------------------------------------------------------------+
void AtlasContext::GetPosition(const int index, PositionState &out) const
{
    if(index < 0 || index >= m_position_count)
    {
        ZeroMemory(out);
        return;
    }
    out = m_positions[index];
}

//+------------------------------------------------------------------+
void AtlasContext::SetPositions(const PositionState &src[], const int count)
{
    int n = count;
    if(n > ATLAS_MAX_POSITIONS) n = ATLAS_MAX_POSITIONS;
    m_position_count = n;
    for(int i = 0; i < n; i++)
        m_positions[i] = src[i];
    IncrementContextVersion();
}

//+------------------------------------------------------------------+
bool AtlasContext::IsDecisionProcessed(const string decision_id) const
{
    for(int i = 0; i < m_processed_count; i++)
    {
        if(m_processed_decisions[i] == decision_id)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
void AtlasContext::MarkDecisionProcessed(const string decision_id)
{
    if(IsDecisionProcessed(decision_id))
        return;

    //--- FIFO eviction when ring is full
    if(m_processed_count >= ATLAS_IDEMPOTENCY_SLOTS)
    {
        for(int i = 1; i < ATLAS_IDEMPOTENCY_SLOTS; i++)
            m_processed_decisions[i-1] = m_processed_decisions[i];
        m_processed_count = ATLAS_IDEMPOTENCY_SLOTS - 1;
    }

    m_processed_decisions[m_processed_count] = decision_id;
    m_processed_count++;
    IncrementContextVersion();
}

//+------------------------------------------------------------------+
void AtlasContext::ResetDaily(void)
{
    //--- NOTE: equity must be set by the caller via SetDailyStartEquity()
    //--- and UpdateDailyPeakEquity() after calling this method.
    //--- Core does NOT call AccountInfoDouble directly (layering rule).
    m_daily_start_equity    = 0.0;
    m_daily_peak_equity     = 0.0;
    m_daily_drawdown_pct    = 0.0;
    m_daily_realized_pnl    = 0.0;
    m_daily_trade_count     = 0;
    m_daily_loss_count      = 0;
    m_trading_day_start     = TimeCurrent();
    m_consecutive_losses    = 0;
    m_cooldown_until        = 0;
    IncrementContextVersion();
}

//+------------------------------------------------------------------+
void AtlasContext::ResetAll(void)
{
    m_snapshot_id           = 0;
    m_tick_time             = 0;
    m_trading_day_start     = 0;

    m_daily_start_equity    = 0.0;
    m_daily_peak_equity     = 0.0;
    m_daily_drawdown_pct    = 0.0;
    m_daily_realized_pnl    = 0.0;
    m_daily_trade_count     = 0;
    m_daily_loss_count      = 0;

    m_current_exposure_pct  = 0.0;
    m_total_floating_pnl    = 0.0;

    m_kill_switch_active    = false;
    m_kill_switch_reason    = "";
    m_kill_switch_time      = 0;

    m_consecutive_losses    = 0;
    m_last_trade_time       = 0;
    m_cooldown_until        = 0;

    m_position_count        = 0;

    m_total_ticks_processed = 0;
    m_total_events_emitted  = 0;
    m_total_orders_sent     = 0;
    m_total_orders_filled   = 0;

    m_context_version       = 0;
    m_processed_count       = 0;
}

#endif // ATLAS_ATLAS_CONTEXT_MQH
//+------------------------------------------------------------------+
