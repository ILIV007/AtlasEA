# 📦 AtlasEA Contract Layer Specification v1.0

## Institutional-Grade Data Contract & Communication Protocol

---

## 1. COMPLETE CONTRACT DEFINITIONS

All contracts are versioned, deterministic, and MQL5-compatible. Every struct includes a `contract_version` field for forward compatibility.

---

### 1.1 ENUMERATIONS (System-Wide)

```mql5
enum ENUM_CONTRACT_VERSION
{
    CONTRACT_V1 = 1    // Current version
};

enum ENUM_DIRECTION
{
    DIR_LONG     = 1,
    DIR_SHORT    = 2,
    DIR_NEUTRAL  = 0
};

enum ENUM_DECISION_STATUS
{
    DEC_APPROVED = 1,
    DEC_REJECTED = 2,
    DEC_MODIFIED = 3
};

enum ENUM_FILL_STATUS
{
    FILL_PENDING  = 0,
    FILL_FILLED   = 1,
    FILL_PARTIAL  = 2,
    FILL_REJECTED = 3,
    FILL_ERROR    = 4,
    FILL_CANCELLED= 5
};

enum ENUM_ORDER_TYPE_ATLAS
{
    ATLAS_MARKET      = 0,
    ATLAS_LIMIT       = 1,
    ATLAS_STOP        = 2,
    ATLAS_STOP_LIMIT  = 3
};

enum ENUM_SESSION_STATE
{
    SESSION_CLOSED    = 0,
    SESSION_PREMARKET = 1,
    SESSION_OPEN      = 2,
    SESSION_POSTMARKET= 3,
    SESSION_HOLIDAY   = 4
};

enum ENUM_TREND_DIRECTION
{
    TREND_UP      = 1,
    TREND_DOWN    = 2,
    TREND_SIDEWAYS= 0
};
```

---

### 1.2 MarketState

**Purpose:** Canonical market snapshot at a single point in time.

```mql5
struct MarketState
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       snapshot_id;            // Monotonic context version
    datetime    snapshot_time;          // UTC timestamp
    string      symbol;                 // e.g. "EURUSD"
    
    // ── PRICE ──
    double      bid;
    double      ask;
    double      last;
    double      spread;                 // ask - bid (in points)
    double      point;                  // Symbol point value
    int         digits;                 // Decimal places
    
    // ── VOLUME ──
    long        tick_volume;            // Current tick volume
    long        bar_volume;             // Current bar cumulative volume
    double      real_volume;            // Exchange volume if available
    
    // ── VOLATILITY ──
    double      atr_14;                 // 14-period ATR
    double      volatility_index;       // Normalized 0.0 - 1.0
    bool        is_fast_market;         // True if vol > threshold
    
    // ── TREND ──
    ENUM_TREND_DIRECTION trend_direction;
    double      trend_strength;         // 0.0 - 1.0
    int         trend_duration_bars;    // Bars in current trend
    
    // ── BAR STATE ──
    double      bar_open;
    double      bar_high;
    double      bar_low;
    double      bar_close;
    datetime    bar_time;
    
    // ── SESSION ──
    ENUM_SESSION_STATE session_state;
    datetime    session_open_time;
    datetime    session_close_time;
    
    // ── FEATURE VECTOR (extensible, fixed-size for MQL5) ──
    double      features[32];           // Normalized feature values
    int         feature_count;          // Active features (0-32)
    string      feature_names[32];      // Human-readable feature labels
    
    // ── VALIDATION ──
    bool        is_valid;               // False if data is stale/corrupt
    string      invalid_reason;         // Explanation if is_valid == false
};
```

**Ownership:** Written **exclusively** by Market Engine.  
**Immutability:** **YES** — once snapshot_id is assigned, no module may modify.  
**Readers:** All modules (receive read-only copy).  
**Update Frequency:** Every `OnTick()` or bar close.

---

### 1.3 StrategyVote

**Purpose:** Output of any strategy evaluation. Stateless and idempotent.

