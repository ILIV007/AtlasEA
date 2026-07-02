# AtlasEA v1.0 — Strategy Engine Production Specification

**Document version:** 1.0
**Target module:** `Engines/StrategyEngine.mqh` (+ internal helpers under `Engines/StrategyEngine/`)
**Interface implemented:** `IStrategySet` (defined in `Interfaces/IStrategySet.mqh`)
**Contracts consumed:** `MarketState` (from `Contracts/MarketState.mqh`), `StrategyVote` (from `Contracts/RiskDecision.mqh`)
**Constants available:** `ATLAS_MAX_STRATEGIES = 8`, `ATLAS_MAX_VOTES = 16`, `ATLAS_FEATURE_SIZE = 32`, `ATLAS_ORDER_BUY = 1`, `ATLAS_ORDER_SELL = -1`, `ATLAS_ORDER_NONE = 0`, `ATLAS_MIN_CONFIDENCE = 0.30`, `ATLAS_LOG_*` levels

---

# 1. Strategy Engine Responsibilities

The Strategy Engine is the **decision-proposing layer** of AtlasEA. It never executes trades, never queries the broker, never touches account state, and never mutates shared context. Its sole output is a set of `StrategyVote` structs that the Core Engine's `VoteAggregator` merges into an `AggregatedVote` for the Risk Engine.

### R1.1 — MarketState Validation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reject invalid or stale market states before any strategy executes. |
| **Owner** | `StrategyEngine` (entry point of `EvaluateStrategies`) |
| **Inputs** | `const MarketState &state` |
| **Outputs** | Boolean: proceed or abort (abort → return 0 votes) |
| **Failure handling** | On invalid state, return 0 immediately. Log WARN with `invalid_reason`. |
| **Performance constraints** | O(1), ≤ 0.05 ms. |
| **Forbidden behaviors** | Must NOT call `state.features[i]` before checking `state.is_valid`. Must NOT modify the state. Must NOT call any broker/account/position API. |

Validation checks (fail-fast): `is_valid`, `snapshot_id > 0`, `feature_count == 32`, `atr_14 > 0`, `timestamp > 0`, `symbol` non-empty.

### R1.2 — Snapshot Validation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Ensure strategies evaluate against a valid snapshot. |
| **Owner** | `StrategyEngine` |
| **Inputs** | `state.snapshot_id` |
| **Outputs** | Boolean |
| **Failure handling** | Reject if ≤ 0. |
| **Forbidden behaviors** | Must NOT cache snapshot_id across ticks. |

### R1.3 — Strategy Execution

| Attribute | Value |
|-----------|-------|
| **Purpose** | Run each enabled strategy and collect raw votes. |
| **Owner** | `StrategyRunner` (internal) |
| **Inputs** | Validated `MarketState`, enabled `StrategyEntry` descriptors |
| **Outputs** | Array of `StrategyVote` (0..ATLAS_MAX_VOTES) |
| **Failure handling** | Per-strategy isolation: invalid output → skip, increment failure counter, continue. |
| **Performance constraints** | Total ≤ 2 ms. Per-strategy: 0.25 ms. |
| **Forbidden behaviors** | Must NOT share mutable state between strategies. |

### R1.4 — Vote Normalization

| Attribute | Value |
|-----------|-------|
| **Purpose** | Clamp and sanitize every vote field. |
| **Owner** | `VoteValidator` (internal) |
| **Inputs** | Raw `StrategyVote` |
| **Outputs** | Validated vote or rejection |
| **Failure handling** | Discard invalid votes silently. |
| **Performance constraints** | O(1) per vote |

### R1.5 — Vote Collection & Return

| Attribute | Value |
|-----------|-------|
| **Purpose** | Collect validated votes into caller-provided array. |
| **Owner** | `StrategyEngine` |
| **Inputs** | Caller-allocated `StrategyVote &votes[]` |
| **Outputs** | Vote count (0..ATLAS_MAX_VOTES) |
| **Failure handling** | Truncate if array too small. Log WARN. |
| **Performance constraints** | O(N), N ≤ ATLAS_MAX_VOTES |

### R1.6 — Metrics Collection

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track per-strategy and aggregate statistics. |
| **Owner** | `StrategyStatistics` (internal) |
| **Inputs** | Per-evaluation: strategy_id, execution time, result |
| **Performance constraints** | O(1) per update |

