# AtlasEA v2.0 Roadmap (NOT IMPLEMENTED)

**This document outlines potential future directions for AtlasEA v2.0.**
**None of these features are implemented in v1.0.**
**v1.0 is feature-complete and frozen.**

---

## Potential v2.0 Topics

### 1. Machine Learning Integration
- Strategy parameter adaptation via supervised learning
- Regime classification via neural networks
- Not for signal generation (deterministic trading only)
- Would require IClock injection (deferred from v1.0)

### 2. AI-Assisted Optimization
- Bayesian optimization (more efficient than grid/random)
- Genetic algorithm parameter search
- Reinforcement learning for profile selection
- Would build on existing Optimization Framework

### 3. Portfolio Trading
- Multi-symbol orchestration
- Cross-symbol correlation management
- Portfolio-level risk management
- Capital allocation across symbols
- Would require multi-symbol AtlasContext

### 4. Multi-Terminal Management
- Coordinate multiple MT5 instances
- Distributed position management
- Failover between terminals
- Would require external coordination service

### 5. Cloud Synchronization
- Remote configuration management
- Cloud-based trade logging
- Cross-device state synchronization
- Would require networking layer (not in v1.0)

### 6. Web Dashboard
- Real-time monitoring via web interface
- Remote control (pause/resume, profile switch)
- Historical performance visualization
- Would require embedded web server or external service

### 7. Remote Monitoring
- Mobile push notifications
- Email alerts for critical events
- Telegram bot integration
- Would require notification service

### 8. Advanced Analytics
- Trade-by-trade attribution analysis
- Strategy correlation matrix
- Drawdown heatmaps
- Equity curve decomposition
- Would build on existing Validation Framework

### 9. Breaking Changes (v2.0)
- IStateStore interface: AtlasContext& → IContextStore* (decouple RecoveryManager)
- IClock injection (replace TimeCurrent in CoreEngine)
- Remove legacy Trading/MoneyManagement/ files
- Remove unused IPipelineStatistics.mqh
- Remove legacy Core/DependencyBuilder.mqh
- Non-blocking order retry (replace Sleep in MT5Adapter)

---

**All v2.0 topics are strictly OUTSIDE v1.0 scope.**
**v1.0 is production-ready and frozen.**
