# AtlasEA Bootstrap Architecture

**Version:** 0.1.8.0
**Date:** 2025-07-01

This document describes the Bootstrap layer, startup sequence, dependency graph, service lifetime, and shutdown sequence for AtlasEA v0.1.8.0.

---

## 1. Overview

The Bootstrap layer is the **composition root** of AtlasEA. It is the single place where:

- All services are constructed
- All engines are constructed
- All infrastructure components are constructed
- All dependencies are injected (via interfaces)
- Shared singletons are registered in the ServiceRegistry
- Startup validation is performed
- An initialized `CoreEngine` is returned

Before v0.1.8.0, `CoreEngine` owned its sub-components and constructed them internally (Service Locator anti-pattern). With the Bootstrap layer, `CoreEngine` receives fully-constructed, injected dependencies — it no longer calls `new`.

---

## 2. Startup Sequence

The startup sequence is a strict 10-step process. If any step fails, all previously-constructed components are cleaned up and `NULL` is returned.

```
┌─────────────────────────────────────────────────────────┐
│  1. Create ServiceRegistry                              │
│     └─ new ServiceRegistry()                            │
│                                                         │
│  2. Create Services                                     │
│     ├─ new NullLogger()                                 │
│     └─ new HealthMonitor()                              │
│                                                         │
│  3. Register Services                                   │
│     ├─ registry.Register(ATLAS_SERVICE_LOGGER, ...)     │
│     └─ registry.Register(ATLAS_SERVICE_HEALTH_MONITOR,.)│
│                                                         │
│  4. Create Infrastructure                               │
│     ├─ new MT5Adapter(NULL)        ← EventBus injected  │
│     ├─ new TradeManager(NULL)      ←   later by Core    │
│     └─ new PersistenceManager()                         │
│                                                         │
│  5. Create Engines                                      │
│     ├─ new MarketEngine()                               │
│     ├─ new StrategyEngine()                             │
│     ├─ new RiskEngine()                                 │
│     └─ new ExecutionEngine()                            │
│                                                         │
│  6. Inject Dependencies                                 │
│     └─ engines.SetDependencies(broker, logger, config)  │
│                                                         │
│  7. Validate Startup                                    │
│     ├─ all pointers non-NULL?                           │
│     ├─ config valid (magic > 0, symbol non-empty)?      │
│     └─ no duplicate registrations?                      │
│                                                         │
│  8. Create CoreEngine                                   │
│     ├─ new CoreEngine()                                 │
│     └─ core.Initialize(config, logger, market,          │
│         strategy, risk, execution, broker, trade,       │
│         persistence)                                    │
│                                                         │
│  9. Wire HealthMonitor                                  │
│     └─ health.SetSources(logger, queue, stats, broker)  │
│                                                         │
│ 10. Final Validation + Log                              │
│     └─ "Bootstrap complete. N services registered."     │
└─────────────────────────────────────────────────────────┘
```

### Failure Handling

If any step fails:
1. The error is logged (if logger is available).
2. `Shutdown()` is called to clean up all partially-constructed components.
3. `NULL` is returned to the caller.
4. The caller (`AtlasEA.mq5::OnInit`) returns `INIT_FAILED`.

---

## 3. Dependency Graph

### Construction Order (top = first)

