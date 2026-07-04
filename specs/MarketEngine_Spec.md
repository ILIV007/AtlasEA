# AtlasEA v1.0 — Market Engine Production Specification

**Document version:** 2.0 (updated v0.1.9.0)
**Target module:** `Engines/MarketEngine.mqh` (+ internal helpers under `Engines/MarketEngine/`)
**Interface implemented:** `IMarketDataSource`
**Contracts consumed:** `RawTick`, `MarketState`

---

# 1. Components

The Market Engine consists of 9 components:

| Component | File | Responsibility |
|-----------|------|----------------|
| TickValidator | `TickValidator.mqh` | Validate raw ticks (NaN/INF/zero/negative/spread/timestamp) |
| BarBuffer | `BarBuffer.mqh` | Fixed-capacity circular OHLCV buffer (100 bars) |
| ATRCalculator | `ATRCalculator.mqh` | ATR(14) with Wilder smoothing (incremental) |
| TrendDetector | `TrendDetector.mqh` | EMA crossover trend detection (non-repainting) |
| SessionDetector | `SessionDetector.mqh` | Asia/London/NY/Overlap/Closed detection |
| RegimeDetector | `RegimeDetector.mqh` | 8 market regime classification |
| FeatureExtractor | `FeatureExtractor.mqh` | 32 normalized features |
| IndicatorCache | `IndicatorCache.mqh` | Cache indicator values (invalidate on bar close) |
| MarketEngine | `MarketEngine.mqh` | Orchestrator — integrates all components |

---

# 2. TickValidator

## Algorithm

Sequential fail-fast validation of 10 checks:

1. Bid is a valid number (reject NaN / INF) — `MathIsValidNumber(tick.bid)`
2. Ask is a valid number (reject NaN / INF) — `MathIsValidNumber(tick.ask)`
3. Bid > 0
4. Ask > 0
5. Ask >= Bid (no negative spread)
6. Spread within configurable range (`spread_points <= max_spread_points`)
7. Timestamp > 0
8. Timestamp not too far in the future (`timestamp <= now + tolerance`)
9. Stale tick check (`now - timestamp <= stale_threshold`)
10. Out-of-order check (`timestamp >= last_tick_timestamp`)

Returns `TickValidationResult` struct with `valid`, `reject_code`, `reason`, `spread_points`.

## Complexity

- **Time:** O(1) — all checks are arithmetic comparisons
- **Space:** O(1) — no allocation, fixed-size counters

## Memory Usage

| Field | Size |
|-------|------|
| m_reject_reasons[10] | 40 bytes |
| m_last_tick (RawTick) | ~40 bytes |
| Scalars | ~48 bytes |
| **Total** | **~128 bytes** |

## Edge Cases

- NaN bid/ask → rejected with `nan_bid` / `nan_ask`
- Zero bid/ask → rejected with `invalid_bid` / `invalid_ask`
- INF bid/ask → `MathIsValidNumber` returns false → rejected as NaN
- Negative spread (ask < bid) → rejected
- Wide spread (> max_spread_points) → rejected
- Zero timestamp → rejected
- Future timestamp → rejected
- Stale timestamp → rejected
- Out-of-order timestamp → rejected
- First tick ever → no monotonic check (last_tick_time == 0)

## Performance Notes

- All checks are O(1) arithmetic
- `MathIsValidNumber` is a built-in MQL5 function (fast)
- No string operations in the hot path (reason strings are only set on rejection)
- Total budget: ≤ 0.01 ms per tick

---

# 3. BarBuffer

## Algorithm

Fixed-capacity circular buffer using a stack-allocated array.

- **Insert (Push/AddBar):** If buffer is not full, write at `m_head` and increment. If full, shift all elements left by 1 and write at the end (FIFO eviction).
- **Access (Get/Current/Previous):** Direct array index — O(1).
- **Size (Count):** Return `m_count` — O(1).

## Complexity

