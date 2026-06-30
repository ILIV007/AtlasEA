# 🏛️ AtlasEA — System Architecture Specification

## Institutional-Grade Modular Trading Engine for MetaTrader 5

---

## 1. SYSTEM OVERVIEW

### What AtlasEA Is

AtlasEA is not a trading strategy. It is a **trading system** — a runtime environment that hosts, orchestrates, and governs trading strategies within the MetaTrader 5 ecosystem. It functions as the middleware between raw market data and actionable trading decisions, enforcing structural discipline, risk governance, and operational transparency at every layer.

AtlasEA treats the trading account as a **mission-critical system** where every tick, every decision, and every state transition must be observable, auditable, and reversible.

### Why Modular Architecture Is Required

Institutional trading systems fail not because of bad strategies, but because of **tight coupling** between unrelated concerns. A strategy that can directly access the broker API can bypass risk controls. A risk system embedded inside a strategy cannot enforce global limits. A logging system scattered across modules cannot guarantee audit completeness.

Modularity ensures:

- **Independent evolution**: Strategies can be added, removed, or upgraded without touching the core.
- **Parallel development**: Multiple AI coding agents can implement different modules simultaneously, bound only by interface contracts.
- **Fault isolation**: A failure in one module cannot cascade into another.
- **Testability**: Each module can be validated in isolation against its contract.

### Why Separation of Concerns Is Non-Negotiable

| Layer | Responsibility | What It Must Never Do |
|-------|---------------|----------------------|
| Strategy | Generate directional bias and confidence | Execute orders, read account balance, manage positions |
| Risk | Authorize or deny every proposed action | Generate trade signals, choose entry prices |
| Execution | Translate approved decisions into broker commands | Override risk decisions, modify strategy logic |
| Core | Orchestrate data flow and lifecycle | Implement business logic of any kind |

### Why AI Integration Must Come After Rule-Based Stability

AI is non-deterministic. A rule-based system provides the **safety floor** — the deterministic behavior that guarantees the system cannot lose more than configured limits regardless of what the AI suggests. AI layers must plug *into* the decision pipeline, not replace it. The risk engine must remain the final authority even when AI is involved.

---

## 2. HIGH LEVEL ARCHITECTURE

### System Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ATLAS EA SYSTEM                              │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │
│  │   CONFIG    │   │   LOGGER    │   │  ANALYTICS  │               │
│  │   SYSTEM    │◄──│   SYSTEM    │◄──│   ENGINE    │               │
│  │  (Static)   │   │  (Observes) │   │  (Observes) │               │
│  └──────┬──────┘   └──────▲──────┘   └──────▲──────┘               │
│         │                 │                 │                       │
│         │    ┌────────────┴─────────────────┘                       │
│         │    │         CORE ENGINE                                   │
│         │    │  ┌─────────────────────────────────┐                  │
│         └───►│  │  • Lifecycle Manager            │                  │
│              │  │  • Event Router                 │                  │
│              │  │  • Module Registry              │                  │
│              │  │  • Atlas Context Guardian       │                  │
│              │  └─────────────────────────────────┘                  │
│              │                    │                                  │
│              │    ┌───────────────┼───────────────┐                  │
│              │    │               │               │                  │
│         ┌────▼────┐      ┌──────▼──────┐   ┌────▼────┐             │
│         │  MARKET │      │  STRATEGY   │   │  RISK   │             │
│         │ ENGINE  │      │   ENGINE    │   │ ENGINE  │             │
│         │         │      │             │   │         │             │
│         │• Tick   │      │• Evaluate  │   │• Validate│             │
│         │• Bar    │      │• Score    │   │• Authorize│            │
│         │• Feature│      │• Vote     │   │• Limit   │             │
│         │• State  │      │• Signal   │   │• Block   │             │
│         └────┬────┘      └──────┬────┘   └────┬────┘             │
│              │                  │             │                      │
│              │                  │             │                      │
│              │         ┌────────▼─────────────┘                      │
│              │         │                                            │
│              │    ┌────▼────┐   ┌────────────┐                     │
│              │    │EXECUTION│   │   TRADE    │                     │
│              │    │ ENGINE  │──►│  MANAGER   │                     │
│              │    │         │   │            │                     │
│              │    │• Route  │   │• Track    │                     │
│              │    │• Send   │   │• Monitor  │                     │
│              │    │• Confirm│   │• Lifecycle│                     │
│              │    │• Retry  │   │• P&L      │                     │
│              │    └─────────┘   └────────────┘                     │
│              │                                                      │
│              └──────────────────────────────────► BROKER / MT5     │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
┌──────────┐     ┌────────────┐     ┌─────────────┐     ┌──────────┐
│   TICK   │────►│   MARKET   │────►│   ATLAS     │────►│ STRATEGY │
│  EVENT   │     │   ENGINE   │     │   CONTEXT   │     │  ENGINE  │
└──────────┘     └────────────┘     └─────────────┘     └─────┬────┘
                                                              │
                                                              ▼
┌──────────┐     ┌────────────┐     ┌─────────────┐     ┌──────────┐
│  TRADE   │◄────│ EXECUTION  │◄────│    RISK     │◄────│  VOTES   │
│  RESULT  │     │   ENGINE   │     │   ENGINE    │     │ & SCORES │
└──────────┘     └────────────┘     └─────────────┘     └──────────┘
     │
     ▼
┌──────────┐     ┌────────────┐
│  TRADE   │────►│  ANALYTICS │
│ MANAGER  │     │  & LOGGER  │
└──────────┘     └────────────┘
```

### Execution Flow (Per Tick)

```
Tick Arrives
    │
    ▼
┌─────────────────┐
│ 1. MARKET UPDATE│ ──► Update price, bar, feature state in Atlas Context
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 2. STRATEGY VOTE│ ──► Each active strategy evaluates context, emits vote
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 3. AGGREGATION  │ ──► Confidence score computed from strategy votes
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 4. RISK GATE    │ ──► Risk Engine approves, modifies, or rejects
└─────────────────┘
    │
    ├── REJECTED ──► Log, Analytics, Done
    │
    └── APPROVED ──► Proceed
              │
              ▼
┌─────────────────┐
│ 5. EXECUTION    │ ──► Order constructed, routed, sent to broker
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 6. TRADE TRACK  │ ──► Position opened/closed, state updated
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 7. OBSERVATION  │ ──► Logger + Analytics record full lifecycle
└─────────────────┘
```

### Control Flow

The Core Engine holds **orchestration authority** but **zero business logic**. It does not decide what to trade. It decides *when* each module runs, *what data* they receive, and *how* their outputs are routed.

Control is **unidirectional**:
- Downstream: Data flows from Market → Strategy → Risk → Execution
- Upstream: State updates flow from Execution → Trade Manager → Atlas Context
- Observation: Logger and Analytics observe all layers without participating in control

---

## 3. ATLAS CONTEXT — THE SINGLE SOURCE OF TRUTH

### Definition

Atlas Context is the **central, versioned, immutable-in-transition data structure** that represents the complete state of the trading system at any given moment. No module may maintain private state that contradicts the Atlas Context. All modules read from it. Only designated modules write to it, and writes are atomic and logged.

### Philosophy

- **Single Source of Truth**: If it is not in Atlas Context, it does not exist for the system.
- **Snapshot Model**: Every tick produces a new context snapshot. Historical snapshots are retained for debugging and replay.
- **Write Guardianship**: Only the Core Engine's Context Guardian may commit writes. Modules request changes; they do not execute them.

### Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    ATLAS CONTEXT SNAPSHOT                     │
├─────────────────────────────────────────────────────────────┤
│  META                                                       │
│  ├── timestamp          : datetime (UTC, nanosecond)        │
│  ├── tick_id            : UUID (monotonic)                  │
│  ├── session_id         : UUID (trading session)            │
│  └── snapshot_version   : integer (auto-increment)          │
├─────────────────────────────────────────────────────────────┤
│  MARKET STATE                                               │
│  ├── symbol             : string                            │
│  ├── timeframe          : enum                              │
│  ├── price_snapshot     : {bid, ask, last, spread}        │
│  ├── bar_state          : {open, high, low, close, volume}  │
│  ├── tick_state         : {price, volume, flags}            │
│  ├── volatility_index   : float (normalized 0-1)            │
│  ├── trend_state        : {direction, strength, duration}   │
│  ├── session_info       : {market_open, pre/post, holiday}  │
│  └── feature_vector     : {key: value} (engine-computed)    │
├─────────────────────────────────────────────────────────────┤
│  POSITION STATE                                             │
│  ├── open_positions     : array[Position]                   │
│  ├── position_count     : integer                           │
│  ├── net_exposure       : float (base currency)             │
│  ├── directional_bias   : {long, short, neutral}              │
│  └── pending_orders     : array[Order]                      │
├─────────────────────────────────────────────────────────────┤
│  RISK STATUS                                                │
│  ├── daily_pnl          : float                             │
│  ├── daily_drawdown     : float (from high watermark)       │
│  ├── margin_used        : float                             │
│  ├── margin_available   : float                             │
│  ├── risk_budget_remaining: float (0-1)                     │
│  ├── current_exposure_pct: float (of max allowed)         │
│  ├── kill_switch_active : boolean                         │
│  └── last_violation     : string (or null)                │
├─────────────────────────────────────────────────────────────┤
│  DECISION STATE                                             │
│  ├── active_strategies  : array[string]                   │
│  ├── strategy_votes     : array[{id, direction, confidence}]│
│  ├── aggregated_confidence: float (0-1)                     │
│  ├── consensus_direction: enum                              │
│  ├── risk_decision      : {status, reason, modified_params} │
│  └── execution_decision : {status, order_params}            │
├─────────────────────────────────────────────────────────────┤
│  SYSTEM HEALTH                                              │
│  ├── engine_status      : enum (running, degraded, halted)  │
│  ├── module_health      : {module: status}                  │
│  ├── last_error         : string (or null)                  │
│  └── recovery_mode      : boolean                         │
└─────────────────────────────────────────────────────────────┘
```