```
ServiceRegistry
    │
    ├── NullLogger ──────────────────────────────┐
    │                                             │
    ├── HealthMonitor ───────────────────────────┤
    │                                             │
    ├── MT5Adapter (IBrokerAdapter) ─────────────┤
    │                                             │
    ├── TradeManager (IPositionStore) ───────────┤
    │                                             │
    ├── PersistenceManager (IStateStore) ────────┤
    │                                             │
    ├── MarketEngine (IMarketDataSource) ────────┤
    │   └─ needs: IBrokerAdapter, ILogger, AtlasConfig
    │                                             │
    ├── StrategyEngine (IStrategySet) ───────────┤
    │   └─ needs: ILogger, IContextStore (from Core), AtlasConfig
    │                                             │
    ├── RiskEngine (IRiskEvaluator) ─────────────┤
    │   └─ needs: IBrokerAdapter, ILogger, IContextStore, IEventBus, AtlasConfig
    │                                             │
    ├── ExecutionEngine (IOrderBuilder) ─────────┤
    │   └─ needs: IBrokerAdapter, ILogger, IContextStore, AtlasConfig
    │                                             │
    └── CoreEngine (IEventBus) ──────────────────┘
        └─ needs: ALL of the above (via interfaces)
            ├─ Creates: AtlasContext, EventQueue, EventDispatcher,
            │           PhaseScheduler, SnapshotManager, ContextGuardian,
            │           PermissionMatrix, PipelineStatistics, TimeBudgetRunner,
            │           KillSwitchPropagator, ModuleRegistry
        └─ Wires: context into engines/infra, event bus into adapter/trade
```

### Key Insight

Engines depend on **interfaces** (`IBrokerAdapter`, `ILogger`, `IContextStore`), never on concrete classes. The Bootstrap layer constructs the concretes and passes them as interface pointers. This means:

- Engines are testable (inject mocks).
- Engines can be swapped without touching other engines.
- No engine knows about another engine.

---

## 4. Service Lifetime

| Service | Lifetime | Owner | Registered? |
|---------|----------|-------|-------------|
| `ServiceRegistry` | EA lifetime | Bootstrap | N/A (is the registry) |
| `NullLogger` | EA lifetime | Bootstrap | ✅ `ATLAS_SERVICE_LOGGER` |
| `HealthMonitor` | EA lifetime | Bootstrap | ✅ `ATLAS_SERVICE_HEALTH_MONITOR` |
| `MT5Adapter` | EA lifetime | Bootstrap | ❌ (injected directly) |
| `TradeManager` | EA lifetime | Bootstrap | ❌ |
| `PersistenceManager` | EA lifetime | Bootstrap | ❌ |
| `MarketEngine` | EA lifetime | Bootstrap | ❌ |
| `StrategyEngine` | EA lifetime | Bootstrap | ❌ |
| `RiskEngine` | EA lifetime | Bootstrap | ❌ |
| `ExecutionEngine` | EA lifetime | Bootstrap | ❌ |
| `CoreEngine` | EA lifetime | Bootstrap | ❌ |
| `AtlasContext` | EA lifetime | CoreEngine | ❌ |
| `EventQueue` | EA lifetime | CoreEngine | ❌ |
| `EventDispatcher` | EA lifetime | CoreEngine | ❌ |
| `PhaseScheduler` | EA lifetime | CoreEngine | ❌ |
| All other Core components | EA lifetime | CoreEngine | ❌ |

### Registry vs Direct Injection

- **Registry**: Used ONLY for cross-cutting singletons that many modules need (Logger, HealthMonitor, future Clock/UUIDGenerator/Metrics). Resolves by integer ID.
- **Direct injection**: Used for engines and infrastructure. Bootstrap constructs them and passes pointers directly to `CoreEngine.Initialize()`. This is explicit and type-safe.

### No Global Singletons

There are NO global `static` instances. The only globals are:
- `g_bootstrap` (in `AtlasEA.mq5`) — the composition root.
- `g_core_engine` (in `AtlasEA.mq5`) — convenience pointer for OnTick/OnTrade/OnTimer.

All other instances are owned by `AtlasBootstrap` or `CoreEngine`.

---

## 5. Shutdown Sequence

Shutdown is the **reverse** of construction. The `AtlasBootstrap::Shutdown()` method:

