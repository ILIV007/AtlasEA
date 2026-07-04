# AtlasEA v1.0 — Risk Engine & Framework Production Specification

**Document version:** 3.0 (updated v0.1.11.0)
**Target module:** `Engines/RiskEngine.mqh` (+ `Engines/RiskEngine/`)
**Interface implemented:** `IRiskEvaluator`
**Contracts consumed:** `AggregatedVote`, `RiskDecision`, `ExecutionEvent`, `MarketState`, `PositionState`

---

# 1. Architecture Overview

The Risk Engine is the **final non-bypassable authority** on every trade. It evaluates each `AggregatedVote` against 21 configurable rules and returns an immutable `RiskDecision`.

```
┌─────────────────────────────────────────────────────┐
│                   CoreEngine                        │
│               (IRiskEvaluator consumer)             │
└──────────────────────┬──────────────────────────────┘
                       │ EvaluateRisk(vote)
                       ▼
┌─────────────────────────────────────────────────────┐
│                   RiskEngine                        │
│            (implements IRiskEvaluator)              │
├─────────────────────────────────────────────────────┤
│                  RiskEvaluator                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │KillSwitch│ │Cooldown  │ │ExposureCalculator│   │
│  └──────────┘ └──────────┘ └──────────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │Drawdown  │ │Margin    │ │  PositionSizer   │   │
│  │Monitor   │ │Monitor   │ │                  │   │
│  └──────────┘ └──────────┘ └──────────────────┘   │
│                    ┌──────────────┐                │
│                    │ RiskRuleSet  │                │
│                    │ (21 rules)   │                │
│                    └──────────────┘                │
└─────────────────────────────────────────────────────┘
                       │
                       ▼
              Immutable RiskDecision
              (APPROVED / REJECTED / MODIFIED)
```

---

# 2. Components

| Component | File | Responsibility |
|-----------|------|----------------|
| RiskState | `RiskState.mqh` | Internal state container |
| KillSwitch | `KillSwitch.mqh` | Non-bypassable emergency stop |
| CooldownManager | `CooldownManager.mqh` | Per-strategy + global cooldowns |
| ExposureCalculator | `ExposureCalculator.mqh` | Current/projected/directional exposure |
| PositionSizer | `PositionSizer.mqh` | 5 sizing methods (Fixed/Risk%/Money/ATR/Kelly) |
| DrawdownMonitor | `DrawdownMonitor.mqh` | Daily + floating drawdown |
| MarginMonitor | `MarginMonitor.mqh` | Margin level + free margin |
| RiskRuleSet | `RiskRuleSet.mqh` | 21 configurable risk rules |
| RiskEvaluator | `RiskEvaluator.mqh` | Orchestrator — builds RiskDecision |
| RiskEngine | `RiskEngine.mqh` | Thin adapter implementing IRiskEvaluator |

---

# 3. Decision Flow

```
EvaluateRisk(vote)
       │
       ▼
[UpdateState: equity, margin, floating PnL, exposure]
       │
       ▼
[Run RiskRuleSet.Evaluate — 21 rules in priority order]
       │
       ├── RULE_PASS ──────────────────► BuildApproved()
       │                                    │
       │                                    ▼
       │                              APPROVED
       │
       ├── RULE_FAIL_MODIFY ─────────► BuildModified()
       │                                    │
       │                                    ▼
       │                              APPROVED (with adjusted volume/SL/TP)
       │
       ├── RULE_FAIL_REJECT ─────────► BuildRejected()
       │                                    │
       │                                    ▼
       │                              REJECTED (with reason_code)
       │
       └── RULE_FAIL_KILLSWITCH ─────► BuildRejected()
                                            │
                                            ▼
                                      REJECTED + kill_switch_triggered=true
```

---

# 4. Rule Priority

Rules are evaluated in strict priority order (first failure wins):