| Operation | Time | Space |
|-----------|------|-------|
| Push (not full) | O(1) | O(1) |
| Push (full) | O(N) shift | O(1) |
| Get(index) | O(1) | O(1) |
| Current() | O(1) | O(1) |
| Previous() | O(1) | O(1) |
| Count() | O(1) | O(1) |
| IsReady(min) | O(1) | O(1) |
| HighestHigh(n) | O(n) | O(1) |
| LowestLow(n) | O(n) | O(1) |

**N** = capacity (100). The O(N) shift on full Push is acceptable because it happens once per bar (not per tick).

## Memory Usage

| Field | Size |
|-------|------|
| m_bars[100] (BarData × 100) | 100 × ~56 bytes = ~5.6 KB |
| Scalars | ~24 bytes |
| **Total** | **~5.7 KB** |

## Edge Cases

- Empty buffer: `Current()` returns false, `Get(0)` returns false
- Single bar: `Previous()` returns false (needs ≥ 2 bars)
- Index out of range: returns false, output is zeroed
- Full buffer: oldest bar evicted on Push

## Performance Notes

- No heap allocation (stack array)
- `IsReady(14)` checks if enough bars for ATR calculation
- `HighestHigh(n)` / `LowestLow(n)` are O(n) — used by RegimeDetector

---

# 4. ATRCalculator

## Algorithm

ATR(14) using Wilder's smoothing method:

**True Range (TR):**
```
TR = max(
    high - low,
    |high - prev_close|,
    |low - prev_close|
)
```

**Seed ATR (first 14 bars):**
```
ATR_seed = (1/14) × Σ TR_i  for i = 1..14
```

**Wilder Smoothing (bar 15+):**
```
ATR_today = (ATR_yesterday × (period - 1) + TR_today) / period
```

This is equivalent to an EMA with alpha = 1/period.

## Complexity

| Operation | Time | Space |
|-----------|------|-------|
| OnBarClose (collecting) | O(1) | O(1) |
| OnBarClose (smoothing) | O(1) | O(1) |
| GetATR() | O(1) | O(1) |
| ComputeSeedATR() | O(period) | O(1) |

## Memory Usage

| Field | Size |
|-------|------|
| m_tr_ring[14] | 112 bytes |
| Scalars | ~48 bytes |
| **Total** | **~160 bytes** |

## Edge Cases

- First bar (no prev_close): TR = high - low
- Gap up (prev_close > high): TR = |low - prev_close| (largest)
- Gap down (prev_close < low): TR = |high - prev_close| (largest)
- Fewer than 14 bars: ATR = running average (not yet initialized)
- Exactly 14 bars: seed ATR computed
- Bar 15+: Wilder smoothing applied

## Performance Notes

- Incremental update — O(1) per bar close
- Cached: ATR value stored, only recomputed on bar close
- No dynamic allocation (fixed ring of 14 doubles)
- Non-repainting: only uses closed bars

---

# 5. TrendDetector

## Algorithm

EMA crossover trend detection using EMA(fast) and EMA(slow) from closed bars.

**Direction:**
```
separation = EMA_fast - EMA_slow
threshold  = ATR × 0.25

if separation > threshold:  direction = +1 (uptrend)
if separation < -threshold: direction = -1 (downtrend)
else:                       direction =  0 (no trend)
```

**Strength:**
```
strength = |separation| / ATR × 50  (clamped to [0, 100])
```

**Duration:** Bars since last direction change. Incremented if direction unchanged, reset to 1 on change.

## Complexity

- **Time:** O(1) — all values pre-cached in IndicatorCache
- **Space:** O(1) — 3 scalars

## Non-Repainting Guarantee

All inputs (EMA_fast, EMA_slow, ATR) are read from IndicatorCache at shift=1 (last closed bar). The forming bar is never consulted. Therefore the trend output for a given bar never changes once that bar closes.

## Memory Usage

