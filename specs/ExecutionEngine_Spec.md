# AtlasEA v1.0 — Execution Engine Production Specification

**Document version:** 1.0
**Target module:** `Engines/ExecutionEngine.mqh` (+ internal helpers under `Engines/ExecutionEngine/`)
**Interface implemented:** `IOrderBuilder` (defined in `Interfaces/IOrderBuilder.mqh`)
**Contracts consumed:** `RiskDecision` (from `Contracts/RiskDecision.mqh`), `MarketState` (from `Contracts/MarketState.mqh`), `OrderRequest` (from `Contracts/RiskDecision.mqh`)
**Constants available:**
- Direction: `ATLAS_ORDER_BUY = 1`, `ATLAS_ORDER_SELL = -1`, `ATLAS_ORDER_NONE = 0`
- Decision status: `ATLAS_DECISION_APPROVED = 1`, `ATLAS_DECISION_REJECTED = 0`, `ATLAS_DECISION_DEFERRED = -1`
- Capacities: `ATLAS_IDEMPOTENCY_SLOTS = 32`
- Module ID: `ATLAS_MODULE_EXECUTION = 5`

---

# 1. Responsibilities

The Execution Engine is the **order construction layer**. It receives an APPROVED `RiskDecision` from the Core Engine and transforms it into a validated `OrderRequest` ready for broker dispatch. It has NO trading authority — it cannot approve, reject, or modify the risk outcome. Its sole purpose is to translate a risk-approved decision into a broker-compliant request, enforcing idempotency so the same decision is never sent twice.

### R1.1 — RiskDecision Validation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Verify the incoming RiskDecision is valid, approved, and internally consistent before any construction work begins. |
| **Owner** | `DecisionValidator` (internal component) |
| **Inputs** | `const RiskDecision &decision` |
| **Outputs** | Boolean: valid or invalid. On invalid, returns a reason string. |
| **Performance limits** | O(1), ≤ 0.01 ms. |
| **Failure handling** | If invalid, abort pipeline. Return `false` from `BuildOrderRequest`. Log WARN with the reason. |
| **Forbidden behaviors** | Must NOT modify the decision. Must NOT reject based on strategy content (that's Risk Engine's job). Must NOT call broker APIs. |

### R1.2 — Volume Normalization

| Attribute | Value |
|-----------|-------|
| **Purpose** | Normalize the approved volume to the broker's lot step, min, and max constraints. |
| **Owner** | `VolumeNormalizer` (internal component) |
| **Inputs** | `decision.approved_volume`, broker's `VolumeMin`, `VolumeMax`, `VolumeStep` (via `IBrokerAdapter`) |
| **Outputs** | Normalized volume (double). |
| **Performance limits** | O(1) |
| **Failure handling** | If volume ≤ 0 after normalization, abort. If volume > max, clamp to max and log WARN. |
| **Forbidden behaviors** | Must NOT increase volume beyond the approved amount (except rounding up to lot step, capped at max). Must NOT decrease below min lot. |

### R1.3 — Price Normalization

| Attribute | Value |
|-----------|-------|
| **Purpose** | Normalize SL, TP, and entry price to the broker's tick size and digit precision. |
| **Owner** | `PriceValidator` (internal component) |
| **Inputs** | `decision.approved_price`, `approved_sl`, `approved_tp`, `MarketState.bid`, `MarketState.ask`, broker's `SymbolPoint`, `SymbolDigits`, `SymbolStopsLevel` (via `IBrokerAdapter`) |
| **Outputs** | Normalized entry, SL, TP (each a double). |
| **Performance limits** | O(1) |
| **Failure handling** | If any price ≤ 0, abort. If SL/TP violates stops-level distance, adjust to minimum distance and log WARN. |
| **Forbidden behaviors** | Must NOT modify the MarketState. Must NOT set prices that would increase risk beyond the decision (e.g., must NOT widen SL away from entry). |

### R1.4 — Broker Constraints Enforcement

| Attribute | Value |
|-----------|-------|
| **Purpose** | Ensure the final OrderRequest complies with all broker constraints (stops level, filling mode, volume limits). |
| **Owner** | `OrderConstraints` (internal component) |
| **Inputs** | Normalized volume, entry, SL, TP, broker symbol properties |
| **Outputs** | Boolean: compliant or not. |
| **Performance limits** | O(1) |
| **Failure handling** | If non-compliant and cannot be auto-corrected, abort. Log WARN. |
| **Forbidden behaviors** | Must NOT call broker order APIs. Only query symbol properties. |

### R1.5 — Idempotency Enforcement

| Attribute | Value |
|-----------|-------|
| **Purpose** | Prevent the same RiskDecision from being processed twice (e.g., after a restart or retry). |
| **Owner** | `IdempotencyGuard` (internal component) |
| **Inputs** | `decision.decision_id` |
| **Outputs** | Boolean: first-seen or duplicate. |
| **Performance limits** | O(N) where N ≤ `ATLAS_IDEMPOTENCY_SLOTS` (32). ≤ 0.005 ms. |
| **Failure handling** | If duplicate, abort. Return `false`. Log WARN. |
| **Forbidden behaviors** | Must NOT remove entries from the cache except via FIFO eviction. Must NOT persist across restarts in this phase (context recovery handles that). |

### R1.6 — Request ID Generation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Generate a unique `request_id` for each OrderRequest. |
| **Owner** | `ExecutionEngine` (direct) |
| **Inputs** | Current timestamp, monotonic counter |
| **Outputs** | String: "REQ_{timestamp}_{counter}". |
| **Performance limits** | O(1) |
| **Failure handling** | None — always succeeds. |
| **Forbidden behaviors** | Must NOT use `MathRand()` (non-deterministic). Must use a monotonic counter. |

### R1.7 — Broker Comment Construction

| Attribute | Value |
|-----------|-------|
| **Purpose** | Build a broker-compliant comment string for traceability. |
| **Owner** | `CommentBuilder` (internal component) |
| **Inputs** | `request_id`, `decision_id` |
| **Outputs** | String, max 31 characters (MT5 broker limit). |
| **Performance limits** | O(1) |
| **Failure handling** | If the comment exceeds 31 chars, truncate. |
| **Forbidden behaviors** | Must NOT include prohibited characters. Must NOT exceed 31 chars. |

### R1.8 — OrderRequest Construction