### R1.7 — Kill Switch Awareness

| Attribute | Value |
|-----------|-------|
| **Purpose** | Skip all evaluation if kill switch is active. |
| **Owner** | `StrategyEngine` |
| **Inputs** | `IContextStore::IsKillSwitchActive()` |
| **Outputs** | 0 votes if active |
| **Performance constraints** | O(1), checked first |

### R1.8 — Fast Market Awareness

| Attribute | Value |
|-----------|-------|
| **Purpose** | Per-strategy decision (NOT a global skip). |
| **Owner** | Individual strategies |
| **Forbidden behaviors** | Engine must NOT globally skip on fast market. |

---

# 2. Internal Components

### 2.1 — StrategyRegistry

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Store registered strategy descriptors. Lookup. Uniqueness. Max count. |
| **Owned data** | `StrategyEntry[ATLAS_MAX_STRATEGIES]`, count |
| **Public API** | `Register()`, `Unregister()`, `Find()`, `Count()`, `Reset()`, `GetEnabled()` |
| **Private helpers** | `FindIndex()` |
| **Dependencies** | `StrategyEntry` struct, `ATLAS_MAX_STRATEGIES` |
| **Failure modes** | Full → false. Duplicate → false. |

### 2.2 — StrategyRunner

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Execute a single strategy. Isolate failures. |
| **Owned data** | None |
| **Public API** | `Run(entry, state, out_vote, out_elapsed_ms)` |
| **Private helpers** | `ValidateOutput()`, `BuildAbstainVote()` |
| **Failure modes** | NaN → discard. Invalid direction → discard. |

### 2.3 — VoteValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Validate and normalize a raw vote. |
| **Public API** | `Validate(in, out, out_reason)` |
| **Private helpers** | `IsValidDirection()`, `IsValidConfidence()`, `IsValidPrice()`, `Clamp()` |

### 2.4 — ConfidenceNormalizer

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Apply weight, clamp [0,1]. |
| **Public API** | `Normalize(raw_confidence, weight)` |

### 2.5 — StrategyStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track per-strategy metrics. |
| **Owned data** | `StrategyStatEntry[ATLAS_MAX_STRATEGIES]` |
| **Public API** | `RecordEvaluation()`, `Reset()`, `GetStats()`, `LogSummary()` |

### 2.6 — StrategyEngine (main)

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Implement `IStrategySet`. Orchestrate pipeline. |
| **Owned data** | All 5 internal components + logger + config + context |
| **Public API** | `SetDependencies()`, `EvaluateStrategies()`, `Initialize()`, `Shutdown()`, `RegisterStrategy()`, `LogDiagnostics()` |

---

# 3. Strategy Lifecycle

### 3.1 — Initialization
1. `SetDependencies(logger, context, config)` called before `Initialize()`.
2. `Initialize()` validates logger != NULL.
3. Resets registry, registers built-in strategies, resets stats.
4. Sets `m_initialized = true`.

### 3.2 — Registration
- `RegisterStrategy(entry)` → `Registry.Register()` validates capacity, duplicate, valid ID.

### 3.3 — Loading
- Identical to registration (no dynamic loading in this phase).

### 3.4 — Enable / Disable
- `StrategyEntry.enabled` field. Runtime mutation. No re-init needed.

### 3.5 — Evaluation
- See Section 6.

### 3.6 — Vote Generation
- Directional vote (BUY/SELL, confidence > 0) or abstention (NONE, 0).

### 3.7 — Vote Validation
- See `VoteValidator` component.

### 3.8 — Cleanup
- No per-tick cleanup. Fixed-size arrays.

### 3.9 — Shutdown
1. Log stats summary.
2. Reset registry.
3. Set `m_initialized = false`.

### 3.10 — Recovery
- Stateless across sessions. No persistence. Re-registers on restart.

---

# 4. Strategy Interface

### 4.1 — Class: `IStrategy`

| Method | Signature |
|--------|-----------|
| `Evaluate` | `virtual StrategyVote Evaluate(const MarketState &state) = 0` |
| `GetId` | `virtual int GetId() const = 0` |
| `GetName` | `virtual string GetName() const = 0` |
| `GetVersion` | `virtual string GetVersion() const = 0` |
| `GetWeight` | `virtual double GetWeight() const = 0` |
| `Initialize` | `virtual bool Initialize(const AtlasConfig &config) = 0` |
| `Shutdown` | `virtual void Shutdown() = 0` |