```mql5
struct StrategyVote
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       vote_id;                // Unique per vote (UUID)
    ulong       snapshot_id;            // Links to MarketState snapshot
    datetime    vote_time;              // UTC
    
    // ── SOURCE ──
    string      strategy_id;            // Registered strategy identifier
    string      strategy_version;       // Strategy version for tracking
    string      symbol;                 // Target symbol
    
    // ── DECISION ──
    ENUM_DIRECTION direction;             // LONG, SHORT, NEUTRAL
    double      confidence;             // 0.0 - 1.0 (NaN = invalid)
    
    // ── SUGGESTED PARAMETERS (advisory only) ──
    double      suggested_volume;       // Lots
    double      suggested_entry_price;  // For limit orders (0.0 = market)
    double      suggested_sl;           // Stop loss price
    double      suggested_tp;           // Take profit price
    int         suggested_timeframe;    // Minutes (e.g. 15, 60, 240)
    
    // ── METADATA (key-value pairs, fixed arrays for MQL5) ──
    string      meta_keys[16];
    string      meta_values[16];
    int         meta_count;             // 0-16
    
    // ── CONTEXT ──
    double      market_regime_score;    // Strategy's view of regime
    string      rationale;              // Human-readable reasoning
};
```

**Ownership:** Written **exclusively** by Strategy Engine (or AI Adapter feeding into Strategy Engine).  
**Immutability:** **YES** — submitted once, never modified.  
**Readers:** Core Engine, Risk Engine, Analytics.  
**Validation Rules:**
- `confidence` must be in `[0.0, 1.0]` or `NEUTRAL`
- `strategy_id` must exist in Strategy Registry
- `snapshot_id` must reference a valid `MarketState` within last 5 seconds
- `direction` cannot be null/undefined

---

### 1.4 RiskDecision

**Purpose:** Final authority on every proposed trading action. Non-bypassable.

```mql5
struct RiskDecision
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       decision_id;            // Unique
    ulong       vote_aggregation_id;    // Links to aggregated vote batch
    datetime    decision_time;          // UTC
    
    // ── STATUS ──
    ENUM_DECISION_STATUS status;        // APPROVED, REJECTED, MODIFIED
    
    // ── REASONING ──
    string      rejection_reason;       // Required if REJECTED
    int         reason_code;            // Machine-readable code (enum)
    string      risk_checks_passed[16]; // CSV of passed checks
    string      risk_checks_failed[16]; // CSV of failed checks
    int         passed_count;
    int         failed_count;
    
    // ── APPROVED PARAMETERS (final, binding) ──
    double      approved_volume;        // Final lots (<= suggested)
    double      approved_entry_price;   // Final entry price
    double      approved_sl;            // Mandatory stop loss
    double      approved_tp;            // Optional take profit
    ENUM_ORDER_TYPE_ATLAS approved_order_type;
    
    // ── EXPOSURE IMPACT ──
    double      projected_exposure;     // Post-trade exposure in base currency
    double      projected_margin;       // Post-trade margin requirement
    double      projected_daily_dd;     // Post-trade daily drawdown %
    
    // ── LIMITS APPLIED ──
    double      max_volume_limit;       // System max volume rule applied
    double      exposure_limit;         // System exposure rule applied
    bool        kill_switch_triggered;  // True if this decision triggered KS
    bool        cooldown_applied;       // True if strategy cooled off
    
    // ── TRACEABILITY ──
    ulong       snapshot_id;            // Context version at decision time
    string      strategy_votes_summary; // JSON summary of input votes
};
```

**Ownership:** Written **exclusively** by Risk Engine.  
**Immutability:** **YES** — once rendered, locked forever.  
**Readers:** Execution Engine (primary), Core Engine, Analytics, Logger.  
**Validation Rules:**
- If `status == APPROVED`, `approved_sl` must be > 0 (mandatory stop loss)
- If `status == REJECTED`, `approved_volume` must be exactly 0.0
- If `status == MODIFIED`, `approved_volume` must be <= original suggested volume
- `decision_id` must be monotonically unique

---

### 1.5 OrderRequest

**Purpose:** Execution-intent object. Created only after Risk approval.

```mql5
struct OrderRequest
{
    // ── META ──
    int         contract_version;       // = 1
    string      request_id;             // UUID for idempotency (mandatory)
    ulong       decision_id;            // Links to RiskDecision (mandatory)
    datetime    request_time;           // UTC
    
    // ── BROKER PARAMETERS ──
    string      symbol;
    ENUM_ORDER_TYPE_ATLAS order_type;
    ENUM_DIRECTION direction;           // Derived from decision
    double      volume;                 // Final volume (from RiskDecision)
    double      entry_price;            // 0.0 for market orders
    double      stop_loss;              // Mandatory
    double      take_profit;            // Optional (0.0 = none)
    
    // ── MT5-SPECIFIC ──
    ulong       magic_number;           // System magic number
    string      comment;                // "AtlasEA|request_id|strategy_id"
    ulong       expiration;             // Order expiration (0 = no expiration)
    ENUM_ORDER_FILLING filling_mode;    // FOK, IOC, RETURN
    
    // ── TRACEABILITY ──
    string      strategy_source_id;     // Original strategy
    ulong       snapshot_id;            // Context at request time
    
    // ── VALIDATION ──
    bool        is_validated;           // Set by Execution Engine pre-send
    string      validation_errors[8];   // If validation fails
    int         validation_error_count;
};
```

