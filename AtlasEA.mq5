//+------------------------------------------------------------------+
//|                                                       AtlasEA.mq5|
//|                                              AtlasEA v0.1.8.0    |
//|                Event-Driven Multi-Strategy Expert Advisor        |
//|                                                                  |
//|  v0.1.8.0: Bootstrap layer introduced. AtlasEA.mq5 is now a      |
//|  thin entry point — all construction, DI, and wiring lives in    |
//|  Bootstrap/AtlasBootstrap.mqh.                                   |
//+------------------------------------------------------------------+
#property copyright   "AtlasEA v0.1.8.0"
#property link        "https://atlas.example"
#property version     "0.18"
#property description "AtlasEA - event-driven, multi-strategy EA"
#property description "Bootstrap-driven dependency injection"

#include "Bootstrap/AtlasBootstrap.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input long             InpMagicNumber      = 20251001;   // Magic number
input double           InpBaseVolume       = 0.10;       // Base volume (lots)
input double           InpMaxDrawdownPct   = 5.0;        // Max daily drawdown (%)
input double           InpMaxExposure      = 0.20;       // Max exposure (fraction of equity)
input int              InpMaxEventsPerTick = 8;          // Max events processed per tick
input int              InpMaxMsPerTick     = 50;         // Max ms per tick (phase budget)
input int              InpAtrPeriod        = 14;         // ATR period
input int              InpMaFast           = 20;         // EMA fast period
input int              InpMaSlow           = 50;         // EMA slow period
input int              InpSlAtrMult        = 2;          // SL = ATR * mult
input int              InpTpAtrMult        = 4;          // TP = ATR * mult
input int              InpMaxRetries       = 3;          // OrderSend retries
input int              InpSnapshotSec      = 300;        // Snapshot interval (sec)
input int              InpHeartbeatSec     = 10;         // Heartbeat interval (sec)
input int              InpLogLevel         = 1;          // Log level (0=Debug,1=Info,2=Warn,3=Error,4=Fatal)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
AtlasBootstrap *g_bootstrap = NULL;
CoreEngine     *g_core_engine = NULL;

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
    cfg.log_level               = InpLogLevel;
}

//+------------------------------------------------------------------+
//| OnInit — thin entry point                                        |
//|                                                                  |
//|  All construction and wiring is delegated to AtlasBootstrap.     |
//|  The .mq5 file only:                                             |
//|    1. Builds the config from inputs                              |
//|    2. Creates the bootstrap                                      |
//|    3. Calls bootstrap.Initialize(config)                         |
//|    4. Stores the returned CoreEngine                             |
//+------------------------------------------------------------------+
int OnInit(void)
{
    AtlasConfig cfg;
    BuildConfigFromInputs(cfg);

    g_bootstrap = new AtlasBootstrap();
    if(g_bootstrap == NULL)
    {
        Print("AtlasEA: FATAL — cannot create AtlasBootstrap");
        return INIT_FAILED;
    }

    g_core_engine = g_bootstrap.Initialize(cfg);
    if(g_core_engine == NULL)
    {
        Print("AtlasEA: FATAL — bootstrap initialization failed");
        delete g_bootstrap;
        g_bootstrap = NULL;
        return INIT_FAILED;
    }

    Print("AtlasEA v0.1.8.0: initialized successfully on ", cfg.symbol);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit — thin entry point                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_bootstrap != NULL)
    {
        g_bootstrap.Shutdown();
        delete g_bootstrap;
        g_bootstrap   = NULL;
        g_core_engine = NULL;  //--- deleted by bootstrap.Shutdown()
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