### 4.2 — Inputs
- `MarketState` (pre-validated), `AtlasConfig` (trusted)

### 4.3 — Outputs
- `StrategyVote` (post-validated by VoteValidator)

### 4.4 — Error Codes
- No error codes. Abstention = `direction=NONE, confidence=0`. Invalid output = discarded.

### 4.5 — Validation Rules (Strategy-side)
- Read only from `MarketState`. No broker APIs. No `Print()`. No `new`. No modification of state. ≤ 0.25 ms.

### 4.6 — Versioning
- `GetVersion()` stamped onto every vote.

---

# 5. Strategy Registry

### 5.1 — Registration Process
- Validate `entry.strategy_id > 0`, unique, capacity available.

### 5.2 — Duplicate Prevention
- Duplicate ID → reject. Duplicate name → allowed (logged DEBUG).

### 5.3 — Priority
- `priority` field (int, lower = higher priority). Evaluated in priority order.

### 5.4 — Weights
- `weight` field [0.1, 2.0], default 1.0. Applied to confidence.

### 5.5 — Tags
- `tags` string (informational only in this phase).

### 5.6 — Categories
- `category` enum (TREND, REVERSION, MOMENTUM, BREAKOUT, CUSTOM).

### 5.7 — Hot Reload Policy
- No hot reload. Enable/disable only runtime mutation.

### 5.8 — Maximum Strategies
- `ATLAS_MAX_STRATEGIES = 8` (compile-time).

### 5.9 — Disabled Strategies
- Remain registered, skipped during evaluation.

### 5.10 — Strategy Versioning
- Version stored in `StrategyEntry`, stamped on every vote.

---

# 6. Evaluation Pipeline

### Stage 1 — MarketState Validation
- Check `is_valid`, `snapshot_id`, `feature_count`, `atr_14`, `timestamp`, `symbol`.

### Stage 2 — Snapshot Validation
- Check `snapshot_id > 0`.

### Stage 3 — Kill Switch Check
- If active: return 0.

### Stage 4 — Context Preparation
- None needed (strategies receive MarketState directly).

### Stage 5 — Strategy Execution
- `GetEnabled()` → iterate in priority order → `Run()` each.

### Stage 6 — Vote Normalization
- Apply weight inside `StrategyRunner.Run()`.

### Stage 7 — Vote Validation
- `VoteValidator.Validate()` → discard invalid.

### Stage 8 — Result Collection
- Copy to caller array. Cap at `ATLAS_MAX_VOTES`.

### Stage 9 — Timeout Handling
- Per-strategy: 0.25 ms soft limit (logged). Total: CoreEngine budget.

### Stage 10 — Failure Isolation
- Per-strategy failures do NOT affect others.

### Stage 11 — Statistics Update
- O(1) counter increments.

### Stage 12 — Return to Core Engine
- Return vote count.

---

# 7. StrategyVote Specification

### Field: `strategy_id`
- **Meaning:** Unique strategy identifier.
- **Type:** `int`
- **Range:** 1 to INT_MAX.
- **Validation:** > 0, must exist in registry.
- **Default:** 0 (invalid).
- **Immutability:** Immutable after validation.

### Field: `strategy_version`
- **Meaning:** Strategy version string.
- **Type:** `string`
- **Range:** Non-empty, max 16 chars.
- **Validation:** `StringLen > 0`.
- **Default:** "" (invalid).

### Field: `direction`
- **Meaning:** Proposed trade direction.
- **Type:** `int`
- **Range:** `{-1, 0, 1}`.
- **Validation:** Must be one of the three. NONE = abstention.
- **Default:** 0.

### Field: `confidence`
- **Meaning:** Strategy confidence after weight normalization.
- **Type:** `double`
- **Range:** [0.0, 1.0].
- **Validation:** Not NaN, not infinite, in [0,1] after clamp.
- **Default:** 0.0.

### Field: `suggested_volume`
- **Meaning:** Suggested volume in lots.
- **Type:** `double`
- **Range:** [0.0, 100.0]. 0 = use default.
- **Validation:** Not NaN, ≥ 0.
- **Default:** 0.0.

