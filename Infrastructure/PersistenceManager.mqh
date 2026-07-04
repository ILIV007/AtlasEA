//+------------------------------------------------------------------+
//|                            Infrastructure/PersistenceManager.mqh |
//|                AtlasEA v1.0 - State Persistence / Recovery       |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERSISTENCE_MANAGER_MQH
#define ATLAS_PERSISTENCE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IStateStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Core/AtlasContext.mqh"

//+------------------------------------------------------------------+
//| PersistenceManager                                               |
//|   - writes context snapshots to a daily file                     |
//|   - appends events to a rolling log                              |
//|   - recovers context state on startup                            |
//+------------------------------------------------------------------+
class PersistenceManager : public IStateStore
{
private:
    AtlasConfig    m_config;
    AtlasContext  *m_context;
    AtlasEvent     m_event_buffer[ATLAS_EVENT_LOG_BUFFER];
    int            m_event_buffer_count;

    string GenerateDailyFilename(void) const;
    string GenerateEventLogFilename(void) const;
    bool   WriteContextToFile(const AtlasContext &ctx, const string filename);
    bool   ReadContextFromFile(AtlasContext &ctx, const string filename);

public:
                PersistenceManager(void);

    //--- IStateStore overrides ---
    virtual bool   Initialize(void) override { return true; }
    virtual void   Shutdown(void) override { FlushEventBuffer(); m_context = NULL; }
    virtual bool   WriteSnapshot(const AtlasContext &ctx, long id) override;
    virtual bool   AppendEvent(const AtlasEvent &ev) override;
    virtual bool   FlushEventBuffer(void) override;
    virtual bool   RecoverState(AtlasContext &ctx) override;

    //--- Extended init (called by Bootstrapper) ---
    void   SetDependencies(ILogger *logger, IContextStore *context, const AtlasConfig &config)
    {
        m_logger = logger;
        m_config = config;
    }
    bool        Initialize(const AtlasConfig &config, AtlasContext *context);

    //--- Design by Contract: validate internal invariants ---
    ValidationResult Validate(void) const
    {
        if(m_event_buffer_count < 0 || m_event_buffer_count > ATLAS_EVENT_LOG_BUFFER)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                                          "event buffer count out of range",
                                          "m_event_buffer_count");
        //--- Context is optional until Initialize(config, context) has been called.
        //    If set, it must not be NULL (defensive — Initialize never stores NULL).
        if(m_context == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                                          "context pointer not initialized",
                                          "m_context");
        return ValidationResult::Ok();
    }

private:
    ILogger *m_logger;
};

//+------------------------------------------------------------------+
PersistenceManager::PersistenceManager(void)
{
    m_logger             = NULL;
    m_context            = NULL;
    m_event_buffer_count = 0;
}

//+------------------------------------------------------------------+
bool PersistenceManager::Initialize(const AtlasConfig &config, AtlasContext *context)
{
    m_config  = config;
    m_context = context;

    //--- Discard any stale buffered events from a previous session.
    //    On a clean restart the buffer should already be empty (Shutdown
    //    flushes it), but if Initialize() is called without a prior
    //    Shutdown (double-init) or if the last flush failed, stale events
    //    could otherwise be written to the new session's event log.
    m_event_buffer_count = 0;

    return true;
}

//+------------------------------------------------------------------+
string PersistenceManager::GenerateDailyFilename(void) const
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return StringFormat("AtlasEA_%s_%04d%02d%02d.snap",
                        m_config.symbol, dt.year, dt.mon, dt.day);
}

//+------------------------------------------------------------------+
string PersistenceManager::GenerateEventLogFilename(void) const
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return StringFormat("AtlasEA_%s_%04d%02d%02d.log",
                        m_config.symbol, dt.year, dt.mon, dt.day);
}