### Read/Write Permissions

| Module | Read Access | Write Access | Notes |
|--------|------------|-------------|-------|
| Core Engine | Full | Meta, System Health | Guardian of all writes |
| Market Engine | Full (except Decision) | Market State | Updates prices, features, bars |
| Strategy Engine | Market State, Position State, Risk Status | Decision State (Strategy Votes only) | Cannot write to Position or Risk |
| Risk Engine | Full | Risk Status, Decision State (Risk Decision only) | Can modify execution params, not execute |
| Execution Engine | Full | Position State (pending orders), Decision State (Execution Decision) | Cannot modify Risk Status |
| Trade Manager | Full | Position State (open positions, P&L) | Reconciles broker state with context |
| Analytics Engine | Full | None | Read-only observer |
| Logger System | Full | None | Read-only observer |
| Configuration System | Full | None | Read-only; config is static after load |

### Update Rules

1. **Tick-Driven Updates**: Market Engine updates Market State on every tick.
2. **Strategy-Driven Updates**: Strategy Engine appends to Strategy Votes during evaluation phase.
3. **Risk-Driven Updates**: Risk Engine writes Risk Decision and may modify Risk Status.
4. **Execution-Driven Updates**: Execution Engine writes Execution Decision and pending orders.
5. **Trade Manager Updates**: Trade Manager updates open positions and P&L based on broker confirmations.
6. **Atomic Commits**: All writes within a single tick cycle are batched and committed as one atomic snapshot.

---

## 4. MODULE DEFINITIONS

---

### 4.1 CORE ENGINE

**Responsibility**
- System lifecycle management (startup, runtime, shutdown, recovery)
- Event routing and scheduling
- Module registry and dependency injection
- Atlas Context version control and write arbitration
- Tick cycle orchestration

**Inputs**
- Configuration from Configuration System
- Module registration requests
- External control commands (start, pause, halt, resume)

**Outputs**
- Orchestrated execution sequence per tick
- Updated Atlas Context snapshots
- System health status
- Module lifecycle events

**Allowed Operations**
- Initialize and register modules
- Route events between modules in correct order
- Commit validated writes to Atlas Context
- Enforce module execution order
- Trigger emergency shutdown (kill switch)
- Manage session state

**Forbidden Operations**
- Generate trading signals
- Evaluate market conditions
- Calculate risk metrics
- Construct or send orders
- Access broker API directly
- Implement any business logic

**Dependencies**
- Configuration System (read-only at startup)
- All other modules (orchestrates but does not depend on their logic)

---

### 4.2 MARKET ENGINE

**Responsibility**
- Ingest raw market data (ticks, bars, book data)
- Compute derived features and indicators
- Maintain market state in Atlas Context
- Detect market regime changes
- Provide normalized data to all downstream modules

**Inputs**
- Raw tick data from MT5
- Bar data from MT5
- Configuration for symbols and timeframes
- Historical data requests

**Outputs**
- Normalized price snapshots
- Computed feature vectors
- Volatility and trend state
- Market regime classification
- Updates to Atlas Context Market State

**Allowed Operations**
- Read raw market data
- Compute technical features (normalized, not strategy-specific)
- Update Market State in Atlas Context
- Detect market anomalies (gaps, halts, extreme volatility)
- Request historical data

**Forbidden Operations**
- Generate trade signals
- Access account information
- Execute orders
- Modify Position State or Risk Status
- Implement strategy-specific logic

**Dependencies**
- Core Engine (receives tick events)
- Configuration System (symbol/timeframe settings)

---

### 4.3 STRATEGY ENGINE

**Responsibility**
- Host and manage multiple trading strategies
- Provide each strategy with a sanitized view of Atlas Context
- Collect strategy votes (direction + confidence)
- Aggregate votes into consensus decision
- Ensure strategies are isolated from each other

**Inputs**
- Atlas Context (Market State, Position State, Risk Status)
- Strategy configurations
- Strategy-specific parameters

**Outputs**
- Array of strategy votes
- Aggregated confidence score
- Consensus direction
- Strategy performance metadata

**Allowed Operations**
- Read Atlas Context
- Evaluate market conditions using internal logic
- Emit vote objects (direction, confidence, metadata)
- Request historical data through Market Engine
- Report internal state for analytics

**Forbidden Operations**
- Execute trades
- Modify Atlas Context directly (except via vote emission)
- Access broker API
- Read other strategies' internal state
- Override risk decisions
- Access account balance or margin directly

**Dependencies**
- Core Engine (receives evaluation trigger)
- Market Engine (reads market state)
- Configuration System (strategy parameters)

---

### 4.4 RISK ENGINE

**Responsibility**
- Serve as the **final authority** on all trading decisions
- Validate every proposed action against risk limits
- Enforce position sizing, exposure limits, and drawdown controls
- Maintain kill switch capability
- Log all risk decisions with rationale

**Inputs**
- Aggregated strategy votes
- Atlas Context (full, especially Position State and Risk Status)
- Risk configuration (limits, thresholds, rules)

**Outputs**
- Risk decision: APPROVED, REJECTED, or MODIFIED
- Modified order parameters (if approved with changes)
- Risk Status updates
- Violation alerts

**Allowed Operations**
- Read full Atlas Context
- Approve, reject, or modify proposed trades
- Update Risk Status
- Activate kill switch
- Enforce cooling-off periods
- Calculate and validate position sizing
- Log risk decisions

**Forbidden Operations**
- Generate trade signals
- Execute orders
- Modify Market State
- Modify Strategy Votes
- Access broker API directly
- Override its own limits

**Dependencies**
- Core Engine (receives risk check trigger)
- Configuration System (risk parameters)
- Trade Manager (reads position state)

---

### 4.5 EXECUTION ENGINE

**Responsibility**
- Translate approved risk decisions into broker orders
- Manage order lifecycle (pending, filled, partial, rejected)
- Handle execution errors and retries
- Ensure idempotency of order placement
- Route orders to correct symbols and order types

**Inputs**
- Risk-approved execution decisions
- Atlas Context (Position State, Market State)
- Broker connection state

**Outputs**
- Order placement confirmations
- Order status updates
- Execution errors
- Updates to Atlas Context (pending orders, execution decisions)

**Allowed Operations**
- Construct order objects from approved decisions
- Send orders to broker API
- Track order status
- Handle retries with exponential backoff
- Report execution failures
- Update Execution Decision in Atlas Context

**Forbidden Operations**
- Approve or reject trades (only Risk Engine may do this)
- Modify risk parameters
- Generate signals
- Modify Position State directly (only Trade Manager does this)
- Access strategy logic