### Field: `suggested_entry`
- **Meaning:** Suggested entry price.
- **Type:** `double`
- **Range:** > 0.0.
- **Validation:** Not NaN, > 0.
- **Default:** 0.0 (invalid).

### Field: `suggested_sl`
- **Meaning:** Suggested stop-loss.
- **Type:** `double`
- **Range:** > 0.0.
- **Validation:** Not NaN, > 0 (for directional votes).
- **Default:** 0.0 (invalid for directional).

### Field: `suggested_tp`
- **Meaning:** Suggested take-profit.
- **Type:** `double`
- **Range:** > 0.0.
- **Validation:** Same as SL.
- **Default:** 0.0 (invalid for directional).

### Field: `snapshot_id`
- **Meaning:** MarketState snapshot this vote was generated against.
- **Type:** `long`
- **Range:** > 0.
- **Validation:** Must equal `state.snapshot_id`.
- **Default:** 0 (invalid).

### Field: `vote_time`
- **Meaning:** Timestamp of vote generation.
- **Type:** `datetime`
- **Range:** > 0.
- **Validation:** > 0.
- **Default:** 0 (invalid).

---

# 8. Confidence Model

### 8.1 — Confidence Calculation
- Raw confidence in [0,1] from strategy.

### 8.2 — Clamping
- `VoteValidator` clamps to [0,1] before weight. NaN → 0.0 (discard).

### 8.3 — Normalization (Weight Application)
- `normalized = raw × weight`, clamped to [0,1].

### 8.4 — Calibration
- Static weights from config. No adaptive calibration in this phase.

### 8.5 — Weight Interaction
- Weights multiply confidence, not direction.

### 8.6 — Multiple Signals
- One vote per strategy per evaluation. Internal conflict resolution is strategy's responsibility.

### 8.7 — Neutral Confidence
- 0.0 = abstention (discarded). Below 0.30 = valid but weak (Risk Engine rejects).

### 8.8 — Conflicting Signals
- Not resolved by Strategy Engine. All valid votes returned. VoteAggregator handles.

### 8.9 — Invalid Confidence
- NaN/infinite → discard + failure counter increment.

---

# 9. Multi Strategy Behaviour

### 9.1 — Isolation
- Full isolation. No shared mutable state. No cross-strategy visibility.

### 9.2 — Shared State
- Only immutable `MarketState` (read-only).

### 9.3 — Weighting
- Per-strategy weight applied to confidence.

### 9.4 — Conflict Handling
- Not resolved by Strategy Engine. VoteAggregator sums confidence per direction.

### 9.5 — Priority
- Lower priority number = executes first. Budget may exhaust lower-priority strategies.

### 9.6 — Consensus
- Not required. Single strategy vote is sufficient (subject to Risk Engine).

### 9.7 — Abstain
- `direction=NONE` → silently discarded (not a failure).

### 9.8 — Duplicate Votes
- Both returned. Deduplication is VoteAggregator's job.

### 9.9 — Disabled Strategy
- Not evaluated. No votes produced.

### 9.10 — Unknown Strategy
- Cannot produce votes (never invoked). ID mismatch → ERROR + discard.

---

# 10. Error Isolation

### 10.1 — Timeouts
- Soft: 0.25 ms per strategy. Logged WARN. Vote still used.

### 10.2 — Exceptions
- MQL5 has no try/catch. "Exception" = invalid output. VoteValidator catches.

### 10.3 — Invalid Outputs
- Bad direction, NaN confidence, zero prices → discarded.

### 10.4 — Memory Corruption Detection
- Array bounds, string length, numeric range checks.

### 10.5 — NaN Detection
- `MathIsValidNumber()` on every double field.

### 10.6 — Overflow
- Not possible (validation bounds all values).

### 10.7 — Invalid Arrays
- Caller array checked: < ATLAS_MAX_VOTES → truncate + WARN. Size 0 → return 0.

### 10.8 — Stale Snapshot
- Vote snapshot_id != input state snapshot_id → discard.

### 10.9 — Contract Mismatch
- `feature_count != 32` → reject entire evaluation.

---

# 11. Performance Budget

### 11.1 — Maximum Evaluation Time
- Total: ≤ 2 ms. Per-strategy: ≤ 0.25 ms.

### 11.2 — Memory Budget
- Registry: ~1 KB. Stats: ~512 B. Vote buffer: ~2 KB. Total: ~3.5 KB stack.

