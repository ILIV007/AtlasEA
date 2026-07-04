//+------------------------------------------------------------------+
//|                                               Config/Settings.mqh|
//|                            AtlasEA v1.1 - Configuration Center   |
//+------------------------------------------------------------------+
#ifndef ATLAS_SETTINGS_MQH
#define ATLAS_SETTINGS_MQH

//--- Module IDs (ContextGuardian single-writer enforcement)
#define ATLAS_MODULE_CORE          1
#define ATLAS_MODULE_MARKET        2
#define ATLAS_MODULE_STRATEGY      3
#define ATLAS_MODULE_RISK          4
#define ATLAS_MODULE_EXECUTION     5
#define ATLAS_MODULE_MT5           6
#define ATLAS_MODULE_TRADE         7
#define ATLAS_MODULE_PERSISTENCE   8

//--- Contract types (write-access tokens)
#define ATLAS_CONTRACT_MARKET_STATE   1
#define ATLAS_CONTRACT_RISK_DECISION  2
#define ATLAS_CONTRACT_ORDER_REQUEST  3
#define ATLAS_CONTRACT_EVENT          4
#define ATLAS_CONTRACT_CONTEXT        5

//--- Queue / buffer capacities
#define ATLAS_EVENT_QUEUE_SIZE     512
#define ATLAS_PRIORITY_QUEUE_SIZE  64
#define ATLAS_BAR_BUFFER_SIZE      256
#define ATLAS_FEATURE_SIZE         32
#define ATLAS_MAX_STRATEGIES       8
#define ATLAS_MAX_VOTES            16
#define ATLAS_MAX_POSITIONS        64
#define ATLAS_PAYLOAD_MAX_SIZE     256
#define ATLAS_EVENT_LOG_BUFFER     64
#define ATLAS_IDEMPOTENCY_SLOTS    32
#define ATLAS_LATENCY_SAMPLES      256

//--- Runtime budget (MQL5 OnTick constraints)
#define ATLAS_MAX_MS_PER_TICK      50
#define ATLAS_MAX_EVENTS_PER_TICK  8

//--- Risk thresholds
#define ATLAS_KILL_SWITCH_DRAWDOWN   8.0
#define ATLAS_KILL_SWITCH_LOSSES     5
#define ATLAS_MIN_CONFIDENCE         0.30
#define ATLAS_MARGIN_LEVEL_MIN       200.0

//--- Risk reason codes
#define ATLAS_RISK_REASON_OK             0
#define ATLAS_RISK_REASON_DRAWDOWN       1
#define ATLAS_RISK_REASON_EXPOSURE       2
#define ATLAS_RISK_REASON_MARGIN         3
#define ATLAS_RISK_REASON_COOLDOWN       4
#define ATLAS_RISK_REASON_KILLSWITCH     5
#define ATLAS_RISK_REASON_NOVOTE         6
#define ATLAS_RISK_REASON_INVALID        7
#define ATLAS_RISK_REASON_NO_CONTEXT     8
#define ATLAS_RISK_REASON_LOW_CONFIDENCE 9

//--- Direction codes
#define ATLAS_ORDER_BUY    1
#define ATLAS_ORDER_SELL  -1
#define ATLAS_ORDER_NONE   0

//--- Decision status
#define ATLAS_DECISION_APPROVED   1
#define ATLAS_DECISION_REJECTED   0
#define ATLAS_DECISION_DEFERRED  -1

//--- Fill status
#define ATLAS_FILL_PENDING    0
#define ATLAS_FILL_FILLED     1
#define ATLAS_FILL_PARTIAL    2
#define ATLAS_FILL_REJECTED   3
#define ATLAS_FILL_TIMEOUT    4

//--- Session tags
#define ATLAS_SESSION_OFF      0
#define ATLAS_SESSION_ASIAN    1
#define ATLAS_SESSION_LONDON   2
#define ATLAS_SESSION_NY       3
#define ATLAS_SESSION_OVERLAP  4

//--- Log levels
#define ATLAS_LOG_TRACE   0
#define ATLAS_LOG_DEBUG   1
#define ATLAS_LOG_INFO    2
#define ATLAS_LOG_WARN    3
#define ATLAS_LOG_ERROR   4
#define ATLAS_LOG_FATAL   5

//--- Version
#define ATLAS_VERSION_MAJOR  2
#define ATLAS_VERSION_MINOR  0
#define ATLAS_VERSION_STRING "2.0"

//+------------------------------------------------------------------+
//| AtlasConfig - runtime configuration                              |
//+------------------------------------------------------------------+
struct AtlasConfig
{
    string  symbol;
    long    magic_number;
    int     max_active_strategies;
    double  max_daily_drawdown_pct;
    double  max_exposure_limit;
    int     snapshot_interval_sec;
    int     heartbeat_interval_sec;
    int     max_events_per_tick;
    ulong   max_ms_per_tick;

    double  base_volume;
    double  max_volume;
    double  min_volume;
    int     volume_digits;

    int     atr_period;
    int     ma_fast_period;
    int     ma_slow_period;
    int     rsi_period;
    int     macd_fast;
    int     macd_slow;
    int     macd_signal;
    int     stoch_k;
    int     stoch_d;
    int     stoch_slow;
    int     cci_period;
    int     adx_period;
    int     bb_period;
    double  bb_deviation;

    int     sl_atr_multiplier;
    int     tp_atr_multiplier;

    int     max_retries;
    int     retry_delay_ms;
    double  max_spread_points;
    double  fast_market_atr_mult;
    int     slippage_points;

    int     log_level;
};

//+------------------------------------------------------------------+
//| Build default configuration                                      |
//+------------------------------------------------------------------+
void AtlasConfigDefaults(AtlasConfig &cfg)
{
    cfg.symbol                  = _Symbol;
    cfg.magic_number            = 20251001;
    cfg.max_active_strategies   = 4;
    cfg.max_daily_drawdown_pct  = 5.0;
    cfg.max_exposure_limit      = 0.20;
    cfg.snapshot_interval_sec   = 300;
    cfg.heartbeat_interval_sec  = 10;
    cfg.max_events_per_tick     = ATLAS_MAX_EVENTS_PER_TICK;
    cfg.max_ms_per_tick         = ATLAS_MAX_MS_PER_TICK;

    cfg.base_volume             = 0.10;
    cfg.max_volume              = 1.00;
    cfg.min_volume              = 0.01;
    cfg.volume_digits           = 2;

    cfg.atr_period              = 14;
    cfg.ma_fast_period          = 20;
    cfg.ma_slow_period          = 50;
    cfg.rsi_period              = 14;
    cfg.macd_fast               = 12;
    cfg.macd_slow               = 26;
    cfg.macd_signal             = 9;
    cfg.stoch_k                 = 14;
    cfg.stoch_d                 = 3;
    cfg.stoch_slow              = 3;
    cfg.cci_period              = 20;
    cfg.adx_period              = 14;
    cfg.bb_period               = 20;
    cfg.bb_deviation            = 2.0;

    cfg.sl_atr_multiplier       = 2;
    cfg.tp_atr_multiplier       = 4;

    cfg.max_retries             = 3;
    cfg.retry_delay_ms          = 200;
    cfg.max_spread_points       = 50.0;
    cfg.fast_market_atr_mult    = 2.5;
    cfg.slippage_points         = 20;

    cfg.log_level               = ATLAS_LOG_INFO;  ///< Note: TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, FATAL=5
}

#endif // ATLAS_SETTINGS_MQH
//+------------------------------------------------------------------+
