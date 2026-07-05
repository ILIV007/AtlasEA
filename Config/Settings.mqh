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

    //=== Money Management (v1.0) ===
    int     mm_mode;                    ///< ATLAS_MM_* sizing mode
    double  mm_fixed_lot;               ///< Fixed lot size (FIXED_LOT mode)
    double  mm_risk_percent;            ///< Risk % per trade (RISK_PERCENT mode)
    double  mm_max_risk_percent;        ///< Max risk % per trade (validation)
    double  mm_balance_fraction;        ///< Fraction of balance (BALANCE_PERCENT)
    double  mm_equity_fraction;         ///< Fraction of equity (EQUITY_PERCENT)
    double  mm_free_margin_fraction;   ///< Fraction of free margin (FREE_MARGIN_PERCENT)
    double  mm_max_lot;                 ///< Maximum lot (validation)
    double  mm_min_lot;                 ///< Minimum lot (validation)
    double  mm_max_exposure_pct;        ///< Max total exposure %
    double  mm_max_daily_loss_pct;      ///< Max daily loss % (stops trading)
    double  mm_max_drawdown_pct;        ///< Max drawdown % (drawdown protection)
    double  mm_atr_multiplier;          ///< ATR multiplier for SL (ATR_BASED mode)
    double  mm_vol_scale_base_atr;      ///< Reference ATR/price ratio (VOLATILITY_SCALING)
    double  mm_vol_scale_min_mult;      ///< Min vol scaling multiplier
    double  mm_vol_scale_max_mult;      ///< Max vol scaling multiplier
    double  mm_dd_scale_start_pct;      ///< Drawdown % to start scaling
    double  mm_dd_scale_end_pct;        ///< Drawdown % for full reduction
    double  mm_dd_scale_min_mult;       ///< Min multiplier at max drawdown
    int     mm_dl_scale_start_losses;   ///< Daily losses to start scaling
    double  mm_dl_scale_min_mult;       ///< Min multiplier after max losses
    double  mm_min_free_margin_pct;     ///< Min free margin % (validation)

    //=== Trade Lifecycle Manager (v1.0 Step 2) ===
    bool    tcm_enable_trailing;        ///< Enable trailing stop
    bool    tcm_enable_breakeven;       ///< Enable break-even
    bool    tcm_enable_partial_close;   ///< Enable partial close
    bool    tcm_enable_profit_lock;     ///< Enable profit lock
    bool    tcm_enable_time_exit;       ///< Enable time-based exit
    bool    tcm_enable_weekend_exit;    ///< Enable weekend close
    bool    tcm_enable_emergency_exit;  ///< Enable emergency exit

    int     tcm_trailing_mode;          ///< ATLAS_TRAIL_* mode
    double  tcm_trailing_distance;      ///< Classic trailing distance (points)
    double  tcm_trailing_step;          ///< Step trailing increment (points)
    double  tcm_atr_multiplier;         ///< ATR multiplier for ATR trailing
    double  tcm_trailing_start_rr;      ///< Don't trail until this RR reached

    double  tcm_breakeven_trigger;      ///< Trigger distance (points in favor)
    double  tcm_breakeven_offset;       ///< Offset from entry (points)
    double  tcm_breakeven_min_profit;   ///< Minimum profit to activate (points)
    bool    tcm_breakeven_spread_comp;  ///< Spread compensation
    bool    tcm_breakeven_one_time;     ///< One-time activation only

    double  tcm_partial_levels[4];      ///< RR triggers for partial closes (0=unused)
    double  tcm_partial_fractions[4];   ///< Fraction to close at each level
    int     tcm_partial_count;          ///< Number of active partial levels

    double  tcm_profit_lock_levels[4];  ///< RR triggers for profit locks
    double  tcm_profit_lock_lock[4];    ///< Lock fraction at each level
    int     tcm_profit_lock_count;      ///< Number of active profit lock levels

    int     tcm_max_trade_duration_sec; ///< Maximum trade duration (seconds)
    int     tcm_max_bars;               ///< Maximum bars in trade
    int     tcm_session_close_hour;     ///< Session close hour (server time)
    int     tcm_friday_close_hour;      ///< Friday close hour (server time)
    bool    tcm_holiday_close;          ///< Close on holidays

    //=== Profile Manager (v1.0 Step 4) ===
    int     profile_default;            ///< Default profile (ATLAS_PROFILE_*)
    bool    auto_profile_switch;        ///< Enable automatic profile switching
    int     profile_confirmation_bars;  ///< Bars of stable regime before switch
    int     profile_cooldown_minutes;   ///< Min minutes between switches
    bool    allow_manual_override;      ///< Allow manual profile override
    bool    enable_news_protection_profile; ///< Auto-switch to NewsProtection

    //=== Production Safety (v1.0 Step 7) ===
    bool    enable_broker_health_monitor; ///< Enable broker health monitoring
    bool    enable_execution_protection;  ///< Enable execution safety checks
    bool    enable_session_validation;    ///< Enable session validation
    bool    enable_environment_validation; ///< Enable environment validation
    int     max_execution_latency_ms;     ///< Max execution latency before pause
    int     max_rejected_orders;          ///< Max rejected orders before pause
    double  max_spread_multiplier;        ///< Max spread × average spread
    int     max_daily_trades_safety;      ///< Max daily trades (safety limit)
    int     max_simultaneous_trades;      ///< Max simultaneous open positions
    int     max_retries_safety;           ///< Max retries per order
    double  max_slippage_points_safety;   ///< Max acceptable slippage (points)
    int     friday_close_hour_safety;     ///< Friday close hour for session manager
    int     weekend_reopen_hour;          ///< Weekend reopen hour
    int     idle_threshold_sec;           ///< Seconds without tick = idle

    //=== Performance Monitoring (v1.0 Step 8) ===
    bool    enable_runtime_monitoring;    ///< Enable runtime statistics
    bool    enable_cache;                 ///< Enable cache layer
    int     cache_refresh_interval;       ///< Cache refresh interval (seconds)
    int     maintenance_interval;         ///< Maintenance task interval (seconds)
    int     performance_sampling_interval; ///< Performance sampling interval (seconds)
    int     maximum_cache_age;            ///< Maximum cache entry age (seconds, TTL)
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

    //--- Money Management defaults (v1.0)
    cfg.mm_mode                 = 1;        // FIXED_RISK_PERCENT
    cfg.mm_fixed_lot            = 0.10;
    cfg.mm_risk_percent         = 1.0;      // 1% of equity per trade
    cfg.mm_max_risk_percent     = 3.0;      // Max 3% per trade
    cfg.mm_balance_fraction     = 0.02;     // 2% of balance
    cfg.mm_equity_fraction      = 0.02;     // 2% of equity
    cfg.mm_free_margin_fraction = 0.10;     // 10% of free margin
    cfg.mm_max_lot              = 10.0;
    cfg.mm_min_lot              = 0.01;
    cfg.mm_max_exposure_pct     = 20.0;     // 20% max exposure
    cfg.mm_max_daily_loss_pct   = 5.0;      // 5% daily loss limit
    cfg.mm_max_drawdown_pct     = 8.0;      // 8% max drawdown (kill switch)
    cfg.mm_atr_multiplier       = 2.0;      // SL = 2 × ATR
    cfg.mm_vol_scale_base_atr   = 0.0010;   // Reference ATR/price ratio
    cfg.mm_vol_scale_min_mult   = 0.25;     // Min 25% lot (high vol)
    cfg.mm_vol_scale_max_mult   = 2.00;     // Max 200% lot (low vol)
    cfg.mm_dd_scale_start_pct   = 2.0;      // Start scaling at 2% DD
    cfg.mm_dd_scale_end_pct     = 5.0;      // Full reduction at 5% DD
    cfg.mm_dd_scale_min_mult    = 0.25;     // Min 25% lot at max DD
    cfg.mm_dl_scale_start_losses = 3;       // Start scaling after 3 losses
    cfg.mm_dl_scale_min_mult    = 0.50;     // Min 50% lot after many losses
    cfg.mm_min_free_margin_pct  = 30.0;     // Min 30% free margin

    //--- Trade Lifecycle Manager defaults (v1.0 Step 2)
    cfg.tcm_enable_trailing       = true;
    cfg.tcm_enable_breakeven      = true;
    cfg.tcm_enable_partial_close  = false;  // Off by default (advanced)
    cfg.tcm_enable_profit_lock    = true;
    cfg.tcm_enable_time_exit      = true;
    cfg.tcm_enable_weekend_exit   = true;
    cfg.tcm_enable_emergency_exit = true;

    cfg.tcm_trailing_mode         = 2;      // ATR trailing
    cfg.tcm_trailing_distance     = 200;    // 200 points (classic)
    cfg.tcm_trailing_step         = 50;     // 50 points (step trailing)
    cfg.tcm_atr_multiplier        = 2.0;    // SL = 2 × ATR
    cfg.tcm_trailing_start_rr     = 1.0;    // Start trailing at 1R

    cfg.tcm_breakeven_trigger     = 150;    // 150 points in favor
    cfg.tcm_breakeven_offset      = 20;     // 20 points offset
    cfg.tcm_breakeven_min_profit  = 50;     // 50 points min profit
    cfg.tcm_breakeven_spread_comp = true;   // Compensate for spread
    cfg.tcm_breakeven_one_time    = true;   // Activate only once

    cfg.tcm_partial_count         = 0;      // No partials by default
    cfg.tcm_partial_levels[0]     = 1.0;    // At 1R
    cfg.tcm_partial_levels[1]     = 2.0;    // At 2R
    cfg.tcm_partial_levels[2]     = 0.0;
    cfg.tcm_partial_levels[3]     = 0.0;
    cfg.tcm_partial_fractions[0]  = 0.50;   // Close 50%
    cfg.tcm_partial_fractions[1]  = 0.25;   // Close 25%
    cfg.tcm_partial_fractions[2]  = 0.0;
    cfg.tcm_partial_fractions[3]  = 0.0;

    cfg.tcm_profit_lock_count     = 1;      // 1 profit lock level
    cfg.tcm_profit_lock_levels[0] = 1.0;    // At 1R
    cfg.tcm_profit_lock_levels[1] = 2.0;    // At 2R
    cfg.tcm_profit_lock_levels[2] = 0.0;
    cfg.tcm_profit_lock_levels[3] = 0.0;
    cfg.tcm_profit_lock_lock[0]   = 0.0;    // Lock at breakeven
    cfg.tcm_profit_lock_lock[1]   = 0.50;   // Lock 50% of profit
    cfg.tcm_profit_lock_lock[2]   = 0.0;
    cfg.tcm_profit_lock_lock[3]   = 0.0;

    cfg.tcm_max_trade_duration_sec = 86400; // 24 hours
    cfg.tcm_max_bars               = 0;     // 0 = unlimited
    cfg.tcm_session_close_hour     = 22;    // 22:00 server time
    cfg.tcm_friday_close_hour      = 20;    // Friday 20:00
    cfg.tcm_holiday_close          = true;

    //--- Profile Manager defaults (v1.0 Step 4)
    cfg.profile_default            = 1;        // BALANCED
    cfg.auto_profile_switch        = true;
    cfg.profile_confirmation_bars  = 3;        // 3 bars of stable regime
    cfg.profile_cooldown_minutes   = 5;        // 5 min between switches
    cfg.allow_manual_override      = true;
    cfg.enable_news_protection_profile = true;

    //--- Production Safety defaults (v1.0 Step 7)
    cfg.enable_broker_health_monitor  = true;
    cfg.enable_execution_protection   = true;
    cfg.enable_session_validation     = true;
    cfg.enable_environment_validation = true;
    cfg.max_execution_latency_ms      = 5000;    // 5 seconds
    cfg.max_rejected_orders           = 5;       // 5 rejected orders → pause
    cfg.max_spread_multiplier         = 3.0;     // 3× average spread
    cfg.max_daily_trades_safety       = 50;
    cfg.max_simultaneous_trades       = 10;
    cfg.max_retries_safety            = 3;
    cfg.max_slippage_points_safety    = 20.0;
    cfg.friday_close_hour_safety      = 20;      // Friday 20:00
    cfg.weekend_reopen_hour           = 22;      // Sunday 22:00
    cfg.idle_threshold_sec            = 60;      // 60s no tick = idle

    //--- Performance Monitoring defaults (v1.0 Step 8)
    cfg.enable_runtime_monitoring     = true;
    cfg.enable_cache                  = true;
    cfg.cache_refresh_interval        = 60;      // 1 minute
    cfg.maintenance_interval          = 300;     // 5 minutes
    cfg.performance_sampling_interval = 10;      // 10 seconds
    cfg.maximum_cache_age             = 300;     // 5 minutes TTL
}

#endif // ATLAS_SETTINGS_MQH
//+------------------------------------------------------------------+
