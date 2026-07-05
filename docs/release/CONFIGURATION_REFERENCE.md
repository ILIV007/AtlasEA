# AtlasEA v1.0.0 — Configuration Reference

## AtlasConfig Fields

### Base Configuration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `symbol` | string | _Symbol | Trading symbol |
| `magic_number` | long | 20251001 | Magic number for order identification |
| `max_active_strategies` | int | 4 | Maximum active strategies |
| `max_daily_drawdown_pct` | double | 5.0 | Max daily drawdown % |
| `max_exposure_limit` | double | 0.20 | Max exposure (fraction of equity) |
| `snapshot_interval_sec` | int | 300 | Snapshot persistence interval |
| `heartbeat_interval_sec` | int | 10 | Heartbeat timer interval |
| `max_events_per_tick` | int | 8 | Max events processed per tick |
| `max_ms_per_tick` | ulong | 50 | Max ms per tick budget |

### Volume Configuration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_volume` | double | 0.10 | Base volume (lots) |
| `max_volume` | double | 1.00 | Maximum volume |
| `min_volume` | double | 0.01 | Minimum volume |
| `volume_digits` | int | 2 | Volume decimal places |

### Indicator Configuration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `atr_period` | int | 14 | ATR period |
| `ma_fast_period` | int | 20 | Fast EMA period |
| `ma_slow_period` | int | 50 | Slow EMA period |
| `rsi_period` | int | 14 | RSI period |
| `macd_fast/slow/signal` | int | 12/26/9 | MACD parameters |
| `stoch_k/d/slow` | int | 14/3/3 | Stochastic parameters |
| `cci_period` | int | 20 | CCI period |
| `adx_period` | int | 14 | ADX period |
| `bb_period` | int | 20 | Bollinger Bands period |
| `bb_deviation` | double | 2.0 | Bollinger Bands deviation |

### SL/TP Configuration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `sl_atr_multiplier` | int | 2 | SL = ATR × multiplier |
| `tp_atr_multiplier` | int | 4 | TP = ATR × multiplier |

### Order Configuration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_retries` | int | 3 | Order send retries |
| `retry_delay_ms` | int | 200 | Retry delay (ms) |
| `max_spread_points` | double | 50.0 | Max spread (points) |
| `fast_market_atr_mult` | double | 2.5 | Fast market ATR multiplier |
| `slippage_points` | int | 20 | Max slippage (points) |

### Money Management (mm_*)
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mm_mode` | int | 1 (RISK_PERCENT) | Sizing mode (0-9) |
| `mm_fixed_lot` | double | 0.10 | Fixed lot size |
| `mm_risk_percent` | double | 1.0 | Risk % per trade |
| `mm_max_risk_percent` | double | 3.0 | Max risk % per trade |
| `mm_max_lot` | double | 10.0 | Max lot |
| `mm_min_lot` | double | 0.01 | Min lot |
| `mm_max_exposure_pct` | double | 20.0 | Max total exposure % |
| `mm_max_daily_loss_pct` | double | 5.0 | Max daily loss % |
| `mm_max_drawdown_pct` | double | 8.0 | Max drawdown % (kill switch) |
| `mm_atr_multiplier` | double | 2.0 | ATR multiplier for SL |

### Trade Lifecycle Manager (tcm_*)
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tcm_enable_trailing` | bool | true | Enable trailing stop |
| `tcm_enable_breakeven` | bool | true | Enable break-even |
| `tcm_enable_partial_close` | bool | false | Enable partial close |
| `tcm_enable_profit_lock` | bool | true | Enable profit lock |
| `tcm_enable_time_exit` | bool | true | Enable time-based exit |
| `tcm_enable_weekend_exit` | bool | true | Enable weekend close |
| `tcm_trailing_mode` | int | 2 (ATR) | Trailing mode (0-5) |
| `tcm_trailing_distance` | double | 200 | Trailing distance (points) |
| `tcm_atr_multiplier` | double | 2.0 | ATR multiplier for trailing |
| `tcm_breakeven_trigger` | double | 150 | BE trigger (points) |
| `tcm_breakeven_offset` | double | 20 | BE offset (points) |
| `tcm_max_trade_duration_sec` | int | 86400 | Max trade duration (24h) |
| `tcm_friday_close_hour` | int | 20 | Friday close hour |