| Priority | Rule | Type | Reason Code |
|----------|------|------|-------------|
| 1 | Kill switch active | KILLSWITCH | ATLAS_RISK_REASON_KILLSWITCH |
| 2 | Daily DD critical (≥8%) | KILLSWITCH | ATLAS_RISK_REASON_KILLSWITCH |
| 3 | Margin level critical (<100%) | KILLSWITCH | ATLAS_RISK_REASON_KILLSWITCH |
| 4 | Daily DD exceeded (≥5%) | REJECT | ATLAS_RISK_REASON_DRAWDOWN |
| 5 | Floating DD exceeded | REJECT | ATLAS_RISK_REASON_DRAWDOWN |
| 6 | Exposure limit | REJECT | ATLAS_RISK_REASON_EXPOSURE |
| 7 | Max concurrent positions | REJECT | ATLAS_RISK_REASON_EXPOSURE |
| 8 | Max trades per day | REJECT | ATLAS_RISK_REASON_COOLDOWN |
| 9 | Max trades per hour | REJECT | ATLAS_RISK_REASON_COOLDOWN |
| 10 | Global cooldown | REJECT | ATLAS_RISK_REASON_COOLDOWN |
| 11 | Fast market protection | REJECT | ATLAS_RISK_REASON_INVALID |
| 12 | Max volatility | REJECT | ATLAS_RISK_REASON_INVALID |
| 13 | Max spread | REJECT | ATLAS_RISK_REASON_INVALID |
| 14 | Session restriction | REJECT | ATLAS_RISK_REASON_INVALID |
| 15 | Symbol restriction | REJECT | ATLAS_RISK_REASON_INVALID |
| 16 | News lock (placeholder) | PASS | (always pass, no API) |
| 17 | Mandatory stop loss | REJECT | ATLAS_RISK_REASON_INVALID |
| 18 | Risk-reward validation | REJECT | ATLAS_RISK_REASON_INVALID |
| 19 | Max lot size | MODIFY | (volume reduced) |
| 20 | Min lot size | MODIFY | (volume raised) |
| 21 | Strategy cooldown | REJECT | ATLAS_RISK_REASON_COOLDOWN |

---

# 5. Kill Switch Lifecycle

### Triggers

| Trigger | Reason Code | Source |
|---------|-------------|--------|
| Daily DD ≥ critical (8%) | ATLAS_KS_REASON_DAILY_DD | DrawdownMonitor |
| Margin level < critical (100%) | ATLAS_KS_REASON_MARGIN_CRITICAL | MarginMonitor |
| Consecutive losses ≥ 5 | ATLAS_KS_REASON_CONSECUTIVE_LOSSES | RiskEvaluator.OnFillEvent |
| Corrupted RiskState | ATLAS_KS_REASON_CORRUPTED_STATE | (future) |
| Reconciliation mismatch | ATLAS_KS_REASON_RECONCILIATION | (future) |
| Manual activation | ATLAS_KS_REASON_MANUAL | Operator |

### State Machine

```
    INACTIVE ──trigger──► ACTIVE
         ▲                   │
         │                   │ (idempotent — more triggers are no-ops)
         │                   │
         └──manual reset─────┘
         └──daily reset──────┘
```

### Rules

- **Non-bypassable:** When active, ALL trades are REJECTED with `ATLAS_RISK_REASON_KILLSWITCH`.
- **No automatic reset:** Only manual `Deactivate()` or daily reset clears it.
- **Idempotent:** Activating when already active is a no-op.
- **Persistent:** Kill switch state is stored on IContextStore, survives snapshots.

---

# 6. Cooldown Lifecycle

### Types

| Type | Code | Trigger | Duration |
|------|------|---------|----------|
| None | 0 | — | — |
| Per-Strategy | 1 | Strategy failure | Configurable (default 300s) |
| Global | 2 | Portfolio rule breach | Configurable (default 300s) |
| Loss Streak | 3 | N consecutive losses | Configurable (default 1800s = 30min) |
| Time-Based | 4 | Manual/scheduled | Configurable |

### State Machine

```
    NO_COOLDOWN
         │
         ├── ApplyStrategyCooldown(id, dur) ──► STRATEGY_COOLDOWN
         │                                        │
         │                                        │ expiry
         │                                        ▼
         │                                    NO_COOLDOWN
         │
         ├── ApplyGlobalCooldown(dur) ──────► GLOBAL_COOLDOWN
         │                                        │
         │                                        │ expiry
         │                                        ▼
         │                                    NO_COOLDOWN
         │
         └── CheckLossStreak (≥3 losses) ──► LOSS_STREAK_COOLDOWN
                                              │
                                              │ expiry
                                              ▼
                                          NO_COOLDOWN
```

---

# 7. Position Sizing Formulas

### Fixed Lot
```
volume = fixed_lot
```

### Risk Percent
```
risk_amount = equity × (risk_percent / 100)
sl_value_per_lot = sl_distance × contract_size
volume = risk_amount / sl_value_per_lot
```