**Dependencies**
- Core Engine (receives execution trigger)
- Risk Engine (receives approved decisions)
- Trade Manager (receives fill confirmations)

---

### 4.6 TRADE MANAGER

**Responsibility**
- Maintain the definitive record of all open and closed positions
- Reconcile broker-reported state with internal state
- Track P&L, duration, and lifecycle of every trade
- Detect discrepancies between expected and actual positions
- Provide position state to all modules

**Inputs**
- Order fill confirmations from Execution Engine
- Broker position queries
- Atlas Context (current Position State)

**Outputs**
- Updated open positions list
- P&L calculations
- Position lifecycle events (opened, modified, closed)
- Discrepancy alerts
- Updates to Atlas Context Position State

**Allowed Operations**
- Query broker for position state
- Update Position State in Atlas Context
- Calculate P&L and exposure
- Detect and report state mismatches
- Archive closed trades

**Forbidden Operations**
- Place orders
- Approve trades
- Generate signals
- Modify Risk Status
- Modify Market State

**Dependencies**
- Core Engine (receives reconciliation trigger)
- Execution Engine (receives fill events)
- Broker API (read-only position queries)

---

### 4.7 ANALYTICS ENGINE

**Responsibility**
- Compute performance metrics and statistics
- Generate reports on strategy effectiveness
- Track system health trends
- Provide data for optimization without modifying runtime behavior
- Maintain historical decision quality analysis

**Inputs**
- Full Atlas Context snapshots (read-only)
- Historical trade records
- Configuration for metrics to track

**Outputs**
- Performance metrics (Sharpe, win rate, expectancy, etc.)
- Strategy attribution reports
- Risk-adjusted return analysis
- System health dashboards
- Anomaly detection alerts

**Allowed Operations**
- Read all Atlas Context data
- Compute derived metrics
- Store historical analytics
- Generate reports
- Alert on anomalies

**Forbidden Operations**
- Modify any Atlas Context field
- Influence trading decisions
- Execute orders
- Modify configuration

**Dependencies**
- Core Engine (receives observation events)
- Logger System (reads historical logs)

---

### 4.8 LOGGER SYSTEM

**Responsibility**
- Record every significant event in the system
- Provide structured, queryable, tamper-evident logs
- Support replay and debugging
- Ensure no decision is made without an audit trail

**Inputs**
- All events from all modules
- Atlas Context snapshots
- Error and exception data

**Outputs**
- Structured log entries (timestamp, module, event, context)
- Log levels (DEBUG, INFO, WARN, ERROR, FATAL)
- Audit trails for every trade decision
- System event history

**Allowed Operations**
- Observe and log all system events
- Store logs with timestamps and context references
- Provide log querying for debugging
- Archive old logs

**Forbidden Operations**
- Modify Atlas Context
- Influence module behavior
- Suppress log entries
- Access broker API

**Dependencies**
- Core Engine (receives all routed events)
- Configuration System (log levels, retention)

---

### 4.9 CONFIGURATION SYSTEM

**Responsibility**
- Provide static, validated configuration to all modules at startup
- Ensure no runtime configuration changes without explicit reload
- Validate configuration integrity
- Provide default values and schema enforcement

**Inputs**
- Configuration files / external config source
- Module registration requests (for config validation)

**Outputs**
- Validated configuration objects per module
- Configuration schema definitions
- Default values

**Allowed Operations**
- Load and parse configuration
- Validate against schema
- Provide read-only config to modules
- Report configuration errors at startup

**Forbidden Operations**
- Modify configuration at runtime
- Write to Atlas Context
- Execute any trading logic

**Dependencies**
- None (loaded before all other modules)

---

## 5. EVENT-DRIVEN DESIGN

### Paradigm

AtlasEA is **strictly event-driven**, not loop-based. The system does not poll. It reacts.

Every significant occurrence in the system is an **event**:
- `TICK_RECEIVED`
- `MARKET_STATE_UPDATED`
- `STRATEGY_VOTE_SUBMITTED`
- `RISK_DECISION_RENDERED`
- `EXECUTION_ORDER_SENT`
- `TRADE_FILLED`
- `KILL_SWITCH_ACTIVATED`

### Why Event-Driven Over Loop-Based

| Aspect | Loop-Based | Event-Driven |
|--------|-----------|-------------|
| Latency | Fixed polling interval | Immediate reaction |
| Resource Usage | Constant CPU load | Idle between events |
| Determinism | Tick may be missed between polls | Every tick is an event |
| Testability | Hard to simulate timing | Events can be replayed |
| Debugging | State changes scattered | Every change is an event with timestamp |
| Scaling | Loop complexity grows | New handlers simply subscribe |

### Tick Cycle Event Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                        TICK CYCLE                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  EVENT: TICK_RECEIVED                                           │
│  ├── Source: MT5 OnTick callback                                │
│  ├── Payload: {symbol, price, volume, time, flags}              │
│  └── Handler: Core Engine → Route to Market Engine                │
│                                                                 │
│  EVENT: MARKET_STATE_UPDATED                                    │
│  ├── Source: Market Engine                                      │
│  ├── Payload: Updated Market State in Atlas Context               │
│  └── Handler: Core Engine → Route to Strategy Engine            │
│                                                                 │
│  EVENT: STRATEGY_VOTES_AGGREGATED                               │
│  ├── Source: Strategy Engine                                    │
│  ├── Payload: {votes[], confidence, consensus}                  │
│  └── Handler: Core Engine → Route to Risk Engine                  │
│                                                                 │
│  EVENT: RISK_DECISION_RENDERED                                  │
│  ├── Source: Risk Engine                                        │
│  ├── Payload: {status, reason, modified_params (optional)}      │
│  └── Handler: Core Engine → Route to Execution Engine (if APPROVED)│
│                                                                 │
│  EVENT: EXECUTION_ORDER_SENT                                    │
│  ├── Source: Execution Engine                                   │
│  ├── Payload: {order_id, symbol, type, volume, price}           │
│  └── Handler: Core Engine → Route to Trade Manager + Logger       │
│                                                                 │
│  EVENT: TRADE_FILLED                                            │
│  ├── Source: Trade Manager (confirmed by broker)                │
│  ├── Payload: {order_id, fill_price, volume, commission, time}  │
│  └── Handler: Core Engine → Update Atlas Context → Analytics      │
│                                                                 │
│  EVENT: CYCLE_COMPLETE                                          │
│  ├── Source: Core Engine                                        │
│  ├── Payload: {snapshot_id, duration_ms, events_processed}      │
│  └── Handler: Logger → Archive snapshot                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Event Handling Rules

1. **Synchronous Within Phase**: All handlers for a given phase run synchronously to ensure deterministic ordering.
2. **No Cross-Phase Events**: A module cannot emit an event that skips phases. All events flow through the Core Engine.
3. **Idempotency**: Every event handler must be idempotent. The same event replayed must produce the same state change.
4. **No Side Effects in Observers**: Analytics and Logger are pure observers. They cannot emit events or modify state.
5. **Failure Isolation**: A failure in one event handler does not prevent others from running. The Core Engine captures and logs the failure.

---

## 6. DEPENDENCY RULES (CRITICAL)

These rules are **inviolable**. Any implementation that breaks them is architecturally incorrect.

### Rule 1: Strategy Cannot Execute Trades
- Strategy Engine emits **votes only**.
- It never constructs an order, never calls a broker function, never modifies position state.
- Violation: Strategy bypasses risk controls.

### Rule 2: Risk Engine Is Final Authority
- No trade may proceed without explicit Risk Engine approval.
- Risk Engine may approve, reject, or modify any proposed action.
- Even emergency close orders must pass through Risk Engine (with expedited path).
- Violation: Uncontrolled losses.

### Rule 3: Execution Engine Is Isolated from Strategy Logic
- Execution Engine receives only approved, structured decisions.
- It does not know why a trade was approved. It only knows *what* to execute.
- Violation: Strategy logic leaks into execution, making both unmaintainable.

### Rule 4: Core Engine Only Orchestrates
- Core Engine holds no trading knowledge.
- It does not know what a "good trade" is. It knows only *when* to call *which module*.
- Violation: Business logic in infrastructure layer.

### Rule 5: No Module Can Bypass Atlas Context
- All inter-module communication must flow through Atlas Context or Core Engine events.
- No module may hold private state that contradicts Atlas Context.
- No module may read another module's internal memory directly.
- Violation: State inconsistency, race conditions, untraceable bugs.