```
1. Shutdown CoreEngine
   ├─ core.Shutdown(0)
   │   ├─ Emit EV_SYSTEM_SHUTDOWN
   │   ├─ Drain event queues
   │   ├─ Write final snapshot (via PersistenceManager)
   │   ├─ Flush event log (via PersistenceManager)
   │   ├─ EventKillTimer()
   │   ├─ Reset ContextGuardian
   │   └─ Log final statistics
   └─ delete core_engine

2. Shutdown Engines (reverse order)
   ├─ execution_engine.Shutdown() + delete
   ├─ risk_engine.Shutdown() + delete
   ├─ strategy_engine.Shutdown() + delete
   └─ market_engine.Shutdown() + delete

3. Shutdown Infrastructure (reverse order)
   ├─ persistence.Shutdown() + delete
   ├─ trade_manager.Shutdown() + delete
   └─ mt5_adapter.Shutdown() + delete

4. Shutdown Services
   ├─ delete health_monitor
   └─ delete logger

5. Clear ServiceRegistry
   ├─ registry.Clear()
   └─ delete registry
```

### Memory Safety

- Every `new` in `Initialize()` has a matching `delete` in `Shutdown()`.
- `Shutdown()` is idempotent (safe to call twice).
- The destructor `~AtlasBootstrap()` calls `Shutdown()` if not already called.

---

## 6. Service Registry

### Purpose

The `ServiceRegistry` resolves shared singleton services by integer ID. It is NOT a general-purpose IoC container — it handles only the 7 cross-cutting services defined by `ATLAS_SERVICE_*` constants.

### API

| Method | Description |
|--------|-------------|
| `Register(id, name, ptr)` | Register a service. Fails on duplicate or NULL. |
| `Unregister(id)` | Unregister (does NOT delete). |
| `Resolve(id)` | Get a service pointer by ID. Returns NULL if not registered. |
| `IsRegistered(id)` | Check if a service is registered. |
| `ValidateAll()` | Check that all required slots (1..7) are filled. |
| `LogStatus()` | Log all registered services. |

### Usage

```cpp
//--- In Bootstrap:
m_registry.Register(ATLAS_SERVICE_LOGGER, "Logger", m_logger);

//--- In any module (via registry pointer):
ILogger *logger = (ILogger *)registry.Resolve(ATLAS_SERVICE_LOGGER);
if(logger != NULL) logger.Info("MyModule", "Hello");
```

### Current State (v0.1.8.0)

| Slot | Service | Status |
|------|---------|--------|
| 1 | Logger | ✅ Registered (NullLogger) |
| 2 | Clock | ⏳ Future phase |
| 3 | UUIDGenerator | ⏳ Future phase |
| 4 | MetricsCollector | ⏳ Future phase |
| 5 | HealthMonitor | ✅ Registered |
| 6 | ErrorManager | ⏳ Future phase |
| 7 | ConfigProvider | ⏳ Future phase |

`ValidateAll()` is NOT called yet because slots 2-4 and 6-7 are not filled. When those services are implemented, `ValidateAll()` will be added to the startup sequence.

---

## 7. Event Route Table

### Purpose

The `EventRouteTable` replaces the long `switch` statement in `EventDispatcher`. Each event type maps to a handler function pointer + user data (the module instance).

### API

| Method | Description |
|--------|-------------|
| `Register(event_type, handler, user_data, name)` | Register a route. |
| `Unregister(event_type)` | Remove a route. |
| `SetEnabled(event_type, enabled)` | Enable/disable without removing. |
| `Dispatch(event)` | Call the handler for the event's type. |
| `HasRoute(event_type)` | Check if a route exists. |
| `LogRoutes()` | Log all routes. |

### Handler Signature

```cpp
typedef void (*EventRouteHandler)(const AtlasEvent &event, void *user_data);
```

### Usage (Future)

When the EventDispatcher is refactored to use the route table:

```cpp
//--- In Bootstrap, after CoreEngine is created:
EventRouteTable *routes = core_engine->GetRouteTable();
routes->Register(EV_TRADE_EXECUTED, &TradeManager::HandleTradeEvent,
                 m_trade_manager, "TradeManager.HandleTradeEvent");
routes->Register(EV_KILL_SWITCH_ACTIVATED, &RiskEngine::HandleKillSwitch,
                 m_risk_engine, "RiskEngine.HandleKillSwitch");
```

### Current State (v0.1.8.0)