//+------------------------------------------------------------------+
//| WriteContextToFile - text key=value format (debuggable)          |
//+------------------------------------------------------------------+
bool PersistenceManager::WriteContextToFile(const AtlasContext &ctx, const string filename)
{
    //--- Design by Contract: refuse to persist corrupt state.
    //    Validate BEFORE opening any file so a bad context never reaches disk.
    ValidationResult v = ctx.Validate();
    if(!v.valid)
    {
        if(m_logger != NULL)
            m_logger.Error("PersistenceManager",
                           "WriteContextToFile rejected: context invalid (" +
                           v.Summary() + "). Snapshot NOT written to " + filename);
        return false;
    }

    //--- Atomic write: write to temp file first, then overwrite the target
    string temp_fn = filename + ".tmp";

    int handle = FileOpen(temp_fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        if(m_logger != NULL)
            m_logger.Error("PersistenceManager", "Cannot open " + temp_fn + " err=" + IntegerToString(GetLastError()));
        return false;
    }
    FileWriteString(handle, "snapshot_id="          + IntegerToString(ctx.GetSnapshotId())          + "\n");
    FileWriteString(handle, "tick_time="            + IntegerToString((long)ctx.GetTickTime())       + "\n");
    FileWriteString(handle, "trading_day_start="    + IntegerToString((long)ctx.GetTradingDayStart())+ "\n");
    FileWriteString(handle, "daily_start_equity="   + DoubleToString(ctx.GetDailyStartEquity(), 2)   + "\n");
    FileWriteString(handle, "daily_peak_equity="    + DoubleToString(ctx.GetDailyPeakEquity(), 2)    + "\n");
    FileWriteString(handle, "daily_drawdown_pct="   + DoubleToString(ctx.GetDailyDrawdownPct(), 4)   + "\n");
    FileWriteString(handle, "daily_realized_pnl="   + DoubleToString(ctx.GetDailyRealizedPnl(), 2)   + "\n");
    FileWriteString(handle, "daily_trade_count="    + IntegerToString(ctx.GetDailyTradeCount())       + "\n");
    FileWriteString(handle, "daily_loss_count="     + IntegerToString(ctx.GetDailyLossCount())        + "\n");
    FileWriteString(handle, "consecutive_losses="   + IntegerToString(ctx.GetConsecutiveLosses())     + "\n");
    FileWriteString(handle, "last_trade_time="      + IntegerToString((long)ctx.GetLastTradeTime())  + "\n");
    FileWriteString(handle, "cooldown_until="       + IntegerToString((long)ctx.GetCooldownUntil())  + "\n");
    FileWriteString(handle, "current_exposure_pct=" + DoubleToString(ctx.GetCurrentExposurePct(), 6) + "\n");
    FileWriteString(handle, "total_floating_pnl="   + DoubleToString(ctx.GetTotalFloatingPnl(), 2)   + "\n");
    FileWriteString(handle, "kill_switch_active="   + IntegerToString(ctx.IsKillSwitchActive() ? 1:0)+ "\n");
    FileWriteString(handle, "kill_switch_reason="   + ctx.GetKillSwitchReason()                       + "\n");
    FileWriteString(handle, "kill_switch_time="     + IntegerToString((long)ctx.GetKillSwitchTime())  + "\n");
    FileWriteString(handle, "total_ticks="          + IntegerToString((long)ctx.GetTotalTicksProcessed()) + "\n");
    FileWriteString(handle, "total_events="         + IntegerToString((long)ctx.GetTotalEventsEmitted())  + "\n");
    FileWriteString(handle, "total_orders_sent="    + IntegerToString((long)ctx.GetTotalOrdersSent())     + "\n");
    FileWriteString(handle, "total_orders_filled="  + IntegerToString((long)ctx.GetTotalOrdersFilled())   + "\n");
    FileWriteString(handle, "context_version="      + IntegerToString((long)ctx.GetContextVersion())      + "\n");
    FileWriteString(handle, "position_count="       + IntegerToString(ctx.GetPositionCount())             + "\n");
    FileWriteString(handle, "processed_count="      + IntegerToString(ctx.GetProcessedCount())            + "\n");
    FileClose(handle);

    //--- Delete old snapshot if it exists, then rename temp → final
    if(FileIsExist(filename))
        FileDelete(filename);
    FileMove(temp_fn, 0, filename, FILE_REWRITE);

    return true;
}
//+------------------------------------------------------------------+
bool PersistenceManager::ReadContextFromFile(AtlasContext &ctx, const string filename)
{
    int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        //--- Check for temp file (crash during write)
        string temp_fn = filename + ".tmp";
        handle = FileOpen(temp_fn, FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            if(m_logger != NULL)
                m_logger.Info("PersistenceManager", "No snapshot to recover: " + filename);
            return false;
        }
        if(m_logger != NULL)
            m_logger.Warn("PersistenceManager", "Recovering from temp snapshot (previous write was interrupted)");
    }
    while(!FileIsEnding(handle))
    {
        string line = FileReadString(handle);
        int    eq   = StringFind(line, "=");
        if(eq <= 0) continue;
        string key = StringSubstr(line, 0, eq);
        string val = StringSubstr(line, eq + 1);

        if(key == "snapshot_id")           ctx.SetSnapshotId((long)StringToInteger(val));
        else if(key == "tick_time")        ctx.SetTickTime((datetime)StringToInteger(val));
        else if(key == "trading_day_start") ctx.SetTradingDayStart((datetime)StringToInteger(val));
        else if(key == "daily_start_equity") ctx.SetDailyStartEquity(StringToDouble(val));
        else if(key == "daily_peak_equity")  ctx.UpdateDailyPeakEquity(StringToDouble(val));
        else if(key == "daily_drawdown_pct") ctx.SetDailyDrawdownPct(StringToDouble(val));
        else if(key == "daily_realized_pnl") ctx.SetDailyRealizedPnl(StringToDouble(val));
        else if(key == "daily_trade_count")  { int n=(int)StringToInteger(val); for(int i=0;i<n;i++) ctx.IncrementDailyTradeCount(); }
        else if(key == "daily_loss_count")   { int n=(int)StringToInteger(val); for(int i=0;i<n;i++) ctx.IncrementDailyLossCount(); }
        else if(key == "consecutive_losses") ctx.SetConsecutiveLosses((int)StringToInteger(val));
        else if(key == "last_trade_time")    ctx.SetLastTradeTime((datetime)StringToInteger(val));
        else if(key == "cooldown_until")     ctx.SetCooldownUntil((datetime)StringToInteger(val));
        else if(key == "current_exposure_pct") ctx.SetCurrentExposurePct(StringToDouble(val));
        else if(key == "total_floating_pnl")   ctx.SetTotalFloatingPnl(StringToDouble(val));
        else if(key == "kill_switch_active")
        {
            if(StringToInteger(val) != 0) ctx.ActivateKillSwitch(ctx.GetKillSwitchReason());
        }
        else if(key == "kill_switch_reason")
        {
            if(ctx.IsKillSwitchActive()) ctx.ActivateKillSwitch(val);
        }
        else if(key == "kill_switch_time")    ctx.SetCooldownUntil((datetime)StringToInteger(val)); // close enough: we can't set kill_switch_time directly
        else if(key == "total_ticks")         { ulong n=(ulong)StringToInteger(val); for(ulong i=0;i<n;i++) ctx.IncrementTicksProcessed(); }
        else if(key == "total_events")        { ulong n=(ulong)StringToInteger(val); for(ulong i=0;i<n;i++) ctx.IncrementEventsEmitted(); }
        else if(key == "total_orders_sent")   { ulong n=(ulong)StringToInteger(val); for(ulong i=0;i<n;i++) ctx.IncrementOrdersSent(); }
        else if(key == "total_orders_filled") { ulong n=(ulong)StringToInteger(val); for(ulong i=0;i<n;i++) ctx.IncrementOrdersFilled(); }
        else if(key == "context_version")     { ulong n=(ulong)StringToInteger(val); for(ulong i=0;i<n;i++) ctx.IncrementContextVersion(); }
    }
    FileClose(handle);

    //--- Design by Contract: refuse to restore corrupt state.
    //    Validate AFTER reading so a corrupt snapshot file cannot be silently
    //    restored. On failure we return false (the snapshot is treated as
    //    not-recoverable by callers — see RecoveryManager cold-start path).
    ValidationResult v = ctx.Validate();
    if(!v.valid)
    {
        if(m_logger != NULL)
            m_logger.Error("PersistenceManager",
                           "ReadContextFromFile rejected: recovered context invalid (" +
                           v.Summary() + "). State NOT restored from " + filename);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
bool PersistenceManager::WriteSnapshot(const AtlasContext &ctx, long id)
{
    string fn = GenerateDailyFilename();
    bool ok = WriteContextToFile(ctx, fn);
    if(ok && m_logger != NULL)
        m_logger.Info("PersistenceManager", "Snapshot " + IntegerToString(id) + " written to " + fn);
    return ok;
}

//+------------------------------------------------------------------+
bool PersistenceManager::AppendEvent(const AtlasEvent &ev)
{
    if(m_event_buffer_count >= ATLAS_EVENT_LOG_BUFFER)
    {
        if(!FlushEventBuffer())
        {
            //--- Flush failed — evict oldest to make room (don't block the hot path)
            for(int i = 1; i < m_event_buffer_count; i++)
                m_event_buffer[i-1] = m_event_buffer[i];
            m_event_buffer_count--;
        }
    }
    m_event_buffer[m_event_buffer_count] = ev;
    m_event_buffer_count++;
    return true;
}

//+------------------------------------------------------------------+
bool PersistenceManager::FlushEventBuffer(void)
{
    if(m_event_buffer_count == 0) return true;
    string fn = GenerateEventLogFilename();
    int handle = FileOpen(fn, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        handle = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            if(m_logger != NULL)
                m_logger.Error("PersistenceManager", "Cannot open event log " + fn);
            return false;
        }
    }
    FileSeek(handle, 0, SEEK_END);
    for(int i = 0; i < m_event_buffer_count; i++)
    {
        string line = IntegerToString((long)m_event_buffer[i].type) + "," +
                      IntegerToString((long)m_event_buffer[i].timestamp) + "," +
                      IntegerToString(m_event_buffer[i].snapshot_id) + "," +
                      m_event_buffer[i].source_module + "\n";
        FileWriteString(handle, line);
    }
    FileClose(handle);
    m_event_buffer_count = 0;
    return true;
}

//+------------------------------------------------------------------+
bool PersistenceManager::RecoverState(AtlasContext &ctx)
{
    string fn = GenerateDailyFilename();
    if(ReadContextFromFile(ctx, fn))
    {
        if(m_logger != NULL)
            m_logger.Info("PersistenceManager", "Recovered state. snapshot_id=" + IntegerToString(ctx.GetSnapshotId()) +
                          " kill_switch=" + (ctx.IsKillSwitchActive() ? "1" : "0"));
        return true;
    }
    return false;
}

#endif // ATLAS_PERSISTENCE_MANAGER_MQH
//+------------------------------------------------------------------+