### 11.3 — No Dynamic Allocation
- `new`/`delete` forbidden in `EvaluateStrategies`.

### 11.4 — Fixed Arrays
- `StrategyEntry[8]`, `StrategyStatEntry[8]`, `StrategyVote[16]`.

### 11.5 — Maximum Strategies
- 8 (compile-time).

### 11.6 — Maximum Metadata
- Name: 32 chars. Version: 16 chars. Tags: 64 chars.

---

# 12. Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `evaluations` | `ulong` | Total evaluations per strategy. |
| `successes` | `ulong` | Valid directional votes. |
| `abstentions` | `ulong` | NONE votes. |
| `failures` | `ulong` | Invalid votes. |
| `success_rate` | `double` | successes / evaluations. |
| `abstain_rate` | `double` | abstentions / evaluations. |
| `average_confidence` | `double` | Sum confidence / successes. |
| `average_latency_ms` | `double` | Total latency / evaluations. |
| `peak_latency_ms` | `double` | Max single-evaluation latency. |
| `uptime_ticks` | `ulong` | Ticks since registration. |

---

# 13. Logging

| Level | Category | When |
|-------|----------|------|
| DEBUG | Per-strategy result | If `log_level <= DEBUG` |
| DEBUG | Kill switch skip | When skipped |
| INFO | Init / Shutdown / Registration / Diagnostics | Lifecycle events |
| WARN | Invalid MarketState / Timeout / Vote failure / Array too small | Anomalies |
| ERROR | Strategy ID mismatch / Not initialized / Logger NULL | Serious issues |
| FATAL | Registry corruption | Should never happen |

**Hot path rule:** No logging inside per-tick loop unless DEBUG level configured.

---

# 14. Edge Cases

| # | Case | Behavior |
|---|------|----------|
| EC1 | No MarketState | Validation fails, return 0 |
| EC2 | Invalid MarketState | Return 0, log WARN |
| EC3 | No strategies | Return 0, log DEBUG |
| EC4 | All disabled | Return 0, log DEBUG |
| EC5 | Duplicate ID | Reject registration, log WARN |
| EC6 | Confidence 0 + direction BUY | Valid vote (Risk Engine rejects) |
| EC7 | Confidence 0.5 + direction NONE | Abstention, discarded |
| EC8 | NaN confidence | Discard, failure++, WARN |
| EC9 | NaN entry price | Discard, failure++, WARN |
| EC10 | direction = 5 | Discard, failure++, WARN |
| EC11 | 5 ms timeout | Vote used, WARN logged |
| EC12 | feature_count != 32 | Abort, return 0, ERROR |
| EC13 | Snapshot mismatch | Discard vote, WARN |
| EC14 | Registry corruption | FATAL, return 0 |
| EC15 | Negative weight | Reject registration, ERROR |
| EC16 | Kill switch active | Return 0, DEBUG |
| EC17 | Fast market | Strategies still evaluate |
| EC18 | Array size 0 | Return 0, WARN |
| EC19 | Array < MAX_VOTES | Truncate, WARN |
| EC20 | Not initialized | Return 0, ERROR |
| EC21 | Logger NULL | Best-effort, no crash |
| EC22 | Context NULL | Skip kill switch, ERROR once |
| EC23 | Valid direction, zero SL/TP | Discard, WARN |
| EC24 | > MAX_VOTES valid votes | Truncate, WARN |
| EC25 | Empty version | Discard, WARN |

---

# 15. Validation Matrix

