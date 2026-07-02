# AtlasEA v1.0 — AtlasContext Production Specification

**Document version:** 1.0
**Target module:** `Core/AtlasContext.mqh`
**Interface implemented:** `IContextStore` (from `Interfaces/IContextStore.mqh`)
**Consumed by:** RiskEngine, ExecutionEngine, TradeManager, PersistenceManager, ContextGuardian, ContextFactory, SnapshotManager, KillSwitchPropagator
**Constants:** `ATLAS_MAX_POSITIONS=64`, `ATLAS_IDEMPOTENCY_SLOTS=32`, `ATLAS_MODULE_*`, `ATLAS_CONTRACT_CONTEXT`

---

# 1. Responsibilities

AtlasContext is the **single shared runtime state container** of AtlasEA. It is NOT business logic, NOT an engine, NOT a service. It is a pure data holder that the entire system reads from and writes to through a strictly enforced interface. Every piece of mutable runtime state — risk metrics, position mirror, kill switch, telemetry, idempotency — lives here and nowhere else.

### R1.1 — State Container

| Attribute | Value |
|-----------|-------|
| **Purpose** | Hold ALL mutable runtime state in one fixed-size, stack-allocated structure. |
| **Ownership** | `CoreEngine` owns the single instance. All other modules receive `IContextStore*`. |
| **Inputs** | Setter calls from authorized modules. |
| **Outputs** | Getter calls returning current state. |
| **Performance limits** | O(1) for every getter and setter. No computation, no I/O. |
| **Failure handling** | Setters validate ranges; getters return defaults (0/empty) on invalid indices. Never throws. |
| **Forbidden behaviors** | Must NOT call MT5 APIs. Must NOT call ILogger. Must NOT emit events. Must NOT compute derived values. Must NOT allocate memory. |

### R1.2 — Kill Switch State

| Attribute | Value |
|-----------|-------|
| **Purpose** | Store the non-bypassable kill switch flag, reason, and activation time. |
| **Ownership** | Written by `KillSwitchPropagator` / `RiskEngine`. Read by all engines. |
| **Inputs** | `ActivateKillSwitch(reason)`, `DeactivateKillSwitch()` |
| **Outputs** | `IsKillSwitchActive()`, `GetKillSwitchReason()`, `GetKillSwitchTime()` |
| **Performance limits** | O(1) |
| **Failure handling** | Activation is idempotent (no-op if already active). Deactivation clears all three fields. |
| **Forbidden behaviors** | Must NOT auto-deactivate. Must NOT log. Must NOT close positions (that's the broker adapter's job). |

### R1.3 — Idempotency Ring

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track processed decision_ids to prevent duplicate order construction. |
| **Ownership** | Written by `ExecutionEngine`. Read by `ExecutionEngine`. |
| **Inputs** | `MarkDecisionProcessed(id)` |
| **Outputs** | `IsDecisionProcessed(id)` returns bool |
| **Performance limits** | O(N), N ≤ `ATLAS_IDEMPOTENCY_SLOTS` (32). ≤ 0.005 ms. |
| **Failure handling** | FIFO eviction when ring is full. |
| **Forbidden behaviors** | Must NOT persist across sessions (that's `PersistenceManager`'s job — it reads/writes the ring via `IContextStore`). |

### R1.4 — Position Mirror

| Attribute | Value |
|-----------|-------|
| **Purpose** | Cache a copy of broker positions for fast access by engines without broker queries. |
| **Ownership** | Written by `TradeManager.ReconcilePositions()`. Read by `RiskEngine`, `TradeManager`. |
| **Inputs** | `SetPositions(src[], count)` |
| **Outputs** | `GetPositionCount()`, `GetPosition(index, out)`, `GetOpenPositions(out[], count)` |
| **Performance limits** | O(N) for set, O(1) for get by index. |
| **Failure handling** | Index out of range → returns zeroed `PositionState`. |
| **Forbidden behaviors** | Must NOT query broker (positions are pushed in by `TradeManager`). |

### R1.5 — Telemetry Counters

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track lifetime counters (ticks, events, orders). |
| **Ownership** | Written by `CoreEngine`. Read by `PersistenceManager`, `SystemMonitor`. |
| **Inputs** | `IncrementTicksProcessed()`, `IncrementEventsEmitted()`, `IncrementOrdersSent()`, `IncrementOrdersFilled()` |
| **Outputs** | Getters returning `ulong` |
| **Performance limits** | O(1) |
| **Failure handling** | None — counters never fail. |
| **Forbidden behaviors** | Must NOT reset except via `ResetAll()` or `ResetDaily()`. |