| Field | Size |
|-------|------|
| Scalars (direction, strength, duration, threshold_mult) | ~32 bytes |
| **Total** | **~32 bytes** |

---

# 6. SessionDetector

## Algorithm

Classifies the current server time into a trading session based on UTC hour.

**UTC Conversion:**
```
utc_hour = (server_hour - server_utc_offset + 24) % 24
```

**Session Classification (UTC):**
| UTC Hour Range | Session |
|----------------|---------|
| 00:00 - 07:00 | ASIAN |
| 07:00 - 13:00 | LONDON |
| 13:00 - 17:00 | OVERLAP (London + NY) |
| 17:00 - 21:00 | NY |
| 21:00 - 24:00 | OFF |

**Weekend Check:** day_of_week == 0 (Sunday) or 6 (Saturday) → OFF

**Holiday Check:** Fixed-date holidays (Jan 1, Dec 25, Dec 26) → OFF

## Daylight Saving Configuration

The `server_utc_offset` parameter allows configuration of the broker's UTC offset. This is set during initialization and can be adjusted for DST:

- Standard time (winter): offset = broker's standard UTC offset
- DST (summer): offset = broker's standard UTC offset - 1

The offset is a configuration value — the detector does NOT auto-detect DST. The operator must update it twice a year or use a broker with a fixed UTC offset.

## Complexity

- **Time:** O(1) — hour comparison + weekend/holiday check
- **Space:** O(1)

## Memory Usage

| Field | Size |
|-------|------|
| Scalars | ~16 bytes |
| **Total** | **~16 bytes** |

---

# 7. RegimeDetector

## Algorithm

Classifies the market into one of 8 regimes using a priority-ordered decision tree.

**Inputs:** IndicatorCache (ATR, ADX, BB), TrendDetector, BarBuffer, current price.

**Priority Order (first match wins):**

1. **VOLATILE** — ATR > 1.5 × 20-bar avg ATR
2. **BREAKOUT** — BB %B ≥ 0.95 or ≤ 0.05
3. **TRENDING** — ADX > 25 AND direction ≠ 0 AND strength > 30
4. **PULLBACK** — direction ≠ 0 AND duration > 3 AND price near EMA_fast
5. **ACCUMULATION** — ADX < 20 AND BB width < 0.02 AND last bar bullish
6. **DISTRIBUTION** — ADX < 20 AND BB width < 0.02 AND last bar bearish
7. **RANGING** — ADX < 20
8. **QUIET** — default fallback

## Regime Score

Each regime has a normalized score in [0, 1] = `regime_code / 7.0`. This is stored as feature[30] in the feature vector.

## Complexity

- **Time:** O(1) — all inputs pre-cached
- **Space:** O(1)

## Memory Usage

| Field | Size |
|-------|------|
| Thresholds (6 doubles) | 48 bytes |
| State (3 ints) | 12 bytes |
| **Total** | **~60 bytes** |

---

# 8. FeatureExtractor

## Algorithm

Generates exactly 32 normalized features from closed-bar data.

All features are:
- **Deterministic:** same inputs → same output (no randomness)
- **Non-repainting:** derived from closed bars only (shift ≥ 1)
- **Normalized:** bounded to [-1, 1] or [0, 1]

**Feature Vector Layout:**