| Attribute | Value |
|-----------|-------|
| **Purpose** | Assemble the final `OrderRequest` struct from all normalized and validated components. |
| **Owner** | `OrderBuilder` (internal component) |
| **Inputs** | Validated decision, normalized volume, normalized prices, generated request_id, broker comment |
| **Outputs** | Fully populated `OrderRequest`. |
| **Performance limits** | O(1) |
| **Failure handling** | None — all inputs are pre-validated. |
| **Forbidden behaviors** | Must NOT leave any field unset. Must NOT default fields to invalid values. |

### R1.9 — OrderRequest Validation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Final validation of the constructed OrderRequest before returning to CoreEngine. |
| **Owner** | `RequestValidator` (internal component) |
| **Inputs** | Constructed `OrderRequest` |
| **Outputs** | Boolean: valid or invalid. |
| **Performance limits** | O(1) |
| **Failure handling** | If invalid (should never happen after all upstream checks), abort. Log ERROR. |
| **Forbidden behaviors** | Must NOT modify the request (return false, let caller handle). |

### R1.10 — Statistics Collection

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track build counts, validation failures, duplicates, latency. |
| **Owner** | `ExecutionStatistics` (internal component) |
| **Inputs** | Per-call: success/failure, reason, latency |
| **Outputs** | Counters accessible via accessors |
| **Performance limits** | O(1) per update |

---

# 2. Internal Components

The Execution Engine is decomposed into 9 internal components. All are stack-allocated. All live under `Engines/ExecutionEngine/`.

### 2.1 — DecisionValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Validate the incoming RiskDecision. |
| **Owned data** | None. |
| **Public interface** | `bool Validate(const RiskDecision &dec, string &out_reason) const` |
| **Private helpers** | `bool IsApproved(const RiskDecision &dec) const`, `bool HasValidDirection(const RiskDecision &dec) const`, `bool HasValidPrices(const RiskDecision &dec) const`, `bool HasValidVolume(const RiskDecision &dec) const`, `bool HasValidIds(const RiskDecision &dec) const` |
| **Dependencies** | `RiskDecision`, `ATLAS_DECISION_*`, `ATLAS_ORDER_*` |
| **Performance limits** | O(1), ≤ 0.01 ms |
| **Failure modes** | Returns false with reason on any invalid field. |

### 2.2 — VolumeNormalizer

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Round volume to broker step, clamp to [min, max]. |
| **Owned data** | None. |
| **Public interface** | `double Normalize(const double raw_volume, IBrokerAdapter *broker, ILogger *logger) const` |
| **Private helpers** | `double RoundToStep(const double v, const double step) const`, `double Clamp(const double v, const double lo, const double hi) const` |
| **Dependencies** | `IBrokerAdapter`, `ILogger` |
| **Performance limits** | O(1) |
| **Failure modes** | If broker NULL → return raw_volume. If step ≤ 0 → return raw_volume. |

### 2.3 — PriceValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Normalize prices to tick size/digits. Enforce stops-level distance for SL/TP. |
| **Owned data** | None. |
| **Public interface** | `bool ValidateAndNormalize(const RiskDecision &dec, const MarketState &state, IBrokerAdapter *broker, ILogger *logger, double &out_entry, double &out_sl, double &out_tp) const` |
| **Private helpers** | `double RoundToTick(const double price, const double point, const int digits) const`, `double GetMinStopDistance(IBrokerAdapter *broker) const`, `double EnforceStopLoss(const double sl, const int direction, const double entry, const double min_dist, const int digits) const`, `double EnforceTakeProfit(const double tp, const int direction, const double entry, const double min_dist, const int digits) const` |
| **Dependencies** | `IBrokerAdapter`, `ILogger`, `MarketState` |
| **Performance limits** | O(1) |
| **Failure modes** | If any price ≤ 0 → return false. If broker NULL → return false. |

### 2.4 — OrderConstraints

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Final broker constraint check (volume range, stops distance, filling mode compatibility). |
| **Owned data** | None. |
| **Public interface** | `bool Check(const double volume, const double entry, const double sl, const double tp, const int direction, IBrokerAdapter *broker, ILogger *logger, string &out_reason) const` |
| **Private helpers** | `bool CheckVolumeRange(const double v, IBrokerAdapter *broker) const`, `bool CheckStopsDistance(const double entry, const double sl, const double tp, const int direction, IBrokerAdapter *broker) const` |
| **Dependencies** | `IBrokerAdapter`, `ILogger` |
| **Performance limits** | O(1) |
| **Failure modes** | Returns false with reason on any violation. |

### 2.5 — IdempotencyGuard

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track processed decision_ids. Reject duplicates. FIFO eviction when full. |
| **Owned data** | `string m_processed[ATLAS_IDEMPOTENCY_SLOTS]` (32 entries), `int m_count` |
| **Public interface** | `bool IsFirstSeen(const string decision_id)`, `void MarkProcessed(const string decision_id)`, `void Reset()`, `int Count() const` |
| **Private helpers** | `int FindIndex(const string decision_id) const`, `void EvictOldest()` |
| **Dependencies** | `ATLAS_IDEMPOTENCY_SLOTS` |
| **Performance limits** | O(N), N ≤ 32. ≤ 0.005 ms. |
| **Failure modes** | None — always returns a valid boolean. |

### 2.6 — CommentBuilder

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Build a broker comment ≤ 31 characters. |
| **Owned data** | None. |
| **Public interface** | `string Build(const string request_id, const string decision_id) const` |
| **Private helpers** | `string Truncate(const string s, const int max_len) const` |
| **Dependencies** | None. |
| **Performance limits** | O(1) |
| **Failure modes** | None — always returns a valid string. |

### 2.7 — OrderBuilder

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Assemble the final OrderRequest from all components. |
| **Owned data** | None. |
| **Public interface** | `OrderRequest Build(const RiskDecision &dec, const MarketState &state, const AtlasConfig &config, const string request_id, const string comment, const double volume, const double entry, const double sl, const double tp) const` |
| **Private helpers** | `int DirectionToOrderType(const int direction) const` |
| **Dependencies** | `RiskDecision`, `MarketState`, `AtlasConfig`, `OrderRequest` |
| **Performance limits** | O(1) |
| **Failure modes** | None — all inputs pre-validated. |

### 2.8 — RequestValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Final sanity check on the constructed OrderRequest. |
| **Owned data** | None. |
| **Public interface** | `bool Validate(const OrderRequest &req, string &out_reason) const` |
| **Private helpers** | `bool HasValidStrings(const OrderRequest &req) const`, `bool HasValidNumbers(const OrderRequest &req) const`, `bool HasValidLinkage(const OrderRequest &req) const` |
| **Dependencies** | `OrderRequest` |
| **Performance limits** | O(1) |
| **Failure modes** | Returns false with reason on any invalid field. |