### R1.6 — Context Versioning

| Attribute | Value |
|-----------|-------|
| **Purpose** | Monotonic counter incremented on every mutation, for optimistic concurrency and snapshot correlation. |
| **Ownership** | Internal — incremented by every setter. |
| **Inputs** | None (automatic). |
| **Outputs** | `GetContextVersion()` returns `ulong` |
| **Performance limits** | O(1) |
| **Failure handling** | Never wraps (ulong is 64-bit). |
| **Forbidden behaviors** | Must NOT be decremented. Must NOT be set externally. |

---

# 2. Owned State

### 2.1 — MarketState Reference

AtlasContext does NOT own `MarketState`. The `MarketEngine` produces a `MarketState` per tick (value type, stack-allocated in `PhaseScheduler`). The context only holds the **last seen snapshot_id** for correlation.

| Field | Type | Owner |
|-------|------|-------|
| `m_snapshot_id` | `long` | CoreEngine (via SnapshotManager) |

### 2.2 — RiskState

| Field | Type | Owner (writer) | Reader |
|-------|------|----------------|--------|
| `m_daily_start_equity` | `double` | ContextFactory.ResetDaily | RiskEngine |
| `m_daily_peak_equity` | `double` | RiskEngine (DrawdownManager) | RiskEngine, PersistenceManager |
| `m_daily_drawdown_pct` | `double` | RiskEngine | RiskEngine, PersistenceManager |
| `m_daily_realized_pnl` | `double` | RiskEngine.UpdateRiskState | PersistenceManager |
| `m_daily_trade_count` | `int` | RiskEngine.UpdateRiskState | PersistenceManager |
| `m_daily_loss_count` | `int` | RiskEngine.UpdateRiskState | PersistenceManager |
| `m_trading_day_start` | `datetime` | ContextFactory.ResetDaily | CoreEngine (daily check) |
| `m_current_exposure_pct` | `double` | RiskEngine.UpdateExposure | RiskEngine |
| `m_total_floating_pnl` | `double` | RiskEngine.UpdateExposure | RiskEngine |
| `m_consecutive_losses` | `int` | RiskEngine.UpdateRiskState | RiskEngine (CooldownManager) |
| `m_last_trade_time` | `datetime` | RiskEngine.UpdateRiskState | PersistenceManager |
| `m_cooldown_until` | `datetime` | RiskEngine (CooldownManager) | RiskEngine |

### 2.3 — PositionState Mirror

| Field | Type | Owner | Capacity |
|-------|------|-------|----------|
| `m_positions[]` | `PositionState[]` | TradeManager | `ATLAS_MAX_POSITIONS` (64) |
| `m_position_count` | `int` | TradeManager | — |

### 2.4 — Configuration

AtlasContext does NOT own configuration. `AtlasConfig` is owned by `CoreEngine` and passed by const reference to engines. The context does not store a copy.

### 2.5 — Snapshot ID

| Field | Type | Owner |
|-------|------|-------|
| `m_snapshot_id` | `long` | CoreEngine (via SnapshotManager) |

### 2.6 — Kill Switch

| Field | Type | Owner |
|-------|------|-------|
| `m_kill_switch_active` | `bool` | KillSwitchPropagator / RiskEngine |
| `m_kill_switch_reason` | `string` | KillSwitchPropagator |
| `m_kill_switch_time` | `datetime` | KillSwitchPropagator |

### 2.7 — Metrics / Telemetry

| Field | Type | Owner |
|-------|------|-------|
| `m_total_ticks_processed` | `ulong` | CoreEngine |
| `m_total_events_emitted` | `ulong` | CoreEngine |
| `m_total_orders_sent` | `ulong` | CoreEngine |
| `m_total_orders_filled` | `ulong` | CoreEngine |

### 2.8 — System Health

Not stored on the context. `SystemMonitor` (future Diagnostics module) owns health metrics. The context only stores the `m_context_version` for change detection.

### 2.9 — Caches

| Field | Type | Owner | Purpose |
|-------|------|-------|---------|
| `m_processed_decisions[]` | `string[32]` | ExecutionEngine | Idempotency ring |
| `m_processed_count` | `int` | ExecutionEngine | Ring fill level |

### 2.10 — Statistics

No rolling statistics on the context. Statistics (latency, queue depth, etc.) live in `PipelineStatistics`, `EventDispatcher`, etc. The context only holds lifetime counters (Section 2.7).

