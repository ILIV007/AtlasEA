//+------------------------------------------------------------------+
//|                                                       AtlasEA.mq5|
//|                                              AtlasEA v1.0 RC     |
//|                Event-Driven Multi-Strategy Expert Advisor        |
//|                                                                  |
//|  v1.0 RC: Production Release Candidate.                          |
//|  AtlasEA.mq5 is a thin entry point:                              |
//|    1. Create Bootstrapper                                        |
//|    2. Bootstrap application                                      |
//|    3. Resolve CoreEngine                                         |
//|    4. Run                                                        |
//|    5. Shutdown through Bootstrapper                              |
//+------------------------------------------------------------------+
#property copyright   "AtlasEA v1.0 RC"
#property link        "https://atlas.example"
#property version     "1.00"
#property description "AtlasEA - event-driven, multi-strategy EA"
#property description "Production Release Candidate v1.0"

#include "Core/Bootstrapper.mqh"

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
input int              InpLogLevel         = 2;          // Log level (0=Trace,1=Debug,2=Info,3=Warn,4=Error,5=Fatal)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
Bootstrapper  *g_bootstrapper = NULL;
CoreEngine    *g_core_engine  = NULL;

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
//|  Startup flow:                                                   |
//|    1. Build config from inputs                                   |
//|    2. Create Bootstrapper                                        |
//|    3. Bootstrap application (creates + injects + validates all)  |
//|    4. Store CoreEngine pointer                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
    AtlasConfig cfg;
    BuildConfigFromInputs(cfg);

    g_bootstrapper = new Bootstrapper();
    if(g_bootstrapper == NULL)
    {
        Print("AtlasEA: FATAL — cannot create Bootstrapper");
        return INIT_FAILED;
    }

    //--- Bootstrap the entire application
    g_core_engine = g_bootstrapper.Bootstrap(cfg);
    if(g_core_engine == NULL)
    {
        Print("AtlasEA: FATAL — bootstrap failed: ", g_bootstrapper.GetFailureReason());
        delete g_bootstrapper;
        g_bootstrapper = NULL;
        return INIT_FAILED;
    }

    //--- Logger is now available via Bootstrapper; use it for success message.
    //--- Print() is only used above for FATAL pre-logger errors.
    Logger *logger = g_bootstrapper.GetLogger();
    if(logger != NULL)
        logger.Info("AtlasEA", "v1.0 RC initialized successfully on " + cfg.symbol);
    else
        Print("AtlasEA v1.0 RC: initialized successfully on ", cfg.symbol);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit — shutdown through Bootstrapper                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_bootstrapper != NULL)
    {
        g_bootstrapper.Shutdown();
        delete g_bootstrapper;
        g_bootstrapper = NULL;
        g_core_engine  = NULL;  //--- deleted by Bootstrapper.Shutdown()
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
