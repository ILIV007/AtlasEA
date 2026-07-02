# AtlasEA v1.0 — Risk Engine Production Specification

**Document version:** 1.0
**Target module:** `Engines/RiskEngine.mqh` (+ internal helpers under `Engines/RiskEngine/`)
**Interface implemented:** `IRiskEvaluator` (defined in `Interfaces/IRiskEvaluator.mqh`)
**Contracts consumed:** `AggregatedVote`, `RiskDecision`, `ExecutionEvent`, `PositionState`, `MarketState`
**Constants available:**
- Direction: `ATLAS_ORDER_BUY = 1`, `ATLAS_ORDER_SELL = -1`, `ATLAS_ORDER_NONE = 0`
- Decision status: `ATLAS_DECISION_APPROVED = 1`, `ATLAS_DECISION_REJECTED = 0`, `ATLAS_DECISION_DEFERRED = -1`
- Risk reason codes: `ATLAS_RISK_REASON_OK=0`, `DRAWDOWN=1`, `EXPOSURE=2`, `MARGIN=3`, `COOLDOWN=4`, `KILLSWITCH=5`, `NOVOTE=6`, `INVALID=7`, `NO_CONTEXT=8`, `LOW_CONFIDENCE=9`
- Thresholds: `ATLAS_KILL_SWITCH_DRAWDOWN = 8.0`, `ATLAS_KILL_SWITCH_LOSSES = 5`, `ATLAS_MIN_CONFIDENCE = 0.30`, `ATLAS_MARGIN_LEVEL_MIN = 200.0`
- Capacities: `ATLAS_MAX_POSITIONS = 64`

---

# 1. Risk Engine Responsibilities

The Risk Engine is the **final non-bypassable authority** on every trade. No order may be sent to the broker without an APPROVED `RiskDecision` from this engine. It evaluates each `AggregatedVote` produced by the Strategy Engine against the current account, position, and market state, and renders one of three outcomes: APPROVED, REJECTED, or DEFERRED.

### R1.1 — AggregatedVote Evaluation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Receive a confidence-weighted aggregated vote and decide whether to approve, reject, or defer the trade. |
| **Owner** | `RiskEngine` (entry point of `EvaluateRisk`) |
| **Inputs** | `const AggregatedVote &vote` (from CoreEngine VoteAggregator) |
| **Outputs** | `RiskDecision` struct (approved, rejected, or deferred) |
| **Performance limits** | O(1), ≤ 1 ms total. All checks are arithmetic comparisons. |
| **Failure handling** | If any dependency is NULL or any input is invalid, return REJECTED with `ATLAS_RISK_REASON_NO_CONTEXT` or `ATLAS_RISK_REASON_INVALID`. Never crash. |
| **Forbidden behaviors** | Must NOT call `OrderSend`. Must NOT call `PositionsTotal`/`PositionGet*` directly (must use `IBrokerAdapter`). Must NOT call `AccountInfoDouble` directly (must use `IBrokerAdapter`). Must NOT modify the input vote. Must NOT modify `MarketState`. |
| **Decision authority** | FINAL. No other module may override a REJECTED decision. No other module may force an APPROVED decision. |

### R1.2 — Kill Switch Enforcement