---

# 3. Memory Layout

AtlasContext is a single class instance. All fields are private. The memory layout (approximate):

| Section | Fields | Size (approx) |
|---------|--------|---------------|
| Identity / time | snapshot_id, tick_time, trading_day_start | 24 bytes |
| Daily risk | 6 doubles + 2 ints | 56 bytes |
| Exposure | 2 doubles | 16 bytes |
| Kill switch | bool + string + datetime | ~40 bytes |
| Cooldown | int + 2 datetimes | 20 bytes |
| Position mirror | 64 × PositionState + int | ~6 KB |
| Idempotency ring | 32 × string + int | ~2 KB |
| Telemetry | 4 ulongs | 32 bytes |
| Versioning | 2 ulongs (context_version + writer fields) | 16 bytes |
| **Total** | | **~8.2 KB** |

All fields are stack-allocated (the instance lives on the `CoreEngine` stack). No heap allocation except for MQL5 string management (automatic).

---

# 4. Ownership Rules

| Rule | Description |
|------|-------------|
| **Single instance** | Exactly one `AtlasContext` exists, owned by `CoreEngine`. |
| **No sharing of pointers** | Other modules receive `IContextStore*` (the interface), never the concrete class. |
| **No cloning** | The context is never copied. It's too large (~8 KB) and semantically unique. |
| **No nested contexts** | No sub-contexts. One flat state bag. |
| **Lifetime = EA lifetime** | Created in `CoreEngine` constructor, destroyed in `CoreEngine` destructor. |

---

# 5. Single-Writer Enforcement

The `ContextGuardian` (backed by `PermissionMatrix`) enforces that only ONE module may write to a given contract at a time.

### Write Permission Matrix

| Module | Contract | Write Access |
|--------|----------|--------------|
| `ATLAS_MODULE_CORE` | `ATLAS_CONTRACT_CONTEXT` | ✅ (snapshot_id, tick_time, telemetry) |
| `ATLAS_MODULE_RISK` | `ATLAS_CONTRACT_CONTEXT` | ✅ (daily risk, exposure, kill switch, cooldown) |
| `ATLAS_MODULE_EXECUTION` | `ATLAS_CONTRACT_ORDER_REQUEST` | ✅ (idempotency ring) |
| `ATLAS_MODULE_TRADE` | `ATLAS_CONTRACT_CONTEXT` | ✅ (position mirror) |
| `ATLAS_MODULE_PERSISTENCE` | `ATLAS_CONTRACT_CONTEXT` | ✅ (recovery — overwrites all fields) |
| `ATLAS_MODULE_MARKET` | `ATLAS_CONTRACT_MARKET_STATE` | ❌ (MarketState is NOT on the context) |
| `ATLAS_MODULE_STRATEGY` | — | ❌ (Strategy Engine never writes to context) |
| `ATLAS_MODULE_MT5` | `ATLAS_CONTRACT_EVENT` | ❌ (emits events, does not write context) |

### Enforcement Mechanism

- Writers call `ContextGuardian.AcquireWriteAccess(module_id, contract_type)` before writing.
- The guardian checks `PermissionMatrix.AcquireOwnership()`.
- If denied, the writer logs WARN and aborts the write.
- After writing, the writer calls `ReleaseWriteAccess()`.
- This is cooperative (MQL5 is single-threaded) — it catches logic bugs, not race conditions.

---

# 6. Read-Only Views

All consumers except the authorized writer access the context through `IContextStore` getters. The getters are `const`-correct (logically — MQL5 `const` on methods is supported).

### Read Access

Any module with an `IContextStore*` may call any getter. No permission check is needed for reads (the guardian only governs writes).

### Write Access

Only modules with granted permissions (Section 5) may call setters. Setters are on the same `IContextStore` interface — the guardian is the enforcement layer, not the interface.

---

# 7. Write Permissions

(See Section 5 for the full matrix.)

### Setter Restrictions

| Setter Category | Authorized Module |
|-----------------|-------------------|
| Snapshot ID, tick time | CoreEngine |
| Telemetry counters | CoreEngine |
| Daily risk (equity, drawdown, counts) | RiskEngine |
| Exposure, floating PnL | RiskEngine |
| Kill switch | KillSwitchPropagator / RiskEngine |
| Cooldown, consecutive losses | RiskEngine |
| Position mirror | TradeManager |
| Idempotency ring | ExecutionEngine |
| Full reset | PersistenceManager (recovery), ContextFactory (daily reset) |