**Ownership:** Constructed by **Execution Engine** from approved `RiskDecision`.  
**Immutability:** **YES** — after construction, never modified. If invalid, discard and create new.  
**Readers:** MT5 Adapter (sends to broker), Trade Manager, Analytics.  
**Validation Rules:**
- `request_id` must be unique within session (Idempotency Guard enforces)
- `decision_id` must reference an `APPROVED` or `MODIFIED` RiskDecision
- `magic_number` must be registered in system configuration
- `volume` must be > 0 and <= `RiskDecision.approved_volume`
- `comment` must contain `request_id` for broker-side tracing

---

### 1.6 ExecutionEvent

**Purpose:** Broker interaction result. Replay-safe audit record.

```mql5
struct ExecutionEvent
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       event_id;               // Unique system-wide
    string      request_id;             // Links to OrderRequest
    datetime    event_time;             // UTC
    
    // ── BROKER RESPONSE ──
    ENUM_FILL_STATUS fill_status;       // PENDING, FILLED, PARTIAL, etc.
    ulong       broker_order_id;        // MT5 Order ticket
    ulong       broker_position_id;     // MT5 Position ticket (if filled)
    
    // ── FILL DETAILS ──
    double      requested_volume;
    double      filled_volume;
    double      remaining_volume;
    double      fill_price;
    double      slippage;               // fill_price - requested_price
    double      commission;
    double      swap;
    
    // ── ERROR DATA ──
    int         error_code;             // MT5 error code (0 = success)
    string      error_message;          // Broker error description
    int         retry_count;            // Number of retries attempted
    
    // ── TRACEABILITY ──
    ulong       snapshot_id;            // Context at event time
    string      broker_comment;         // Original broker comment returned
};
```

**Ownership:** Written **exclusively** by MT5 Adapter (from `OrderSend` result or `OnTrade()`).  
**Immutability:** **YES** — historical record, never modified.  
**Readers:** Trade Manager (primary), Execution Engine, Analytics, Logger.  
**Validation Rules:**
- `event_id` must be monotonically unique
- `request_id` must reference a valid OrderRequest
- If `fill_status == FILLED`, `broker_position_id` must be > 0
- If `error_code != 0`, `fill_status` must be `ERROR` or `REJECTED`

---

### 1.7 PositionState

**Purpose:** Definitive record of open positions. Must match broker exactly.

```mql5
struct PositionState
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       position_id;            // MT5 Position ticket
    datetime    last_update;            // UTC
    
    // ── IDENTIFICATION ──
    string      symbol;
    ENUM_POSITION_TYPE position_type;   // POSITION_TYPE_BUY / SELL
    string      strategy_id;            // Strategy that opened it
    string      request_id;             // Original OrderRequest
    
    // ── SIZE & PRICE ──
    double      volume;                 // Current volume
    double      open_price;
    double      current_price;          // Last market price
    double      stop_loss;
    double      take_profit;
    
    // ── P&L ──
    double      unrealized_pnl;         // Current floating P&L
    double      realized_pnl;           // If partially closed
    double      commission;
    double      swap;
    double      total_pnl;              // unrealized + realized + commission + swap
    
    // ── MARGIN ──
    double      margin_used;
    double      margin_rate;
    
    // ── LIFECYCLE ──
    datetime    open_time;
    int         duration_minutes;
    bool        is_being_closed;        // Pending close flag
    bool        is_partial;             // True if partially closed
    double      original_volume;        // Volume at open
    
    // ── RECONCILIATION ──
    bool        broker_verified;        // True if matches broker state
    datetime    last_reconcile_time;
    string      reconcile_discrepancy;  // If mismatch detected
};
```