| Attribute | Value |
|-----------|-------|
| **Purpose** | When the kill switch is active, reject ALL trades immediately. This is the FIRST check in the pipeline and is NON-BYPASSABLE. |
| **Owner** | `KillSwitchManager` (internal component) |
| **Inputs** | `IContextStore::IsKillSwitchActive()` |
| **Outputs** | If active: REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`. No further checks run. |
| **Performance limits** | O(1), ≤ 0.001 ms. |
| **Failure handling** | If context is NULL, return REJECTED with `ATLAS_RISK_REASON_NO_CONTEXT`. |
| **Forbidden behaviors** | Must NOT cache kill-switch state across ticks (always query fresh). Must NOT allow any other check to run before this one. |
| **Decision authority** | ABSOLUTE. Once the kill switch is active, no trade may be approved until it is explicitly deactivated. |

### R1.3 — Daily Drawdown Tracking

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track the daily drawdown from peak equity. If drawdown exceeds the configured limit, trigger the kill switch. |
| **Owner** | `DrawdownManager` (internal component) |
| **Inputs** | `IContextStore::GetDailyStartEquity()`, `GetDailyPeakEquity()`, `IBrokerAdapter::AccountEquity()` |
| **Outputs** | Updated `daily_drawdown_pct` on context. Boolean: within limit or exceeded. |
| **Performance limits** | O(1) |
| **Failure handling** | If daily_start_equity ≤ 0, return false (cannot compute). If equity ≤ 0, trigger kill switch. |
| **Forbidden behaviors** | Must NOT use `AccountInfoDouble` directly. Must NOT modify daily_start_equity (set only by ContextFactory.ResetDaily). |
| **Decision authority** | If drawdown ≥ `max_daily_drawdown_pct` (5.0%): trigger kill switch + REJECTED. If drawdown ≥ `ATLAS_KILL_SWITCH_DRAWDOWN` (8.0%): trigger kill switch immediately (absolute limit). |

### R1.4 — Exposure Calculation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Compute the current account exposure as (total volume × contract size) / equity. Ensure new trades do not exceed the exposure limit. |
| **Owner** | `ExposureManager` (internal component) |
| **Inputs** | `IBrokerAdapter::CountPositionsForMagic()`, `IBrokerAdapter::QueryBrokerPositions()`, `IBrokerAdapter::SymbolContractSize()`, `IBrokerAdapter::AccountEquity()` |
| **Outputs** | Updated `current_exposure_pct` on context. Boolean: within limit or exceeded. |
| **Performance limits** | O(N) where N = open positions (≤ ATLAS_MAX_POSITIONS). |
| **Failure handling** | If equity ≤ 0, return false. If contract size ≤ 0, return false. |
| **Forbidden behaviors** | Must NOT call `PositionGet*` directly (must use adapter). Must NOT include positions from other magic numbers. |
| **Decision authority** | If proposed exposure > `max_exposure_limit` (0.20 = 20%): REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |

### R1.5 — Margin Safety Check

| Attribute | Value |
|-----------|-------|
| **Purpose** | Ensure the account has sufficient margin to open the new position without dropping below the minimum margin level. |
| **Owner** | `MarginManager` (internal component) |
| **Inputs** | `IBrokerAdapter::AccountMarginLevel()`, `IBrokerAdapter::AccountEquity()`, `IBrokerAdapter::AccountMargin()` |
| **Outputs** | Boolean: margin safe or unsafe. |
| **Performance limits** | O(1) |
| **Failure handling** | If margin ≤ 0, return true (no existing margin — safe to open). If margin level < `ATLAS_MARGIN_LEVEL_MIN` (200%), return false. |
| **Forbidden behaviors** | Must NOT call `AccountInfoDouble` directly. |
| **Decision authority** | If margin level < 200%: REJECTED with `ATLAS_RISK_REASON_MARGIN`. |

### R1.6 — Cooldown Enforcement

| Attribute | Value |
|-----------|-------|
| **Purpose** | After consecutive losses, enforce a cooldown period during which no new trades are approved. |
| **Owner** | `CooldownManager` (internal component) |
| **Inputs** | `IContextStore::GetConsecutiveLosses()`, `GetCooldownUntil()` |
| **Outputs** | Boolean: cooldown active or expired. |
| **Performance limits** | O(1) |
| **Failure handling** | If context is NULL, return false (defensive — allow trade). |
| **Forbidden behaviors** | Must NOT reset cooldown without explicit operator action or daily reset. |
| **Decision authority** | If cooldown active (current time < cooldown_until): REJECTED with `ATLAS_RISK_REASON_COOLDOWN`. If consecutive_losses ≥ `ATLAS_KILL_SWITCH_LOSSES` (5): trigger kill switch. |

### R1.7 — Confidence Floor

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reject votes with confidence below the minimum threshold. |
| **Owner** | `RiskEngine` (direct check in EvaluateRisk) |
| **Inputs** | `vote.confidence` |
| **Outputs** | Boolean: above floor or below. |
| **Performance limits** | O(1) |
| **Failure handling** | If confidence is NaN, treat as 0.0 → reject. |
| **Forbidden behaviors** | Must NOT modify the confidence. |
| **Decision authority** | If confidence < `ATLAS_MIN_CONFIDENCE` (0.30): REJECTED with `ATLAS_RISK_REASON_LOW_CONFIDENCE`. |

### R1.8 — Vote Validation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reject empty or invalid aggregated votes before running expensive checks. |
| **Owner** | `RiskEngine` (direct check) |
| **Inputs** | `vote.direction`, `vote.vote_count`, `vote.confidence` |
| **Outputs** | Boolean: valid or invalid. |
| **Performance limits** | O(1) |
| **Failure handling** | Invalid vote → REJECTED with `ATLAS_RISK_REASON_NOVOTE`. |
| **Forbidden behaviors** | Must NOT inspect individual votes (the aggregated vote is already merged). |
| **Decision authority** | If direction == ATLAS_ORDER_NONE or vote_count == 0: REJECTED with `ATLAS_RISK_REASON_NOVOTE`. |

### R1.9 — RiskDecision Construction

| Attribute | Value |
|-----------|-------|
| **Purpose** | Build the final `RiskDecision` struct with approved volume, price, SL, and TP. |
| **Owner** | `DecisionBuilder` (internal component) |
| **Inputs** | AggregatedVote (for direction, confidence, entry/SL/TP), AtlasConfig (for volume calculation), MarketState (for current price) |
| **Outputs** | Fully populated `RiskDecision` |
| **Performance limits** | O(1) |
| **Failure handling** | If any input is invalid, build a REJECTED decision. |
| **Forbidden behaviors** | Must NOT call broker APIs. Must NOT modify context. |
| **Decision authority** | Computes approved_volume = base_volume × (0.5 + confidence × 0.5), clamped to [min_volume, max_volume]. |

### R1.10 — Risk State Update

| Attribute | Value |
|-----------|-------|
| **Purpose** | After a fill event, update the risk state (consecutive losses, daily counts, cooldowns). |
| **Owner** | `RiskEngine::UpdateRiskState` |
| **Inputs** | `const ExecutionEvent &event` |
| **Outputs** | Updated context fields (consecutive_losses, daily_trade_count, daily_loss_count, cooldown_until) |
| **Performance limits** | O(1) |
| **Failure handling** | If event is invalid, ignore silently. |
| **Forbidden behaviors** | Must NOT trigger kill switch on a single rejection (only on consecutive threshold). |
| **Decision authority** | If fill_status == REJECTED: increment consecutive_losses. If consecutive_losses ≥ 3: set cooldown_until = now + 1800s (30 min). If consecutive_losses ≥ 5: trigger kill switch. |

### R1.11 — Daily Reset

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reset daily risk stats at the start of a new trading day. |
| **Owner** | `RiskEngine::ResetDailyLimits` |
| **Inputs** | `IBrokerAdapter::AccountEquity()` |
| **Outputs** | Reset context fields (daily_start_equity, daily_peak_equity, daily_drawdown_pct, daily_trade_count, daily_loss_count, consecutive_losses, cooldown_until). Deactivate kill switch. |
| **Performance limits** | O(1) |
| **Failure handling** | If equity ≤ 0, log ERROR and set daily_start_equity = 0. |
| **Forbidden behaviors** | Must NOT reset total telemetry counters. Must NOT clear position mirror. |
| **Decision authority** | None — this is a state mutation, not a decision. |

### R1.12 — Exposure Refresh

| Attribute | Value |
|-----------|-------|
| **Purpose** | Recompute current exposure and floating PnL from broker positions. Called on heartbeat. |
| **Owner** | `RiskEngine::UpdateExposure` |
| **Inputs** | `IBrokerAdapter::QueryBrokerPositions()`, `AccountEquity()`, `SymbolContractSize()` |
| **Outputs** | Updated `current_exposure_pct` and `total_floating_pnl` on context. |
| **Performance limits** | O(N) where N ≤ ATLAS_MAX_POSITIONS |
| **Failure handling** | If equity ≤ 0, skip. If no positions, set exposure = 0. |
| **Forbidden behaviors** | Must NOT call `PositionGet*` directly. |
| **Decision authority** | None — state update only. |

### R1.13 — Kill Switch Trigger

| Attribute | Value |
|-----------|-------|
| **Purpose** | Activate the kill switch and close all open positions. |
| **Owner** | `RiskEngine::TriggerKillSwitch` |
| **Inputs** | Reason string |
| **Outputs** | Activated kill switch on context. Closed all positions via `IBrokerAdapter::CloseAllPositionsForMagic()`. Emitted `EV_KILL_SWITCH_ACTIVATED` event. |
| **Performance limits** | O(N) for position closing (N ≤ ATLAS_MAX_POSITIONS) |
| **Failure handling** | If already active, return immediately (idempotent). If close fails, log ERROR but kill switch remains active. |
| **Forbidden behaviors** | Must NOT call `OrderSend` directly (must use `IBrokerAdapter::CloseAllPositionsForMagic`). Must NOT allow re-entry while closing. |
| **Decision authority** | ABSOLUTE. Once triggered, cannot be bypassed until daily reset. |

---

# 2. Internal Components

The Risk Engine is decomposed into 8 internal components. All are stack-allocated inside `RiskEngine`. All live under `Engines/RiskEngine/` as separate `.mqh` files.

### 2.1 — DrawdownManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track daily peak equity, compute current drawdown percentage, trigger kill switch on limit breach. |
| **Owned data** | None (all state lives on `IContextStore`). |
| **Public API** | `bool CheckDailyDrawdown(IContextStore *ctx, IBrokerAdapter *broker, ILogger *logger, KillSwitchManager *ksm)` |
| **Private helpers** | `double ComputeDrawdownPct(const double peak, const double equity) const`, `bool IsAbsoluteBreach(const double dd_pct) const`, `bool IsConfiguredBreach(const double dd_pct, const double limit) const` |
| **Dependencies** | `IContextStore`, `IBrokerAdapter`, `ILogger`, `KillSwitchManager` |
| **Failure modes** | daily_start_equity ≤ 0 → return false (cannot compute). equity ≤ 0 → trigger kill switch. |
| **Performance constraints** | O(1), ≤ 0.01 ms. |

### 2.2 — ExposureManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Compute current exposure, check proposed exposure against limit. |
| **Owned data** | None. |
| **Public API** | `bool CheckExposureLimit(IContextStore *ctx, IBrokerAdapter *broker, ILogger *logger, const double proposed_volume, const double max_exposure)` |
| **Private helpers** | `double SumOpenVolume(IBrokerAdapter *broker) const`, `double ComputeExposurePct(const double volume, const double contract_size, const double equity) const` |
| **Dependencies** | `IContextStore`, `IBrokerAdapter`, `ILogger` |
| **Failure modes** | equity ≤ 0 → return false. contract_size ≤ 0 → return false. |
| **Performance constraints** | O(N), N ≤ ATLAS_MAX_POSITIONS. ≤ 0.05 ms. |

### 2.3 — MarginManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Check margin level safety. |
| **Owned data** | None. |
| **Public API** | `bool CheckMarginSafety(IBrokerAdapter *broker, ILogger *logger) const` |
| **Private helpers** | `double ComputeMarginLevel(const double equity, const double margin) const` |
| **Dependencies** | `IBrokerAdapter`, `ILogger` |
| **Failure modes** | margin ≤ 0 → return true (safe — no existing margin). margin level < 200% → return false. |
| **Performance constraints** | O(1), ≤ 0.01 ms. |

### 2.4 — KillSwitchManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Check if kill switch is active. Activate kill switch (context + close positions + emit event). |
| **Owned data** | None. |
| **Public API** | `bool IsActive(IContextStore *ctx) const`, `void Activate(IContextStore *ctx, IBrokerAdapter *broker, ILogger *logger, IEventBus *bus, const string reason, const long snapshot_id)` |
| **Private helpers** | `void CloseAllPositions(IBrokerAdapter *broker, ILogger *logger, const string reason)`, `void EmitEvent(IEventBus *bus, const long snapshot_id, const string reason)` |
| **Dependencies** | `IContextStore`, `IBrokerAdapter`, `ILogger`, `IEventBus` |
| **Failure modes** | Already active → return immediately (idempotent). Close fails → log ERROR, kill switch remains active. |
| **Performance constraints** | Check: O(1). Activate: O(N) for closing positions. |

### 2.5 — CooldownManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Check if cooldown is active. Set cooldown after consecutive losses. Reset cooldown on daily reset. |
| **Owned data** | None. |
| **Public API** | `bool IsCooldownActive(IContextStore *ctx) const`, `void ApplyCooldown(IContextStore *ctx, ILogger *logger, const int consecutive_losses) const` |
| **Private helpers** | `datetime ComputeCooldownUntil(const int consecutive_losses) const` |
| **Dependencies** | `IContextStore`, `ILogger` |
| **Failure modes** | context NULL → return false (allow trade). |
| **Performance constraints** | O(1) |

### 2.6 — DecisionBuilder

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Construct the final `RiskDecision` struct from an approved vote. |
| **Owned data** | None. |
| **Public API** | `RiskDecision BuildApproved(const AggregatedVote &vote, const AtlasConfig &config, const MarketState &state, const long snapshot_id) const`, `RiskDecision BuildRejected(const AggregatedVote &vote, const int reason_code, const string reason, const long snapshot_id, const bool kill_switch) const` |
| **Private helpers** | `double CalculateApprovedVolume(const AggregatedVote &vote, const AtlasConfig &config) const`, `string GenerateDecisionId(const long snapshot_id) const`, `double AverageEntry(const AggregatedVote &vote) const`, `double AverageSL(const AggregatedVote &vote) const`, `double AverageTP(const AggregatedVote &vote) const` |
| **Dependencies** | `AggregatedVote`, `RiskDecision`, `AtlasConfig`, `MarketState` |
| **Failure modes** | None — always produces a valid decision struct. |
| **Performance constraints** | O(1) |

### 2.7 — DecisionValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Validate a constructed `RiskDecision` before returning it. |
| **Owned data** | None. |
| **Public API** | `bool Validate(const RiskDecision &dec, string &out_reason) const` |
| **Private helpers** | `bool IsValidStatus(const int s) const`, `bool IsValidReasonCode(const int r) const`, `bool IsValidDirection(const int d) const`, `bool ArePricesValid(const RiskDecision &dec) const` |
| **Dependencies** | `RiskDecision` |
| **Failure modes** | Invalid decision → return false with reason. Caller logs ERROR and rebuilds as REJECTED. |
| **Performance constraints** | O(1) |

### 2.8 — RiskStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track decision counts, approval/rejection rates, rule hit frequency, latency. |
| **Owned data** | Fixed array of counters: `total_decisions`, `approved`, `rejected`, `deferred`, `kill_switch_activations`, `per_reason_count[10]` (one per reason code), `total_latency_ms`, `peak_latency_ms`, `evaluations`. |
| **Public API** | `void RecordDecision(const int status, const int reason_code, const double latency_ms, const bool kill_switch)`, `void Reset()`, `void LogSummary(ILogger *logger) const`, `ulong TotalDecisions() const`, `ulong Approved() const`, `ulong Rejected() const`, `double ApprovalRate() const`, `double RejectRate() const`, `double AvgLatencyMs() const` |
| **Private helpers** | None. |
| **Dependencies** | `ILogger` |
| **Failure modes** | None — best-effort counters. |
| **Performance constraints** | O(1) per update. |

---

# 3. Risk Evaluation Pipeline

The `EvaluateRisk` method executes the following pipeline. The order is CRITICAL — the kill switch check MUST be first and is NON-BYPASSABLE.

### Stage 1 — Receive AggregatedVote

- Input: `const AggregatedVote &vote`
- The vote contains: aggregation_id, direction, confidence, votes[] (up to ATLAS_MAX_VOTES), vote_count, snapshot_id.
- No transformation. The vote is treated as immutable.

### Stage 2 — Validate Snapshot

- Check `vote.snapshot_id > 0`.
- If invalid: REJECTED with `ATLAS_RISK_REASON_INVALID`.
- Note: monotonicity is enforced by SnapshotManager — the Risk Engine only checks positivity.

### Stage 3 — Read Risk State

- Query `IContextStore` for: `IsKillSwitchActive()`, `GetConsecutiveLosses()`, `GetCooldownUntil()`, `GetDailyStartEquity()`, `GetDailyPeakEquity()`, `GetDailyDrawdownPct()`, `GetCurrentExposurePct()`.
- If context is NULL: REJECTED with `ATLAS_RISK_REASON_NO_CONTEXT`.

### Stage 4 — Kill Switch Check (NON-BYPASSABLE, FIRST)

- If `IsKillSwitchActive() == true`: REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`.
- No other checks run. Return immediately.
- This check is ABSOLUTE. No configuration, no override, no bypass.

