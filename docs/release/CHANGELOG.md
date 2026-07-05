# AtlasEA v1.0.0 — Changelog

## v1.0.0 (2025-01-05) — Production Release

### v1.0 Step 9: RC Audit
- Fixed CRITICAL include guard collision (Strategies/BaseStrategy.mqh)
- Fixed include guard collisions (Trading/MoneyManagement/)
- Updated version string to v1.0 RC
- Replaced Print() with logger in AtlasEA.mq5 init success
- Full project audit: 258 files, 58,269 lines verified

### v1.0 Step 8: Performance & Memory
- CacheManager (7 cache types with TTL)
- RuntimeStatistics (tick duration, throughput, memory, drift)
- ResourceMonitor (CPU, memory, cache, queues, file I/O)
- MemoryAudit (32 array entries, overflow/unused detection)
- PerformanceAudit (9 hot path components with budgets)

### v1.0 Step 7: Production Safety
- BrokerCompatibilityManager (4 execution modes, 3 account modes)
- SymbolValidator (10 pre-order checks)
- ExecutionSafetyManager (duplicates, storms, retries, modifications)
- TradingSessionManager (weekend, rollover, DST, restart)
- TradingEnvironmentValidator (8 terminal/account checks)
- Self-protection: auto-pause when unhealthy, auto-resume when healthy

### v1.0 Step 6: Optimization Framework
- ParameterSpace (32 parameters, 4 types)
- ParameterValidator (11 cross-parameter rules)
- ParameterGenerator (grid, random, manual)
- OptimizationRunner (reuses Validation Framework)
- Anti-overfitting (6 rejection checks)
- 9-component composite scoring
- CSV export (25 columns per set)

### v1.0 Step 5.5: Validation Refinement
- ValidationConfig (all thresholds configurable)
- Schema/report versioning (v2)
- ValidationScoringEngine (4 profiles: Balanced, Conservative, Aggressive, Institutional)
- QualityGate (7 pre-validation checks)
- DatasetFingerprint (FNV-1a hash)
- ConfidenceRating (LOW/MEDIUM/HIGH/VERY_HIGH)
- WalkForwardSummary (Stable/Weak/Unstable/Overfitted)
- ValidationCache (fingerprint-based, 16 entries)

### v1.0 Step 5: Validation Framework
- BacktestRunner (19 performance metrics)
- WalkForwardRunner (rolling + expanding windows)
- MonteCarloRunner (deterministic LCG, configurable seed)
- PerformanceAnalyzer, EquityAnalyzer, RiskAnalyzer
- Pass/fail criteria (8 configurable thresholds)
- CSV export

### v1.0 Step 4: Profile System
- MarketClassifier (7 regimes from existing MarketState)
- ProfileManager (7 profiles with 25+ parameters each)
- ProfileSelector (regime → profile with hysteresis)
- Auto-switching with confirmation + cooldown

### v1.0 Step 3: Strategy Pack V1
- BaseStrategy (abstract base with lifecycle + config + cooldown)
- EMATrendStrategy, PullbackStrategy, BreakoutStrategy, MomentumStrategy, RangeStrategy
- VolatilityFilter, SessionFilter (reusable)

### v1.0 Step 2: Trade Lifecycle Manager
- 12 management features (SL/TP, BE, trailing 5 modes, time exit, profit lock, partial, etc.)
- Per-position tracking (64 max)
- 5 trailing modes (Classic, ATR, Step, Dynamic, Volatility)
- IBrokerAdapter extended with ModifyPositionSLTP, ClosePosition, ClosePartialPosition

### v1.0 Step 1: Money Management Engine
- 10 sizing modes (Fixed, Risk%, Balance%, Equity%, FreeMargin%, ATR, SL, Vol, DD, DailyLoss)
- IMoneyManagement interface
- 10 validation checks
- Statistics tracking
- ExecutionEngine requests lot ONLY from MoneyManagementEngine

### v0.2.x: Trading Layer
- TradeLifecycle, TradeSignal, TradeContext, TradeValidator, TradeEntryManager
- PositionManager, TradeExitManager, TradeStatistics
- Signal Pipeline (Collector, Normalizer, Validator, Scoring, PriorityQueue, Router)
- Entry Filter Engine (7 filters, 24 reason codes)
- Money Management (v0.2.3, later superseded by v1.0 Step 1)

### v0.1.x: Infrastructure (25 versions)
- Core Engine, Event Queue, Phase Scheduler, Context Guardian
- Market Engine (9 components, 32 features)
- Strategy Engine (pluggable framework)
- Risk Engine (21 rules, 5 sizer methods, kill switch)
- Execution Engine (order builder, idempotency)
- MT5 Adapter, Trade Manager, Persistence Manager
- Recovery System (7-step pipeline)
- Replay Engine (deterministic)
- Diagnostics (profiler, latency, memory, health)
- Plugin Architecture (SDK, registry, loader)
- Configuration System v2 (6 files, 25+ validation rules)
- Event Sourcing (store, journal, factory, versioning)
- Testing Framework (mocks, scenarios, assertions)
- Production Hardening (resource lifecycle, design by contract, runtime invariants)
