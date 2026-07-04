# AtlasEA — Global State Audit

**Version:** v0.1.14.0
**Date:** 2025-07-02

## 1. Audit Objective

Verify that:
- No mutable global singleton exists (except the CoreEngine entry point)
- No hidden global state exists
- CoreEngine remains the sole owner of runtime state
- Every global object is documented

## 2. Global Objects Inventory

The following are the ONLY global objects in AtlasEA:

| Object | Location | Type | Mutable? | Owner | Lifetime |
|--------|----------|------|----------|-------|----------|
| `g_bootstrap` | `AtlasEA.mq5` | `AtlasBootstrap*` | Yes (pointer) | `AtlasEA.mq5` (OnInit/OnDeinit) | EA session |
| `g_core_engine` | `AtlasEA.mq5` | `CoreEngine*` | Yes (pointer) | `AtlasBootstrap` | EA session |

### Notes

- `g_bootstrap` is the composition root — it constructs and owns everything.
- `g_core_engine` is a convenience pointer for `OnTick`/`OnTrade`/`OnTimer` — it points to the `CoreEngine` instance owned by `g_bootstrap`.
- Both are deleted in `OnDeinit`.

## 3. No Other Global State

### 3.1 No Global Static Variables

No module declares `static` mutable variables at file scope. All state is:
- Instance members of classes (owned by `CoreEngine` or `Bootstrap`)
- Stack-allocated locals
- Const compile-time constants (`#define`)

### 3.2 No Global Singletons

There is no `GetInstance()` pattern anywhere. The `ServiceRegistry` is NOT a global singleton — it is an instance owned by `Bootstrap` and accessed via pointer.

### 3.3 No Hidden Global State

- No module uses `GlobalVariableGet`/`GlobalVariableSet` (MQL5 terminal global variables).
- No module uses `ChartGetInteger`/`ChartSetInteger` for hidden state.
- No module stores state in file system (except `PersistenceManager` for snapshots — which is explicit, documented, and goes through `IStateStore`).

## 4. CoreEngine Ownership

`CoreEngine` owns (directly or transitively):

```
CoreEngine
├── AtlasContext (the single mutable state bag)
├── ServiceRegistry (pointer, owned by Bootstrap)
├── EventQueue (normal + priority ring buffers)
├── EventDispatcher
├── PhaseScheduler
├── SnapshotManager
├── ContextGuardian
├── PermissionMatrix
├── PipelineStatistics
├── TimeBudgetRunner
├── KillSwitchPropagator
├── ModuleRegistry
├── EventRouteTable
└── (pointers to injected engines/infra)
```

All other modules receive dependencies via `SetDependencies()` (DI pattern) and do NOT own global state.

## 5. Compliance Checklist

| Check | Status |
|-------|--------|
| No mutable global singleton (except g_bootstrap/g_core_engine) | ✅ |
| No hidden global state | ✅ |
| CoreEngine is sole runtime state owner | ✅ |
| All globals documented | ✅ (Section 2) |
| No file-scope static mutable variables | ✅ |
| No GlobalVariableGet/Set usage | ✅ |
| ServiceRegistry is instance, not singleton | ✅ |
| All state is instance-owned | ✅ |

## 6. Conclusion

AtlasEA has **2 global objects** (`g_bootstrap`, `g_core_engine`), both in `AtlasEA.mq5`, both managed by `OnInit`/`OnDeinit`. There is no hidden global state. All runtime state is owned by `CoreEngine` (via `AtlasContext`) and injected into engines/infra via interfaces.