**Ownership:** Written **exclusively** by Trade Manager.  
**Immutability:** **PARTIAL** — Trade Manager updates `current_price`, `unrealized_pnl`, `is_being_closed` on every tick, but historical fields (`open_price`, `original_volume`, `request_id`) are immutable.  
**Readers:** All modules (read-only).  
**Validation Rules:**
- `position_id` must exist in broker's `PositionSelect()` or be archived
- `volume` must be >= 0
- If `volume == 0`, position must be marked closed and archived
- `broker_verified` must be checked every 30 seconds minimum

---

### 1.8 RiskState (GLOBAL)

**Purpose:** System-level risk health. Live, evolving state.

```mql5
struct RiskState
{
    // ── META ──
    int         contract_version;       // = 1
    ulong       state_id;               // Version increments on every update
    datetime    last_update;            // UTC
    
    // ── DRAWDOWN ──
    double      daily_pnl;              // Today realized + unrealized
    double      daily_high_watermark;   // Highest equity today
    double      daily_drawdown;         // From high watermark (negative)
    double      daily_drawdown_pct;     // As percentage
    double      max_drawdown;           // All-time max
    double      max_drawdown_pct;       // All-time max percentage
    
    // ── EXPOSURE ──
    double      total_exposure;         // Sum of all position notionals
    double      exposure_pct;           // Of account equity
    double      long_exposure;          // Sum of long positions
    double      short_exposure;         // Sum of short positions
    int         open_position_count;
    
    // ── MARGIN ──
    double      margin_used;
    double      margin_available;
    double      margin_level_pct;       // (equity / margin) * 100
    
    // ── LIMITS & GATES ──
    double      risk_budget_remaining;  // 0.0 - 1.0 (percentage of daily limit)
    bool        kill_switch_active;     // TRUE = all trading halted
    string      kill_switch_reason;     // Why KS was triggered
    
    // ── COOLDOWNS ──
    string      cooled_strategies[16];  // Strategy IDs in cooldown
    int         cooled_count;
    datetime    cooldown_until[16];     // Expiry per strategy
    
    // ── VIOLATIONS ──
    int         daily_violation_count;
    string      last_violation_reason;
    datetime    last_violation_time;
    
    // ── HEALTH ──
    bool        is_healthy;             // FALSE if any critical check fails
    string      health_warnings[8];     // Active warnings
    int         warning_count;
};
```

**Ownership:** Written **exclusively** by Risk Engine.  
**Immutability:** **PARTIAL** — Risk Engine updates continuously, but every update is versioned (`state_id`). Previous versions are logged, not overwritten in audit.  
**Readers:** All modules. Critical for Strategy Engine (may reduce confidence if risk budget low) and Core Engine (may halt if kill switch active).  
**Validation Rules:**
- `daily_drawdown` must be <= 0 (zero or negative)
- `exposure_pct` must be >= 0
- If `kill_switch_active == true`, no new `RiskDecision` with `APPROVED` status may be generated
- `risk_budget_remaining` in `[0.0, 1.0]`

---

## 2. EVENT SCHEMA SPECIFICATION

### 2.1 Core Event Struct

```mql5
enum ENUM_EVENT_TYPE
{
    // Market Events
    EV_TICK_RECEIVED        = 100,
    EV_BAR_CLOSED           = 101,
    EV_MARKET_STATE_UPDATED = 102,
    
    // Strategy Events
    EV_STRATEGY_VOTE_SUBMITTED   = 200,
    EV_VOTES_AGGREGATED          = 201,
    EV_STRATEGY_DISABLED         = 202,
    
    // Risk Events
    EV_RISK_DECISION_RENDERED    = 300,
    EV_KILL_SWITCH_ACTIVATED     = 301,
    EV_KILL_SWITCH_RESET         = 302,
    EV_RISK_LIMIT_BREACHED       = 303,
    
    // Execution Events
    EV_ORDER_REQUESTED             = 400,
    EV_ORDER_SENT                  = 401,
    EV_ORDER_DISPATCHED            = 402,
    EV_TRADE_EXECUTED              = 403,
    EV_EXECUTION_ERROR             = 404,
    
    // Trade Management Events
    EV_POSITION_OPENED             = 500,
    EV_POSITION_UPDATED            = 501,
    EV_POSITION_CLOSED             = 502,
    EV_RECONCILE_COMPLETE          = 503,
    
    // System Events
    EV_SYSTEM_INIT                 = 600,
    EV_SYSTEM_SHUTDOWN             = 601,
    EV_CONFIG_RELOADED             = 602,
    EV_HEARTBEAT                   = 603,
    EV_ERROR_OCCURRED              = 604,
    EV_STATE_PERSISTED             = 605,
    
    // Replay Events (Backtesting only)
    EV_REPLAY_START                = 900,
    EV_REPLAY_TICK                 = 901,
    EV_REPLAY_END                  = 902
};

struct AtlasEvent
{
    // ── HEADER ──
    ulong       event_id;               // Monotonic system-wide counter
    ENUM_EVENT_TYPE event_type;         // Typed discriminator
    datetime    timestamp;              // UTC generation time
    string      source_module;          // Module name (e.g. "MarketEngine")
    ulong       snapshot_id;            // AtlasContext version at event time
    
    // ── PAYLOAD ──
    // MQL5 does not support generics. Payload is serialized to JSON string.
    // The event_type determines which contract to deserialize into.
    string      payload_json;           // Serialized contract
    string      payload_type;           // Contract type name for validation
    
    // ── META ──
    bool        is_replay;              // True if generated by ReplayEngine
    bool        is_system_event;        // True if from Core/Health/Config
    int         priority;               // 0-9 (9 = critical, e.g. kill switch)
    
    // ── TRACEABILITY ──
    ulong       parent_event_id;        // For causal chains (0 = root)
    string      correlation_id;         // Groups related events
};
```

