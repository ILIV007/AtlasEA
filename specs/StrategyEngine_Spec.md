# AtlasEA v1.0 — Strategy Engine & Framework Production Specification

**Document version:** 2.0 (updated v0.1.10.0)
**Target module:** `Engines/StrategyEngine.mqh` (+ `Engines/StrategyFramework/`)
**Interface implemented:** `IStrategySet`
**Contracts consumed:** `MarketState`, `StrategyVote`

---

# 1. Architecture Overview

The Strategy Engine is now a **pluggable framework**. No trading strategies are hardcoded. Instead, the framework provides:

- `IStrategy` — interface every strategy implements
- `StrategyMetadata` — immutable descriptor
- `StrategyContext` — read-only context (MarketState + Config + Logger only)
- `StrategyRegistry` — registration, lookup, enable/disable
- `VoteBuilder` — validated vote construction
- `StrategyExecutor` — isolated execution with failure handling
- `StrategyEngine` — thin adapter implementing `IStrategySet`

```
┌─────────────────────────────────────────────────────┐
│                   CoreEngine                        │
│                (IStrategySet consumer)              │
└──────────────────────┬──────────────────────────────┘
                       │ EvaluateStrategies()
                       ▼
┌─────────────────────────────────────────────────────┐
│                  StrategyEngine                     │
│            (implements IStrategySet)                │
├─────────────────────────────────────────────────────┤
│  StrategyRegistry  ──→  StrategyExecutor            │
│                          │                          │
│                          ├─ VoteBuilder             │
│                          ├─ StrategyContext         │
│                          └─ IStrategy[] (iterate)   │
└─────────────────────────────────────────────────────┘
                       │ Evaluate()
                       ▼
┌─────────────────────────────────────────────────────┐
│              IStrategy (pluggable)                  │
│   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐              │
│   │Strat1│ │Strat2│ │Strat3│ │StratN│              │
│   └──────┘ └──────┘ └──────┘ └──────┘              │
└─────────────────────────────────────────────────────┘
```

---

# 2. IStrategy Interface

Every strategy must implement:

| Method | Signature | Description |
|--------|-----------|-------------|
| `Initialize` | `bool Initialize(const AtlasConfig &config)` | Called once at startup |
| `Shutdown` | `void Shutdown(void)` | Called at EA shutdown |
| `GetMetadata` | `const StrategyMetadata& GetMetadata() const` | Return strategy descriptor |
| `Evaluate` | `bool Evaluate(const StrategyContext &ctx, StrategyVote &vote)` | Produce a vote |
| `IsEnabled` | `bool IsEnabled() const` | Check if strategy is active |
| `Reset` | `void Reset(void)` | Reset internal state |

### Error Contract

- Return `false` from `Evaluate()` → executor treats as failure, logs, substitutes neutral vote, continues
- Return `ATLAS_ORDER_NONE` → abstention (not a failure)
- Return invalid vote (NaN, bad direction) → `VoteBuilder.Validate()` catches it

### Forbidden Behaviors

A strategy MUST NOT:
- Call `OrderSend`, `SymbolInfo*`, `AccountInfo*`, `PositionGet*`
- Access `IBrokerAdapter`
- Access `IContextStore` (no positions, no risk state)
- Access `IEventBus` (cannot emit events)
- Communicate with other strategies
- Use static mutable variables
- Allocate memory in `Evaluate()`

---

# 3. StrategyMetadata

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `strategy_id` | int | > 0 | Unique ID |
| `name` | string | ≤ 32 chars | Human-readable name |
| `version` | string | ≤ 16 chars | Version string |
| `author` | string | ≤ 32 chars | Author name |
| `description` | string | ≤ 128 chars | Description |
| `required_features` | int[32] | 0/1 | Bitmask of features used |
| `supported_symbols` | string | "*" or list | Symbol filter |
| `priority` | int | ≥ 0 | Lower = executed first |
| `weight` | double | [0.1, 2.0] | Confidence multiplier |
| `enabled` | bool | true/false | Runtime flag |
| `category` | int | enum | Trend/Reversion/Momentum/etc. |

### Validation

- `strategy_id > 0`
- `name` non-empty, ≤ 32 chars
- `version` non-empty
- `weight` in [0.1, 2.0]
- `priority >= 0`

---

# 4. StrategyContext

Read-only context passed to `Evaluate()`. Contains ONLY:

| Field | Type | Access |
|-------|------|--------|
| MarketState | `const MarketState*` | Read-only |
| AtlasConfig | `const AtlasConfig*` | Read-only |
| ILogger | `ILogger*` | May be NULL |
| Snapshot ID | `long` | Read-only |

