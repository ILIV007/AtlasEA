# AtlasEA v1.0.0 — Architecture Overview

## System Architecture

AtlasEA is an event-driven, multi-strategy Expert Advisor for MetaTrader 5.

### Design Principles

1. **Single composition root** — Bootstrapper is the ONLY object that calls `new`
2. **Interface-driven** — 51 interfaces; engines depend on interfaces, not concrete classes
3. **Zero hot-path allocation** — All fixed-size arrays, stack-allocated
4. **Deterministic** — No MathRand, no TimeCurrent in logic paths, monotonic counters
5. **Single-threaded** — MQL5 model, no locks, no atomics, no mutexes
6. **Design by Contract** — Every critical struct has Validate(); every module has Shutdown()

### 4-Phase Pipeline

```
OnTick → PhaseScheduler.RunPipeline()
  │
  ├─ Phase 1: MARKET — CaptureTick → ProcessTick → MarketState
  ├─ Phase 2: STRATEGY — EvaluateStrategies → StrategyVote[] → AggregateVotes
  ├─ Phase 3: RISK — EvaluateRisk → RiskDecision
  └─ Phase 4: EXECUTION — BuildOrderRequest → SendOrder
```

### Module Responsibilities

| Folder | Responsibility |
|--------|---------------|
| `Core/` | CoreEngine, EventQueue, PhaseScheduler, AtlasContext, Bootstrapper |
| `Contracts/` | Data transfer objects (MarketState, RiskDecision, Events) |
| `Interfaces/` | 51 abstract interfaces (ILogger, IBrokerAdapter, IStrategy, etc.) |
| `Engines/` | MarketEngine, StrategyEngine, RiskEngine, ExecutionEngine, MoneyManagementEngine |
| `Infrastructure/` | MT5Adapter, TradeManager, PersistenceManager, TradeLifecycleManager, Logger |
| `Diagnostics/` | HealthMonitor, MetricsCollector, PerformanceProfiler, LatencyMonitor |
| `Strategies/` | 5 production strategies + BaseStrategy + 2 reusable filters |
| `Trading/` | TradeLifecycle, SignalPipeline, EntryFilters, MoneyManagement (legacy) |
| `Profiles/` | ProfileManager, MarketClassifier, ProfileSelector |
| `Validation/` | Backtest, WalkForward, MonteCarlo, analyzers, scoring, cache |
| `Optimization/` | ParameterSpace, Generator, Validator, Runner, Report |
| `Production/` | BrokerCompatibility, ExecutionSafety, SessionManager, SymbolValidator |
| `Performance/` | CacheManager, RuntimeStatistics, ResourceMonitor, MemoryAudit, PerformanceAudit |
| `Recovery/` | RecoveryManager, SnapshotValidator, EventReplayer, StateVerifier |
| `Replay/` | ReplayEngine, ReplayClock, ReplaySession, ReplayValidator |
| `Config/` | AtlasConfig, ConfigurationManager, Serializer, Validator, Defaults |
| `Testing/` | TestRunner, Assert, MockBrokerAdapter, MockMarketDataSource, Scenarios |

### Dependency Layering

```
Interfaces (abstract, no dependencies)
    ↑
Contracts (data structs, depend on Interfaces)
    ↑
Core (depends on Interfaces + Contracts)
    ↑
Engines (depend on Interfaces, NOT on Core or Infrastructure)
    ↑
Infrastructure (depends on Interfaces + Core)
    ↑
Bootstrapper (depends on everything — composition root)
```

### Execution Flow

1. **OnInit**: Bootstrapper creates all modules, injects dependencies, validates graph
2. **OnTick**: PhaseScheduler runs 4-phase pipeline + drains event queue
3. **OnTimer**: Heartbeat — snapshots, position reconciliation, health checks
4. **OnTrade**: Broker position reconciliation + risk state update
5. **OnDeinit**: Bootstrapper.Shutdown() — reverse-order cleanup

### Recovery Flow

1. Detect crash (no shutdown marker)
2. Load latest snapshot via PersistenceManager
3. Validate snapshot (magic, version, checksum, timestamp)
4. Check event log integrity
5. Verify state consistency
6. Reconcile with broker positions
7. Determine status (GREEN/YELLOW/RED)
8. Enter safe mode if RED

### Trading Pipeline (full)

```
Strategies → SignalPipeline → EntryFilterEngine → TradeLifecycle →
  RiskEngine → MoneyManagementEngine → ExecutionEngine → IBrokerAdapter →
  TradeLifecycleManager (manage open positions)
```