### 2.2 Event Processing Rules

| Rule | Description | Rationale |
|------|-------------|-----------|
| **E1: Single Queue** | All events pass through one `CArrayObj` queue in MT5 Adapter | MQL5 has no native event bus |
| **E2: Synchronous Dequeue** | Core Engine processes events FIFO, one at a time | Prevents race conditions in single-threaded MQL5 |
| **E3: No Direct Emission** | Modules push to queue via Core Engine API only | No module-to-module hidden communication |
| **E4: Deterministic Ordering** | Same input sequence always produces same event sequence | Required for replay and debugging |
| **E5: Event Batching** | Multiple strategy votes in one tick are batched into single `EV_VOTES_AGGREGATED` | Reduces queue pressure |
| **E6: Priority Override** | Priority 9 events (kill switch) jump queue | Safety-critical events must not wait |
| **E7: Payload Validation** | Core Engine validates `payload_type` matches `event_type` before routing | Prevents deserialization errors |
| **E8: Idempotency** | Duplicate `event_id` is silently dropped | Prevents replay duplicates |

### 2.3 Event Lifecycle Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     EVENT LIFECYCLE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [SOURCE] ──► [MT5 ADAPTER QUEUE] ──► [CORE ENGINE]      │
│                  │                    │                      │
│                  │                    ▼                      │
│                  │            [VALIDATE HEADER]              │
│                  │                    │                      │
│                  │                    ▼                      │
│                  │            [DESERIALIZE PAYLOAD]         │
│                  │            (type-check against schema)  │
│                  │                    │                      │
│                  │                    ▼                      │
│                  │            [ROUTE TO MODULE]             │
│                  │            (based on event_type map)      │
│                  │                    │                      │
│                  │                    ▼                      │
│                  │            [MODULE HANDLER]               │
│                  │            (synchronous, bounded time)     │
│                  │                    │                      │
│                  │                    ▼                      │
│                  │            [EMIT NEW EVENTS]             │
│                  │            (push back to queue)            │
│                  │                    │                      │
│                  └────────────────────┘                      │
│                                                             │
│  [OBSERVERS] ──► Logger + Analytics (read-only, no emit)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. OWNERSHIP MATRIX (CRITICAL)

| Contract | Writer | Readers | Immutable? | Update Frequency | MQL5 Type |
|----------|--------|---------|------------|------------------|-----------|
| **MarketState** | Market Engine | All modules | **YES** | Every tick | `struct` |
| **StrategyVote** | Strategy Engine | Risk Engine, Core Engine, Analytics | **YES** | Per strategy evaluation | `struct` |
| **RiskDecision** | Risk Engine | Execution Engine, Core Engine, Analytics | **YES** | Per vote batch | `struct` |
| **OrderRequest** | Execution Engine | MT5 Adapter, Trade Manager, Analytics | **YES** | Per approved decision | `struct` |
| **ExecutionEvent** | MT5 Adapter | Trade Manager, Execution Engine, Analytics | **YES** | Per broker interaction | `struct` |
| **PositionState** | Trade Manager | All modules | **PARTIAL** | Every tick + OnTrade | `struct` |
| **RiskState** | Risk Engine | All modules | **PARTIAL** | Every tick | `struct` |
| **AtlasEvent** | Source Module | Core Engine (queue), Logger, Analytics | **YES** | Per event | `struct` |