### Does NOT Contain

- PositionState
- RiskState
- IBrokerAdapter
- Account info
- Event bus

### Convenience Accessors

- `GetMidPrice()` → (bid + ask) / 2
- `GetATR()` → state.atr_14
- `GetFeature(index)` → state.features[index]
- `GetSession()` → state.session_state
- `GetTrendDirection()` → state.trend_direction
- `GetTrendStrength()` → state.trend_strength

---

# 5. StrategyRegistry

### Responsibilities

- `Register(strategy)` — add a strategy (prevents duplicates, null, full)
- `Unregister(id)` — remove by ID
- `Enable(id)` / `Disable(id)` — runtime toggle
- `Find(id)` — lookup by ID
- `GetAll(out[], count)` — all registered
- `GetEnabledSorted(out[], count)` — enabled, sorted by priority
- `ValidateId(id)` — check ID is valid and unique
- `Clear()` — remove all

### Capacity

- Maximum: `ATLAS_MAX_STRATEGIES = 8` (compile-time)
- Memory: 8 pointers + counter = ~72 bytes

### Duplicate Prevention

- Duplicate `strategy_id` → rejected
- NULL pointer → rejected
- Invalid metadata → rejected

---

# 6. VoteBuilder

The only way to construct a `StrategyVote`. Validates and normalizes:

- Confidence: clamped to [0, 1], multiplied by weight, clamped again
- Direction: must be BUY, SELL, or NONE
- Prices: NaN/INF/negative → 0.0
- Snapshot ID: must be > 0

### Methods

- `BuildDirectional(vote, meta, direction, confidence, entry, sl, tp, volume, snapshot_id)`
- `BuildAbstention(vote, meta, snapshot_id)`
- `BuildNeutral(vote, meta, snapshot_id)` — alias for abstention (used on failure)
- `Validate(vote, out_reason)` — full validation

---

# 7. StrategyExecutor

### Execution Pipeline