### Rule 6: Trade Manager Is the Only Position Authority
- Only Trade Manager may update open positions and P&L in Atlas Context.
- Execution Engine reports fills; Trade Manager confirms and updates state.
- Violation: Position state divergence between system and broker.

### Rule 7: Configuration Is Immutable at Runtime
- Configuration System loads once at startup.
- Runtime changes require explicit reload command and system validation.
- Violation: Unpredictable behavior, untestable states.

### Rule 8: Logger and Analytics Are Read-Only
- They observe and record. They never influence.
- Violation: Observability becomes a source of bugs.

---

## 7. DECISION PIPELINE

### Overview

The decision pipeline is the heart of AtlasEA. It transforms raw market data into executed trades through a rigorous, multi-stage validation process.

### Stage 1: Strategy Voting

Each active strategy receives a **sanitized copy** of Atlas Context (market state, position state, risk status) and evaluates independently.

```
Strategy A: VOTE {direction: LONG, confidence: 0.72, metadata: {...}}
Strategy B: VOTE {direction: LONG, confidence: 0.45, metadata: {...}}
Strategy C: VOTE {direction: NEUTRAL, confidence: 0.10, metadata: {...}}
Strategy D: VOTE {direction: SHORT, confidence: 0.30, metadata: {...}}
```

### Stage 2: Confidence Aggregation

The Strategy Engine aggregates votes using a configurable aggregation function:

- **Weighted Average**: Confidence weighted by strategy track record
- **Majority Vote**: Simple directional majority
- **Consensus Threshold**: Minimum confidence required for any direction
- **Veto Rules**: Certain strategies may have veto power

```
Aggregated Confidence: 0.58 (LONG)
Consensus Direction: LONG
Participation Rate: 75% (3 of 4 strategies voted)
```

### Stage 3: Risk Validation

The Risk Engine evaluates the aggregated decision against current risk state:

**Checks performed:**
1. **Daily Loss Limit**: Has daily drawdown exceeded threshold?
2. **Exposure Limit**: Would this trade exceed max position size?
3. **Correlation Limit**: Is there excessive correlation with existing positions?
4. **Volatility Gate**: Is current volatility within acceptable range?
5. **Cooldown Check**: Is strategy in mandatory cooling-off period?
6. **Margin Check**: Is sufficient margin available?
7. **Kill Switch**: Is system halted?

**Possible Outcomes:**
- `APPROVED`: Proceed with original parameters
- `MODIFIED`: Proceed with adjusted parameters (reduced size, different order type)
- `REJECTED`: Block trade, log reason

### Stage 4: Execution

Only `APPROVED` or `MODIFIED` decisions reach the Execution Engine.

Execution Engine:
1. Constructs order object from decision parameters
2. Validates order structure
3. Selects order type (market, limit, stop, etc.)
4. Sends to broker
5. Tracks order ID
6. Reports status back to Core Engine

### Stage 5: Confirmation & State Update

Trade Manager:
1. Receives fill confirmation from broker
2. Validates fill against expected order
3. Updates Position State in Atlas Context
4. Recalculates P&L and exposure
5. Archives trade record

### Decision Pipeline Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     DECISION PIPELINE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐  │
│   │Strategy A│   │Strategy B│   │Strategy C│   │Strategy D│  │
│   │  VOTE    │   │  VOTE    │   │  VOTE    │   │  VOTE    │  │
│   │ LONG 0.72│   │ LONG 0.45│   │NEUT 0.10 │   │SHRT 0.30 │  │
│   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘  │
│        │              │              │              │          │
│        └──────────────┴──────┬───────┴──────────────┘          │
│                              ▼                                  │
│                    ┌─────────────────┐                         │
│                    │  AGGREGATION    │                         │
│                    │  Confidence: 0.58│                         │
│                    │  Direction: LONG│                         │
│                    └────────┬────────┘                         │
│                             │                                   │
│                             ▼                                   │
│              ┌─────────────────────────────┐                   │
│              │      RISK ENGINE GATE       │                   │
│              │  ┌───────────────────────┐   │                   │
│              │  │ Daily Loss: PASS     │   │                   │
│              │  │ Exposure: PASS        │   │                   │
│              │  │ Correlation: PASS     │   │                   │
│              │  │ Volatility: PASS      │   │                   │
│              │  │ Margin: PASS          │   │                   │
│              │  │ Kill Switch: INACTIVE │   │                   │
│              │  └───────────────────────┘   │                   │
│              │         STATUS: APPROVED      │                   │
│              └───────────────┬─────────────┘                   │
│                              │                                   │
│                              ▼                                   │
│                   ┌──────────────────┐                          │
│                   │ EXECUTION ENGINE │                          │
│                   │ Order Constructed│                          │
│                   │ Sent to Broker   │                          │
│                   └────────┬─────────┘                          │
│                            │                                    │
│                            ▼                                    │
│                   ┌──────────────────┐                          │
│                   │  TRADE MANAGER   │                          │
│                   │ Fill Confirmed   │                          │
│                   │ Position Updated │                          │
│                   └──────────────────┘                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. EXTENSIBILITY DESIGN

### AI Decision Layer Integration

```
┌─────────────────────────────────────────────────────────────┐
│                    FUTURE: AI LAYER                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐      ┌─────────────┐      ┌──────────┐ │
│   │  LLM AGENT  │      │ ML MODEL   │      │  NLP     │ │
│   │  (Reasoning)│      │ (Inference)│      │ (News)   │ │
│   └──────┬──────┘      └──────┬──────┘      └────┬─────┘ │
│          │                    │                  │       │
│          └────────────────────┼──────────────────┘       │
│                             ▼                            │
│                  ┌─────────────────────┐                  │
│                  │   AI ADAPTER MODULE │                  │
│                  │  (Converts AI output│                  │
│                  │   to strategy votes)│                  │
│                  └──────────┬──────────┘                  │
│                             │                            │
│                             ▼                            │
│                  ┌─────────────────────┐                  │
│                  │   STRATEGY ENGINE   │                  │
│                  │  (AI votes treated  │                  │
│                  │   as strategy votes)│                  │
│                  └─────────────────────┘                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

- AI adapters convert AI outputs into standard `StrategyVote` objects.
- AI strategies participate in the same voting and aggregation pipeline as rule-based strategies.
- Risk Engine treats AI votes identically — no special bypass.
- AI layer is a **plugin**, not a core dependency.

### Multi-Strategy Portfolio Trading

- Strategy Engine supports multiple concurrent strategies.
- Each strategy has isolated configuration, state, and performance tracking.
- Portfolio-level constraints are enforced by Risk Engine (total exposure, correlation limits).
- Strategy weights can be adjusted dynamically based on performance.

### Multi-Symbol Trading

- Atlas Context is **per-symbol** with a **portfolio overlay**.
- Each symbol has its own Market State and Strategy Votes.
- Risk Engine evaluates portfolio-level constraints across all symbols.
- Execution Engine routes orders to correct symbols.

### External Data Sources

```
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   NEWS FEED     │   │  MACRO DATA     │   │  SENTIMENT      │
│   ADAPTER       │   │  ADAPTER        │   │  ADAPTER        │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               ▼
                    ┌─────────────────────┐
                    │   FEATURE ENGINE    │
                    │ (Extends Market     │
                    │  Engine features)   │
                    └─────────────────────┘