| Index | Feature | Range | Source |
|-------|---------|-------|--------|
| 0 | Price vs EMA20 (z-score) | [-1, 1] | IndicatorCache |
| 1 | Price vs EMA50 (z-score) | [-1, 1] | IndicatorCache |
| 2 | EMA20 slope / ATR | [-1, 1] | IndicatorCache |
| 3 | EMA50 slope / ATR | [-1, 1] | IndicatorCache |
| 4 | EMA20 vs EMA50 separation / ATR | [-1, 1] | IndicatorCache |
| 5 | ATR / price | [0, 1] | IndicatorCache |
| 6 | ATR ratio (curr/prev) | [0, 1] | IndicatorCache |
| 7 | BB width / middle | [0, 1] | IndicatorCache |
| 8 | BB %B | [0, 1] | IndicatorCache |
| 9 | RSI / 100 | [0, 1] | IndicatorCache |
| 10 | RSI delta | [-1, 1] | IndicatorCache |
| 11 | MACD histogram / ATR | [-1, 1] | IndicatorCache |
| 12 | MACD signal cross | {-1, 0, 1} | IndicatorCache |
| 13 | CCI / 200 | [-1, 1] | IndicatorCache |
| 14 | Stochastic %K / 100 | [0, 1] | IndicatorCache |
| 15 | Stochastic %D / 100 | [0, 1] | IndicatorCache |
| 16 | Trend direction | {-1, 0, 1} | TrendDetector |
| 17 | Trend strength / 100 | [0, 1] | TrendDetector |
| 18 | Trend duration / 50 | [0, 1] | TrendDetector |
| 19 | ADX / 100 | [0, 1] | IndicatorCache |
| 20 | DI+ / (DI+ + DI-) | [0, 1] | IndicatorCache |
| 21 | DI- / (DI+ + DI-) | [0, 1] | IndicatorCache |
| 22 | Body ratio | [0, 1] | BarBuffer |
| 23 | Upper shadow ratio | [0, 1] | BarBuffer |
| 24 | Lower shadow ratio | [0, 1] | BarBuffer |
| 25 | Bar range / ATR | [0, 1] | BarBuffer + IndicatorCache |
| 26 | Volume change rate | [-1, 1] | BarBuffer |
| 27 | Volume / avg volume | [0, 1] | BarBuffer |
| 28 | Spread / max spread | [0, 1] | TickValidator result |
| 29 | Session / 4 | [0, 1] | SessionDetector |
| 30 | Regime / 7 | [0, 1] | RegimeDetector |
| 31 | Bar progress | [0, 1] | Current bar time |

## Invalid Value Handling

- All `double` inputs are checked for NaN via `MathIsValidNumber`
- Division by zero is guarded (returns 0.0)
- Missing data (empty BarBuffer) → feature = 0.0
- All features are clamped to their specified range

## Complexity

- **Time:** O(1) per feature, O(32) total = O(1)
- **Space:** O(1) — 32 doubles on stack

## Memory Usage

| Field | Size |
|-------|------|
| features[32] | 256 bytes |
| **Total** | **~256 bytes** |

---

# 9. IndicatorCache

## Algorithm

Manages 9 MT5 indicator handles and caches their values from closed bars (shift=1).

**Indicators:**
- ATR(period)
- EMA fast(period) + EMA slow(period)
- RSI(period)
- MACD(fast, slow, signal)
- Stochastic(k, d, slow)
- CCI(period)
- ADX(period) + DI+ + DI-
- Bollinger Bands(period, deviation)

**Cache Invalidation:** Automatic on bar close. The `Refresh()` method is called when a new bar opens, re-reading all indicator values at shift=1.

## Complexity

| Operation | Time |
|-----------|------|
| Initialize (create handles) | O(9) — 9 indicator creations |
| Refresh (read all values) | O(9) — 9 CopyBuffer calls |
| Get any cached value | O(1) |
| Shutdown (release handles) | O(9) |

## Memory Usage

| Field | Size |
|-------|------|
| 9 handles (ints) | 36 bytes |
| ~20 cached doubles | 160 bytes |
| Scalars | ~32 bytes |
| **Total** | **~228 bytes** |

## Non-Repainting Guarantee

All `CopyBuffer` calls use `shift=1` (the last closed bar). The forming bar (shift=0) is never read. Therefore, cached values are stable once a bar closes.

---

# 10. MarketEngine Pipeline

## Algorithm

Per-tick pipeline (8 stages):