1. Receive MarketState, Config, snapshot_id
2. Validate market state (is_valid, snapshot_id > 0)
3. Get enabled strategies sorted by priority
4. Build StrategyContext
5. For each strategy:
   a. Check symbol support
   b. Measure start time
   c. Call `Evaluate(ctx, vote)`
   d. Measure elapsed time
   e. If failed: log, increment failure counter, continue
   f. Validate vote via VoteBuilder
   g. If directional: add to output array
   h. If abstention: skip (don't add)
6. Return vote count

### Isolation Rules

- Each strategy executes independently
- No shared mutable state
- A failure in one strategy does NOT affect others
- The executor NEVER crashes because of a strategy failure

### Timeout Handling

- Per-strategy budget: 5 ms (soft limit)
- Total budget: 30 ms (enforced by CoreEngine's TimeBudgetRunner)
- Timeout is logged at WARN level but does NOT abort the strategy's vote

### Statistics

Per-strategy:
- `evaluations` — total Evaluate() calls
- `successes` — directional votes
- `abstentions` — NONE votes
- `failures` — failed/invalid votes
- `total_latency_ms`, `peak_latency_ms`

Aggregate:
- `total_executions`, `total_failures`
- `avg_latency_ms`, `peak_latency_ms`

---

# 8. Lifecycle

### Initialization

1. `StrategyEngine::SetDependencies(logger, context, config)`
2. `StrategyEngine::Initialize()`
   - Sets logger on registry, vote builder, executor
   - Calls `executor.Initialize(logger, vote_builder)`
3. `StrategyEngine::RegisterStrategy(strategy)` — called for each strategy
   - Delegates to `registry.Register(strategy)`

### Evaluation (per tick)

1. CoreEngine calls `EvaluateStrategies(state, votes[])`
2. StrategyEngine checks kill switch
3. StrategyEngine validates market state
4. StrategyEngine delegates to `executor.Execute(registry, state, config, snapshot_id, votes, count)`
5. Executor iterates enabled strategies, calls Evaluate(), collects votes
6. Returns vote count

### Shutdown

1. `StrategyEngine::Shutdown()`
2. Executor logs stats
3. Registry logs status
4. Registry clears (does NOT delete strategies — caller owns them)

---

# 9. Execution Order

Strategies execute in **priority order** (ascending — lower number = higher priority = executed first).

If the time budget is exhausted, lower-priority strategies may not execute. This is by design — high-priority strategies are more important.

---

# 10. Registration

```cpp
//--- In Bootstrap or application code:
MyStrategy *strat = new MyStrategy();
strat->Initialize(config);
strategyEngine.RegisterStrategy(strat);
```

- Registration is typically done at startup, NOT during operation
- The caller owns the strategy lifetime (Bootstrap deletes on shutdown)
- Unregistration is supported but rarely needed

---

# 11. Isolation Rules

1. **No strategy may access another strategy** — strategies don't have pointers to each other
2. **No shared mutable state** — each strategy has its own private members
3. **No static mutable variables** — strategies must not use `static` fields that persist across instances
4. **No broker access** — StrategyContext has no IBrokerAdapter
5. **No account access** — StrategyContext has no AccountInfo
6. **No position access** — StrategyContext has no PositionState
7. **Read-only market data** — StrategyContext wraps `const MarketState*`
8. **Vote-only output** — the only way a strategy affects the system is through its StrategyVote

---

# 12. Performance Requirements

| Metric | Budget |
|--------|--------|
| Total framework latency | ≤ 30 ms |
| Per-strategy evaluation | ≤ 5 ms (soft) |
| VoteBuilder.BuildDirectional | O(1) |
| VoteBuilder.Validate | O(1) |
| Registry.Register | O(N), N ≤ 8 |
| Registry.GetEnabledSorted | O(N log N), N ≤ 8 |
| Executor.Execute | O(N), N ≤ 8 |
| Heap allocation in Evaluate | 0 |
| String operations in hot path | 0 (except on failure) |
| Dynamic arrays | 0 (all fixed-size) |

---

# 13. Extension Guide

### Adding a New Strategy

1. Create a new class implementing `IStrategy`:
```cpp
class MyStrategy : public IStrategy
{
private:
    StrategyMetadata m_meta;
public:
    MyStrategy(void)
    {
        m_meta.strategy_id = 10;
        m_meta.name = "MyStrategy";
        m_meta.version = "1.0.0";
        m_meta.priority = 50;
        m_meta.weight = 1.0;
        //--- ...
    }
    virtual bool Initialize(const AtlasConfig &config) override { return true; }
    virtual void Shutdown(void) override {}
    virtual const StrategyMetadata& GetMetadata(void) const override { return m_meta; }
    virtual bool Evaluate(const StrategyContext &ctx, StrategyVote &vote) override
    {
        //--- Read features from ctx.GetMarketState().features[]
        //--- Build vote using VoteBuilder (passed via context or member)
        //--- Return true on success, false on failure
    }
    virtual bool IsEnabled(void) const override { return true; }
    virtual void Reset(void) override {}
};
```

2. Register at startup:
```cpp
MyStrategy *strat = new MyStrategy();
strat->Initialize(config);
strategyEngine.RegisterStrategy(strat);
```

3. That's it. The framework handles execution, isolation, validation, and statistics.

### What NOT to Do

- Do NOT modify StrategyEngine.mqh to add strategies
- Do NOT modify StrategyFramework/ files
- Do NOT access broker/account/positions from a strategy
- Do NOT share state between strategies
- Do NOT use `Print()` — use the logger from StrategyContext

---

# 14. Test Coverage

Tests are in `tests/StrategyFrameworkTests.mq5`:

| Test | Coverage |
|------|----------|
| TestDuplicateRegistration | Same ID rejected |
| TestDisabledStrategy | Disabled strategy skipped |
| TestFailedStrategy | Failure doesn't stop others |
| TestTimeoutStrategy | Latency tracked |
| TestEmptyRegistry | Empty registry returns 0 votes |
| TestVoteValidation | VoteBuilder validates/clamps |
| TestMaxStrategyCount | Full registry rejects new |
| TestPrioritySorting | Strategies sorted by priority |

---

# 15. Edge Cases

| # | Case | Behavior |
|---|------|----------|
| EC1 | NULL strategy registered | Rejected |
| EC2 | Duplicate ID | Rejected |
| EC3 | Registry full | Rejected |
| EC4 | Strategy fails (returns false) | Logged, neutral vote, continue |
| EC5 | Strategy returns invalid vote | VoteBuilder catches, logged, continue |
| EC6 | Strategy returns NaN confidence | VoteBuilder clamps to 0, continue |
| EC7 | Strategy exceeds 5ms | Logged WARN, vote still used |
| EC8 | Empty registry | Execute returns false, 0 votes |
| EC9 | All strategies abstain | 0 votes, not an error |
| EC10 | Kill switch active | 0 votes (checked by StrategyEngine) |
| EC11 | Invalid market state | 0 votes |
| EC12 | Feature count mismatch | 0 votes (contract violation) |
| EC13 | Symbol not supported by strategy | Strategy skipped |

---

**End of Specification.**

The Strategy Framework is fully pluggable. New strategies can be added without modifying Core Engine or the framework itself. Every strategy is isolated, validated, and failure-safe.