```

- External data adapters feed into the Feature Engine (extension of Market Engine).
- New features are added to the `feature_vector` in Atlas Context.
- Strategies can consume these features without knowing their source.

### Plugin Architecture

- Each module exposes a **Plugin Interface**.
- New strategies, risk rules, execution adapters, and data sources are plugins.
- Plugins are registered at startup via Configuration System.
- Core Engine loads plugins in isolation — a plugin failure does not crash the system.

---

## 9. DESIGN PRINCIPLES

### 1. Risk-First System Design
The system is built around the premise that **preservation of capital is more important than generation of profit**. Every feature, every module, and every decision path must be evaluated against: "What is the worst thing that can happen if this fails?" If the answer is unacceptable, the design is wrong.

### 2. No Hidden Logic
There is no "magic" in AtlasEA. Every decision is traceable to:
- Which strategy voted what
- Which risk rule approved or rejected
- Which execution parameter was used
- What the state was at the time
If a human cannot reconstruct why a trade happened by reading the logs, the system is broken.

### 3. Full Transparency of Decisions
Every trade decision generates a complete audit trail:
- Pre-trade context snapshot
- Strategy votes and reasoning
- Risk evaluation and rationale
- Execution details and confirmations
- Post-trade state snapshot
This trail is immutable and retained for the lifetime of the system.

### 4. Modular and Replaceable Components
Any module can be replaced with an alternative implementation without changing other modules, provided the interface contract is honored. A strategy can be swapped. A broker adapter can be swapped. Even the Risk Engine can be replaced with a more sophisticated version.

### 5. Deterministic Core System (Before AI)
Before any AI is introduced, the system must be fully deterministic. Given the same market data and configuration, it must produce the same decisions every time. This provides the baseline against which AI enhancements are measured.

### 6. Safety Over Profit
AtlasEA will prefer to miss a profitable trade than to take an uncontrolled loss. It will prefer to halt than to operate in an uncertain state. It will prefer to log excessively than to miss a critical event. Profit is the reward for correct operation; safety is the prerequisite for any operation.

### 7. Fail-Safe by Default
Every module must define its failure mode:
- **Fail-Safe**: On failure, stop trading (default for Risk Engine, Execution Engine)
- **Fail-Operational**: On failure, continue with degraded capability (default for Analytics, Logger)
- **Fail-Transparent**: On failure, log and alert but do not hide (default for all modules)

### 8. Defense in Depth
No single module is trusted completely. The Execution Engine validates orders even after Risk approval. The Trade Manager reconciles positions even after Execution confirmations. The Core Engine validates all context writes. Trust but verify at every layer.

---

## 10. IMPLEMENTATION GUIDANCE FOR AI CODING AGENTS

### Agent Assignment Strategy

| Agent | Module(s) | Interface Contract |
|-------|-----------|-------------------|
| Agent A | Core Engine + Configuration System | Event routing, lifecycle, context guardian |
| Agent B | Market Engine + Feature Engine | Data ingestion, normalization, feature computation |
| Agent C | Strategy Engine + Strategy Plugins | Vote generation, aggregation, strategy isolation |
| Agent D | Risk Engine | Limit enforcement, kill switch, decision gate |
| Agent E | Execution Engine + Trade Manager | Order lifecycle, broker interface, position tracking |
| Agent F | Logger System + Analytics Engine | Structured logging, metrics, reporting |

### Interface Contracts

Each module must expose:
- **Initialization Contract**: How it registers with Core Engine
- **Input Contract**: What data it expects and in what format
- **Output Contract**: What data it produces and in what format
- **Error Contract**: How it reports failures and what its failure mode is
- **Lifecycle Contract**: How it starts, pauses, resumes, and shuts down

### Testing Strategy

- **Unit Tests**: Each module in isolation with mocked dependencies
- **Integration Tests**: Pairs of modules (e.g., Risk + Execution)
- **Pipeline Tests**: Full tick cycle with synthetic data
- **Replay Tests**: Historical tick data replayed to verify deterministic behavior
- **Chaos Tests**: Random failures injected to verify fault isolation

---

## APPENDIX: GLOSSARY

| Term | Definition |
|------|-----------|
| **Atlas Context** | Central, versioned state structure — single source of truth |
| **Strategy Vote** | A strategy's output: direction + confidence + metadata |
| **Risk Gate** | The point where Risk Engine approves/rejects/modifies decisions |
| **Kill Switch** | Emergency halt that stops all trading activity |
| **Feature Vector** | Normalized, computed market data available to strategies |
| **Sanitized Copy** | A read-only, filtered view of Atlas Context for a specific module |
| **Plugin** | A swappable component that conforms to an interface contract |

---

# 🔴 AtlasEA Architecture Review & Correction

## Critical Analysis & Production-Ready Fixes

---

## 1. 🔴 CRITICAL ISSUES — Would Break Production

### Issue 1: **No MT5 Platform Adapter**
**Severity:** System will not run.
**Problem:** The architecture assumes a generic event-driven runtime. MetaTrader 5 does not provide a general event bus. It provides `OnTick()`, `OnInit()`, `OnDeinit()`, and `OnTimer()`. The Core Engine cannot "route events" because there is no underlying event infrastructure in MQL5.
**Fix:** Introduce an **MT5 Adapter Layer** that owns the MQL5 entry points and translates them into AtlasEA events.

### Issue 2: **No Backtesting / Replay Engine**
**Severity:** Cannot validate strategies before live deployment.
**Problem:** An institutional system without deterministic replay is un-testable. The architecture has no concept of historical tick replay, bar replay, or deterministic simulation.
**Fix:** Add **Replay Engine** as a first-class module that can replace the MT5 Adapter during backtesting.

### Issue 3: **No State Persistence / Crash Recovery**
**Severity:** A terminal crash or EA restart loses all context.
**Problem:** Atlas Context is described as in-memory only. If MT5 crashes, the EA restarts with zero knowledge of open positions, pending orders, or daily P&L. This violates "survive live markets for years."
**Fix:** Add **Persistence Manager** with atomic snapshot writes to disk. On restart, system must reconcile with broker state, not start from zero.

### Issue 4: **Event System Is Undefined**
**Severity:** AI agents will implement incompatible event handlers.
**Problem:** "Event-driven" is stated but no event schema, queue, or delivery guarantees are defined. In MQL5, you cannot spawn true async handlers. Events must be processed cooperatively within `OnTick()`.
**Fix:** Define **Event Queue** with strict schema and synchronous, ordered processing within the tick cycle.

### Issue 5: **MQL5 Single-Threaded Execution Model Ignored**
**Severity:** Architecture implies concurrent module execution.
**Problem:** Phrases like "All handlers for a given phase run synchronously" and "Failure in one handler does not prevent others" suggest a multi-threaded runtime. MQL5 EAs run in a single thread. A crash in Strategy Engine crashes the entire EA.
**Fix:** Explicitly model cooperative execution with error boundaries (try/catch per phase) and no assumption of thread isolation.

### Issue 6: **No Formal Data Contracts**
**Severity:** Module interfaces are ambiguous; AI agents will produce incompatible implementations.
**Problem:** StrategyVote, RiskDecision, OrderRequest are described narratively but not as strict schemas with field types, validation rules, and immutability.
**Fix:** Define strict MQL5-compatible struct schemas for all inter-module messages.

---

## 2. 🟡 STRUCTURAL ISSUES — Design Weaknesses

### Issue 7: **Atlas Context Is Monolithic**
**Weakness:** A single giant context snapshot updated atomically per tick is theoretically clean but impractical in MQL5. Copying a massive struct every tick is CPU-heavy and memory-intensive.
**Fix:** Split into **AtlasContext** (current state, mutable by designated guardians) and **AtlasSnapshot** (immutable read-only copies for modules). Use selective updates, not full copies.

### Issue 8: **Logger and Analytics Are Pure Observers**
**Weakness:** In MQL5, file I/O in `OnTick()` blocks the thread. A Logger that writes every event to disk synchronously will cause tick misses and requotes.
**Fix:** Logger must use an **async write buffer** (MQL5 file flush is the only async primitive available). Analytics must aggregate in-memory and flush on timer, not per tick.

### Issue 9: **Configuration Is Immutable at Runtime**
**Weakness:** While philosophically correct, this is impractical for live trading. Risk limits may need emergency adjustment without EA restart.
**Fix:** Allow **controlled runtime reload** via a `RELOAD_CONFIG` event that passes through Risk Engine validation. Config changes become audit-logged events.

### Issue 10: **Strategy Engine Vote Aggregation Is Vague**
**Weakness:** "Configurable aggregation function" is undefined. How does a strategy's track record weight its vote? Where is track record stored?
**Fix:** Define **StrategyRegistry** with performance tracking. Aggregation is a module function with explicit formula.

### Issue 11: **Execution Engine Retry Logic Is Dangerous**
**Weakness:** "Retries with exponential backoff" in an execution engine can lead to duplicate orders in MT5 if not handled with idempotency keys.
**Fix:** Every `OrderRequest` must carry a **client-generated UUID** (magic number + comment field in MT5) for idempotency. Execution Engine must check for existing orders before retry.

### Issue 12: **Trade Manager vs. Execution Engine Boundary Is Blurred**
**Weakness:** Execution Engine sends orders; Trade Manager tracks positions. But who handles `OnTrade()` (MT5 fill event)? The architecture does not map MT5 callbacks to modules.
**Fix:** MT5 Adapter receives `OnTrade()` and routes to Trade Manager. Execution Engine only handles `OrderSend()` and status polling.

---

## 3. 🟢 FIXED ARCHITECTURE SUGGESTIONS

### Fix A: MT5 Adapter Layer (NEW)

```
┌─────────────────────────────────────────────────────────────┐
│                    MT5 RUNTIME ENVIRONMENT                  │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ OnInit()│  │OnTick() │  │OnTrade()│  │OnTimer()│        │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘        │
│       │            │            │            │              │
│       └────────────┴────────────┴────────────┘              │
│                    │                                        │
│                    ▼                                        │
│         ┌─────────────────┐                                │
│         │   MT5 ADAPTER   │                                │
│         │  ┌─────────────┐ │                                │
│         │  │Event Queue  │ │  Buffers raw MT5 events       │
│         │  │(MQL5 struct)│ │  into typed AtlasEA events    │
│         │  └─────────────┘ │                                │
│         │  ┌─────────────┐ │                                │
│         │  │State Recon. │ │  Reconciles broker state on   │
│         │  │  OnTrade()   │ │  OnTrade() and restart        │
│         │  └─────────────┘ │                                │
│         └────────┬────────┘                                │
│                  │                                          │
│                  ▼                                          │
│         ┌─────────────────┐                                │
│         │   CORE ENGINE   │                                │
│         └─────────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