### 2.9 — ExecutionStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track build counts, failures, duplicates, latency. |
| **Owned data** | `ulong m_total_built`, `m_validation_failures`, `m_duplicates`, `m_rejected`, `m_invalid_prices`, `m_invalid_volumes`, `double m_total_latency_ms`, `m_peak_latency_ms` |
| **Public interface** | `void RecordBuild(const bool success, const double latency_ms)`, `void RecordDuplicate()`, `void RecordValidationFailure(const string reason)`, `void RecordInvalidPrice()`, `void RecordInvalidVolume()`, `void Reset()`, `void LogSummary(ILogger *logger) const`, accessors for all counters |
| **Private helpers** | None. |
| **Dependencies** | `ILogger` |
| **Performance limits** | O(1) |

---

# 3. Execution Pipeline

The `BuildOrderRequest` method executes the following pipeline. Every stage is fail-fast.

### Stage 1 — Receive RiskDecision

- Input: `const RiskDecision &decision`, `const MarketState &state`, `OrderRequest &req` (output).
- The decision is treated as immutable.

### Stage 2 — Validate Decision

- Call `DecisionValidator.Validate(decision, reason)`.
- Checks: `status == APPROVED`, `order_type in {BUY, SELL}`, `approved_volume > 0`, `approved_price > 0`, `approved_sl > 0`, `approved_tp > 0`, `decision_id` non-empty, `snapshot_id > 0`.
- On failure: return `false`. Log WARN with reason. Increment `m_validation_failures`.

### Stage 3 — Read MarketState

- Validate `state.is_valid`, `state.snapshot_id == decision.snapshot_id`.
- On mismatch: return `false`. Log WARN. (Stale state — the decision was made against an old snapshot.)

### Stage 4 — Read Config

- The Execution Engine receives `AtlasConfig` during `SetDependencies()`. It reads `magic_number`, `symbol`, `volume_digits`, `slippage_points`.
- No validation needed — config is trusted.

### Stage 5 — Check Idempotency

- Call `IdempotencyGuard.IsFirstSeen(decision.decision_id)`.
- If duplicate: return `false`. Log WARN. Increment `m_duplicates`.
- If first-seen: do NOT mark yet (mark only after successful build).

### Stage 6 — Normalize Volume

- Call `VolumeNormalizer.Normalize(decision.approved_volume, broker, logger)`.
- Round to `VolumeStep`, clamp to `[VolumeMin, VolumeMax]`.
- If result ≤ 0: return `false`. Log ERROR. Increment `m_invalid_volumes`.

### Stage 7 — Normalize Prices