```
1. Validate Tick (TickValidator.ValidateDetailed)
   ├── invalid → return invalid MarketState
   └── valid → continue

2. Update BarBuffer (CheckNewBar)
   ├── new bar → CloseCurrentBar (push to buffer + update ATR)
   └── same bar → UpdateCurrentBar (update OHLC)

3. Refresh Indicator Cache (only on new bar)
   └── Read all 9 indicators at shift=1

4. Update Trend Detector (only on new bar)
   └── EMA crossover on cached values

5. Update Session Detector (every tick)
   └── Classify current time

6. Update Regime Detector (only on new bar)
   └── 8-regime classification

7. Extract Features (every tick)
   └── 32 normalized features

8. Build MarketState (every tick)
   └── Immutable struct returned
```

## Complexity

| Stage | Time | Frequency |
|-------|------|-----------|
| Validate Tick | O(1) | Every tick |
| Update BarBuffer | O(1) or O(N) on new bar | Every tick |
| Refresh Indicators | O(9) | New bar only |
| Update Trend | O(1) | New bar only |
| Update Session | O(1) | Every tick |
| Update Regime | O(1) | New bar only |
| Extract Features | O(32) = O(1) | Every tick |
| Build MarketState | O(1) | Every tick |
| **Total (same bar)** | **O(1)** | **Every tick** |
| **Total (new bar)** | **O(N) for shift + O(9) for refresh** | **Once per bar** |

## Memory Usage

| Component | Size |
|-----------|------|
| BarBuffer | ~5.7 KB |
| TickValidator | ~128 bytes |
| SessionDetector | ~16 bytes |
| IndicatorCache | ~228 bytes |
| ATRCalculator | ~160 bytes |
| TrendDetector | ~32 bytes |
| RegimeDetector | ~60 bytes |
| FeatureExtractor | ~256 bytes |
| Current bar + diagnostics | ~256 bytes |
| **Total** | **~6.8 KB** |

## Performance Budget

| Target | Value |
|--------|-------|
| Max ProcessTick latency | < 10 ms |
| Typical ProcessTick (same bar) | < 0.5 ms |
| Typical ProcessTick (new bar) | < 2 ms |
| Memory | < 7 KB (all stack) |
| Dynamic allocation | 0 (none in hot path) |
| String operations in hot path | 0 (except on rejection) |

## Edge Cases

- Invalid tick → return invalid MarketState with `is_valid = false`
- No broker adapter → return invalid MarketState
- Not initialized → return invalid MarketState
- First tick ever → no previous bar, ATR not yet initialized
- Bar buffer not ready (< 14 bars) → ATR = 0, trend = 0, regime = QUIET
- NaN in indicator values → FeatureExtractor replaces with 0
- Broker returns 0 for SymbolPoint → defensive default 0.00001

## Non-Repainting Guarantee

The entire pipeline uses only closed-bar data for:
- ATR (updated on bar close)
- Trend (EMA values at shift=1)
- Regime (based on closed-bar indicators)
- Features 0-27 (all from closed bars)

Features 28-31 (spread, session, regime, bar progress) are per-tick but deterministic — they don't affect indicator-based decisions.

Once a bar closes, the MarketState for that bar's snapshot is final and will not change on subsequent ticks.

---

# 11. Test Coverage

Tests are in `tests/MarketEngineTests.mq5`:

| Test | Coverage |
|------|----------|
| TestInvalidTick | NaN bid, zero bid, negative spread, valid tick |
| TestGapDetection | Out-of-order timestamp, future timestamp |
| TestFirst14Bars | ATR seed behavior (not initialized until 14 bars) |
| TestATRCorrectness | Wilder smoothing formula verification |
| TestBarBuffer | Push, Current, Previous, IsReady, Count |
| TestSessionDetection | Session name mapping, current session validity |
| TestFeatureNormalization | All features bounded [-1, 1] |
| TestATREdgeCases | Reset, single bar, gap (True Range with gap) |

---

**End of Specification.**