### Stage 5 — Vote Validation

- If `vote.direction == ATLAS_ORDER_NONE` or `vote.vote_count == 0`: REJECTED with `ATLAS_RISK_REASON_NOVOTE`.
- If `vote.confidence < ATLAS_MIN_CONFIDENCE (0.30)`: REJECTED with `ATLAS_RISK_REASON_LOW_CONFIDENCE`.
- If `vote.confidence` is NaN: REJECTED with `ATLAS_RISK_REASON_INVALID`.

### Stage 6 — Daily Drawdown Check

- Call `DrawdownManager.CheckDailyDrawdown()`.
- Updates peak equity and drawdown percentage on context.
- If drawdown ≥ `max_daily_drawdown_pct` (5.0%): KillSwitchManager.Activate("daily_drawdown: X%") → REJECTED with `ATLAS_RISK_REASON_DRAWDOWN`.
- If drawdown ≥ `ATLAS_KILL_SWITCH_DRAWDOWN` (8.0%): KillSwitchManager.Activate("absolute_drawdown: X%") → REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`.

### Stage 7 — Exposure Check

- Compute proposed volume via `DecisionBuilder.CalculateApprovedVolume()`.
- Call `ExposureManager.CheckExposureLimit()`.
- If proposed exposure > `max_exposure_limit` (0.20): REJECTED with `ATLAS_RISK_REASON_EXPOSURE`.

### Stage 8 — Margin Safety Check

- Call `MarginManager.CheckMarginSafety()`.
- If margin level < `ATLAS_MARGIN_LEVEL_MIN` (200%): REJECTED with `ATLAS_RISK_REASON_MARGIN`.

### Stage 9 — Cooldown Check

- Call `CooldownManager.IsCooldownActive()`.
- If active (current time < cooldown_until): REJECTED with `ATLAS_RISK_REASON_COOLDOWN`.
- Check consecutive losses: if ≥ `ATLAS_KILL_SWITCH_LOSSES` (5): KillSwitchManager.Activate("consecutive_losses: N") → REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`.

### Stage 10 — Build RiskDecision

- All checks passed → call `DecisionBuilder.BuildApproved()`.
- Computes: approved_volume (base × (0.5 + confidence × 0.5), clamped to [min, max]).
- Computes: approved_price (average of vote entry prices).
- Computes: approved_sl (average of vote SL prices).
- Computes: approved_tp (average of vote TP prices).
- Sets: status = APPROVED, reason_code = OK, order_type = vote.direction, kill_switch_triggered = false.

### Stage 11 — Validate RiskDecision

- Call `DecisionValidator.Validate()`.
- If invalid (should never happen): rebuild as REJECTED with `ATLAS_RISK_REASON_INVALID`.

### Stage 12 — Update Risk State