---

# 8. Snapshot Lifecycle

The context's relationship with snapshots:

1. **During operation:** `PersistenceManager.WriteSnapshot(ctx, id)` serializes the context to disk.
2. **On recovery:** `PersistenceManager.RecoverState(ctx)` deserializes and populates the context.
3. **Versioning:** Every setter increments `m_context_version`. The snapshot stores this version. On recovery, the version is restored.
4. **Correlation:** `m_snapshot_id` links the context to the market snapshot. Incremented by `SnapshotManager.AssignId()`.

The context itself does NOT manage snapshot files — it only provides the data to be serialized.

---

# 9. Versioning

| Field | Type | Purpose |
|-------|------|---------|
| `m_context_version` | `ulong` | Incremented on every mutation. Used for optimistic concurrency and snapshot correlation. |
| `m_snapshot_id` | `long` | Market snapshot correlation. Set by `SnapshotManager`. |

### Version Increment Rules

- Every setter that mutates a field calls `IncrementContextVersion()`.
- Getters do NOT increment.
- `ResetDaily()` and `ResetAll()` increment.
- The version is never decremented, never reset to 0 (except `ResetAll()`).

---

# 10. Synchronization Model

MQL5 EAs are **single-threaded per chart**. There are no race conditions. The context does NOT use locks, mutexes, or atomics.

### Cooperative Discipline

- The `ContextGuardian` enforces single-writer discipline at the logic level.
- If a module forgets to acquire write access, the guardian logs a WARN but the write still succeeds (defensive — better to log than to drop data).
- Future hardening could make the guardian strictly enforced (setters check ownership and refuse if not held).

---

# 11. Recovery Behavior

On startup:

1. `CoreEngine` creates a fresh `AtlasContext` (constructor sets all fields to defaults).
2. `CoreEngine` calls `PersistenceManager.RecoverState(ctx)`.
3. If a snapshot exists, `PersistenceManager` calls setters on the context to restore each field.
4. If no snapshot (cold start), the context remains at defaults.
5. `CoreEngine` checks `ctx.GetTradingDayStart()`. If 0, calls `ContextFactory.ResetDaily()`.
6. If `ctx.IsKillSwitchActive()` is true, it remains active until the next daily reset.

### Recovery Safety

- Recovery overwrites ALL fields (including version and telemetry).
- The idempotency ring is restored (processed decisions survive restart).
- The position mirror is NOT restored from the snapshot — `TradeManager` reconciles from the broker on the first tick.

---

# 12. Serialization Compatibility

### Snapshot Format Version

- `version=1` (stored in the snapshot file).
- The context does NOT store its own format version — the `PersistenceManager` handles versioning.

### Forward Compatibility

- New fields can be added to the context. The snapshot serializer adds new `key=value` lines.
- Old snapshots (missing new fields) are loaded; missing fields retain their constructor defaults.
- The reader ignores unknown keys (defensive parsing).

### Backward Compatibility

- Old readers cannot read new snapshots if required fields are missing.
- The version field gates this: if version > 1 and the reader only supports version 1, it rejects the snapshot.

### Field Add/Remove Policy

- Adding fields: safe (old snapshots still load; new fields get defaults).
- Removing fields: unsafe (old snapshots have the field, new readers ignore it — safe but wasteful).
- Renaming fields: treated as remove + add (old value lost, new field gets default).

---

# 13. Performance Constraints

| Operation | Complexity | Time Budget |
|-----------|------------|-------------|
| Any getter | O(1) | ≤ 0.001 ms |
| Any setter | O(1) | ≤ 0.001 ms |
| `IsDecisionProcessed(id)` | O(N), N ≤ 32 | ≤ 0.005 ms |
| `MarkDecisionProcessed(id)` | O(N), N ≤ 32 | ≤ 0.005 ms |
| `SetPositions(src[], count)` | O(N), N ≤ 64 | ≤ 0.01 ms |
| `GetPosition(index, out)` | O(1) | ≤ 0.001 ms |
| `ResetDaily()` | O(1) | ≤ 0.001 ms |
| `ResetAll()` | O(1) | ≤ 0.001 ms |

**Total per-tick context access budget:** ≤ 0.05 ms (all getters/setters combined).

---

# 14. Memory Constraints

| Constraint | Value |
|------------|-------|
| Total instance size | ~8.2 KB |
| Heap allocation | 0 (all stack/static) |
| Dynamic arrays | 0 (all fixed-size) |
| String fields | 35 strings (idempotency ring + kill_switch_reason) — managed by MQL5 runtime |
| Position mirror | 64 × ~96 bytes = ~6 KB |
| Idempotency ring | 32 × ~64 bytes = ~2 KB |