| Field | Validation | Action | Severity | Recovery |
|-------|------------|--------|----------|----------|
| `state.is_valid` | Must be true | Abort, return 0 | WARN | None |
| `state.snapshot_id` | > 0 | Abort, return 0 | WARN | None |
| `state.feature_count` | == 32 | Abort, return 0 | ERROR | None |
| `state.atr_14` | > 0 | Abort, return 0 | WARN | None |
| `state.timestamp` | > 0 | Abort, return 0 | WARN | None |
| `state.symbol` | Non-empty | Abort, return 0 | WARN | None |
| Kill switch | Inactive | Return 0 | DEBUG | None |
| `strategy_id` | > 0 | Discard vote | WARN | Continue |
| `strategy_id` | In registry | Discard vote | ERROR | Continue |
| `strategy_version` | Non-empty | Discard vote | WARN | Continue |
| `direction` | In {-1,0,1} | Discard vote | WARN | Continue |
| `direction` | NONE → abstention | Discard (not failure) | DEBUG | Continue |
| `confidence` | Not NaN | Discard vote | WARN | Continue |
| `confidence` | In [0,1] after clamp | Clamp, accept | DEBUG | None |
| `suggested_entry` | > 0 | Discard vote | WARN | Continue |
| `suggested_sl` | > 0 (directional) | Discard vote | WARN | Continue |
| `suggested_tp` | > 0 (directional) | Discard vote | WARN | Continue |
| `suggested_volume` | ≥ 0 | Set to 0 (default) | DEBUG | None |
| `snapshot_id` (vote) | == state.snapshot_id | Discard vote | WARN | Continue |
| `vote_time` | > 0 | Set to TimeCurrent() | DEBUG | None |
| Caller array | Size ≥ 1 | Return 0 | WARN | None |
| Caller array | Size ≥ MAX_VOTES | Truncate | WARN | None |
| Strategy weight | [0.1, 2.0] | Clamp | WARN | None |
| Strategy elapsed | ≤ 0.25 ms | Log WARN, accept | WARN | None |

---

# 16. State Machine

```
UNREGISTERED → REGISTERED → ENABLED → RUNNING → (ENABLED | FAILED)
                                        │              │
                                        │              │ ≥3 failures
                                        │              ▼
                                        │          RECOVERING → ENABLED
                                        │
                                    DISABLED → ENABLED
```

| State | Description |
|-------|-------------|
| **UNREGISTERED** | Not in registry. |
| **REGISTERED** | In registry, disabled. |
| **ENABLED** | Ready to evaluate. |
| **RUNNING** | Currently executing. |
| **FAILED** | Last output invalid. |
| **DISABLED** | Explicitly disabled. |
| **RECOVERING** | Cooldown after 3+ failures. |

---

# 17. Production Checklist

### 17.1 — Contract Alignment
- [ ] `StrategyVote` matches `Contracts/RiskDecision.mqh`.
- [ ] `MarketState` matches `Contracts/MarketState.mqh`.
- [ ] `IStrategySet` matches `Interfaces/IStrategySet.mqh`.
- [ ] Constants: `ATLAS_MAX_STRATEGIES`, `ATLAS_MAX_VOTES`, `ATLAS_FEATURE_SIZE`, `ATLAS_ORDER_*`, `ATLAS_MIN_CONFIDENCE`.

### 17.2 — Dependency Alignment
- [ ] `ILogger`, `IContextStore`, `AtlasConfig` available.
- [ ] NO dependency on `IBrokerAdapter`, `IRiskEvaluator`, `IOrderBuilder`, `IMarketDataSource`.

### 17.3 — File Structure
- [ ] `Engines/StrategyEngine.mqh`
- [ ] `Engines/StrategyEngine/`: StrategyEntry, StrategyRegistry, StrategyRunner, VoteValidator, ConfidenceNormalizer, StrategyStatistics, IStrategy, TrendFollowerStrategy, MeanReversionStrategy, MomentumStrategy, BreakoutStrategy

### 17.4 — Performance
- [ ] No `new`/`delete`. No `Print()`. No broker APIs. No file I/O. No recursion. Fixed arrays. < 4 KB stack.

### 17.5 — MQL5 Compliance
- [ ] Include guards. No `#pragma once`. No `->`. No STL. No dynamic arrays in structs.

### 17.6 — Feature Vector Usage

| Strategy | Features Used |
|----------|---------------|
| Trend Follower | 16, 17, 19, 4 |
| Mean Reversion | 9, 8, 13 |
| Momentum | 11, 12, 14 |
| Breakout | 8, 7, 19 |

### 17.7 — Error Handling
- [ ] Input validation on every public method.
- [ ] Strategy failure isolation.
- [ ] NaN checks on all doubles.
- [ ] Array bounds checks.

### 17.8 — Documentation
- [ ] Doxygen on every class/method/member.

### 17.9 — Integration
- [ ] `SetDependencies()` signature matches CoreEngine.
- [ ] Output array caller-allocated.

### 17.10 — Versioning
- [ ] File header: `AtlasEA v0.1.2.0`.
- [ ] All strategies return version "1.0.0".

---

**End of Specification.**
