# AtlasEA — Architecture Audit Report

**Version:** v0.1.19.1 (cleanup patch)
**Date:** 2025-07-03

## 1. Architecture Score

| Dimension | Score | Notes |
|-----------|-------|-------|
| Layer consistency | 8/10 | Interfaces→Core→Engines DAG is clean; IStateStore still depends on AtlasContext concrete |
| Dependency health | 9/10 | No circular includes; all cycles eliminated |
| Interface consistency | 9/10 | All interfaces in Interfaces/; IEventBus duplicate removed |
| Duplicate responsibility | 9/10 | ServiceRegistry, EventRouteTable, Diagnostics/Logger removed |
| Legacy components | 8/10 | Dead code in Events/, Audit/, Plugins/, StrategySDK/, Config/Configuration* — pending integration decision |
| Compile safety | 7/10 | 4 concrete classes now inherit interfaces; 2 struct redefinitions fixed |
| **Overall** | **8.3/10** | **Production-ready for active code paths; dead subsystems need integration or removal** |

## 2. Layer Consistency Score

| Layer | Score | Issues |
|-------|-------|--------|
| Contracts/ | 9/10 | Contains 1 enum (acceptable); pure DTOs |
| Interfaces/ | 8/10 | IStateStore includes Core/AtlasContext (known tech debt) |
| Core/ | 9/10 | Orchestration only; no business logic |
| Engines/ | 9/10 | Interface-driven; ExecutionEngine now inherits IOrderBuilder |
| Infrastructure/ | 9/10 | MT5Adapter, TradeManager, PersistenceManager now inherit interfaces |
| Diagnostics/ | 9/10 | Clean DAG; no cross-deps; Logger moved to Infrastructure/Logging/ |
| Testing/ | 10/10 | Isolated; no production deps |
| Plugins/ | 7/10 | Dead code — not integrated into CoreEngine |
| Events/ | 7/10 | Dead code — not integrated |
| Audit/ | 7/10 | Dead code — not integrated |
| StrategySDK/ | 7/10 | Dead code — not integrated |
| Config/ (v2) | 7/10 | Dead code — not integrated |

## 3. Cleanup Summary

### Files Removed (6 files)
| File | Reason |
|------|--------|
| `Core/IEventBus.mqh` | Duplicate of `Interfaces/IEventBus.mqh` (compile-breaker) |
| `Core/ServiceRegistry.mqh` | Obsolete — superseded by `Core/ServiceContainer.mqh` |
| `Core/EventRouteTable.mqh` | Dead code — routing in `EventDispatcher` |
| `Diagnostics/Logger.mqh` | Duplicate of `Infrastructure/Logging/Logger.mqh` |
| `Diagnostics/PipelineStatistics.mqh` | Dead — `Core/PipelineStatistics.mqh` is active |

### Files Modified (8 files)
| File | Change |
|------|--------|
| `Infrastructure/MT5Adapter.mqh` | Added `: public IBrokerAdapter`, fixed IEventBus include |
| `Infrastructure/TradeManager.mqh` | Added `: public IPositionStore`, fixed IEventBus include |
| `Infrastructure/PersistenceManager.mqh` | Added `: public IStateStore`, added IStateStore include |
| `Engines/ExecutionEngine.mqh` | Added `: public IOrderBuilder`, added IOrderBuilder include |
| `Diagnostics/HealthMonitor.mqh` | Removed duplicate HealthReport struct + ATLAS_HEALTH_* macros; use canonical from IHealthMonitor |
| `Diagnostics/MetricsCollector.mqh` | Removed PipelineStatisticsImpl + IPipelineStatistics dependency |
| `Interfaces/ISystemMetrics.mqh` | Removed GetPipelineStats() + IPipelineStatistics include |
| `Diagnostics/LatencyMonitor.mqh` | Removed duplicate ATLAS_LATENCY_SAMPLES macro |
| `Plugins/PluginValidator.mqh` | Fixed typo ATLAS_ATLAS_VERSION → ATLAS_PLUGIN_VERSION |

## 4. Duplicate Responsibility Report

| Duplicate | Status |
|-----------|--------|
| IEventBus (Core vs Interfaces) | ✅ RESOLVED — Core version deleted |
| HealthReport (Diagnostics vs Interfaces) | ✅ RESOLVED — Diagnostics version deleted |
| Logger (Diagnostics vs Infrastructure/Logging) | ✅ RESOLVED — Diagnostics version deleted |
| ServiceRegistry vs ServiceContainer | ✅ RESOLVED — ServiceRegistry deleted |
| EventRouteTable vs EventDispatcher | ✅ RESOLVED — EventRouteTable deleted |
| PipelineStatistics (Core vs Diagnostics) | ✅ RESOLVED — Diagnostics version deleted |
| StrategyContext (StrategyFramework vs StrategySDK) | ⚠️ PENDING — Both exist with same guard; SDK version is dead code |

## 5. Remaining Technical Debt

| # | Debt | Severity | Recommendation |
|---|------|----------|----------------|
| 1 | IStateStore includes Core/AtlasContext.mqh | HIGH | Refactor to use IContextStore& instead of AtlasContext& |
| 2 | StrategyContext duplicate (2 versions, same guard) | HIGH | Pick one (SDK version is richer), delete the other |
| 3 | Events/Audit/Plugins/StrategySDK/Config-v2 are dead code | MEDIUM | Either integrate into CoreEngine or document as "future subsystems" |
| 4 | ExecutionEngine/TradeManager/PersistenceManager still include Core/AtlasContext.mqh | MEDIUM | Should use IContextStore* instead |
| 5 | AtlasEA.mq5 still references g_bootstrap (global) | LOW | Acceptable — entry point pattern |
| 6 | Docs (BOOTSTRAP.md, GLOBAL_STATE_AUDIT.md) out of date | LOW | Update references to removed files |

## 6. Recommendations Before v0.2

1. **Integrate or remove dead subsystems** — Events/, Audit/, Plugins/, StrategySDK/, Config-v2 were built but never wired into CoreEngine. Either integrate them or remove them to reduce maintenance burden.
2. **Resolve StrategyContext duplication** — Two versions with the same include guard is a compile landmine.
3. **Refactor IStateStore** — Remove AtlasContext dependency from the interface; use IContextStore&.
4. **Update documentation** — BOOTSTRAP.md and GLOBAL_STATE_AUDIT.md reference removed files (ServiceRegistry, EventRouteTable).
5. **Add `virtual` + `override`** to all interface-implementing methods in MT5Adapter, TradeManager, PersistenceManager, ExecutionEngine for compile-time safety.