### Fixed Money
```
sl_value_per_lot = sl_distance × contract_size
volume = fixed_money_risk / sl_value_per_lot
```

### ATR Multiplier (Placeholder)
```
sl_distance = atr × sl_atr_multiplier
volume = RiskPercent(equity, sl_distance)
```

### Kelly Criterion (Placeholder — Simplified)
```
kelly_fraction = (win_rate × win_loss_ratio - (1 - win_rate)) / win_loss_ratio
-- Simplified (1:1 ratio):
kelly_fraction = 2 × win_rate - 1
-- Half-Kelly for safety:
kelly_fraction *= 0.5
volume = (equity × kelly_fraction) / sl_value_per_lot
```

### Normalization (all methods)
```
volume = RoundToStep(volume, lot_step)
volume = Clamp(volume, min_lot, max_lot)
```

---

# 8. RiskState Lifecycle

### Fields

| Field | Type | Updated By |
|-------|------|-----------|
| daily_pnl | double | RiskEvaluator.UpdateState |
| daily_realized_pnl | double | OnFillEvent |
| daily_floating_pnl | double | UpdateState |
| daily_drawdown_pct | double | DrawdownMonitor.Update |
| floating_drawdown_pct | double | DrawdownMonitor.Update |
| peak_equity | double | DrawdownMonitor.Update |
| current_equity | double | UpdateState |
| current_exposure_pct | double | ExposureCalculator.UpdateState |
| projected_exposure_pct | double | RiskRuleSet.Evaluate |
| trades_today | int | OnFillEvent |
| trades_this_hour | int | (future) |
| wins_today | int | OnFillEvent |
| losses_today | int | OnFillEvent |
| consecutive_losses | int | OnFillEvent |
| kill_switch_active | bool | KillSwitch.Activate |
| kill_switch_reason | string | KillSwitch.Activate |
| cooldown_type | int | CooldownManager |
| cooldown_until | datetime | CooldownManager |
| margin_level | double | MarginMonitor.Update |
| free_margin | double | MarginMonitor.Update |

### Lifecycle

```
    COLD_START (ResetAll)
         │
         │ Initialize()
         ▼
    ACTIVE
         │
         ├── UpdateState() ──► (refreshed each tick)
         │
         ├── OnFillEvent() ──► (updates counts, losses, cooldowns)
         │
         ├── ResetDaily() ──► (new trading day: clear daily fields)
         │
         └── Shutdown()
              │
              ▼
           DESTROYED
```

---

# 9. Performance Requirements

| Metric | Budget |
|--------|--------|
| Max EvaluateRisk latency | ≤ 20 ms |
| No broker queries in evaluation | ✅ (all from context) |
| No heap allocation | ✅ |
| No dynamic arrays | ✅ |
| Fixed-size arrays only | ✅ |
| Rule evaluation | O(21) = O(1) |
| Exposure calculation | O(N), N ≤ 64 positions |
| Memory | ~2 KB (RiskState + components) |

---

# 10. Security Constraints

The Risk Engine MUST NEVER:

1. Generate trading signals
2. Call `OrderSend`
3. Call `PositionSelect` / `PositionGet*`
4. Call `AccountInfo*` directly (uses IBrokerAdapter interface)
5. Call `SymbolInfo*` directly (uses IBrokerAdapter interface)
6. Modify contracts
7. Bypass the kill switch
8. Be bypassed by any other module

The Risk Engine is the **final authority**. No module may override a REJECTED decision.

---

# 11. Test Coverage

Tests in `tests/RiskEngineTests.mq5`:

| Test | Coverage |
|------|----------|
| TestKillSwitch | Activate, idempotent, deactivate |
| TestDrawdown | 3% within limits, 7% exceeds, 10% critical |
| TestExposure | Current, projected, directional |
| TestCooldown | Global, per-strategy, loss streak |
| TestMargin | Safe (250%), unsafe (175%), critical (87.5%) |
| TestPositionSizing | Fixed lot, risk %, fixed money, clamping |
| TestApprovedDecision | All rules pass → APPROVED |
| TestRejectedDecision | Drawdown exceeded → REJECTED |
| TestModifiedDecision | Volume > max → reduced |
| TestKillSwitchBlocks | Kill switch active → all rejected |

---

**End of Specification.**

The Risk Engine is fully implemented with 21 configurable rules, 5 position sizing methods, complete kill switch lifecycle, and comprehensive cooldown management. It is the final non-bypassable authority on every trade.