- No context mutation on approval (the trade hasn't executed yet).
- Statistics: `RiskStatistics.RecordDecision(APPROVED, OK, latency_ms, false)`.

### Stage 13 — Return to Core Engine

- Return the `RiskDecision`.
- CoreEngine's PhaseScheduler passes it to ExecutionEngine if approved.

---

# 4. RiskDecision Specification

The `RiskDecision` struct is defined in `Contracts/RiskDecision.mqh`.

### Field: `decision_id`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Unique identifier for this decision. Used for idempotency in ExecutionEngine. |
| **Type** | `string` |
| **Allowed range** | Non-empty, max 32 characters. Format: "DEC_{snapshot_id}_{random}". |
| **Default** | "" (must be set by DecisionBuilder). |
| **Validation** | Must be non-empty. Must be unique per decision. |
| **Ownership** | Set by `DecisionBuilder.GenerateDecisionId()`. |
| **Immutability** | Immutable after construction. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Failure handling** | If empty after construction, ExecutionEngine will reject the order. |

### Field: `aggregation_id`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Correlation back to the AggregatedVote that produced this decision. |
| **Type** | `string` |
| **Allowed range** | Copied from `AggregatedVote.aggregation_id`. |
| **Default** | "" (must be copied from vote). |
| **Validation** | Must be non-empty (if vote had a valid aggregation_id). |
| **Ownership** | Copied from input vote. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Failure handling** | If empty, logged at WARN but decision is still valid. |

### Field: `status`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The decision outcome. |
| **Type** | `int` |
| **Allowed range** | `ATLAS_DECISION_APPROVED (1)`, `ATLAS_DECISION_REJECTED (0)`, `ATLAS_DECISION_DEFERRED (-1)`. |
| **Default** | `ATLAS_DECISION_REJECTED (0)`. |
| **Validation** | Must be one of the three constants. |
| **Ownership** | Set by DecisionBuilder. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Failure handling** | Invalid status → DecisionValidator rejects, decision is rebuilt as REJECTED. |

### Field: `reason_code`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Machine-readable reason for the decision (especially for rejections). |
| **Type** | `int` |
| **Allowed range** | `ATLAS_RISK_REASON_OK (0)` through `ATLAS_RISK_REASON_LOW_CONFIDENCE (9)`. |
| **Default** | `ATLAS_RISK_REASON_OK (0)` for approved, specific code for rejected. |
| **Validation** | Must be in [0, 9]. |
| **Ownership** | Set by DecisionBuilder based on which check failed. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Failure handling** | Out-of-range code → logged at ERROR, treated as `ATLAS_RISK_REASON_INVALID`. |

### Field: `rejection_reason`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Human-readable explanation for the rejection. |
| **Type** | `string` |
| **Allowed range** | Non-empty for rejections, empty for approvals. Max 128 characters. |
| **Default** | "" (for approvals). |
| **Validation** | Should be non-empty when status == REJECTED. |
| **Ownership** | Set by DecisionBuilder. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Failure handling** | Empty reason on rejection → logged at WARN but decision is still valid. |

### Field: `approved_volume`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The volume (in lots) approved for the trade. |
| **Type** | `double` |
| **Allowed range** | > 0.0 for approvals. 0.0 for rejections. |
| **Default** | 0.0 (for rejections). |
| **Validation** | Must be > 0 for approvals. Must not be NaN. |
| **Ownership** | Set by DecisionBuilder.CalculateApprovedVolume(). |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | NaN or ≤ 0 on approval → DecisionValidator rejects. |

### Field: `approved_price`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The entry price approved for the trade. |
| **Type** | `double` |
| **Allowed range** | > 0.0 for approvals. 0.0 for rejections. |
| **Default** | 0.0 (for rejections). |
| **Validation** | Must be > 0 for approvals. Must not be NaN. |
| **Ownership** | Average of vote.votes[].suggested_entry. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | NaN or ≤ 0 on approval → DecisionValidator rejects. |

### Field: `approved_sl`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The stop-loss price approved for the trade. |
| **Type** | `double` |
| **Allowed range** | > 0.0 for approvals. 0.0 for rejections. |
| **Default** | 0.0 (for rejections). |
| **Validation** | Must be > 0 for approvals. Must not be NaN. |
| **Ownership** | Average of vote.votes[].suggested_sl. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | NaN or ≤ 0 on approval → DecisionValidator rejects. |

### Field: `approved_tp`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The take-profit price approved for the trade. |
| **Type** | `double` |
| **Allowed range** | > 0.0 for approvals. 0.0 for rejections. |
| **Default** | 0.0 (for rejections). |
| **Validation** | Must be > 0 for approvals. Must not be NaN. |
| **Ownership** | Average of vote.votes[].suggested_tp. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | NaN or ≤ 0 on approval → DecisionValidator rejects. |

### Field: `order_type`

| Attribute | Value |
|-----------|-------|
| **Purpose** | The trade direction. |
| **Type** | `int` |
| **Allowed range** | `ATLAS_ORDER_BUY (1)` or `ATLAS_ORDER_SELL (-1)` for approvals. `ATLAS_ORDER_NONE (0)` for rejections. |
| **Default** | `ATLAS_ORDER_NONE (0)` (for rejections). |
| **Validation** | Must match `vote.direction` for approvals. |
| **Ownership** | Copied from `vote.direction`. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Failure handling** | Mismatch with vote → DecisionValidator rejects. |

### Field: `kill_switch_triggered`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Indicates whether this decision triggered (or was caused by) the kill switch. |
| **Type** | `bool` |
| **Allowed range** | `true` or `false`. |
| **Default** | `false`. |
| **Validation** | Must be `true` if reason_code == `ATLAS_RISK_REASON_KILLSWITCH`. |
| **Ownership** | Set by DecisionBuilder. |
| **Immutability** | Immutable. |
| **Serialization** | 1 byte. |
| **Memory layout** | 1 byte. |
| **Failure handling** | Inconsistent state → logged at WARN. |

### Field: `snapshot_id`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Correlation to the market snapshot this decision was made against. |
| **Type** | `long` |
| **Allowed range** | > 0. |
| **Default** | 0 (must be set). |
| **Validation** | Must be > 0. Must match `vote.snapshot_id`. |
| **Ownership** | Copied from `vote.snapshot_id`. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | Mismatch with vote → DecisionValidator rejects. |

### Field: `decision_time`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Timestamp when the decision was rendered. |
| **Type** | `datetime` |
| **Allowed range** | > 0. |
| **Default** | 0 (must be set). |
| **Validation** | Must be > 0. |
| **Ownership** | Set to `TimeCurrent()` by DecisionBuilder. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Failure handling** | Zero → logged at WARN. |

---

# 5. RiskState Specification

All risk state lives on `IContextStore` (implemented by `AtlasContext`). The Risk Engine reads and writes this state through the interface. The following fields constitute the "RiskState":

### 5.1 — Daily Risk State

| Field | Type | Purpose | Owner | Recovery |
|-------|------|---------|-------|----------|
| `daily_start_equity` | `double` | Equity at the start of the trading day. | ContextFactory.ResetDaily | Persisted in snapshots. |
| `daily_peak_equity` | `double` | Highest equity seen today. | DrawdownManager (via UpdateDailyPeakEquity) | Persisted. |
| `daily_drawdown_pct` | `double` | Current drawdown from peak (%). | DrawdownManager | Persisted. |
| `daily_realized_pnl` | `double` | Sum of realized PnL today. | RiskEngine.UpdateRiskState | Persisted. |
| `daily_trade_count` | `int` | Number of trades today. | RiskEngine.UpdateRiskState | Persisted. |
| `daily_loss_count` | `int` | Number of losing trades today. | RiskEngine.UpdateRiskState | Persisted. |
| `trading_day_start` | `datetime` | When the trading day started. | ContextFactory.ResetDaily | Persisted. |

### 5.2 — Exposure State

| Field | Type | Purpose | Owner | Recovery |
|-------|------|---------|-------|----------|
| `current_exposure_pct` | `double` | (volume × contract_size) / equity. | ExposureManager | Computed on heartbeat. |
| `total_floating_pnl` | `double` | Sum of open position PnL. | RiskEngine.UpdateExposure | Computed on heartbeat. |

### 5.3 — Kill Switch State

| Field | Type | Purpose | Owner | Recovery |
|-------|------|---------|-------|----------|
| `kill_switch_active` | `bool` | Is the kill switch currently active? | KillSwitchManager | Persisted. |
| `kill_switch_reason` | `string` | Human-readable reason. | KillSwitchManager | Persisted. |
| `kill_switch_time` | `datetime` | When it was activated. | KillSwitchManager | Persisted. |

### 5.4 — Cooldown State

| Field | Type | Purpose | Owner | Recovery |
|-------|------|---------|-------|----------|
| `consecutive_losses` | `int` | Current consecutive loss streak. | RiskEngine.UpdateRiskState | Persisted. |
| `last_trade_time` | `datetime` | Time of the last fill. | RiskEngine.UpdateRiskState | Persisted. |
| `cooldown_until` | `datetime` | Time until which trades are blocked. | CooldownManager | Persisted. |

### 5.5 — Telemetry

| Field | Type | Purpose | Owner | Recovery |
|-------|------|---------|-------|----------|
| `total_ticks_processed` | `ulong` | Lifetime tick count. | CoreEngine | Persisted. |
| `total_events_emitted` | `ulong` | Lifetime event count. | CoreEngine | Persisted. |
| `total_orders_sent` | `ulong` | Lifetime order count. | CoreEngine | Persisted. |
| `total_orders_filled` | `ulong` | Lifetime fill count. | CoreEngine | Persisted. |

### 5.6 — Context Versioning

| Field | Type | Purpose |
|-------|------|---------|
| `context_version` | `ulong` | Incremented on every mutation. Used for optimistic concurrency and snapshot correlation. |

### 5.7 — Snapshot Linkage

Every RiskDecision carries the `snapshot_id` of the MarketState it was evaluated against. This enables end-to-end correlation: MarketState → AggregatedVote → RiskDecision → OrderRequest → ExecutionEvent.

### 5.8 — Recovery

On startup, `PersistenceManager.RecoverState()` loads the last snapshot into `AtlasContext`. The Risk Engine reads this recovered state. If the kill switch was active in the snapshot, it remains active until the next daily reset.

---

# 6. Risk Rules

### 6.1 — Maximum Exposure

| Attribute | Value |
|-----------|-------|
| **Purpose** | Prevent over-leveraging the account. |
| **Calculation** | `exposure = (sum_of_open_volumes + proposed_volume) × contract_size / equity` |
| **Configuration** | `max_exposure_limit` (default 0.20 = 20% of equity). |
| **Failure response** | REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |

### 6.2 — Maximum Positions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Prevent too many concurrent positions. |
| **Calculation** | `count = IBrokerAdapter::CountPositionsForMagic()` |
| **Configuration** | Hard limit: `ATLAS_MAX_POSITIONS = 64`. Soft limit: configurable (future phase). |
| **Failure response** | If count ≥ 64: REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |

### 6.3 — Maximum Daily Loss

| Attribute | Value |
|-----------|-------|
| **Purpose** | Stop trading after a configurable daily drawdown. |
| **Calculation** | `dd_pct = (peak_equity - current_equity) / daily_start_equity × 100` |
| **Configuration** | `max_daily_drawdown_pct` (default 5.0%). |
| **Failure response** | Kill switch activate + REJECTED with `ATLAS_RISK_REASON_DRAWDOWN`. |

### 6.4 — Maximum Drawdown (Absolute)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Hard stop — never lose more than this in a day. |
| **Calculation** | Same as 6.3. |
| **Configuration** | `ATLAS_KILL_SWITCH_DRAWDOWN = 8.0%` (compile-time constant). |
| **Failure response** | Kill switch activate immediately + REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`. |

### 6.5 — Margin Safety

| Attribute | Value |
|-----------|-------|
| **Purpose** | Ensure sufficient margin to open new positions. |
| **Calculation** | `margin_level = equity / margin × 100` |
| **Configuration** | `ATLAS_MARGIN_LEVEL_MIN = 200.0%`. |
| **Failure response** | REJECTED with `ATLAS_RISK_REASON_MARGIN`. |

### 6.6 — Consecutive Losses

| Attribute | Value |
|-----------|-------|
| **Purpose** | Stop trading after a streak of losses (indicates strategy malfunction or bad market). |
| **Calculation** | `count = IContextStore::GetConsecutiveLosses()` |
| **Configuration** | `ATLAS_KILL_SWITCH_LOSSES = 5`. Cooldown at 3 losses: 30 minutes. |
| **Failure response** | At 3 losses: set cooldown, REJECTED with `ATLAS_RISK_REASON_COOLDOWN`. At 5 losses: kill switch + REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`. |

### 6.7 — Confidence Floor

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reject low-confidence votes. |
| **Calculation** | Compare `vote.confidence` against threshold. |
| **Configuration** | `ATLAS_MIN_CONFIDENCE = 0.30`. |
| **Failure response** | REJECTED with `ATLAS_RISK_REASON_LOW_CONFIDENCE`. |

### 6.8 — Cooldown Period

| Attribute | Value |
|-----------|-------|
| **Purpose** | Enforce a waiting period after losses. |
| **Calculation** | `if (TimeCurrent() < cooldown_until) → reject` |
| **Configuration** | 30 minutes (1800 seconds) after 3 consecutive losses. |
| **Failure response** | REJECTED with `ATLAS_RISK_REASON_COOLDOWN`. |

### 6.9 — Kill Switch (Emergency Stop)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Non-bypassable emergency stop. Closes all positions and blocks all new trades. |
| **Calculation** | Triggered by: daily drawdown ≥ limit, absolute drawdown ≥ 8%, consecutive losses ≥ 5, or manual trigger. |
| **Configuration** | Hard-coded thresholds. |
| **Failure response** | REJECTED with `ATLAS_RISK_REASON_KILLSWITCH` for all trades until daily reset. |

### 6.10 — Session Restrictions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Avoid trading in low-liquidity sessions (future phase). |
| **Calculation** | Check `MarketState.session_state`. |
| **Configuration** | Not enforced in this phase (informational only). |
| **Failure response** | None in this phase. |

### 6.11 — Weekend Restrictions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Avoid holding positions over the weekend (future phase). |
| **Calculation** | Check day_of_week. |
| **Configuration** | Not enforced in this phase. |
| **Failure response** | None in this phase. |

### 6.12 — Volatility Restrictions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Avoid trading in fast markets (informational — passed to strategies via MarketState). |
| **Calculation** | `MarketState.is_fast_market` flag. |
| **Configuration** | `fast_market_atr_mult = 2.5`. |
| **Failure response** | NOT a rejection. The Risk Engine does NOT reject based on fast market — strategies decide how to react. |

### 6.13 — Spread Restrictions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Avoid trading when spread is too wide (future phase — currently handled by MarketEngine tick validation). |
| **Calculation** | Compare spread against `max_spread_points`. |
| **Configuration** | `max_spread_points = 50.0`. |
| **Failure response** | Not a Risk Engine rejection in this phase (MarketEngine invalidates the tick). |

### 6.14 — Manual Override

| Attribute | Value |
|-----------|-------|
| **Purpose** | Allow the operator to manually trigger the kill switch. |
| **Calculation** | External call to `RiskEngine::TriggerKillSwitch(reason)`. |
| **Configuration** | N/A. |
| **Failure response** | Kill switch activates. All trades rejected until daily reset. |

---

# 7. Kill Switch

### 7.1 — Activation

The kill switch is activated by:
1. Daily drawdown ≥ `max_daily_drawdown_pct` (5.0%)
2. Absolute drawdown ≥ `ATLAS_KILL_SWITCH_DRAWDOWN` (8.0%)
3. Consecutive losses ≥ `ATLAS_KILL_SWITCH_LOSSES` (5)
4. Manual trigger via `RiskEngine::TriggerKillSwitch(reason)`

Activation is IDEMPOTENT — activating when already active is a no-op.

### 7.2 — Propagation

On activation:
1. `IContextStore::ActivateKillSwitch(reason)` — sets the flag on context.
2. `IBrokerAdapter::CloseAllPositionsForMagic(reason)` — closes all open positions.
3. `IEventBus::EmitPriorityEvent(EV_KILL_SWITCH_ACTIVATED)` — notifies all modules.

### 7.3 — Persistence

The kill switch state (`active`, `reason`, `time`) is persisted in context snapshots. On restart, if the snapshot has `kill_switch_active == true`, the kill switch remains active.

### 7.4 — Manual Reset

The kill switch can only be deactivated by:
1. `RiskEngine::ResetDailyLimits()` — called on new trading day.
2. `KillSwitchManager.Deactivate()` — called by daily reset.

There is NO runtime manual reset. The operator must wait for the next trading day or restart the EA after fixing the configuration.

### 7.5 — Automatic Restrictions

While the kill switch is active:
- ALL `EvaluateRisk` calls return REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`.
- No checks run (kill switch is checked FIRST).
- No positions can be opened.
- All existing positions were closed on activation.

### 7.6 — Recovery

Recovery happens automatically on the next trading day:
1. `CoreEngine::CheckDailyReset()` detects a new day.
2. Calls `RiskEngine::ResetDailyLimits()`.
3. `ResetDailyLimits` calls `KillSwitchManager.Deactivate()`.
4. Kill switch flag is cleared on context.
5. Trading resumes (if all other checks pass).

### 7.7 — Logging

| Event | Level | Message |
|-------|-------|---------|
| Activation | FATAL | "*** KILL SWITCH ACTIVATED *** {reason}" |
| Close attempt | INFO | "Closing {N} positions for magic {M}" |
| Close failure | ERROR | "Failed to close position {ticket}: {retcode}" |
| Deactivation | INFO | "Kill switch deactivated (was: {reason})" |
| Rejection while active | DEBUG | "Trade rejected: kill switch active" |

### 7.8 — State Transitions

```
    INACTIVE ──activation──► ACTIVE ──daily reset──► INACTIVE
         ▲                      │
         │                      │ (idempotent)
         └──────────────────────┘
```

### 7.9 — Priority

The kill switch check is the FIRST check in `EvaluateRisk`. It has ABSOLUTE priority over all other checks. No configuration, no override, no bypass.

---

# 8. Position Limits

### 8.1 — Maximum Concurrent Trades

| Attribute | Value |
|-----------|-------|
| **Limit** | `ATLAS_MAX_POSITIONS = 64` (compile-time). |
| **Enforcement** | ExposureManager checks `IBrokerAdapter::CountPositionsForMagic()`. |
| **Breach response** | REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |

### 8.2 — Maximum Symbol Exposure

| Attribute | Value |
|-----------|-------|
| **Limit** | `max_exposure_limit = 0.20` (20% of equity). |
| **Enforcement** | ExposureManager computes `(volume × contract_size) / equity`. |
| **Breach response** | REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |

### 8.3 — Maximum Account Exposure

Same as 8.2 — the EA trades a single symbol, so symbol exposure = account exposure.

### 8.4 — Maximum Direction Exposure

| Attribute | Value |
|-----------|-------|
| **Limit** | Not enforced in this phase. Future phase may add directional bias limits. |
| **Enforcement** | None. |
| **Breach response** | None. |

### 8.5 — Hedging Policy

| Attribute | Value |
|-----------|-------|
| **Policy** | Hedging is NOT prevented by the Risk Engine. If the broker allows hedging and two strategies produce opposite votes, both may be approved (subject to exposure limits). |
| **Enforcement** | None in this phase. |

### 8.6 — Scaling Policy

| Attribute | Value |
|-----------|-------|
| **Policy** | No scaling in this phase. Each approved trade is a single market order. |
| **Enforcement** | None. |

### 8.7 — Partial Close Interaction

| Attribute | Value |
|-----------|-------|
| **Policy** | The Risk Engine does not manage partial closes. The TradeManager tracks position state; the Risk Engine only reads position count and volume. |
| **Enforcement** | None. |

---

# 9. Volatility Protection

### 9.1 — ATR Filters

| Attribute | Value |
|-----------|-------|
| **Purpose** | The Risk Engine does NOT apply ATR filters. ATR is used by strategies for SL/TP calculation and by the MarketEngine for feature extraction. |
| **Enforcement** | None by Risk Engine. |

### 9.2 — Fast Market Detection

| Attribute | Value |
|-----------|-------|
| **Purpose** | The `MarketState.is_fast_market` flag is informational. |
| **Enforcement** | The Risk Engine does NOT reject based on fast market. Strategies decide how to react. |
| **Future** | A future phase may add a "fast market" risk rule that reduces approved volume. |

### 9.3 — Spread Spikes

| Attribute | Value |
|-----------|-------|
| **Purpose** | Spread spikes are detected by the MarketEngine's TickValidator (rejects ticks with spread > `max_spread_points`). |
| **Enforcement** | The Risk Engine does not see ticks with excessive spread — they are invalidated upstream. |

### 9.4 — Price Gaps

| Attribute | Value |
|-----------|-------|
| **Purpose** | Gap detection is not implemented in this phase. |
| **Future** | A future phase may compare the current price to the previous bar's close and reject if the gap exceeds a threshold. |

### 9.5 — Low Liquidity

| Attribute | Value |
|-----------|-------|
| **Purpose** | Low liquidity is indirectly detected via spread spikes and session state. |
| **Enforcement** | None by Risk Engine in this phase. |

### 9.6 — High Impact Sessions

| Attribute | Value |
|-----------|-------|
| **Purpose** | Session state is available via `MarketState.session_state`. |
| **Enforcement** | Not enforced in this phase. Future phase may restrict trading during OFF sessions. |

### 9.7 — News Mode Compatibility

| Attribute | Value |
|-----------|-------|
| **Purpose** | News filtering is not implemented. |
| **Future** | A future phase may integrate an economic calendar. |

---

# 10. Cooldown System

### 10.1 — Per Strategy Cooldown

| Attribute | Value |
|-----------|-------|
| **Purpose** | Not implemented in this phase. All cooldowns are global. |
| **Future** | Per-strategy cooldown after consecutive strategy-specific failures. |

### 10.2 — Global Cooldown

| Attribute | Value |
|-----------|-------|
| **Purpose** | After 3 consecutive losses, enforce a 30-minute cooldown on ALL trading. |
| **Trigger** | `consecutive_losses >= 3` (checked in `UpdateRiskState`). |
| **Duration** | 1800 seconds (30 minutes). |
| **Enforcement** | `CooldownManager.IsCooldownActive()` returns true if `TimeCurrent() < cooldown_until`. |
| **Breach response** | REJECTED with `ATLAS_RISK_REASON_COOLDOWN`. |

### 10.3 — Loss Cooldown

Same as 10.2 — the only cooldown in this phase is the loss-based global cooldown.

### 10.4 — Manual Cooldown

Not implemented. The operator can only trigger the kill switch (which is stricter than a cooldown).

### 10.5 — Expiration

The cooldown expires automatically when `TimeCurrent() >= cooldown_until`. No action needed — the `IsCooldownActive` check simply returns false.

### 10.6 — Persistence

The `cooldown_until` timestamp is persisted in context snapshots. On restart, if the cooldown has not expired, it remains in effect.

### 10.7 — Reset Conditions

The cooldown is reset by:
1. `ResetDailyLimits()` — called on new trading day.
2. Cooldown expiration (natural).
3. A successful fill (resets `consecutive_losses` to 0, but does NOT clear `cooldown_until` — the cooldown must expire naturally).

---

# 11. Decision Logic

### 11.1 — APPROVED

| Attribute | Value |
|-----------|-------|
| **Conditions** | Kill switch inactive AND vote valid AND confidence ≥ 0.30 AND drawdown < 5% AND exposure ≤ 20% AND margin level ≥ 200% AND cooldown inactive AND consecutive losses < 5. |
| **Priority** | Lowest — only reached if all checks pass. |
| **Side effects** | None on context (the trade hasn't executed). Statistics counter incremented. |
| **Logging** | DEBUG: "Decision APPROVED: vol={v} dir={d} conf={c}". |
| **RiskState updates** | None. State updates happen on fill (`UpdateRiskState`). |

### 11.2 — REJECTED

| Attribute | Value |
|-----------|-------|
| **Conditions** | Any check fails. The reason_code identifies which check. |
| **Priority** | Highest — rejection can happen at any stage. |
| **Side effects** | If the rejection is due to drawdown or consecutive losses, the kill switch is activated. Statistics counter incremented. |
| **Logging** | DEBUG for normal rejections (cooldown, low confidence). WARN for serious rejections (exposure, margin). FATAL for kill switch. |
| **RiskState updates** | Drawdown percentage is updated (even on rejection). Peak equity is updated. Exposure is NOT updated (no trade was placed). |

### 11.3 — DEFERRED

| Attribute | Value |
|-----------|-------|
| **Conditions** | Not used in this phase. Reserved for future use (e.g., waiting for better entry price). |
| **Priority** | N/A. |
| **Side effects** | None. |
| **Logging** | N/A. |
| **RiskState updates** | None. |

---

# 12. Performance Budget

### 12.1 — Maximum Evaluation Time

| Stage | Budget |
|-------|--------|
| Kill switch check | 0.001 ms |
| Vote validation | 0.005 ms |
| Drawdown check | 0.01 ms |
| Exposure check | 0.05 ms (O(N) positions) |
| Margin check | 0.01 ms |
| Cooldown check | 0.005 ms |
| Decision construction | 0.01 ms |
| Decision validation | 0.005 ms |
| Statistics update | 0.005 ms |
| **Total** | **≤ 1 ms** |

### 12.2 — Maximum Checks

9 checks per `EvaluateRisk` call (kill switch, vote valid, confidence, drawdown, exposure, margin, cooldown, consecutive losses, decision validation).

### 12.3 — Memory Budget

- Total memory: stack-allocated only. No heap allocation in the hot path.
- `RiskStatistics`: ~128 bytes (counters).
- Local variables: ~64 bytes.
- Total: ~200 bytes stack.

### 12.4 — Fixed Arrays Only

All arrays are fixed-size. No dynamic arrays. No `ArrayResize()` in the hot path.

### 12.5 — No Dynamic Allocation

`new` and `delete` are FORBIDDEN inside `EvaluateRisk`.

### 12.6 — Maximum History

The Risk Engine does not maintain historical data in this phase. All state is current (on context) or computed on-demand (exposure from broker).

### 12.7 — Maximum Counters

`RiskStatistics` has 10 reason-code counters + 8 aggregate counters = 18 `ulong` values = 144 bytes.

---

# 13. Metrics

The `RiskStatistics` component collects:

### 13.1 — Decision Counts

| Metric | Type | Description |
|--------|------|-------------|
| `total_decisions` | `ulong` | Total `EvaluateRisk` calls. |
| `approved` | `ulong` | Decisions with status APPROVED. |
| `rejected` | `ulong` | Decisions with status REJECTED. |
| `deferred` | `ulong` | Decisions with status DEFERRED (always 0 in this phase). |

### 13.2 — Rates

| Metric | Computation |
|--------|-------------|
| `approval_rate` | `approved / total_decisions` |
| `reject_rate` | `rejected / total_decisions` |
| `modify_rate` | 0 (no modifications in this phase) |

### 13.3 — Kill Switch

| Metric | Type | Description |
|--------|------|-------------|
| `kill_switch_activations` | `ulong` | Total times the kill switch was activated. |

### 13.4 — Latency

| Metric | Type | Description |
|--------|------|-------------|
| `total_latency_ms` | `double` | Sum of all evaluation latencies. |
| `peak_latency_ms` | `double` | Maximum single-evaluation latency. |
| `average_latency_ms` | `double` | `total_latency_ms / total_decisions`. |

### 13.5 — Rule Hit Frequency

| Metric | Type | Description |
|--------|------|-------------|
| `per_reason_count[10]` | `ulong[10]` | Count per reason code (0=OK, 1=DRAWDOWN, ..., 9=LOW_CONFIDENCE). |

### 13.6 — Exposure History

Not tracked in this phase. Future phase may add a rolling exposure history for trend analysis.

### 13.7 — Risk Utilization

| Metric | Computation |
|--------|-------------|
| `exposure_utilization` | `current_exposure_pct / max_exposure_limit` (computed on demand). |
| `drawdown_utilization` | `daily_drawdown_pct / max_daily_drawdown_pct` (computed on demand). |

---

# 14. Logging

All logging through `ILogger`. `Print()` is FORBIDDEN.

### 14.1 — Log Categories

| Level | Category | When |
|-------|----------|------|
| **DEBUG** | Decision approved | "Decision APPROVED: vol={v} dir={d}" |
| **DEBUG** | Decision rejected (normal) | "Rejected: {reason_code} {reason}" |
| **DEBUG** | Kill switch skip | "EvaluateRisk skipped: kill switch active" |
| **DEBUG** | Cooldown active | "Cooldown active: {seconds_remaining}s" |
| **INFO** | Initialization | "RiskEngine initialized" |
| **INFO** | Shutdown | "RiskEngine shutdown" |
| **INFO** | Daily reset | "Daily limits reset: start_equity={e}" |
| **INFO** | Exposure update | "Exposure: {pct}% Floating PnL: {pnl}" |
| **INFO** | Diagnostics summary | On `LogDiagnostics()` (heartbeat only) |
| **WARN** | Vote rejected (low confidence) | "Low confidence: {c} < {min}" |
| **WARN** | Vote rejected (no vote) | "Empty vote: direction={d} count={n}" |
| **WARN** | Exposure exceeded | "Exposure {pct}% > limit {limit}%" |
| **WARN** | Margin unsafe | "Margin level {level}% < min {min}%" |
| **WARN** | Drawdown warning | "Drawdown {pct}% approaching limit {limit}%" |
| **ERROR** | Context is NULL | "EvaluateRisk: context is NULL" |
| **ERROR** | Broker is NULL | "EvaluateRisk: broker adapter is NULL" |
| **ERROR** | Decision validation failed | "Decision invalid: {reason}" |
| **ERROR** | Close position failed | "Failed to close ticket {t}: retcode {r}" |
| **FATAL** | Kill switch activated | "*** KILL SWITCH ACTIVATED *** {reason}" |

### 14.2 — Hot Path Logging Policy

**No INFO/WARN/ERROR/FATAL logging inside `EvaluateRisk` on the success path.** Only DEBUG is allowed (and only if `config.log_level <= ATLAS_LOG_DEBUG`).

Rejections log at DEBUG for normal cases (cooldown, low confidence, no vote) and WARN for serious cases (exposure, margin). Kill switch activation logs at FATAL.

The heartbeat (`UpdateExposure`, `LogDiagnostics`) may log at INFO.

---

# 15. Edge Cases

| # | Edge Case | Engine Behavior |
|---|-----------|-----------------|
| EC1 | Invalid AggregatedVote (direction = NONE) | REJECTED with `ATLAS_RISK_REASON_NOVOTE`. |
| EC2 | Invalid AggregatedVote (vote_count = 0) | REJECTED with `ATLAS_RISK_REASON_NOVOTE`. |
| EC3 | Invalid AggregatedVote (confidence = NaN) | REJECTED with `ATLAS_RISK_REASON_INVALID`. |
| EC4 | Snapshot mismatch (vote.snapshot_id ≤ 0) | REJECTED with `ATLAS_RISK_REASON_INVALID`. |
| EC5 | Context is NULL | REJECTED with `ATLAS_RISK_REASON_NO_CONTEXT`. |
| EC6 | Broker adapter is NULL | REJECTED with `ATLAS_RISK_REASON_NO_CONTEXT`. |
| EC7 | Logger is NULL | Proceed with best-effort (no logging). Do NOT crash. |
| EC8 | Kill switch already active | Return REJECTED immediately. No side effects. |
| EC9 | Daily start equity ≤ 0 | Skip drawdown check. Log ERROR. |
| EC10 | Current equity ≤ 0 | Trigger kill switch. REJECTED. |
| EC11 | Margin ≤ 0 | Margin check passes (no existing margin). |
| EC12 | Contract size ≤ 0 | Exposure check fails. REJECTED with `ATLAS_RISK_REASON_EXPOSURE`. |
| EC13 | No open positions | Exposure = proposed_volume only. |
| EC14 | Consecutive losses = 3 | Set cooldown 30 min. REJECTED with `ATLAS_RISK_REASON_COOLDOWN`. |
| EC15 | Consecutive losses ≥ 5 | Trigger kill switch. REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`. |
| EC16 | Drawdown exactly at limit (5.0%) | Trigger kill switch. REJECTED. |
| EC17 | Drawdown > absolute limit (8.0%) | Trigger kill switch immediately. REJECTED. |
| EC18 | Margin level exactly at 200% | Margin check passes (≥ comparison). |
| EC19 | Margin level 199.9% | Margin check fails. REJECTED. |
| EC20 | Confidence exactly at 0.30 | Confidence check passes (≥ comparison). |
| EC21 | Confidence 0.299 | REJECTED with `ATLAS_RISK_REASON_LOW_CONFIDENCE`. |
| EC22 | Configuration corruption (max_exposure = 0) | Treat as 0% limit → all trades rejected. Log ERROR. |
| EC23 | Configuration corruption (max_drawdown = 0) | Treat as 0% limit → kill switch on first loss. Log ERROR. |
| EC24 | Recovery failure (snapshot load failed) | Start fresh. daily_start_equity = current equity. Kill switch = inactive. |
| EC25 | Kill switch close fails (OrderSend error) | Log ERROR. Kill switch remains active. Retry on next tick. |
| EC26 | Broker inconsistency (position count mismatch) | Use broker truth (QueryBrokerPositions). Log WARN. |
| EC27 | NaN in approved_volume | DecisionValidator catches it. Rebuild as REJECTED. |
| EC28 | Infinite value in equity | Treated as valid (very large equity). Proceed. |
| EC29 | Overflow in exposure calculation | Not possible (double has huge range). |
| EC30 | UpdateRiskState called with NULL event | Ignore silently. |

---

# 16. Validation Matrix

| Field | Validation | Severity | Action | Recovery |
|-------|------------|----------|--------|----------|
| `vote.direction` | Must be in {-1, 0, 1} | WARN | REJECTED (NOVOTE if 0, INVALID if other) | None |
| `vote.vote_count` | Must be > 0 | WARN | REJECTED (NOVOTE) | None |
| `vote.confidence` | Must not be NaN | WARN | REJECTED (INVALID) | None |
| `vote.confidence` | Must be ≥ 0.30 | DEBUG | REJECTED (LOW_CONFIDENCE) | None |
| `vote.snapshot_id` | Must be > 0 | WARN | REJECTED (INVALID) | None |
| `IsKillSwitchActive()` | Must be false | FATAL | REJECTED (KILLSWITCH) | Daily reset |
| `daily_start_equity` | Must be > 0 | ERROR | Skip drawdown check | Daily reset |
| `current_equity` | Must be > 0 | FATAL | Trigger kill switch | Daily reset |
| `daily_drawdown_pct` | Must be < 5.0% | FATAL | Trigger kill switch + REJECTED (DRAWDOWN) | Daily reset |
| `daily_drawdown_pct` | Must be < 8.0% | FATAL | Trigger kill switch + REJECTED (KILLSWITCH) | Daily reset |
| `current_exposure_pct` | Must be ≤ 20% | WARN | REJECTED (EXPOSURE) | None |
| `margin_level` | Must be ≥ 200% | WARN | REJECTED (MARGIN) | None |
| `consecutive_losses` | Must be < 5 | FATAL | Trigger kill switch + REJECTED (KILLSWITCH) | Daily reset |
| `cooldown_until` | Must be ≤ TimeCurrent() | DEBUG | REJECTED (COOLDOWN) | Cooldown expiration |
| `approved_volume` | Must be > 0 | ERROR | Rebuild as REJECTED (INVALID) | None |
| `approved_price` | Must be > 0 | ERROR | Rebuild as REJECTED (INVALID) | None |
| `approved_sl` | Must be > 0 | ERROR | Rebuild as REJECTED (INVALID) | None |
| `approved_tp` | Must be > 0 | ERROR | Rebuild as REJECTED (INVALID) | None |
| `decision_id` | Must be non-empty | ERROR | Rebuild as REJECTED (INVALID) | None |
| `snapshot_id` (in decision) | Must match vote | ERROR | Rebuild as REJECTED (INVALID) | None |

---

# 17. State Machine

The Risk Engine itself does not have a complex state machine — it is stateless between calls (all state lives on context). However, each `EvaluateRisk` call transitions through the following internal states:

```
    READY (entry)
       │
       ▼
    [Kill switch check]
       │
       ├── active ──► KILL_SWITCH ──► return REJECTED
       │
       ▼ (inactive)
    [Vote validation]
       │
       ├── invalid ──► REJECTED (NOVOTE / INVALID)
       │
       ▼ (valid)
    [Confidence check]
       │
       ├── low ──► REJECTED (LOW_CONFIDENCE)
       │
       ▼ (sufficient)
    [Drawdown check]
       │
       ├── breach ──► KILL_SWITCH ──► return REJECTED (DRAWDOWN)
       │
       ▼ (within limit)
    [Exposure check]
       │
       ├── exceeded ──► REJECTED (EXPOSURE)
       │
       ▼ (within limit)
    [Margin check]
       │
       ├── unsafe ──► REJECTED (MARGIN)
       │
       ▼ (safe)
    [Cooldown check]
       │
       ├── active ──► REJECTED (COOLDOWN)
       │
       ▼ (inactive)
    [Consecutive loss check]
       │
       ├── ≥ 5 ──► KILL_SWITCH ──► return REJECTED (KILLSWITCH)
       │
       ▼ (< 5)
    EVALUATING (all checks passed)
       │
       ▼
    [Build decision]
       │
       ▼
    [Validate decision]
       │
       ├── invalid ──► ERROR ──► rebuild as REJECTED
       │
       ▼ (valid)
    APPROVED ──► return RiskDecision(status=APPROVED)
```

### State Definitions

| State | Description | Entry | Exit |
|-------|-------------|-------|------|
| **READY** | Initial state, received vote. | Method entry. | First check. |
| **EVALUATING** | All checks passed, building decision. | Last check passed. | Decision built. |
| **APPROVED** | Decision built and validated as approved. | DecisionValidator passes. | Return. |
| **REJECTED** | A check failed (non-kill-switch). | Any check fails (except kill switch). | Return. |
| **KILL_SWITCH** | Kill switch is active or was triggered. | Kill switch check returns true, or drawdown/loss threshold breached. | Return. |
| **ERROR** | Decision construction produced invalid output. | DecisionValidator fails. | Rebuild as REJECTED. |
| **RECOVERING** | Not applicable to Risk Engine (stateless between calls). | N/A. | N/A. |

---

# 18. Security Constraints

### 18.1 — Risk Engine is the Final Authority

No order may be sent to the broker without an APPROVED `RiskDecision` from the Risk Engine. The `PhaseScheduler` in CoreEngine checks `decision.status == ATLAS_DECISION_APPROVED` before passing to ExecutionEngine.

### 18.2 — Execution Engine Cannot Override

The ExecutionEngine receives an approved `RiskDecision` and builds an `OrderRequest`. It may reject the decision (e.g., idempotency check fails, volume normalization fails), but it may NEVER approve a trade that the Risk Engine rejected.

### 18.3 — Strategy Engine Cannot Override

The StrategyEngine produces votes. It has no authority to approve or execute trades. Its votes are inputs to the Risk Engine, not commands.

### 18.4 — Core Engine Cannot Override

The CoreEngine orchestrates the pipeline but does NOT evaluate risk. It may trigger the kill switch (via `KillSwitchPropagator`), which makes the Risk Engine reject everything — but the CoreEngine may NEVER force the Risk Engine to approve a trade.

### 18.5 — No Module May Bypass the Risk Engine

There is no "back door" to send orders. The `IBrokerAdapter::SendOrder()` method is only called from `PhaseScheduler::RunPipeline()` after the Risk Engine approves. No other code path calls `SendOrder()` (except `KillSwitchManager` for closing positions — which is a risk action, not a trade entry).

### 18.6 — Kill Switch is Non-Bypassable

The kill switch check is the FIRST operation in `EvaluateRisk`. It returns immediately if active. No configuration, no override, no bypass. The only way to clear it is `ResetDailyLimits()` on a new trading day.

### 18.7 — Kill Switch Cannot Be Disabled at Runtime

There is no runtime API to deactivate the kill switch. The operator must:
1. Wait for the next trading day (automatic reset), OR
2. Restart the EA after fixing the configuration.

---

# 19. Production Checklist

### 19.1 — Contract Alignment

- [ ] `RiskDecision` struct fields match `Contracts/RiskDecision.mqh` exactly (12 fields).
- [ ] `AggregatedVote` struct consumed from `Contracts/RiskDecision.mqh`.
- [ ] `ExecutionEvent` struct consumed from `Contracts/Events.mqh`.
- [ ] `IRiskEvaluator` interface methods match exactly (7 methods: `EvaluateRisk`, `UpdateRiskState`, `UpdateExposure`, `ResetDailyLimits`, `TriggerKillSwitch`, `Initialize`, `Shutdown`).
- [ ] Constants: `ATLAS_KILL_SWITCH_DRAWDOWN`, `ATLAS_KILL_SWITCH_LOSSES`, `ATLAS_MIN_CONFIDENCE`, `ATLAS_MARGIN_LEVEL_MIN`, all `ATLAS_RISK_REASON_*` codes.

### 19.2 — Dependency Alignment

- [ ] `ILogger` available.
- [ ] `IContextStore` available (for risk state).
- [ ] `IBrokerAdapter` available (for account/position queries + position closing).
- [ ] `IEventBus` available (for kill switch event emission).
- [ ] `AtlasConfig` available (for thresholds).
- [ ] NO dependency on `IMarketDataSource`, `IStrategySet`, `IOrderBuilder` (the Risk Engine must NOT know about market/strategy/execution internals).

### 19.3 — File Structure

- [ ] Main file: `Engines/RiskEngine.mqh` (implements `IRiskEvaluator`).
- [ ] Internal helpers under `Engines/RiskEngine/`:
  - `DrawdownManager.mqh`
  - `ExposureManager.mqh`
  - `MarginManager.mqh`
  - `KillSwitchManager.mqh`
  - `CooldownManager.mqh`
  - `DecisionBuilder.mqh`
  - `DecisionValidator.mqh`
  - `RiskStatistics.mqh`

### 19.4 — Performance Verification

- [ ] No `new` or `delete` in `EvaluateRisk`.
- [ ] No `Print()` anywhere.
- [ ] No direct `AccountInfo*` calls (must use `IBrokerAdapter`).
- [ ] No direct `PositionGet*` calls (must use `IBrokerAdapter`).
- [ ] No direct `OrderSend` calls (must use `IBrokerAdapter::CloseAllPositionsForMagic` for kill switch).
- [ ] No direct `SymbolInfo*` calls (must use `IBrokerAdapter`).
- [ ] No file I/O.
- [ ] No recursion.
- [ ] All arrays fixed-size.
- [ ] Total stack usage < 1 KB.
- [ ] Total evaluation time ≤ 1 ms.

### 19.5 — MQL5 Compliance

- [ ] Include guards on every file.
- [ ] No `#pragma once`.
- [ ] No `->` (use `.`).
- [ ] No STL.
- [ ] No dynamic arrays in structs.

### 19.6 — Kill Switch Verification

- [ ] Kill switch check is FIRST in `EvaluateRisk`.
- [ ] Kill switch is NON-BYPASSABLE (no configuration can skip it).
- [ ] Kill switch activation is idempotent.
- [ ] Kill switch closes all positions via `IBrokerAdapter::CloseAllPositionsForMagic`.
- [ ] Kill switch emits `EV_KILL_SWITCH_ACTIVATED` as a priority event.
- [ ] Kill switch can only be cleared by `ResetDailyLimits`.

### 19.7 — Error Handling

- [ ] NULL pointer checks on all dependencies.
- [ ] NaN checks on all double inputs.
- [ ] Array bounds checks.
- [ ] All edge cases from Section 15 covered.

### 19.8 — Documentation

- [ ] Doxygen comments on every class.
- [ ] Doxygen comments on every public method.
- [ ] Doxygen comments on every public member.
- [ ] Every file has a header comment block.

### 19.9 — Integration Points

- [ ] `RiskEngine::SetDependencies()` matches what CoreEngine will call.
- [ ] `EvaluateRisk()` return value is a `RiskDecision` (not a pointer).
- [ ] `UpdateRiskState()` is called by CoreEngine on `EV_TRADE_EXECUTED`.
- [ ] `UpdateExposure()` is called by CoreEngine on heartbeat.
- [ ] `ResetDailyLimits()` is called by CoreEngine on new trading day.
- [ ] `TriggerKillSwitch()` is callable by CoreEngine (manual override).

### 19.10 — Versioning

- [ ] File header: `AtlasEA v0.1.3.0` (Risk Engine phase).
- [ ] All internal components reference the same version.

---

**End of Specification.**

This document is implementation-ready. GLM can implement the entire Risk Engine from this specification alone without making any architectural decisions. All design choices are fixed. All edge cases are enumerated. All validation rules are specified. All performance budgets are defined. The kill switch is non-bypassable. The Risk Engine is the final authority on every trade.