### Profile System (profile_*)
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `profile_default` | int | 1 (BALANCED) | Default profile |
| `auto_profile_switch` | bool | true | Auto profile switching |
| `profile_confirmation_bars` | int | 3 | Bars of stable regime |
| `profile_cooldown_minutes` | int | 5 | Min minutes between switches |
| `enable_news_protection_profile` | bool | true | Auto-switch during news |

### Production Safety
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enable_broker_health_monitor` | bool | true | Broker health monitoring |
| `enable_execution_protection` | bool | true | Execution safety |
| `max_execution_latency_ms` | int | 5000 | Max latency before pause |
| `max_rejected_orders` | int | 5 | Max rejected before pause |
| `max_spread_multiplier` | double | 3.0 | Max spread × average |
| `max_daily_trades_safety` | int | 50 | Max daily trades |
| `max_simultaneous_trades` | int | 10 | Max open positions |
| `friday_close_hour_safety` | int | 20 | Friday close hour |
| `weekend_reopen_hour` | int | 22 | Sunday reopen hour |

### Performance Monitoring
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enable_runtime_monitoring` | bool | true | Runtime statistics |
| `enable_cache` | bool | true | Cache layer |
| `cache_refresh_interval` | int | 60 | Cache refresh (seconds) |
| `maintenance_interval` | int | 300 | Maintenance (seconds) |
| `maximum_cache_age` | int | 300 | Cache TTL (seconds) |

## Production Presets

### Balanced.set (default)
- mm_mode=1, mm_risk_percent=1.0, mm_max_risk_percent=3.0
- tcm_trailing_mode=2, tcm_atr_multiplier=2.0
- profile_default=1, auto_profile_switch=true
- All safety features enabled

### Conservative.set
- mm_mode=1, mm_risk_percent=0.5, mm_max_risk_percent=1.5
- tcm_trailing_mode=2, tcm_atr_multiplier=1.5
- profile_default=0 (CONSERVATIVE)
- max_daily_trades_safety=20, max_simultaneous_trades=5

### Aggressive.set
- mm_mode=1, mm_risk_percent=2.0, mm_max_risk_percent=5.0
- tcm_trailing_mode=2, tcm_atr_multiplier=2.5
- profile_default=2 (AGGRESSIVE)
- max_daily_trades_safety=100, max_simultaneous_trades=20

### Scalping.set
- mm_mode=1, mm_risk_percent=0.5
- tcm_trailing_mode=1 (CLASSIC), tcm_trailing_distance=50
- profile_default=3 (SCALPING)
- tcm_max_trade_duration_sec=1800 (30 min)

### Swing.set
- mm_mode=1, mm_risk_percent=1.5
- tcm_trailing_mode=2, tcm_atr_multiplier=3.0
- profile_default=4 (SWING)
- tcm_max_trade_duration_sec=259200 (3 days)

### Recovery.set
- mm_mode=1, mm_risk_percent=0.3, mm_max_risk_percent=1.0
- profile_default=6 (RECOVERY)
- max_daily_trades_safety=3, max_simultaneous_trades=2

## Broker Recommendations

| Parameter | Recommended |
|-----------|------------|
| Account Type | Hedging (preferred) or Netting |
| Leverage | 1:100 to 1:500 |
| Execution | Market or Instant |
| Spread | < 30 points (EURUSD) |
| Minimum Deposit | $1,000 (conservative), $5,000 (balanced) |
| Symbols | EURUSD, GBPUSD, USDJPY (major pairs) |
| Timeframes | H1 (primary), M15 (scalping), H4 (swing) |
| Maximum Risk | 1-2% per trade (balanced), 0.5% (conservative) |