- Call `PriceValidator.ValidateAndNormalize(decision, state, broker, logger, entry, sl, tp)`.
- Entry: for BUY use current `SymbolAsk`, for SELL use current `SymbolBid` (market orders use broker price, not the decision's approved_price which was an estimate).
- SL: round to tick, enforce `StopsLevel` distance from entry (on the correct side).
- TP: round to tick, enforce `StopsLevel` distance from entry (on the correct side).
- If any price ≤ 0: return `false`. Log ERROR. Increment `m_invalid_prices`.

### Stage 8 — Validate Broker Constraints

- Call `OrderConstraints.Check(volume, entry, sl, tp, direction, broker, logger, reason)`.
- Checks: volume in `[min, max]`, SL/TP respect stops level, direction is valid.
- On failure: return `false`. Log WARN.

### Stage 9 — Generate request_id

- Generate: `"REQ_{TimeCurrent()}_{m_request_counter}"`.
- Increment `m_request_counter` (monotonic, never resets within a session).

### Stage 10 — Build Broker Comment

- Call `CommentBuilder.Build(request_id, decision_id)`.
- Format: `"ATLAS_{request_id_short}"`, truncated to 31 chars.

### Stage 11 — Build OrderRequest

- Call `OrderBuilder.Build(...)`.
- Populate ALL fields:
  - `request_id` = generated
  - `decision_id` = from decision
  - `symbol` = from config
  - `order_type` = `ORDER_TYPE_BUY` or `ORDER_TYPE_SELL` (as int)
  - `direction` = from decision
  - `volume` = normalized
  - `entry_price` = normalized
  - `stop_loss` = normalized
  - `take_profit` = normalized
  - `magic_number` = from config
  - `snapshot_id` = from decision
  - `comment` = built

### Stage 12 — Validate OrderRequest

- Call `RequestValidator.Validate(req, reason)`.
- Checks: all strings non-empty, all numbers valid, linkage intact (`req.decision_id == decision.decision_id`, `req.snapshot_id == decision.snapshot_id`).
- On failure (should never happen): return `false`. Log ERROR.

### Stage 13 — Mark Idempotency

- Call `IdempotencyGuard.MarkProcessed(decision.decision_id)`.
- This happens LAST — only after a successful build.

### Stage 14 — Update Statistics

- `ExecutionStatistics.RecordBuild(true, latency_ms)`.

### Stage 15 — Return OrderRequest

- The output `req` is fully populated.
- Return `true`.

---

# 4. OrderRequest Specification

The `OrderRequest` struct is defined in `Contracts/RiskDecision.mqh`.

### Field: `request_id`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Unique identifier for this order request. Used for broker tracking and idempotency. |
| **Type** | `string` |
| **Allowed values** | Non-empty, max 32 characters. Format: "REQ_{timestamp}_{counter}". |
| **Default** | "" (must be set by engine). |
| **Validation** | Must be non-empty. Must be unique per request. |
| **Ownership** | Set by ExecutionEngine. |
| **Immutability** | Immutable after construction. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | Not persisted (request_id is per-session). |

### Field: `decision_id`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Correlation back to the RiskDecision that approved this order. |
| **Type** | `string` |
| **Allowed values** | Non-empty. Copied from `RiskDecision.decision_id`. |
| **Default** | "" (must be copied). |
| **Validation** | Must be non-empty. Must match the source decision. |
| **Ownership** | Copied from RiskDecision. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | Used for idempotency dedup after restart (via context snapshot). |

### Field: `symbol`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Trading symbol (e.g., "EURUSD"). |
| **Type** | `string` |
| **Allowed values** | Non-empty. Must match `AtlasConfig.symbol`. |
| **Default** | "" (must be set from config). |
| **Validation** | Must be non-empty. |
| **Ownership** | Set from config. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | N/A. |

### Field: `order_type`

| Attribute | Value |
|-----------|-------|
| **Meaning** | MT5 order type as integer (for `MqlTradeRequest.type`). |
| **Type** | `int` |
| **Allowed values** | `ORDER_TYPE_BUY (0)` or `ORDER_TYPE_SELL (1)` (MQL5 enum values). |
| **Default** | 0 (BUY). |
| **Validation** | Must be 0 or 1. Must be consistent with `direction`. |
| **Ownership** | Set by OrderBuilder from direction. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Recovery** | N/A. |

### Field: `direction`

| Attribute | Value |
|-----------|-------|
| **Meaning** | AtlasEA direction code. |
| **Type** | `int` |
| **Allowed values** | `ATLAS_ORDER_BUY (1)` or `ATLAS_ORDER_SELL (-1)`. |
| **Default** | 0 (invalid — must be set). |
| **Validation** | Must be 1 or -1. Must match `order_type` (BUY→0, SELL→1). |
| **Ownership** | Copied from RiskDecision. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Recovery** | N/A. |

### Field: `volume`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Trade volume in lots. |
| **Type** | `double` |
| **Allowed values** | > 0.0. Must be in `[VolumeMin, VolumeMax]`. Must be a multiple of `VolumeStep`. |
| **Default** | 0.0 (invalid — must be set). |
| **Validation** | Must be > 0. Not NaN. In broker range. Aligned to step. |
| **Ownership** | Set by VolumeNormalizer. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `entry_price`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Entry price for the order. For market orders, this is the current broker price (ask for BUY, bid for SELL). |
| **Type** | `double` |
| **Allowed values** | > 0.0. Rounded to tick size. |
| **Default** | 0.0 (invalid — must be set). |
| **Validation** | Must be > 0. Not NaN. Rounded to `SymbolPoint`. |
| **Ownership** | Set by PriceValidator (from broker bid/ask). |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `stop_loss`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Stop-loss price. |
| **Type** | `double` |
| **Allowed values** | > 0.0. For BUY: < entry - stops_level. For SELL: > entry + stops_level. |
| **Default** | 0.0 (invalid — must be set). |
| **Validation** | Must be > 0. Not NaN. Respects stops-level distance. On correct side of entry. |
| **Ownership** | Set by PriceValidator. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `take_profit`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Take-profit price. |
| **Type** | `double` |
| **Allowed values** | > 0.0. For BUY: > entry + stops_level. For SELL: < entry - stops_level. |
| **Default** | 0.0 (invalid — must be set). |
| **Validation** | Must be > 0. Not NaN. Respects stops-level distance. On correct side of entry. |
| **Ownership** | Set by PriceValidator. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `magic_number`

| Attribute | Value |
|-----------|-------|
| **Meaning** | EA magic number for broker position tagging. |
| **Type** | `long` |
| **Allowed values** | > 0. Must match `AtlasConfig.magic_number`. |
| **Default** | 0 (invalid — must be set). |
| **Validation** | Must be > 0. Must match config. |
| **Ownership** | Set from config. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `snapshot_id`

| Attribute | Value |
|-----------|-------|
| **Meaning** | MarketState snapshot this order was built against. |
| **Type** | `long` |
| **Allowed values** | > 0. Must match `RiskDecision.snapshot_id` and `MarketState.snapshot_id`. |
| **Default** | 0 (invalid — must be set). |
| **Validation** | Must be > 0. Must match decision. |
| **Ownership** | Copied from RiskDecision. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | N/A. |

### Field: `comment`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Broker comment for traceability. |
| **Type** | `string` |
| **Allowed values** | Non-empty. Max 31 characters. No prohibited characters. |
| **Default** | "" (must be set). |
| **Validation** | Must be non-empty. Must be ≤ 31 chars. |
| **Ownership** | Set by CommentBuilder. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | N/A. |

---

# 5. Validation Rules

### 5.1 — Volume Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| V1 | `approved_volume > 0` | ERROR | Abort if ≤ 0 |
| V2 | `approved_volume` not NaN | ERROR | Abort if NaN |
| V3 | Volume ≤ `VolumeMax` | WARN | Clamp to max if exceeded |
| V4 | Volume ≥ `VolumeMin` | WARN | Raise to min if below |
| V5 | Volume aligned to `VolumeStep` | None | Round to nearest step |

### 5.2 — Price Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| P1 | All prices > 0 | ERROR | Abort if ≤ 0 |
| P2 | All prices not NaN | ERROR | Abort if NaN |
| P3 | SL on correct side of entry | ERROR | Abort if wrong side |
| P4 | TP on correct side of entry | ERROR | Abort if wrong side |
| P5 | SL respects stops-level | WARN | Adjust to min distance |
| P6 | TP respects stops-level | WARN | Adjust to min distance |
| P7 | Prices rounded to tick | None | Round via NormalizeDouble |

### 5.3 — Direction Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| D1 | `direction in {BUY, SELL}` | ERROR | Abort if NONE or other |
| D2 | `order_type` consistent with `direction` | ERROR | Abort if mismatch |

### 5.4 — Order Type Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| O1 | `order_type in {ORDER_TYPE_BUY, ORDER_TYPE_SELL}` | ERROR | Abort if other |
| O2 | Only market orders in this phase | None | No limit/stop orders |

### 5.5 — SL / TP Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| S1 | SL > 0 | ERROR | Abort if ≤ 0 |
| S2 | TP > 0 | ERROR | Abort if ≤ 0 |
| S3 | SL ≠ TP | WARN | Log if equal (unusual) |
| S4 | SL/TP distance ≥ stops_level | WARN | Adjust to minimum |

### 5.6 — Magic Number Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| M1 | `magic_number > 0` | ERROR | Abort if ≤ 0 |
| M2 | `magic_number == config.magic_number` | ERROR | Abort if mismatch |

### 5.7 — Comment Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| C1 | Comment non-empty | ERROR | Abort if empty |
| C2 | Comment ≤ 31 chars | None | Truncate if longer |
| C3 | No prohibited characters | None | Filter out |

### 5.8 — Snapshot Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| SN1 | `snapshot_id > 0` | ERROR | Abort if ≤ 0 |
| SN2 | `decision.snapshot_id == state.snapshot_id` | ERROR | Abort if mismatch (stale state) |

### 5.9 — Decision Linkage Validation

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| DL1 | `decision_id` non-empty | ERROR | Abort if empty |
| DL2 | `req.decision_id == decision.decision_id` | ERROR | Abort if mismatch |
| DL3 | Decision not previously processed (idempotency) | WARN | Abort if duplicate |

### 5.10 — Strategy Linkage

| Rule | Check | Severity | Action |
|------|-------|----------|--------|
| SL1 | Strategy linkage is via the decision (not direct) | None | Execution Engine does NOT access strategy info |

---

# 6. Price Handling

### 6.1 — Market Orders

- **Entry price:** For BUY orders, use `IBrokerAdapter::SymbolAsk()`. For SELL orders, use `IBrokerAdapter::SymbolBid()`. The `decision.approved_price` is an estimate from the vote and is NOT used as the actual entry — the current broker price is always used.
- **Rationale:** The decision was made against a snapshot that may be milliseconds old. Using the live broker price ensures the order is executable.

### 6.2 — Limit Orders

- Not supported in this phase. All orders are market orders (`ORDER_TYPE_BUY` / `ORDER_TYPE_SELL`).

### 6.3 — Stop Orders

- Not supported in this phase.

### 6.4 — StopLimit Orders

- Not supported in this phase.

### 6.5 — Price Normalization

- All prices are rounded to the broker's tick size using `NormalizeDouble(price, digits)`.
- The `digits` value comes from `IBrokerAdapter::SymbolDigits()`.
- The `point` value comes from `IBrokerAdapter::SymbolPoint()`.

### 6.6 — Tick Size

- Tick size = `SymbolPoint`. All prices must be multiples of this.
- Rounding: `NormalizeDouble(price, digits)` handles this.

### 6.7 — Digits

- From `IBrokerAdapter::SymbolDigits()`. Typically 5 for FX (e.g., EURUSD = 1.08542).

### 6.8 — Broker Precision

- All output prices use `NormalizeDouble(price, digits)` to match broker precision.
- No floating-point drift is allowed.

### 6.9 — Price Drift

- The `decision.approved_price` may differ from the live broker price (drift). This is expected.
- The Execution Engine uses the LIVE broker price, not the decision price.
- If the drift is extreme (e.g., > 1% of price), log WARN (but still proceed — the Risk Engine already approved).

### 6.10 — Tolerance

- No explicit tolerance for price drift — the live broker price is always used.
- For SL/TP, a tolerance of `2 * point` is added to the stops-level distance to avoid borderline rejections.

---

# 7. Volume Handling

### 7.1 — Minimum Lot

- From `IBrokerAdapter::SymbolVolumeMin()`. Typically 0.01.
- If normalized volume < min: raise to min. Log WARN.

### 7.2 — Maximum Lot

- From `IBrokerAdapter::SymbolVolumeMax()`. Typically 100.0 or higher.
- If normalized volume > max: clamp to max. Log WARN.

### 7.3 — Lot Step

- From `IBrokerAdapter::SymbolVolumeStep()`. Typically 0.01.
- Volume is rounded to the nearest multiple of step: `MathRound(volume / step) * step`.

### 7.4 — Normalization

```
rounded = MathRound(raw_volume / step) * step
clamped = Clamp(rounded, min, max)
result  = NormalizeDouble(clamped, volume_digits)
```

### 7.5 — Broker Limits

- Respected via the clamp in 7.4.

### 7.6 — Risk Limits Interaction

- The Execution Engine does NOT re-check risk limits. The `approved_volume` from the RiskDecision is the risk-approved amount. The Execution Engine only normalizes it to broker constraints (which may round up or down slightly, but never beyond broker limits).

### 7.7 — Invalid Volume Handling

| Condition | Action |
|-----------|--------|
| `approved_volume ≤ 0` | Abort. Log ERROR. Increment `m_invalid_volumes`. |
| `approved_volume` is NaN | Abort. Log ERROR. Increment `m_invalid_volumes`. |
| `approved_volume` is infinite | Abort. Log ERROR. Increment `m_invalid_volumes`. |
| Normalized volume > max | Clamp to max. Log WARN. |
| Normalized volume < min | Raise to min. Log WARN. |
| `VolumeStep ≤ 0` | Use raw volume (defensive). Log ERROR. |

---

# 8. Idempotency

### 8.1 — Unique Request Generation

- Each `BuildOrderRequest` call generates a unique `request_id` = `"REQ_{TimeCurrent()}_{counter}"`.
- The counter is monotonic (`m_request_counter++` per call) and never resets within a session.

### 8.2 — Decision Linkage

- The `decision_id` is the idempotency key. Each decision should produce at most one OrderRequest.
- The `IdempotencyGuard` tracks `decision_id` values.

### 8.3 — Replay Protection

- If `BuildOrderRequest` is called twice with the same `decision_id`:
  - First call: processes normally, marks the decision_id as processed.
  - Second call: `IdempotencyGuard.IsFirstSeen()` returns false. The call aborts. Log WARN. Increment `m_duplicates`.

### 8.4 — Recovery After Restart

- The `IdempotencyGuard` cache is in-memory only (32-slot ring).
- After an EA restart, the cache is empty. To prevent replaying a decision that was already sent before the restart:
  - The `AtlasContext` persists `processed_decisions[]` in snapshots.
  - On recovery, `IContextStore::IsDecisionProcessed()` is checked as a secondary idempotency layer.
  - The Execution Engine calls `IContextStore::MarkDecisionProcessed()` after a successful build (in addition to the local guard).
  - On startup, the guard is empty but the context has recovered state. The guard catches intra-session duplicates; the context catches cross-session duplicates.

### 8.5 — Persistence

- The local `IdempotencyGuard` cache is NOT persisted (in-memory ring).
- The `IContextStore::MarkDecisionProcessed()` IS persisted (via context snapshots).
- Cross-session idempotency relies on the context, not the guard.

### 8.6 — Expiration

- The local guard uses FIFO eviction: when the 32-slot ring is full, the oldest entry is evicted.
- The context's `processed_decisions[]` also uses FIFO eviction (32 slots).
- There is no time-based expiration. A decision_id remains "processed" until evicted by newer entries.

### 8.7 — Cache Size

- `ATLAS_IDEMPOTENCY_SLOTS = 32` (compile-time constant).
- Both the local guard and the context use this capacity.

### 8.8 — Cleanup

- No active cleanup. FIFO eviction is the only cleanup mechanism.
- `IdempotencyGuard.Reset()` clears the cache (called on shutdown).

---

# 9. Broker Comment

### 9.1 — Maximum Length

- 31 characters (MT5 broker limit for order comments).

### 9.2 — Allowed Characters

- Alphanumeric (A-Z, a-z, 0-9).
- Underscore (`_`).
- Hyphen (`-`).
- No spaces, no special characters, no Unicode.

### 9.3 — Encoding

- ASCII (MQL5 strings are Unicode internally, but broker comments are ASCII).

### 9.4 — Traceability

- The comment must allow tracing back to the decision and request.
- Format: `ATLAS_{request_id_short}` where `request_id_short` is the last ~24 chars of the request_id.

### 9.5 — Decision ID

- The full `decision_id` is NOT included in the comment (too long). It is traced via the `OrderRequest.decision_id` field.

### 9.6 — Strategy ID

- Not included in the comment (the Execution Engine does not know which strategy produced the vote — that information is in the AggregatedVote, which is not passed to the Execution Engine).

### 9.7 — Snapshot ID

- Not included in the comment (traced via `OrderRequest.snapshot_id`).

### 9.8 — Compression Rules

- If the comment exceeds 31 chars: truncate from the right, keeping the "ATLAS_" prefix.
- Example: `"ATLAS_REQ_1750000000_42"` (23 chars) — fits.
- Example: `"ATLAS_REQ_1750000000_999999"` (28 chars) — fits.
- If counter exceeds 7 digits: truncate to `"ATLAS_REQ_{counter}"` (drop timestamp).

---

# 10. Performance Budget

### 10.1 — Maximum Execution Time

| Stage | Budget |
|-------|--------|
| Decision validation | 0.01 ms |
| MarketState check | 0.005 ms |
| Idempotency check | 0.005 ms |
| Volume normalization | 0.01 ms |
| Price normalization | 0.01 ms |
| Broker constraints | 0.01 ms |
| Request ID generation | 0.001 ms |
| Comment building | 0.001 ms |
| OrderRequest construction | 0.005 ms |
| Request validation | 0.005 ms |
| Statistics update | 0.001 ms |
| **Total** | **≤ 0.1 ms** |

### 10.2 — Memory Limits

- Total memory: stack-allocated only. No heap allocation.
- `IdempotencyGuard`: 32 strings (~64 bytes each) = ~2 KB.
- `ExecutionStatistics`: ~128 bytes.
- Local variables: ~64 bytes.
- Total: ~2.2 KB stack.

### 10.3 — Maximum Cache Size

- `IdempotencyGuard`: 32 entries (fixed, compile-time).
- No other caches.

### 10.4 — Maximum Requests

- No limit on total requests per session (the idempotency ring evicts old entries).

### 10.5 — Fixed Arrays Only

- All arrays are fixed-size. No `ArrayResize()` in the hot path.

### 10.6 — No Dynamic Allocation

- `new` and `delete` are FORBIDDEN inside `BuildOrderRequest`.
- String operations (concatenation for request_id, comment) are unavoidable but minimal.

---

# 11. Metrics

The `ExecutionStatistics` component collects:

| Metric | Type | Description |
|--------|------|-------------|
| `total_built` | `ulong` | Total successful `BuildOrderRequest` calls. |
| `validation_failures` | `ulong` | Total calls that failed validation. |
| `duplicates` | `ulong` | Total calls rejected as duplicates. |
| `rejected` | `ulong` | Total calls that returned false (any reason). |
| `invalid_prices` | `ulong` | Calls that failed due to invalid prices. |
| `invalid_volumes` | `ulong` | Calls that failed due to invalid volumes. |
| `total_latency_ms` | `double` | Sum of all build latencies. |
| `peak_latency_ms` | `double` | Maximum single-build latency. |
| `average_latency_ms` | `double` | `total_latency_ms / total_built`. |
| `build_success_rate` | `double` | `total_built / (total_built + rejected)`. |

---

# 12. Logging

All logging through `ILogger`. `Print()` is FORBIDDEN.

### 12.1 — Log Categories

| Level | Category | When |
|-------|----------|------|
| **DEBUG** | Build success | "OrderRequest built: req={id} vol={v} dir={d}" |
| **DEBUG** | Volume normalized | "Volume: {raw} → {normalized}" |
| **DEBUG** | Price normalized | "SL: {raw} → {normalized}" |
| **INFO** | Initialization | "ExecutionEngine initialized" |
| **INFO** | Shutdown | "ExecutionEngine shutdown" |
| **INFO** | Diagnostics summary | On `LogDiagnostics()` (heartbeat only) |
| **WARN** | Duplicate decision | "Duplicate decision_id: {id}" |
| **WARN** | Volume clamped | "Volume clamped: {raw} → {clamped} (broker limit)" |
| **WARN** | SL adjusted | "SL adjusted for stops-level: {old} → {new}" |
| **WARN** | TP adjusted | "TP adjusted for stops-level: {old} → {new}" |
| **WARN** | Price drift | "Price drift: decision={d} live={l} drift={pct}%" |
| **ERROR** | Decision not approved | "Decision status is not APPROVED: {status}" |
| **ERROR** | Invalid direction | "Invalid direction: {d}" |
| **ERROR** | Invalid volume | "Invalid volume: {v}" |
| **ERROR** | Invalid price | "Invalid price: entry={e} sl={s} tp={t}" |
| **ERROR** | Snapshot mismatch | "Snapshot mismatch: decision={d} state={s}" |
| **ERROR** | Broker NULL | "IBrokerAdapter is NULL" |
| **ERROR** | Request validation failed | "OrderRequest invalid: {reason}" |
| **CRITICAL** | Not used | N/A (no critical conditions in Execution Engine) |

### 12.2 — Hot Path Logging Policy

**No INFO/WARN/ERROR logging on the success path.** Only DEBUG is allowed (and only if `config.log_level <= ATLAS_LOG_DEBUG`).

Failures log at WARN (duplicate, clamp, adjustment) or ERROR (invalid input, NULL dependency).

---

# 13. Edge Cases

| # | Edge Case | Engine Behavior |
|---|-----------|-----------------|
| EC1 | Rejected decision (`status != APPROVED`) | Abort. Log ERROR. Return false. |
| EC2 | Deferred decision (`status == DEFERRED`) | Abort. Log ERROR. Return false. |
| EC3 | Missing SL (`approved_sl == 0`) | Abort. Log ERROR. Return false. |
| EC4 | Missing TP (`approved_tp == 0`) | Abort. Log ERROR. Return false. |
| EC5 | Unknown direction (`order_type == 0`) | Abort. Log ERROR. Return false. |
| EC6 | Negative volume | Abort. Log ERROR. Return false. |
| EC7 | NaN volume | Abort. Log ERROR. Return false. |
| EC8 | NaN price (any) | Abort. Log ERROR. Return false. |
| EC9 | Invalid price (≤ 0) | Abort. Log ERROR. Return false. |
| EC10 | Snapshot mismatch | Abort. Log WARN. Return false. |
| EC11 | Duplicate request (same decision_id) | Abort. Log WARN. Return false. |
| EC12 | Configuration corruption (magic = 0) | Abort. Log ERROR. Return false. |
| EC13 | Invalid broker precision (digits = 0) | Use default digits (5). Log WARN. Continue. |
| EC14 | Volume overflow (> 1e9) | Clamp to max. Log WARN. |
| EC15 | Volume underflow (0 < v < min) | Raise to min. Log WARN. |
| EC16 | Price overflow (> 1e6) | Abort. Log ERROR. (Unlikely for FX.) |
| EC17 | Price underflow (0 < p < point) | Abort. Log ERROR. |
| EC18 | Recovery after restart (cache empty) | Context provides cross-session idempotency. Proceed normally. |
| EC19 | Broker adapter NULL | Abort. Log ERROR. Return false. |
| EC20 | Logger NULL | Proceed with best-effort. No logging. |
| EC21 | MarketState invalid | Abort. Log WARN. Return false. |
| EC22 | Comment exceeds 31 chars | Truncate. Continue. |
| EC23 | SL == TP | Log WARN. Continue (unusual but valid). |
| EC24 | SL on wrong side of entry | Abort. Log ERROR. Return false. |
| EC25 | TP on wrong side of entry | Abort. Log ERROR. Return false. |
| EC26 | Stops level = 0 (no minimum) | Use 0 distance. Continue. |
| EC27 | Volume step = 0 | Use raw volume. Log ERROR. Continue. |
| EC28 | Volume min = 0 | Treat as 0.01. Log WARN. |
| EC29 | Volume max = 0 | Treat as infinity (no clamp). Log WARN. |
| EC30 | Decision ID empty | Abort. Log ERROR. Return false. |

---

# 14. Validation Matrix

| Field | Validation | Severity | Recovery | Action |
|-------|------------|----------|----------|--------|
| `decision.status` | Must be APPROVED (1) | ERROR | None | Abort |
| `decision.order_type` | Must be BUY (1) or SELL (-1) | ERROR | None | Abort |
| `decision.approved_volume` | Must be > 0, not NaN | ERROR | None | Abort |
| `decision.approved_price` | Must be > 0, not NaN | ERROR | None | Abort |
| `decision.approved_sl` | Must be > 0, not NaN | ERROR | None | Abort |
| `decision.approved_tp` | Must be > 0, not NaN | ERROR | None | Abort |
| `decision.decision_id` | Must be non-empty | ERROR | None | Abort |
| `decision.snapshot_id` | Must be > 0 | ERROR | None | Abort |
| `state.is_valid` | Must be true | WARN | None | Abort |
| `state.snapshot_id` | Must equal `decision.snapshot_id` | WARN | None | Abort |
| Idempotency | `decision_id` must be first-seen | WARN | None | Abort |
| Volume > max | Clamp to max | WARN | Clamp | Continue |
| Volume < min | Raise to min | WARN | Raise | Continue |
| Volume not aligned to step | Round to step | None | Round | Continue |
| SL violates stops-level | Adjust to min distance | WARN | Adjust | Continue |
| TP violates stops-level | Adjust to min distance | WARN | Adjust | Continue |
| SL on wrong side | Abort | ERROR | None | Abort |
| TP on wrong side | Abort | ERROR | None | Abort |
| Comment > 31 chars | Truncate | None | Truncate | Continue |
| `magic_number` | Must be > 0, match config | ERROR | None | Abort |
| `request_id` | Must be non-empty | ERROR | None | Abort |
| `req.decision_id` | Must match `decision.decision_id` | ERROR | None | Abort |
| `req.snapshot_id` | Must match `decision.snapshot_id` | ERROR | None | Abort |
| Broker NULL | Cannot proceed | ERROR | None | Abort |

---

# 15. State Machine

The Execution Engine is stateless between calls (no persistent state). Each `BuildOrderRequest` call transitions through internal states:

```
    READY (entry)
       │
       ▼
    [Validate decision]
       │
       ├── invalid ──► FAILED ──► return false
       │
       ▼ (valid)
    VALIDATING
       │
       [Check MarketState, snapshot]
       │
       ├── mismatch ──► FAILED ──► return false
       │
       ▼ (valid)
    [Check idempotency]
       │
       ├── duplicate ──► FAILED ──► return false
       │
       ▼ (first-seen)
    NORMALIZING
       │
       [Normalize volume]
       [Normalize prices]
       [Check broker constraints]
       │
       ├── invalid ──► FAILED ──► return false
       │
       ▼ (valid)
    BUILDING
       │
       [Generate request_id]
       [Build comment]
       [Assemble OrderRequest]
       │
       ▼
    [Validate OrderRequest]
       │
       ├── invalid ──► FAILED ──► return false
       │
       ▼ (valid)
    [Mark idempotency]
       │
       ▼
    COMPLETED ──► return true
```

### State Definitions

| State | Description | Entry | Exit |
|-------|-------------|-------|------|
| **READY** | Initial state, received decision. | Method entry. | First validation. |
| **VALIDATING** | Decision validated, checking context. | Decision valid. | MarketState check done. |
| **NORMALIZING** | Normalizing volume and prices. | Idempotency passed. | All normalizations done. |
| **BUILDING** | Constructing the OrderRequest. | All normalizations valid. | Request built. |
| **COMPLETED** | Request built and validated. | RequestValidator passes. | Return true. |
| **FAILED** | A check failed. | Any check fails. | Return false. |
| **RECOVERING** | Not applicable (stateless between calls). | N/A. | N/A. |

---

# 16. Security Constraints

### 16.1 — Execution Engine Must NEVER Approve Trades

The Execution Engine receives an APPROVED decision and builds a request. It cannot approve a REJECTED or DEFERRED decision. If `decision.status != APPROVED`, it aborts.

### 16.2 — Execution Engine Must NEVER Reject Trades Based on Strategy

The Execution Engine does not see strategy information. It does not know which strategy produced the vote. It only sees the RiskDecision. It cannot reject based on strategy content.

### 16.3 — Execution Engine Must NEVER Modify RiskDecision

The decision is `const`. The Execution Engine reads from it but cannot modify any field. Normalization affects the OrderRequest, not the decision.

### 16.4 — Execution Engine Must NEVER Increase Risk

- Volume: may only be rounded (up or down to step) or clamped DOWN to broker max. Cannot be increased beyond the approved amount (except rounding up to step, capped at max).
- SL: may only be adjusted to be FURTHER from entry (more conservative) or to respect stops-level. Cannot be moved CLOSER to entry (less conservative).
- TP: may only be adjusted to respect stops-level. Cannot be moved further from entry (greedier).

### 16.5 — Execution Engine Must NEVER Bypass Risk Engine

There is no code path that sends an order without a RiskDecision. The `BuildOrderRequest` method requires a `const RiskDecision &` parameter. If the decision is REJECTED, no request is built.

### 16.6 — Execution Engine Must NEVER Access Broker Order API

The Execution Engine uses `IBrokerAdapter` only for **symbol property queries** (`SymbolPoint`, `SymbolDigits`, `SymbolBid`, `SymbolAsk`, `SymbolVolumeMin/Max/Step`, `SymbolStopsLevel`). It NEVER calls `SendOrder`, `CloseAllPositionsForMagic`, `QueryBrokerPositions`, or `CaptureTick`.

### 16.7 — Execution Engine Must NEVER Generate Trading Signals

The Execution Engine produces OrderRequests from RiskDecisions. It does not produce votes, decisions, or signals. It is a pure translator.

### 16.8 — Execution Engine Must NEVER Modify PositionState

The Execution Engine does not access `PositionState` or `IContextStore` positions. It only accesses `IContextStore` for idempotency (`IsDecisionProcessed`, `MarkDecisionProcessed`).

### 16.9 — Execution Engine Must NEVER Modify MarketState

The `MarketState` is `const`. The Execution Engine reads from it but cannot modify it.

---

# 17. Production Checklist

### 17.1 — Contract Alignment

- [ ] `OrderRequest` struct fields match `Contracts/RiskDecision.mqh` exactly (11 fields).
- [ ] `RiskDecision` struct consumed from `Contracts/RiskDecision.mqh`.
- [ ] `MarketState` struct consumed from `Contracts/MarketState.mqh`.
- [ ] `IOrderBuilder` interface matches `Interfaces/IOrderBuilder.mqh` exactly (3 methods: `BuildOrderRequest`, `Initialize`, `Shutdown`).
- [ ] Constants: `ATLAS_ORDER_*`, `ATLAS_DECISION_*`, `ATLAS_IDEMPOTENCY_SLOTS`, `ATLAS_MODULE_EXECUTION`.

### 17.2 — Dependency Alignment

- [ ] `ILogger` available.
- [ ] `IBrokerAdapter` available (for symbol queries only — NOT for order dispatch).
- [ ] `IContextStore` available (for idempotency only).
- [ ] `AtlasConfig` available.
- [ ] NO dependency on `IMarketDataSource`, `IStrategySet`, `IRiskEvaluator`, `IPositionStore`, `IStateStore`.

### 17.3 — File Structure

- [ ] Main file: `Engines/ExecutionEngine.mqh` (implements `IOrderBuilder`).
- [ ] Internal helpers under `Engines/ExecutionEngine/`:
  - `DecisionValidator.mqh`
  - `VolumeNormalizer.mqh`
  - `PriceValidator.mqh`
  - `OrderConstraints.mqh`
  - `IdempotencyGuard.mqh`
  - `CommentBuilder.mqh`
  - `OrderBuilder.mqh`
  - `RequestValidator.mqh`
  - `ExecutionStatistics.mqh`

### 17.4 — Performance Verification

- [ ] No `new` or `delete` in `BuildOrderRequest`.
- [ ] No `Print()` anywhere.
- [ ] No broker order API calls (`SendOrder`, `CloseAllPositions`, `QueryBrokerPositions`).
- [ ] No direct `SymbolInfo*` calls (must use `IBrokerAdapter`).
- [ ] No direct `AccountInfo*` calls.
- [ ] No file I/O.
- [ ] No recursion.
- [ ] All arrays fixed-size.
- [ ] Total stack usage < 3 KB.
- [ ] Total build time ≤ 0.1 ms.

### 17.5 — MQL5 Compliance

- [ ] Include guards on every file.
- [ ] No `#pragma once`.
- [ ] No `->` (use `.`).
- [ ] No STL.
- [ ] No dynamic arrays in structs.

### 17.6 — Idempotency Verification

- [ ] `IdempotencyGuard` with 32-slot FIFO ring.
- [ ] `IsFirstSeen()` checks before processing.
- [ ] `MarkProcessed()` called AFTER successful build (not before).
- [ ] Cross-session idempotency via `IContextStore::MarkDecisionProcessed()`.

### 17.7 — Price Handling Verification

- [ ] Entry price uses live broker price (ask for BUY, bid for SELL), NOT `decision.approved_price`.
- [ ] All prices normalized via `NormalizeDouble(price, digits)`.
- [ ] SL/TP respect `SymbolStopsLevel` with `2 * point` buffer.
- [ ] SL on correct side (below entry for BUY, above for SELL).
- [ ] TP on correct side (above entry for BUY, below for SELL).

### 17.8 — Volume Handling Verification

- [ ] Volume rounded to `VolumeStep`.
- [ ] Volume clamped to `[VolumeMin, VolumeMax]`.
- [ ] Volume never exceeds `decision.approved_volume` by more than one step.
- [ ] Volume normalized to `config.volume_digits` decimal places.

### 17.9 — Error Handling

- [ ] NULL pointer checks on all dependencies.
- [ ] NaN checks on all double inputs.
- [ ] All edge cases from Section 13 covered.

### 17.10 — Documentation

- [ ] Doxygen comments on every class.
- [ ] Doxygen comments on every public method.
- [ ] Doxygen comments on every public member.
- [ ] Every file has a header comment block.

### 17.11 — Integration Points

- [ ] `ExecutionEngine::SetDependencies()` signature matches what CoreEngine will call.
- [ ] `BuildOrderRequest()` return value: `bool` (true = success, false = failure).
- [ ] Output `OrderRequest &req` is caller-allocated (CoreEngine provides the reference).
- [ ] Called by CoreEngine PhaseScheduler after RiskEngine approves.

### 17.12 — Versioning

- [ ] File header: `AtlasEA v0.1.4.0` (Execution Engine phase).

---

**End of Specification.**

This document is implementation-ready. GLM can implement the entire Execution Engine from this specification alone without making any architectural decisions. All design choices are fixed. All edge cases are enumerated. All validation rules are specified. All performance budgets are defined. The Execution Engine is a pure translator with no trading authority.