**Responsibility:** The MT5 Adapter is the **only** module allowed to call MQL5-specific functions (`SymbolInfoDouble`, `OrderSend`, `PositionSelect`, etc.). It translates MT5 reality into AtlasEA abstraction.

### Fix B: Event Queue Schema (MQL5-Compatible)

```
┌─────────────────────────────────────────────────────────────┐
│                     EVENT STRUCT SCHEMA                       │
├─────────────────────────────────────────────────────────────┤
│  struct AtlasEvent                                           │
│  {                                                           │
│      ulong      event_id;        // Monotonic, unique       │
│      datetime   timestamp;        // Event generation time    │
│      ENUM_EVENT_TYPE type;      // TICK, BAR, TRADE, etc.    │
│      string     source_module;  // Originating module       │
│      string     payload_json;   // Serialized data (MQL5   │
│                                 // has no generics, use    │
│                                 // string + parser)        │
│      bool       is_replay;      // True if from ReplayEng.  │
│  };                                                          │
│                                                              │
│  enum ENUM_EVENT_TYPE                                        │
│  {                                                           │
│      EV_TICK_RECEIVED,                                       │
│      EV_BAR_CLOSED,                                          │
│      EV_MARKET_STATE_UPDATED,                                │
│      EV_STRATEGY_VOTE_SUBMITTED,                            │
│      EV_VOTES_AGGREGATED,                                    │
│      EV_RISK_DECISION_RENDERED,                             │
│      EV_ORDER_REQUESTED,                                     │
│      EV_ORDER_SENT,                                          │
│      EV_TRADE_EXECUTED,                                     │
│      EV_POSITION_UPDATED,                                     │
│      EV_KILL_SWITCH_ACTIVATED,                              │
│      EV_CONFIG_RELOAD_REQUESTED,                            │
│      EV_ERROR_OCCURRED,                                      │
│      EV_HEARTBEAT                                            │
│  };                                                          │
└─────────────────────────────────────────────────────────────┘
```

**Rule:** All events are pushed to a single `CArrayObj` queue in MT5 Adapter. Core Engine dequeues and routes synchronously. No module emits directly to another module.

### Fix C: Strict Data Contracts

#### StrategyVote
```
struct StrategyVote
{
    string    strategy_id;       // Unique strategy identifier
    string    symbol;            // Target symbol
    ENUM_DIRECTION direction;    // LONG, SHORT, NEUTRAL
    double    confidence;        // 0.0 to 1.0
    double    suggested_volume;  // Lots (advisory only)
    double    suggested_price;   // Limit price (optional)
    string    rationale;         // Human-readable reason
    ulong     context_version;   // AtlasContext snapshot ID
    ulong     timestamp;         // Vote generation time
    
    // VALIDATION: confidence must be in [0,1]
    // VALIDATION: direction cannot be NULL
    // VALIDATION: strategy_id must be registered
};
// WRITER: Strategy Engine
// READERS: Core Engine, Risk Engine, Analytics
// IMMUTABLE: After submission, never modified
```

#### RiskDecision
```
struct RiskDecision
{
    ulong     decision_id;       // Unique
    ulong     vote_aggregation_id; // Links to votes
    ENUM_RISK_STATUS status;   // APPROVED, REJECTED, MODIFIED
    string    rejection_reason;  // Required if REJECTED
    double    approved_volume; // Final volume after risk
    double    approved_price;  // Final price after risk
    ENUM_ORDER_TYPE order_type; // Modified order type
    double    stop_loss;         // Mandatory stop loss
    double    take_profit;       // Optional take profit
    ulong     timestamp;
    string    risk_checks_passed; // CSV of passed checks
    string    risk_checks_failed; // CSV of failed checks
    
    // VALIDATION: If APPROVED, stop_loss must be > 0
    // VALIDATION: approved_volume must be <= suggested_volume
    // VALIDATION: If REJECTED, approved_volume must be 0
};
// WRITER: Risk Engine ONLY
// READERS: Execution Engine, Core Engine, Analytics
// IMMUTABLE: After rendering, never modified
```

#### OrderRequest
```
struct OrderRequest
{
    string    request_id;        // UUID for idempotency
    string    symbol;
    ENUM_ORDER_TYPE order_type;
    double    volume;
    double    price;
    double    stop_loss;
    double    take_profit;
    ulong     magic_number;      // MT5 magic number
    string    comment;           // AtlasEA + request_id
    ulong     risk_decision_id;  // Links to RiskDecision
    ulong     expiration;        // Order expiration time
    ENUM_TRADE_REQUEST_FLAGS flags;
    
    // VALIDATION: request_id must be unique in session
    // VALIDATION: risk_decision_id must reference APPROVED decision
    // VALIDATION: magic_number must be system-registered
};
// WRITER: Execution Engine (from RiskDecision)
// SENDER: MT5 Adapter (only module that calls OrderSend)
// IMMUTABLE: After construction, never modified
```

#### MarketState
```
struct MarketState
{
    string    symbol;
    double    bid;
    double    ask;
    double    last;
    double    spread;
    double    point;
    int       digits;
    double    volume_tick;
    datetime  tick_time;
    double    bar_open;
    double    bar_high;
    double    bar_low;
    double    bar_close;
    long      bar_volume;
    double    atr_14;            // Normalized volatility
    double    trend_strength;    // 0.0 to 1.0
    ENUM_TREND_DIRECTION trend_dir;
    double    feature_vector[32]; // Fixed-size array for MQL5
    bool      market_open;
    bool      is_fast_market;    // High volatility flag
};
// WRITER: Market Engine
// UPDATED: Every OnTick()
// READERS: All modules (read-only copy)
```

#### PositionState
```
struct PositionState
{
    string    ticket;            // MT5 position ticket
    string    symbol;
    ENUM_POSITION_TYPE type;   // LONG or SHORT
    double    volume;
    double    open_price;
    double    current_price;
    double    stop_loss;
    double    take_profit;
    double    unrealized_pnl;
    double    commission;
    double    swap;
    datetime  open_time;
    string    strategy_id;       // Which strategy opened this
    ulong     order_request_id;  // Links to OrderRequest
    bool      is_being_closed;   // Pending close flag
};
// WRITER: Trade Manager ONLY
// UPDATED: OnTrade() event + periodic reconciliation
// READERS: All modules (read-only copy)
```

#### ExecutionEvent
```
struct ExecutionEvent
{
    ulong     event_id;
    string    request_id;      // Links to OrderRequest
    string    ticket;            // MT5 order/position ticket
    ENUM_EXEC_STATUS status;   // PENDING, FILLED, PARTIAL, REJECTED, ERROR
    double    filled_volume;
    double    fill_price;
    double    slippage;
    string    broker_message;
    ulong     timestamp;
    int       error_code;        // MT5 error code if failed
};
// WRITER: MT5 Adapter (from OnTrade / OrderSend result)
// ROUTED: Core Engine → Trade Manager + Execution Engine
// IMMUTABLE: After creation
```

