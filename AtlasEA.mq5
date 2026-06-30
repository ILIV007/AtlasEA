//+------------------------------------------------------------------+
//|                                                       AtlasEA.mq5|
//|                                              AtlasEA v1.0        |
//|                Event-Driven Multi-Strategy Expert Advisor        |
//+------------------------------------------------------------------+
#property copyright   "AtlasEA v1.0"
#property link        "https://atlas.example"
#property version     "1.00"
#property description "AtlasEA v1.0 - event-driven, multi-strategy EA"
#property description "Architecture: Core -> Market/Strategy/Risk/Execution"
#property description "Infra: MT5Adapter / TradeManager / PersistenceManager"

#include "Core/CoreEngine.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input long             InpMagicNumber      = 20251001;   // Magic number
input double           InpBaseVolume       = 0.10;       // Base volume (lots)
input double           InpMaxDrawdownPct   = 5.0;        // Max daily drawdown (%)
input double           InpMaxExposure      = 0.20;       // Max exposure (fraction of equity)
input int              InpMaxEventsPerTick = 50;         // Max events processed per tick
input int              InpMaxMsPerTick     = 50;         // Max ms per tick (phase budget)
input int              InpAtrPeriod        = 14;         // ATR period
input int              InpMaFast           = 20;         // EMA fast period
input int              InpMaSlow           = 50;         // EMA slow period
input int              InpSlAtrMult        = 2;          // SL = ATR * mult
input int              InpTpAtrMult        = 4;          // TP = ATR * mult
input int              InpMaxRetries       = 3;          // OrderSend retries
input int              InpSnapshotSec      = 300;        // Snapshot interval (sec)
input int              InpHeartbeatSec     = 10;         // Heartbeat interval (sec)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CoreEngine *g_core_engine = NULL;

//+------------------------------------------------------------------+
//| Build config from inputs                                         |
//+------------------------------------------------------------------+
void BuildConfigFromInputs(AtlasConfig &cfg)
{
    AtlasConfigDefaults(cfg);
    cfg.magic_number            = InpMagicNumber;
    cfg.base_volume             = InpBaseVolume;
    cfg.max_daily_drawdown_pct  = InpMaxDrawdownPct;
    cfg.max_exposure_limit      = InpMaxExposure;
    cfg.max_events_per_tick     = InpMaxEventsPerTick;
    cfg.max_ms_per_tick         = (ulong)InpMaxMsPerTick;
    cfg.atr_period              = InpAtrPeriod;
    cfg.ma_fast_period          = InpMaFast;
    cfg.ma_slow_period          = InpMaSlow;
    cfg.sl_atr_multiplier       = InpSlAtrMult;
    cfg.tp_atr_multiplier       = InpTpAtrMult;
    cfg.max_retries             = InpMaxRetries;
    cfg.snapshot_interval_sec   = InpSnapshotSec;
    cfg.heartbeat_interval_sec  = InpHeartbeatSec;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void)
{
    AtlasConfig cfg;
    BuildConfigFromInputs(cfg);

    g_core_engine = new CoreEngine();
    if(!g_core_engine.Initialize(cfg))
    {
        Print("AtlasEA: initialization FAILED");
        delete g_core_engine;
        g_core_engine = NULL;
        return INIT_FAILED;
    }
    Print("AtlasEA: initialized successfully on ", cfg.symbol);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_core_engine != NULL)
    {
        g_core_engine.Shutdown(reason);
        delete g_core_engine;
        g_core_engine = NULL;
    }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick(void)
{
    if(g_core_engine != NULL)
        g_core_engine.OnTick();
}

//+------------------------------------------------------------------+
//| OnTrade                                                          |
//+------------------------------------------------------------------+
void OnTrade(void)
{
    if(g_core_engine != NULL)
        g_core_engine.OnTrade();
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer(void)
{
    if(g_core_engine != NULL)
        g_core_engine.OnTimer();
}
//+------------------------------------------------------------------+