### 3.1 Ownership Rules (Non-Negotiable)

**R1: Single Writer Per Contract**
- No contract may have more than one writer. If two modules need to update the same concept, they write to different contracts and Core Engine merges.

**R2: Write-Only Through Guardian**
- Only Core Engine's Context Guardian may commit writes to Atlas Context. Modules submit "write requests" (events), not direct memory writes.

**R3: Read-Only Copies**
- Every module receives a deep copy of the contract at the time of event routing. No module holds a reference to mutable shared state.

**R4: Version Chaining**
- Every contract references `snapshot_id` of the `MarketState` that was current when it was created. This creates a causal chain for debugging.

**R5: No Contract Mutation**
- If a module needs to "modify" a contract (e.g., Risk Engine modifies a strategy's suggested volume), it creates a **new** contract (`RiskDecision`) rather than mutating the original `StrategyVote`.

---

## 4. DATA FLOW RULES

### 4.1 Canonical Pipeline (Per Tick)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DATA FLOW PER TICK CYCLE                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Step 1: MT5 Adapter                                                │
│  ├── Reads raw tick from MT5                                        │
│  ├── Creates MarketState                                            │
│  ├── Emits EV_TICK_RECEIVED + EV_MARKET_STATE_UPDATED               │
│  └── Pushes to Event Queue                                          │
│                                                                     │
│  Step 2: Core Engine (Dequeue)                                      │
│  ├── Routes EV_MARKET_STATE_UPDATED to Market Engine                │
│  ├── Market Engine validates + stores MarketState in Context        │
│  └── (No new events emitted here)                                   │
│                                                                     │
│  Step 3: Core Engine triggers Strategy Phase                          │
│  ├── Sends sanitized MarketState copy to Strategy Engine            │
│  ├── Strategy Engine evaluates each active strategy                 │
│  ├── Each strategy creates StrategyVote                             │
│  ├── Strategy Engine emits EV_STRATEGY_VOTE_SUBMITTED (per vote)  │
│  └── After all votes: emits EV_VOTES_AGGREGATED                     │
│                                                                     │
│  Step 4: Core Engine routes to Risk Engine                            │
│  ├── Risk Engine receives: MarketState + StrategyVote[]             │
│  ├── Risk Engine evaluates against RiskState                        │
│  ├── Risk Engine creates RiskDecision                               │
│  ├── Risk Engine updates RiskState (if needed)                      │
│  ├── Emits EV_RISK_DECISION_RENDERED                                │
│  └── If kill switch triggered: emits EV_KILL_SWITCH_ACTIVATED       │
│                                                                     │
│  Step 5: Core Engine routes to Execution Engine (if APPROVED)       │
│  ├── Execution Engine receives RiskDecision                         │
│  ├── Execution Engine constructs OrderRequest                       │
│  ├── Validates idempotency (checks request_id not used)             │
│  ├── Emits EV_ORDER_REQUESTED                                       │
│  └── Routes to MT5 Adapter                                          │
│                                                                     │
│  Step 6: MT5 Adapter sends to broker                                  │
│  ├── Calls OrderSend()                                              │
│  ├── Receives broker response                                       │
│  ├── Creates ExecutionEvent                                           │
│  ├── Emits EV_ORDER_DISPATCHED + EV_TRADE_EXECUTED (if filled)      │
│  └── Pushes to Event Queue                                          │
│                                                                     │
│  Step 7: Core Engine routes to Trade Manager                          │
│  ├── Trade Manager receives ExecutionEvent                            │
│  ├── Queries broker via PositionSelect()                            │
│  ├── Updates PositionState in Context                               │
│  ├── Emits EV_POSITION_UPDATED                                      │
│  └── Archives if position closed                                    │
│                                                                     │
│  Step 8: Observers                                                    │
│  ├── Logger writes all events to disk (buffered)                    │
│  ├── Analytics updates in-memory metrics                            │
│  └── Persistence Manager writes Context snapshot (if interval met)│
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Cross-Cutting Data Flows

| Flow | Source | Target | Contract | Frequency |
|------|--------|--------|----------|-----------|
| Market data | MT5 Adapter | Market Engine | Raw tick | Every tick |
| Features | Market Engine | Atlas Context | MarketState | Every tick |
| Strategy signals | Strategy Engine | Risk Engine | StrategyVote[] | Per evaluation |
| Risk approval | Risk Engine | Execution Engine | RiskDecision | Per vote batch |
| Order intent | Execution Engine | MT5 Adapter | OrderRequest | Per approval |
| Broker response | MT5 Adapter | Trade Manager | ExecutionEvent | Per OrderSend |
| Position tracking | Trade Manager | Atlas Context | PositionState | Every tick + OnTrade |
| Risk health | Risk Engine | All modules | RiskState | Every tick |
| System events | Core Engine | All modules | AtlasEvent | As needed |
| Persistence | Core Engine | Disk | AtlasContext snapshot | Every 30s |

### 4.3 Forbidden Data Flows (Violations)

| Forbidden Flow | Why | Correct Path |
|----------------|-----|--------------|
| Strategy → Execution | Bypasses risk | Strategy → Risk → Execution |
| Risk → Broker | Risk doesn't know broker API | Risk → Execution → MT5 Adapter |
| Market → Strategy (direct) | Must go through Core Engine | Market → Core → Strategy |
| Trade Manager → Risk State | Only Risk Engine writes risk | Trade Manager emits event → Risk Engine updates |
| AI → OrderRequest | AI is strategy, not execution | AI → StrategyVote → Risk → Execution |
| Logger → Any module | Logger is read-only observer | Logger writes to disk only |

---

## 5. FAILURE CASES

### 5.1 Contract Failure Matrix

| Contract | Failure Mode | System Response | Recovery |
|----------|------------|-----------------|----------|
| **MarketState** | Stale data (>5s old) | Mark `is_valid = false`, skip strategy evaluation | Wait for next tick |
| **MarketState** | Corrupt price (zero/negative) | Mark `is_valid = false`, alert | Filter + next tick |
| **MarketState** | Feature computation error | `feature_count = 0`, continue | Log error, continue with reduced features |
| **StrategyVote** | Invalid confidence (>1.0 or <0.0) | Reject vote, log warning | Discard vote, continue with others |
| **StrategyVote** | Unknown strategy_id | Reject vote, alert operator | Discard, flag strategy registry |
| **StrategyVote** | Snapshot mismatch (old context) | Reject vote | Discard, strategy must re-evaluate |
| **RiskDecision** | Missing mandatory stop_loss | Reject decision, log CRITICAL | Halt execution for this cycle |
| **RiskDecision** | Approved but daily limit already breached | Reject, trigger audit | Risk Engine bug — alert operator |
| **OrderRequest** | Duplicate request_id | Block send, log warning | Idempotency Guard catches it |
| **OrderRequest** | Invalid magic_number | Block send, alert | Config error — halt until fixed |
| **ExecutionEvent** | Broker error but no error_code | Mark as ERROR, retry limit | Retry 3x then alert |
| **ExecutionEvent** | Fill price outside slippage bounds | Log anomaly, alert | Manual review required |
| **PositionState** | Broker mismatch (volume differs) | Set `broker_verified = false` | Trigger reconciliation, halt new trades |
| **PositionState** | Negative volume | Log CRITICAL, halt trading | State corruption — manual review |
| **RiskState** | Kill switch active but trades continue | EMERGENCY: Core Engine halts all | Manual restart required |
| **RiskState** | Drawdown calculation overflow | Set to max double, trigger KS | Restart with fresh state |

### 5.2 Failure Propagation Rules

**F1: Fail-Safe by Default**
- Any contract validation failure in Market/Strategy/Risk phases → skip that phase, continue to next tick.
- Any contract validation failure in Execution/Trade phases → halt new orders for that symbol, alert operator.

**F2: No Cascade**
- A failure in Strategy Engine does not prevent Risk Engine from running (Risk Engine uses last known good state).
- A failure in Execution Engine does not corrupt PositionState (Trade Manager reconciles independently).

**F3: Audit Everything**
- Every failure generates an `EV_ERROR_OCCURRED` event with full context snapshot.
- No failure is silently swallowed.

**F4: Kill Switch Triggers**
The following contract failures **immediately** trigger kill switch:
- `RiskState` shows `daily_drawdown_pct` > configured limit (but `kill_switch_active` was false)
- `PositionState` shows `broker_verified = false` for > 60 seconds
- `ExecutionEvent` shows `error_code` indicating broker disconnection
- `MarketState` shows `is_valid = false` for > 30 seconds (no valid market data)

---

## 6. FINAL CONTRACT LAYER SUMMARY

### Architecture Statement

> **The AtlasEA Contract Layer is the formal grammar of the system. It defines what modules may say to each other, how they may say it, and what happens when communication breaks. Without this layer, AtlasEA is a collection of ideas. With it, AtlasEA is a machine.**

### Core Principles

1. **Determinism:** Given the same sequence of `MarketState` inputs, the system must produce the same sequence of `StrategyVote`, `RiskDecision`, and `OrderRequest` outputs. Every contract is designed to support this guarantee.

2. **Immutability:** Contracts are not modified. They are created, validated, routed, and archived. If a downstream module needs different data, it creates a new contract.

3. **Traceability:** Every contract links to its causal predecessors via `snapshot_id`, `vote_id`, `decision_id`, `request_id`, and `event_id`. A complete audit trail can be reconstructed from any point.

4. **MQL5 Reality:** Contracts use MQL5-native types (`double`, `string`, `datetime`, `enum`, fixed arrays). No dynamic memory, no generics, no polymorphism. Serialization uses MQL5's built-in `JSON` class or binary struct dumps.

5. **Safety Over Convenience:** Strict validation rules may reject valid-but-unusual data. This is intentional. A rejected vote is better than a corrupted position.

### System Boundaries

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONTRACT LAYER BOUNDARIES                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────┐         ┌─────────────┐         ┌─────────────┐   │
│   │   MT5 API   │◄──────►│  MT5 ADAPTER│◄──────►│  ATLAS EVENT│   │
│   │  (External) │         │  (Boundary) │         │   QUEUE     │   │
│   └─────────────┘         └─────────────┘         └──────┬──────┘   │
│                                                          │         │
│   ┌────────────────────────────────────────────────────────┘         │
│   │   CORE ENGINE (Orchestrator)                                    │
│   │   • Validates all contracts                                     │
│   │   • Enforces ownership rules                                    │
│   │   • Routes to modules                                         │
│   └──────┬────────┬────────┬────────┬────────┬────────┬────────┘   │
│          │        │        │        │        │        │             │
│   ┌──────▼──┐ ┌──▼─────┐ ┌▼──────┐ ┌▼──────┐ ┌▼──────┐ ┌▼──────┐ │
│   │ Market  │ │Strategy│ │ Risk  │ │Execute│ │ Trade │ │ Logger│ │
│   │ Engine  │ │ Engine │ │Engine │ │Engine │ │Manager│ │& Analyt│ │
│   └────┬────┘ └───┬────┘ └──┬────┘ └──┬────┘ └──┬────┘ └──┬────┘ │
│        │          │         │         │         │         │       │
│        └──────────┴─────────┴─────────┴─────────┴─────────┘       │
│                              │                                     │
│                              ▼                                     │
│                    ┌─────────────────┐                             │
│                    │  ATLAS CONTEXT  │                             │
│                    │  (Guarded by    │                             │
│                    │   Core Engine)   │                             │
│                    └─────────────────┘                             │
│                                                                     │
│   All contracts flow IN through the event queue.                    │
│   All state updates flow INTO Atlas Context through the Guardian.   │
│   No module touches another module's contract directly.            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Implementation Checklist for AI Agents

| Agent | Contract Responsibility |
|-------|------------------------|
| **Agent A (Core)** | `AtlasEvent` queue, routing table, Context Guardian, event validation |
| **Agent B (Market)** | `MarketState` struct, feature computation, `EV_MARKET_STATE_UPDATED` |
| **Agent C (Strategy)** | `StrategyVote` struct, vote aggregation, `EV_VOTES_AGGREGATED` |
| **Agent D (Risk)** | `RiskDecision` + `RiskState` structs, limit enforcement, kill switch logic |
| **Agent E (Execution)** | `OrderRequest` + `ExecutionEvent` structs, idempotency guard, MT5 order mapping |
| **Agent F (Trade)** | `PositionState` struct, broker reconciliation, lifecycle tracking |
| **Agent G (Infrastructure)** | `AtlasEvent` serialization (JSON), persistence format, replay reader |

### Versioning Strategy

- **Contract Version:** `contract_version = 1` in every struct. Future versions increment this field.
- **Backward Compatibility:** Readers must ignore unknown fields. Writers must populate all known fields.
- **Schema Registry:** Configuration System holds the master schema definition. On startup, Core Engine validates that all modules use matching `CONTRACT_V1` definitions.

---

**End of Contract Layer Specification v1.0**

*This document is the immutable foundation of AtlasEA. All code implementation must conform to these contracts. Any deviation requires a contract revision and full system re-validation.*