### Fix D: Cooperative Execution Model (MQL5 Reality)

```
┌─────────────────────────────────────────────────────────────┐
│                     ON TICK CYCLE (MQL5)                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  OnTick()                                                     │
│    │                                                          │
│    ▼                                                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  MT5 ADAPTER                                            │ │
│  │  1. Read tick data from MT5                             │ │
│  │  2. Push EV_TICK_RECEIVED to Event Queue                │ │
│  │  3. Check OnTrade() buffer (if trade occurred)          │ │
│  │  4. Push EV_TRADE_EXECUTED if needed                    │ │
│  └─────────────────────────────────────────────────────────┘ │
│    │                                                          │
│    ▼                                                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  CORE ENGINE: PROCESS EVENT QUEUE                       │ │
│  │  (Synchronous, single-threaded, cooperative)            │ │
│  │                                                          │ │
│  │  while (queue not empty)                                │ │
│  │  {                                                      │ │
│  │      event = queue.Dequeue();                           │ │
│  │      switch(event.type)                                 │ │
│  │      {                                                  │ │
│  │          case EV_TICK_RECEIVED:                         │ │
│  │              MarketEngine.OnTick(event);                │ │
│  │              break;                                     │ │
│  │          case EV_MARKET_STATE_UPDATED:                  │ │
│  │              StrategyEngine.Evaluate(context);          │ │
│  │              break;                                     │ │
│  │          case EV_VOTES_AGGREGATED:                      │ │
│  │              RiskEngine.Evaluate(votes);                │ │
│  │              break;                                     │ │
│  │          case EV_RISK_DECISION_RENDERED:                │ │
│  │              if (decision.status == APPROVED)           │ │
│  │                  ExecutionEngine.Execute(decision);     │ │
│  │              break;                                     │ │
│  │          case EV_TRADE_EXECUTED:                        │ │
│  │              TradeManager.UpdatePosition(event);        │ │
│  │              break;                                     │ │
│  │      }                                                  │ │
│  │  }                                                      │ │
│  │                                                          │ │
│  │  // Error boundary per phase                             │ │
│  │  try { ... } catch { LogError(); ContinueNextEvent(); } │ │
│  └─────────────────────────────────────────────────────────┘ │
│    │                                                          │
│    ▼                                                          │
│  Return from OnTick() → MT5 handles next tick               │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Critical Rule:** Each phase has a **max execution time budget**. If a phase exceeds its budget, it is skipped, an error is logged, and the system continues. This prevents one slow module from missing ticks.

---

## 4. 📦 MISSING COMPONENTS (NEW)

### Component 1: **MT5 Adapter** (Mandatory)
- Owns all MQL5 API calls
- Normalizes MT5-specific data into AtlasEA structs
- Handles `OnTick`, `OnTrade`, `OnTimer`, `OnInit`, `OnDeinit`
- Manages EA lifecycle (initialization, shutdown, error recovery)
- Provides idempotency via magic number + comment tracking

### Component 2: **Replay Engine** (Mandatory)
- Replaces MT5 Adapter during backtesting
- Reads historical tick/bar data from files
- Replays events in chronological order
- Produces deterministic output for strategy validation
- Can run at accelerated speed (not real-time)
- Validates that live behavior matches backtest behavior

### Component 3: **Persistence Manager** (Mandatory)
- Writes Atlas Context snapshots to disk every N seconds
- Writes event log to binary file (not CSV, for speed)
- On `OnInit()`, reads last snapshot and reconstructs state
- On restart, reconciles persisted state with broker-reported positions
- Ensures crash recovery without data loss

### Component 4: **Strategy Registry** (Mandatory)
- Maintains list of active strategies
- Tracks per-strategy performance metrics (win rate, expectancy, Sharpe)
- Provides strategy weights for vote aggregation
- Enables/disable strategies dynamically via config
- Prevents duplicate strategy IDs

### Component 5: **Health Monitor** (Mandatory)
- Runs on `OnTimer()` (not OnTick, to save CPU)
- Checks: tick reception frequency, memory usage, event queue depth
- Detects "stuck" states (e.g., position open but no updates for X minutes)
- Triggers kill switch if health checks fail
- Reports system status to Analytics

### Component 6: **Idempotency Guard** (Mandatory)
- Prevents duplicate orders from retries or race conditions
- Maintains set of `request_id` values for current session
- Before any `OrderSend`, checks if `request_id` already exists in broker history
- Critical for MQL5 where `OrderSend` may fail silently and retry is needed

---

## 5. 🧠 FINAL CLEAN ARCHITECTURE SUMMARY

### Revised System Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ATLAS EA SYSTEM v1.1 (Production-Ready)         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MT5 RUNTIME LAYER                         │   │
│  │  OnTick() │ OnTrade() │ OnTimer() │ OnInit() │ OnDeinit()   │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                         │                                           │
│                         ▼                                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  MT5 ADAPTER (MQL5 API Isolation)                           │   │
│  │  • Event Queue (CArrayObj)                                  │   │
│  │  • Tick Normalization                                       │   │
│  │  • OrderSend / OrderSelect Wrappers                         │   │
│  │  • State Reconciliation on Restart                          │   │
│  │  • Idempotency Guard                                        │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                         │                                           │
│                         ▼                                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  CORE ENGINE (Orchestrator, Single-Threaded Cooperative)   │   │
│  │  • Event Router (synchronous dequeue)                       │   │
│  │  • Phase Scheduler (budgeted execution time)              │   │
│  │  • Atlas Context Guardian (atomic selective updates)      │   │
│  │  • Module Registry (lifecycle management)                 │   │
│  │  • Kill Switch Controller                                 │   │
│  └─────┬────────────┬────────────┬────────────┬───────────────┘   │
│        │            │            │            │                     │
│   ┌────▼────┐  ┌───▼────┐  ┌────▼────┐  ┌───▼────┐  ┌──────────┐ │
│   │ MARKET  │  │STRATEGY│  │  RISK   │  │EXECUTE │  │  TRADE   │ │
│   │ ENGINE  │  │ENGINE  │  │ ENGINE  │  │ENGINE  │  │ MANAGER  │ │
│   │         │  │        │  │         │  │        │  │          │ │
│   │• Feature│  │• Vote  │  │• Validate│  │• Build │  │• Reconcile│
│   │• Regime │  │• Aggregate│• Approve│  │• Send  │  │• Track   │ │
│   │• Anomaly│  │• Weight │  │• Modify │  │• Retry │  │• P&L     │ │
│   └────┬────┘  └───┬────┘  └────┬────┘  └───┬────┘  └────┬─────┘ │
│        │           │            │           │            │       │
│        └───────────┴────────────┴───────────┴────────────┘       │
│                              │                                     │
│                              ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  ATLAS CONTEXT (Selective Update, Not Full Snapshot)         │  │
│  │  • MarketState (MarketEngine writes)                        │  │
│  │  • PositionState[] (TradeManager writes)                   │  │
│  │  • RiskStatus (RiskEngine writes)                          │  │
│  │  • DecisionState (Strategy + Risk + Execution write)       │  │
│  │  • SystemHealth (CoreEngine writes)                        │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│        ┌─────────────────────┼─────────────────────┐              │
│        │                     │                     │              │
│   ┌────▼────┐          ┌────▼────┐          ┌────▼────┐          │
│   │ LOGGER  │          │ANALYTICS│          │PERSIST. │          │
│   │ SYSTEM  │          │ ENGINE  │          │ MANAGER │          │
│   │(Buffered│          │(In-Mem, │          │(Disk    │          │
│   │  Flush) │          │  Flush) │          │ Snapshot)│          │
│   └─────────┘          └─────────┘          └─────────┘          │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  SUPPORT MODULES (Not in main tick path)                   │  │
│  │  • Configuration System (read-only after load)            │  │
│  │  • Strategy Registry (performance tracking)                 │  │
│  │  • Health Monitor (OnTimer-based)                         │  │
│  │  • Replay Engine (backtesting only)                        │  │
│  │  • AI Adapter (converts AI output to StrategyVote)         │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Revised Dependency Rules (Enforced)

| # | Rule | Enforcement |
|---|------|-------------|
| 1 | Strategy cannot execute trades | StrategyVote has no order fields. Only RiskDecision → ExecutionEngine path exists. |
| 2 | Risk Engine is final authority | ExecutionEngine requires RiskDecision object with `status == APPROVED`. No bypass. |
| 3 | Execution is isolated from strategy | ExecutionEngine receives only RiskDecision, never sees StrategyVote array. |
| 4 | Core Engine only orchestrates | No business logic. Only event routing and phase scheduling. |
| 5 | No module bypasses Atlas Context | All inter-module data flows through Context or Event Queue. |
| 6 | Trade Manager is position authority | Only TradeManager calls `PositionSelect` / `PositionGetDouble`. |
| 7 | Config is immutable at runtime | Reload requires `EV_CONFIG_RELOAD_REQUESTED` → RiskEngine validation → CoreEngine application. |
| 8 | Logger/Analytics are read-only | No event emission. No state modification. |
| 9 | **NEW:** MT5 Adapter owns all broker calls | No module except MT5 Adapter calls `OrderSend`, `SymbolInfo`, etc. |
| 10 | **NEW:** Idempotency on all orders | Every OrderRequest has UUID. Duplicate detection before send. |

### Revised Event Flow (MQL5-Compatible)

```
OnTick()
  │
  ▼