**No `new` or `delete` in any method.**

---

# 15. Validation Rules

| Field | Validation | On Violation |
|-------|------------|--------------|
| `snapshot_id` | Must be ≥ 0 | Setter accepts any long (CoreEngine guarantees monotonicity) |
| `daily_start_equity` | Must not be NaN | Setter uses `MathIsValidNumber`; NaN → ignored, logged by caller |
| `daily_peak_equity` | Must not be NaN | Same |
| `daily_drawdown_pct` | Must be ≥ 0 | Negative → clamped to 0 |
| `daily_trade_count` | Must be ≥ 0 | Negative → set to 0 |
| `consecutive_losses` | Must be ≥ 0 | Negative → set to 0 |
| `kill_switch_active` | Must be 0 or 1 | Other → treated as false |
| `positions[]` index | Must be in [0, count) | Out of range → zeroed PositionState |
| `processed_decisions[]` | FIFO eviction at 32 | No validation needed |
| `context_version` | Monotonic | Never decremented |

---

# 16. State Machine

AtlasContext itself does not have a state machine — it's a passive data holder. However, the **kill switch** and **daily reset** imply lifecycle states:

```
    COLD_START (constructor defaults)
       │
       │ RecoveryState() loads snapshot
       ▼
    RECOVERED (snapshot loaded)
       │
       │ ResetDaily() if new day or cold start
       ▼
    ACTIVE (normal operation)
       │
       ├── KillSwitch Activate() ──► KILL_SWITCH_ACTIVE
       │                                │
       │                                │ ResetDaily() (new day)
       │                                ▼
       │                              ACTIVE (kill switch cleared)
       │
       └── Shutdown() ──► DESTROYED
```

### Context Lifecycle States

| State | Description |
|-------|-------------|
| **COLD_START** | Just constructed. All fields at defaults. |
| **RECOVERED** | Snapshot loaded. Fields restored. |
| **ACTIVE** | Normal operation. Daily reset applied. |
| **KILL_SWITCH_ACTIVE** | Kill switch is on. All trades rejected. |
| **DESTROYED** | Destructor called. Instance no longer valid. |

---

# 17. Security Constraints

### 17.1 — AtlasContext MUST NEVER Call MT5 APIs

No `SymbolInfoTick`, `AccountInfoDouble`, `OrderSend`, `PositionsTotal`. The context is pure data.

### 17.2 — AtlasContext MUST NEVER Call ILogger

The context does not log. Logging is the caller's responsibility. (This keeps the context dependency-free.)

### 17.3 — AtlasContext MUST NEVER Emit Events

No `IEventBus::EmitEvent`. The context is passive.

### 17.4 — AtlasContext MUST NEVER Compute Derived Values

No `CalculateDrawdown()`, no `ComputeExposure()`. Those are engine responsibilities. The context only stores what engines compute.

### 17.5 — AtlasContext MUST NEVER Allocate Memory

No `new`, no `ArrayResize`. All arrays are fixed-size at compile time.

### 17.6 — AtlasContext MUST NEVER Be Copied

The instance is unique. Copying would duplicate ~8 KB and break the single-state-owner invariant. (MQL5 does not have deleted copy constructors, so this is a discipline rule.)

### 17.7 — AtlasContext MUST NEVER Reset Itself Spontaneously

`ResetDaily()` and `ResetAll()` are only called by `ContextFactory` (authorized). The context does not self-reset.

### 17.8 — AtlasContext MUST NEVER Hold Pointers to Other Modules

No `IBrokerAdapter*`, no `IEventBus*`, no `ILogger*`. The context is a leaf — it depends on nothing.

---

# 18. Edge Cases