The `EventRouteTable` class is implemented but NOT yet wired into `EventDispatcher`. The dispatcher still uses its internal switch statement. The route table is available for the next refactor pass, where the dispatcher's `ProcessEvent` switch will be replaced with `m_route_table.Dispatch(event)`.

---

## 8. Health Monitor

### Purpose

The `HealthMonitor` aggregates system health metrics from multiple sources and exposes a single `HealthSnapshot` struct.

### Health Snapshot Fields

| Field | Source | Description |
|-------|--------|-------------|
| `queue_depth` | EventQueue | Total events in both queues |
| `priority_queue_depth` | EventQueue | Events in priority queue |
| `total_dropped_events` | EventQueue | Lifetime dropped events |
| `avg_pipeline_latency_ms` | PipelineStatistics | Average tick pipeline latency |
| `peak_pipeline_latency_ms` | PipelineStatistics | Peak tick pipeline latency |
| `broker_connected` | IBrokerAdapter | Terminal connected to server |
| `trading_enabled` | IBrokerAdapter | Auto-trading allowed |
| `market_open` | IBrokerAdapter | Symbol trade mode enabled |
| `memory_used_mb` | MQLInfoInteger | MQL5 memory in use |
| `last_fatal_error` | HealthMonitor (internal) | Last FATAL error message |
| `total_errors` | HealthMonitor (internal) | Lifetime ERROR count |
| `system_healthy` | Computed | Composite health flag |
| `health_reason` | Computed | If unhealthy, the reason |

### Composite Health Logic

The `system_healthy` flag is `true` only if ALL of:
- No fatal error recorded
- Broker connected
- Trading enabled
- Queue depth < critical threshold (400)
- Peak tick latency ≤ 50 ms

If any condition fails, `health_reason` contains the specific cause.

---

## 9. File Inventory (New in v0.1.8.0)

| File | Type | Description |
|------|------|-------------|
| `Bootstrap/AtlasBootstrap.mqh` | New | Composition root — constructs, injects, validates |
| `Core/ServiceRegistry.mqh` | New | Lightweight singleton service registry |
| `Core/EventRouteTable.mqh` | New | Declarative event routing (replaces switch) |
| `Interfaces/IHealthMonitor.mqh` | New | Health monitor interface |
| `Diagnostics/HealthMonitor.mqh` | New | Concrete health monitor implementation |
| `AtlasEA.mq5` | Modified | Thin entry point ( delegates to Bootstrap) |
| `docs/BOOTSTRAP.md` | New | This document |

---

## 10. Migration Notes

### From v0.1.7.0 to v0.1.8.0

1. `AtlasEA.mq5` no longer constructs `CoreEngine` directly — it creates `AtlasBootstrap`.
2. `CoreEngine.Initialize()` signature is unchanged — it still accepts all dependencies via interface pointers. The difference is that Bootstrap constructs the concretes, not CoreEngine.
3. `CoreEngine` no longer calls `new MT5Adapter(this)` or `new TradeManager(this)` internally. These were removed (if they existed) — all construction is in Bootstrap.
4. The `NullLogger` is now heap-allocated in Bootstrap and registered in the ServiceRegistry, instead of being a stack member of CoreEngine.

### Backward Compatibility

- All public contracts (`MarketState`, `RiskDecision`, `Events`, `OrderRequest`) are unchanged.
- All interface signatures (`IEventBus`, `IBrokerAdapter`, etc.) are unchanged.
- `CoreEngine`'s public API is unchanged.
- Existing engine implementations do not need modification (they already accept interfaces).

---

## 11. Next Steps

1. **Wire EventRouteTable into EventDispatcher** — replace the switch statement with table-driven dispatch.
2. **Implement remaining services** — Clock, UUIDGenerator, MetricsCollector, ErrorManager, ConfigProvider.
3. **Implement real Logger** — replace NullLogger with a file-based logger.
4. **Expose CoreEngine internals to HealthMonitor** — add accessors for EventQueue and PipelineStatistics.
5. **Add startup validation for services** — call `ValidateAll()` once all 7 service slots are filled.
6. **Integration testing** — verify the full startup → operation → shutdown cycle.