MT5 Adapter ──► Push EV_TICK_RECEIVED
  │
  ▼
Core Engine Dequeue
  │
  ├──► MarketEngine ──► Update MarketState in Context
  │       └──► Push EV_MARKET_STATE_UPDATED
  │
  ├──► StrategyEngine ──► Evaluate ──► Push EV_STRATEGY_VOTE_SUBMITTED
  │       └──► (All votes received) ──► Push EV_VOTES_AGGREGATED
  │
  ├──► RiskEngine ──► Evaluate ──► Push EV_RISK_DECISION_RENDERED
  │       ├── APPROVED ──► Push EV_ORDER_REQUESTED
  │       └── REJECTED ──► Log, Analytics, Done
  │
  ├──► ExecutionEngine ──► Build OrderRequest
  │       └──► Push EV_ORDER_SENT (to MT5 Adapter)
  │
  ├──► MT5 Adapter ──► OrderSend() ──► Push EV_ORDER_DISPATCHED
  │
  ├──► OnTrade() (async from broker)
  │       └──► MT5 Adapter ──► Push EV_TRADE_EXECUTED
  │
  └──► TradeManager ──► Update PositionState in Context
            └──► Push EV_POSITION_UPDATED
```

### AI Integration (Tightened)

```
┌─────────────────────────────────────────────────────────────┐
│                    AI INTEGRATION (Plugin)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│   │ LLM Agent│    │ ML Model │    │ NLP Feed │            │
│   └────┬─────┘    └────┬─────┘    └────┬─────┘            │
│        │               │               │                    │
│        └───────────────┼───────────────┘                    │
│                        ▼                                    │
│              ┌─────────────────┐                           │
│              │   AI ADAPTER    │                           │
│              │  (Converts AI    │                           │
│              │   output to      │                           │
│              │   StrategyVote)  │                           │
│              └────────┬────────┘                           │
│                       │                                     │
│                       ▼                                     │
│              ┌─────────────────┐                           │
│              │ STRATEGY REGISTRY │                           │
│              │  (AI registered  │                           │
│              │   as strategy)   │                           │
│              └────────┬────────┘                           │
│                       │                                     │
│                       ▼                                     │
│              ┌─────────────────┐                           │
│              │  STRATEGY ENGINE │                           │
│              │  (AI votes are   │                           │
│              │   treated exactly │                           │
│              │   like rule-based)│                           │
│              └─────────────────┘                           │
│                                                             │
│   AI NEVER:                                                 │
│   • Calls OrderSend()                                       │
│   • Modifies RiskStatus                                     │
│   • Reads account balance                                   │
│   • Bypasses Risk Engine                                    │
│                                                             │
│   AI ALWAYS:                                                │
│   • Submits StrategyVote                                    │
│   • Gets approved/rejected like any strategy                │
│   • Is observed by Analytics like any strategy              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Backtesting / Replay (NEW)

```
┌─────────────────────────────────────────────────────────────┐
│                    REPLAY ENGINE                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Mode: REPLAY (replaces MT5 Adapter)                      │
│                                                             │
│  ┌─────────────────┐                                       │
│  │ Historical Tick │                                       │
│  │    Data File    │                                       │
│  │  (CSV / Binary) │                                       │
│  └────────┬────────┘                                       │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                       │
│  │  Event Player   │                                       │
│  │  (Deterministic)│                                       │
│  │  • Reads ticks  │                                       │
│  │  • Replays in   │                                       │
│  │    chronological│                                       │
│  │    order        │                                       │
│  │  • Same event   │                                       │
│  │    types as live│                                       │
│  └────────┬────────┘                                       │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  CORE ENGINE + ALL MODULES (identical to live)         ││
│  └─────────────────────────────────────────────────────────┘│
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                       │
│  │  Result Store   │                                       │
│  │  • Trades       │                                       │
│  │  • Decisions    │                                       │
│  │  • Performance  │                                       │
│  │  • Compare to   │                                       │
│  │    live later   │                                       │
│  └─────────────────┘                                       │
│                                                             │
│  Guarantee: If backtest and live use same config and data, │
│  decisions must be IDENTICAL (deterministic core).         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Persistence & Recovery (NEW)

```
┌─────────────────────────────────────────────────────────────┐
│              PERSISTENCE & RECOVERY MODEL                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  OnDeinit() / Periodic Timer:                               │
│  ┌─────────────────┐                                        │
│  │ Atlas Context   │──► Serialize to binary file           │
│  │ Snapshot        │──► Write to MQL5/Files/atlas_state.bin │
│  │ (selective)     │                                        │
│  └─────────────────┘                                        │
│                                                             │
│  OnInit() (Restart):                                        │
│  ┌─────────────────┐                                        │
│  │ 1. Load last    │                                        │
│  │    snapshot     │                                        │
│  │ 2. Query broker │                                        │
│  │    for open     │                                        │
│  │    positions    │                                        │
│  │ 3. RECONCILE:   │                                        │
│  │    If broker    │                                        │
│  │    positions    │                                        │
│  │    match saved  │                                        │
│  │    state → OK   │                                        │
│  │    If mismatch  │                                        │
│  │    → ALERT,     │                                        │
│  │    manual       │                                        │
│  │    intervention │                                        │
│  │    required     │                                        │
│  │ 4. Restore      │                                        │
│  │    RiskStatus   │                                        │
│  │    (daily P&L,  │                                        │
│  │    drawdown)   │                                        │
│  └─────────────────┘                                        │
│                                                             │
│  Failure Modes:                                             │
│  • File corrupt → Start fresh, alert operator               │
│  • Broker mismatch → Halt trading, require manual check     │
│  • Missing file → Start fresh, log warning                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Summary of Changes

| Area | Original | Corrected |
|------|----------|-----------|
| **Platform** | Generic event-driven | MQL5-specific with MT5 Adapter |
| **Execution** | Implied concurrent | Cooperative single-threaded with time budgets |
| **Events** | Described narratively | Strict `AtlasEvent` struct with typed queue |
| **Data** | Informal fields | Formal MQL5 structs with validation rules |
| **Recovery** | Not mentioned | Persistence Manager + reconciliation |
| **Backtesting** | Not mentioned | Replay Engine as first-class module |
| **AI** | Plugin concept | Tightened: AI is just another strategy, no special path |
| **Risk** | Final authority | Same, but with explicit `RiskDecision` schema and no bypass |
| **Idempotency** | Not mentioned | Mandatory `request_id` + duplicate guard |
| **Logging** | Synchronous observer | Buffered async flush (MQL5 file I/O constraints) |

---

**AtlasEA v1.1 is now implementable in MQL5.** It preserves all original philosophy — modularity, risk-first, event-driven, strategy-agnostic — while adding the concrete constraints, contracts, and components required for production deployment in MetaTrader 5.

*This document defines the architecture of AtlasEA. It contains no implementation code, no trading logic, and no broker-specific details. It is the contract under which all implementation agents must operate.*

**AtlasEA is a system. It is not a strategy. It is not a bot. It is infrastructure for disciplined trading.**