| # | Edge Case | Behavior |
|---|-----------|----------|
| EC1 | Setter called with NaN | `MathIsValidNumber` check; NaN → ignore, field unchanged |
| EC2 | `SetPositions` called with count > 64 | Truncate to 64 |
| EC3 | `GetPosition` called with index ≥ count | Return zeroed PositionState |
| EC4 | `MarkDecisionProcessed` called with empty string | Accept (defensive) — but unlikely to match anything |
| EC5 | `ActivateKillSwitch` called when already active | No-op (idempotent) |
| EC6 | `DeactivateKillSwitch` called when inactive | No-op |
| EC7 | `ResetDaily` called twice in same day | Allowed (idempotent) — resets equity to current |
| EC8 | `ResetAll` called during operation | Allowed but destructive — all state lost. Only called by `ContextFactory` on explicit reset. |
| EC9 | Recovery loads snapshot from previous day | Loaded as-is. `CoreEngine` detects new day and calls `ResetDaily()`. |
| EC10 | Recovery loads snapshot with kill switch active | Loaded as-is. Kill switch remains active until daily reset. |
| EC11 | Recovery loads snapshot with NaN equity | `PersistenceManager` should validate before calling setter. If it reaches the setter, NaN is ignored. |
| EC12 | Context version overflow (ulong max) | Wraps to 0. Practically impossible (would need 2^64 mutations). |
| EC13 | Idempotency ring full (32 entries) | FIFO eviction — oldest entry removed. |
| EC14 | `SetPositions` called with count = 0 | `m_position_count` set to 0. Array contents unchanged but inaccessible. |
| EC15 | Getter called before any setter | Returns default (0, 0.0, empty string, false). |
| EC16 | Two modules try to write simultaneously | Single-threaded — impossible. `ContextGuardian` catches logic bugs if they occur. |
| EC17 | Context used after `Shutdown` | Not possible — `CoreEngine` destructor deletes the context. |
| EC18 | Snapshot ID set to negative | Accepted (no validation). `SnapshotManager` guarantees positivity upstream. |
| EC19 | `IncrementContextVersion` called 2^64 times | Wraps to 0. Not a concern. |
| EC20 | Position mirror has stale data (broker changed) | Not the context's problem. `TradeManager.ReconcilePositions()` pushes fresh data. |

---

# 19. Production Checklist

### 19.1 — Contract Alignment

- [ ] `IContextStore` interface matches `Interfaces/IContextStore.mqh` exactly (~40 methods).
- [ ] All getters/setters present and correctly typed.
- [ ] Constants: `ATLAS_MAX_POSITIONS`, `ATLAS_IDEMPOTENCY_SLOTS`.

### 19.2 — Dependency Alignment

- [ ] NO dependencies on any interface or module. AtlasContext is a leaf.
- [ ] NO `#include` except `Config/Settings.mqh`, `Contracts/Events.mqh`, `Interfaces/IContextStore.mqh`.

### 19.3 — Memory Verification

- [ ] All arrays fixed-size (`PositionState[64]`, `string[32]`).
- [ ] No `new` or `delete` in any method.
- [ ] No `ArrayResize`.
- [ ] Total instance size < 10 KB.

### 19.4 — Performance Verification

- [ ] All getters O(1) (except idempotency check which is O(32)).
- [ ] All setters O(1) (except `SetPositions` which is O(64)).
- [ ] No I/O, no logging, no computation.

### 19.5 — Single-Writer Compliance

- [ ] Setters do NOT call `ContextGuardian` directly (that's the caller's job).
- [ ] The context trusts that the caller has acquired write access.
- [ ] `ContextGuardian` is enforced at the `CoreEngine`/engine level, not inside the context.

### 19.6 — Recovery Compliance

- [ ] All fields restorable via setters (no private-only fields).
- [ ] `ResetAll()` clears everything to constructor defaults.
- [ ] `ResetDaily()` clears only daily fields (not telemetry, not positions).

### 19.7 — MQL5 Compliance

- [ ] Include guards.
- [ ] No `#pragma once`.
- [ ] No `->`.
- [ ] No STL.
- [ ] No dynamic arrays in the class.

### 19.8 — Security Compliance

- [ ] No MT5 API calls.
- [ ] No logger calls.
- [ ] No event emission.
- [ ] No derived value computation.
- [ ] No pointers to other modules.

### 19.9 — Documentation

- [ ] Doxygen on every getter/setter.
- [ ] Doxygen on the class.
- [ ] Header comment block.

### 19.10 — Integration Points

- [ ] `CoreEngine` owns the instance.
- [ ] All engines receive `IContextStore*`.
- [ ] `PersistenceManager` reads/writes via `IContextStore`.
- [ ] `ContextGuardian` attaches to the instance.

### 19.11 — Versioning

- [ ] File header: `AtlasEA v0.1.7.0` (AtlasContext infrastructure phase).

---

**End of Specification.**

This document is implementation-ready. AtlasContext is the single shared state container — pure data, no logic, no dependencies, no I/O. All engines read and write through `IContextStore` under `ContextGuardian` enforcement. The context is the heart of AtlasEA's runtime state.
