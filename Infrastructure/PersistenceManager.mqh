//+------------------------------------------------------------------+
//|                            Infrastructure/PersistenceManager.mqh |
//|                AtlasEA v1.0 - State Persistence / Recovery       |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERSISTENCE_MANAGER_MQH
#define ATLAS_PERSISTENCE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"

//+------------------------------------------------------------------+
//| PersistenceManager                                               |
//|   - writes context snapshots to a daily file                     |
//|   - appends events to a rolling log                              |
//|   - recovers context state on startup                            |
//+------------------------------------------------------------------+
class PersistenceManager
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
    bool        Initialize(const AtlasConfig &config, AtlasContext *context);
    bool        WriteSnapshot(const AtlasContext &ctx, long id);
    bool        AppendEvent(const AtlasEvent &ev);
    bool        FlushEventBuffer(void);
    bool        RecoverState(AtlasContext &ctx);
};

//+------------------------------------------------------------------+
PersistenceManager::PersistenceManager(void)
{
    m_context            = NULL;
    m_event_buffer_count = 0;
}

//+------------------------------------------------------------------+
bool PersistenceManager::Initialize(const AtlasConfig &config, AtlasContext *context)
{
    m_config  = config;
    m_context = context;
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
    int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        Print("[Persistence] Cannot open ", filename, " err=", GetLastError());
        return false;
    }
    FileWriteString(handle, "snapshot_id="         + IntegerToString(ctx.current_snapshot_id)        + "\n");
    FileWriteString(handle, "trading_day_start="   + IntegerToString((long)ctx.trading_day_start)     + "\n");
    FileWriteString(handle, "daily_start_equity="  + DoubleToString(ctx.daily_start_equity, 2)        + "\n");
    FileWriteString(handle, "daily_peak_equity="   + DoubleToString(ctx.daily_peak_equity, 2)         + "\n");
    FileWriteString(handle, "daily_drawdown_pct="  + DoubleToString(ctx.daily_drawdown_pct, 4)        + "\n");
    FileWriteString(handle, "daily_realized_pnl="  + DoubleToString(ctx.daily_realized_pnl, 2)        + "\n");
    FileWriteString(handle, "daily_trade_count="   + IntegerToString(ctx.daily_trade_count)           + "\n");
    FileWriteString(handle, "daily_loss_count="    + IntegerToString(ctx.daily_loss_count)            + "\n");
    FileWriteString(handle, "consecutive_losses="  + IntegerToString(ctx.consecutive_losses)          + "\n");
    FileWriteString(handle, "kill_switch_active="  + IntegerToString(ctx.kill_switch_active ? 1 : 0)  + "\n");
    FileWriteString(handle, "kill_switch_reason="  + ctx.kill_switch_reason                           + "\n");
    FileWriteString(handle, "kill_switch_time="    + IntegerToString((long)ctx.kill_switch_time)      + "\n");
    FileWriteString(handle, "total_ticks="         + IntegerToString((long)ctx.total_ticks_processed) + "\n");
    FileWriteString(handle, "total_events="        + IntegerToString((long)ctx.total_events_emitted)  + "\n");
    FileWriteString(handle, "total_orders_sent="   + IntegerToString((long)ctx.total_orders_sent)     + "\n");
    FileWriteString(handle, "total_orders_filled=" + IntegerToString((long)ctx.total_orders_filled)   + "\n");
    FileClose(handle);
    return true;
}

//+------------------------------------------------------------------+
//| ReadContextFromFile - parse key=value back into context           |
//+------------------------------------------------------------------+
bool PersistenceManager::ReadContextFromFile(AtlasContext &ctx, const string filename)
{
    int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        Print("[Persistence] No snapshot to recover: ", filename);
        return false;
    }
    while(!FileIsEnding(handle))
    {
        string line = FileReadString(handle);
        int    eq   = StringFind(line, "=");
        if(eq <= 0) continue;
        string key = StringSubstr(line, 0, eq);
        string val = StringSubstr(line, eq + 1);

        if(key == "snapshot_id")          ctx.current_snapshot_id    = (long)StringToInteger(val);
        else if(key == "trading_day_start") ctx.trading_day_start    = (datetime)StringToInteger(val);
        else if(key == "daily_start_equity") ctx.daily_start_equity  = StringToDouble(val);
        else if(key == "daily_peak_equity")  ctx.daily_peak_equity   = StringToDouble(val);
        else if(key == "daily_drawdown_pct") ctx.daily_drawdown_pct  = StringToDouble(val);
        else if(key == "daily_realized_pnl") ctx.daily_realized_pnl  = StringToDouble(val);
        else if(key == "daily_trade_count")  ctx.daily_trade_count   = (int)StringToInteger(val);
        else if(key == "daily_loss_count")   ctx.daily_loss_count    = (int)StringToInteger(val);
        else if(key == "consecutive_losses") ctx.consecutive_losses  = (int)StringToInteger(val);
        else if(key == "kill_switch_active") ctx.kill_switch_active  = (StringToInteger(val) != 0);
        else if(key == "kill_switch_reason") ctx.kill_switch_reason  = val;
        else if(key == "kill_switch_time")   ctx.kill_switch_time    = (datetime)StringToInteger(val);
        else if(key == "total_ticks")        ctx.total_ticks_processed = (ulong)StringToInteger(val);
        else if(key == "total_events")       ctx.total_events_emitted  = (ulong)StringToInteger(val);
        else if(key == "total_orders_sent")  ctx.total_orders_sent     = (ulong)StringToInteger(val);
        else if(key == "total_orders_filled") ctx.total_orders_filled  = (ulong)StringToInteger(val);
    }
    FileClose(handle);
    return true;
}

//+------------------------------------------------------------------+
bool PersistenceManager::WriteSnapshot(const AtlasContext &ctx, long id)
{
    string fn = GenerateDailyFilename();
    bool ok = WriteContextToFile(ctx, fn);
    if(ok)
        Print("[Persistence] Snapshot ", id, " written to ", fn);
    return ok;
}

//+------------------------------------------------------------------+
bool PersistenceManager::AppendEvent(const AtlasEvent &ev)
{
    if(m_event_buffer_count >= ATLAS_EVENT_LOG_BUFFER)
    {
        if(!FlushEventBuffer()) return false;
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
            Print("[Persistence] Cannot open event log ", fn);
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
        Print("[Persistence] Recovered state. snapshot_id=", ctx.current_snapshot_id,
              " kill_switch=", ctx.kill_switch_active);
        return true;
    }
    return false;
}

#endif // ATLAS_PERSISTENCE_MANAGER_MQH
//+------------------------------------------------------------------+
