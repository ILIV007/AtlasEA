# AtlasEA v1.0 — MT5 Adapter Production Specification

**Document version:** 1.0
**Target module:** `Infrastructure/MT5Adapter.mqh` (+ internal helpers under `Infrastructure/MT5Adapter/`)
**Interface implemented:** `IBrokerAdapter` (defined in `Interfaces/IBrokerAdapter.mqh`)
**Contracts consumed:** `OrderRequest` (from `Contracts/RiskDecision.mqh`), `RawTick`, `MarketState`, `PositionState`, `PositionSnapshotEvent`, `ExecutionEvent`, `AtlasEvent` (from `Contracts/Events.mqh` and `Contracts/MarketState.mqh`)
**Constants available:**
- Fill status: `ATLAS_FILL_PENDING=0`, `ATLAS_FILL_FILLED=1`, `ATLAS_FILL_PARTIAL=2`, `ATLAS_FILL_REJECTED=3`, `ATLAS_FILL_TIMEOUT=4`
- Direction: `ATLAS_ORDER_BUY=1`, `ATLAS_ORDER_SELL=-1`
- Module ID: `ATLAS_MODULE_MT5=6`
- Config fields: `max_retries`, `retry_delay_ms`, `slippage_points`, `magic_number`, `symbol`

---

# 1. Responsibilities

The MT5 Adapter is the **sole boundary** between AtlasEA and the MetaTrader 5 terminal. Every broker API call (`SymbolInfoTick`, `OrderSend`, `PositionsTotal`, `PositionGet*`, `AccountInfoDouble`, `iATR`, `CopyBuffer`, etc.) MUST go through this module. No other module may call MT5 APIs directly. The adapter wraps these calls, adds retry logic, translates retcodes, and emits execution events onto the event bus.

### R1.1 — Tick Capture

| Attribute | Value |
|-----------|-------|
| **Purpose** | Capture the latest tick from the terminal and normalize it into a `RawTick` struct. |
| **Owner** | `TickCapture` (internal component) |
| **Inputs** | None (queries terminal via `SymbolInfoTick`) |
| **Outputs** | `RawTick` struct (bid, ask, last, volume, timestamp) |
| **Performance limits** | O(1), ≤ 0.05 ms. `SymbolInfoTick` is a terminal call — typically < 0.01 ms. |
| **Failure handling** | If `SymbolInfoTick` returns false, return a zeroed `RawTick` with `timestamp=0`. Log ERROR. |
| **Forbidden behaviors** | Must NOT cache ticks (always read fresh). Must NOT modify any market state. Must NOT call `OrderSend`. |

### R1.2 — Order Dispatch

| Attribute | Value |
|-----------|-------|
| **Purpose** | Send an `OrderRequest` to the broker via `OrderSend` with retry logic. |
| **Owner** | `OrderSender` (internal component) |
| **Inputs** | `const OrderRequest &req` (validated by ExecutionEngine) |
| **Outputs** | Boolean: filled (true) or rejected/timeout (false). Emits `ExecutionEvent` onto event bus. |
| **Performance limits** | Single attempt: ≤ 5 ms (broker round-trip). With retries: ≤ 50 ms (budget permitting). |
| **Failure handling** | Retryable errors (REQUOTE, PRICE_OFF, PRICE_CHANGED, TIMEOUT, CONNECTION): retry up to `max_retries`. Non-retryable: return false immediately. On all failures, emit `ExecutionEvent` with appropriate fill_status. |
| **Forbidden behaviors** | Must NOT modify the `OrderRequest`. Must NOT call `OrderSend` for any request not received via `SendOrder()`. Must NOT block indefinitely (Sleep is bounded by `retry_delay_ms × max_retries`). |

### R1.3 — Position Close (Kill Switch)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Close all open positions matching the EA's magic number. Used by the kill switch. |
| **Owner** | `OrderSender` (shared with order dispatch) |
| **Inputs** | `const string reason` (for broker comment) |
| **Outputs** | Integer: number of close orders submitted. |
| **Performance limits** | O(N) where N = open positions (≤ 64). Each close: ≤ 5 ms. Total: ≤ 320 ms (64 positions × 5 ms). |
| **Failure handling** | Per-position: if close fails, log ERROR and continue with next position. Does NOT abort the loop. |
| **Forbidden behaviors** | Must NOT close positions from other magic numbers. Must NOT open new positions. |

### R1.4 — Position Query

| Attribute | Value |
|-----------|-------|
| **Purpose** | Query all broker positions matching the EA's magic number and return them as a `PositionSnapshotEvent`. |
| **Owner** | `PositionQuery` (internal component) |
| **Inputs** | None (scans `PositionsTotal`) |
| **Outputs** | `PositionSnapshotEvent` (array of up to `ATLAS_MAX_POSITIONS` `PositionState` structs + count + timestamp) |
| **Performance limits** | O(N), N ≤ ATLAS_MAX_POSITIONS. ≤ 0.1 ms. |
| **Failure handling** | If a position select fails, skip it. If count exceeds capacity, truncate. |
| **Forbidden behaviors** | Must NOT include positions from other magic numbers. Must NOT include positions from other symbols (if config.symbol is set). |

### R1.5 — Account Query

| Attribute | Value |
|-----------|-------|
| **Purpose** | Query account properties (equity, balance, margin, margin level). |
| **Owner** | `AccountQuery` (internal component) |
| **Inputs** | None |
| **Outputs** | Double values: equity, balance, margin, margin level. |
| **Performance limits** | O(1) each. ≤ 0.01 ms. |
| **Failure handling** | If `AccountInfoDouble` returns 0, log WARN (may be legitimate if account has no margin). |
| **Forbidden behaviors** | Must NOT cache account values (always read fresh). |

### R1.6 — Symbol Query

| Attribute | Value |
|-----------|-------|
| **Purpose** | Query symbol properties (point, digits, bid, ask, volume min/max/step, stops level, contract size, filling mode). |
| **Owner** | `SymbolQuery` (internal component) |
| **Inputs** | None (uses `config.symbol`) |
| **Outputs** | Symbol properties as doubles/longs/ints. |
| **Performance limits** | O(1) each. ≤ 0.01 ms. |
| **Failure handling** | If `SymbolInfoDouble/Integer` returns 0 or fails, log WARN and return 0. |
| **Forbidden behaviors** | Must NOT cache (always read fresh — symbol properties can change). |

### R1.7 — Indicator Management

| Attribute | Value |
|-----------|-------|
| **Purpose** | Create, query, and release indicator handles (ATR, MA, RSI, MACD, Stochastic, CCI, ADX, Bollinger Bands). |
| **Owner** | `SymbolQuery` (shared — indicator ops are symbol-related) |
| **Inputs** | Indicator parameters (periods, methods, applied prices) |
| **Outputs** | Handle (int) on creation. Buffer data on `CopyBuffer`. Rates on `CopyRates`. |
| **Performance limits** | Handle creation: O(1) but may take 1-5 ms (terminal initializes indicator). `CopyBuffer`: O(count), ≤ 0.1 ms for small counts. |
| **Failure handling** | If handle creation returns `INVALID_HANDLE`, log ERROR and return `INVALID_HANDLE`. If `CopyBuffer` returns ≤ 0, log WARN and return 0. |
| **Forbidden behaviors** | Must NOT create duplicate handles without releasing. Must NOT call `CopyBuffer` on an invalid handle. |

### R1.8 — Trade Event Capture

| Attribute | Value |
|-----------|-------|
| **Purpose** | Handle the terminal's `OnTrade()` callback. Emit a trade-executed event onto the bus. |
| **Owner** | `TradeTransactionListener` (internal component) |
| **Inputs** | None (triggered by `OnTrade()`) |
| **Outputs** | `EV_TRADE_EXECUTED` event emitted as priority. |
| **Performance limits** | O(1) (just emit event). The actual position reconciliation happens in CoreEngine. |
| **Failure handling** | If event bus is NULL, log ERROR and return. |
| **Forbidden behaviors** | Must NOT do reconciliation itself (CoreEngine handles that). Must NOT call `OrderSend`. |

### R1.9 — Retcode Translation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Translate MT5 `MqlTradeResult.retcode` into AtlasEA `ATLAS_FILL_*` status. |
| **Owner** | `RetcodeTranslator` (internal component) |
| **Inputs** | `int retcode` (MT5 retcode) |
| **Outputs** | `int fill_status` (ATLAS_FILL_*), `bool is_retryable` |
| **Performance limits** | O(1) (switch statement) |
| **Failure handling** | Unknown retcodes → `ATLAS_FILL_REJECTED`, non-retryable. |
| **Forbidden behaviors** | Must NOT invent new fill statuses. |

### R1.10 — Retry Management

| Attribute | Value |
|-----------|-------|
| **Purpose** | Manage retry logic for retryable broker errors. |
| **Owner** | `RetryManager` (internal component) |
| **Inputs** | Retcode, attempt number, config (`max_retries`, `retry_delay_ms`) |
| **Outputs** | Boolean: should retry. Int: delay before next attempt. |
| **Performance limits** | O(1) |
| **Failure handling** | If attempt ≥ `max_retries`, return false (no more retries). |
| **Forbidden behaviors** | Must NOT use exponential backoff (fixed delay for predictability). Must NOT retry non-retryable errors. |

### R1.11 — Slippage Calculation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Calculate slippage between requested and filled price for diagnostics. |
| **Owner** | `SlippageCalculator` (internal component) |
| **Inputs** | Requested price, filled price, order type |
| **Outputs** | Slippage in price units (positive = unfavorable) |
| **Performance limits** | O(1) |
| **Failure handling** | None — pure arithmetic. |
| **Forbidden behaviors** | Must NOT modify any state. |

### R1.12 — Execution Event Emission

| Attribute | Value |
|-----------|-------|
| **Purpose** | Build and emit an `ExecutionEvent` onto the event bus after each `OrderSend` attempt. |
| **Owner** | `OrderSender` (uses `ExecutionEvent` struct) |
| **Inputs** | `OrderRequest`, `MqlTradeResult`, fill status |
| **Outputs** | `EV_TRADE_EXECUTED` event (priority if filled, normal if rejected) |
| **Performance limits** | O(1) |
| **Failure handling** | If event bus is NULL, log ERROR but do not fail the order. |
| **Forbidden behaviors** | Must NOT emit events for orders not actually sent. |

### R1.13 — Execution Statistics

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track order counts, retcode frequency, latency, slippage. |
| **Owner** | `ExecutionStatistics` (internal component) |
| **Inputs** | Per-send: retcode, fill status, latency, slippage |
| **Outputs** | Counters accessible via accessors |
| **Performance limits** | O(1) per update |

---

# 2. Internal Components

The MT5 Adapter is decomposed into 12 internal components. All are stack-allocated. All live under `Infrastructure/MT5Adapter/`.

### 2.1 — TickCapture

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Call `SymbolInfoTick`, normalize to `RawTick`. |
| **Owned data** | None. |
| **Public API** | `RawTick Capture(const string symbol) const` |
| **Private helpers** | None. |
| **Dependencies** | None (uses MQL5 `SymbolInfoTick` directly). |
| **Failure modes** | `SymbolInfoTick` returns false → zeroed RawTick. |
| **Performance limits** | ≤ 0.05 ms. |

### 2.2 — OrderSender

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Translate `OrderRequest` to `MqlTradeRequest`, call `OrderSend`, manage retries, emit events. |
| **Owned data** | None (stateless between calls). |
| **Public API** | `bool Send(const OrderRequest &req, IEventBus *bus, ILogger *logger, const AtlasConfig &config)`, `int CloseAllForMagic(const string reason, IEventBus *bus, ILogger *logger, const AtlasConfig &config)` |
| **Private helpers** | `void BuildTradeRequest(const OrderRequest &req, MqlTradeRequest &out, const AtlasConfig &config) const`, `void EmitEvent(const OrderRequest &req, const MqlTradeResult &res, const int fill_status, IEventBus *bus)`, `void RefreshPrice(const string symbol, const int order_type, double &out_price) const`, `ENUM_ORDER_TYPE_FILLING PickFillingMode(const string symbol) const` |
| **Dependencies** | `RetryManager`, `RetcodeTranslator`, `SlippageCalculator`, `IEventBus`, `ILogger`, `AtlasConfig` |
| **Failure modes** | All retries exhausted → return false. Broker NULL → return false. |
| **Performance limits** | Single attempt ≤ 5 ms. Total with retries ≤ 50 ms. |

### 2.3 — TradeTransactionListener

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Handle `OnTrade()` callback. Emit trade event. |
| **Owned data** | None. |
| **Public API** | `void OnTradeEvent(IEventBus *bus, ILogger *logger, const long snapshot_id)` |
| **Private helpers** | None. |
| **Dependencies** | `IEventBus`, `ILogger` |
| **Failure modes** | Bus NULL → log ERROR, return. |
| **Performance limits** | O(1) |

### 2.4 — PositionQuery

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Scan `PositionsTotal`, filter by magic + symbol, build `PositionSnapshotEvent`. |
| **Owned data** | None. |
| **Public API** | `PositionSnapshotEvent QueryForMagic(const long magic, const string symbol) const`, `int CountForMagic(const long magic) const` |
| **Private helpers** | `void CopyPosition(const ulong ticket, PositionState &out) const` |
| **Dependencies** | None (uses MQL5 position functions). |
| **Failure modes** | `PositionSelectByTicket` fails → skip position. |
| **Performance limits** | O(N), N ≤ 64. ≤ 0.1 ms. |

### 2.5 — AccountQuery

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Query account properties. |
| **Owned data** | None. |
| **Public API** | `double Equity() const`, `double Balance() const`, `double Margin() const`, `double MarginLevel() const` |
| **Private helpers** | None. |
| **Dependencies** | None (uses `AccountInfoDouble`). |
| **Failure modes** | Returns 0.0 on failure (logged by caller if needed). |
| **Performance limits** | O(1) each. |

### 2.6 — SymbolQuery

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Query symbol properties + manage indicator handles. |
| **Owned data** | None. |
| **Public API** | `double Point(const string symbol) const`, `int Digits(const string symbol) const`, `double Bid(const string symbol) const`, `double Ask(const string symbol) const`, `double VolumeMin(const string symbol) const`, `double VolumeMax(const string symbol) const`, `double VolumeStep(const string symbol) const`, `long StopsLevel(const string symbol) const`, `double ContractSize(const string symbol) const`, `long FillingMode(const string symbol) const`, `int CreateATR(...)`, `int CreateMA(...)`, ... (all indicator creation methods), `int CopyBuffer(...)`, `int CopyRates(...)`, `void ReleaseIndicator(...)`, `int PeriodSeconds() const` |
| **Private helpers** | None. |
| **Dependencies** | None (uses MQL5 symbol/indicator functions). |
| **Failure modes** | Returns 0 / INVALID_HANDLE on failure. |
| **Performance limits** | O(1) for properties. Handle creation: 1-5 ms. |

### 2.7 — HistoryQuery

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Query deal/order history (for future phases — recovery, reconciliation). Not fully implemented in this phase. |
| **Owned data** | None. |
| **Public API** | `int QueryDeals(const datetime from, const datetime to, MqlDealInfo &out[]) const` (stub — returns 0 in this phase) |
| **Private helpers** | None. |
| **Dependencies** | None. |
| **Failure modes** | Returns 0. |
| **Performance limits** | O(N) — not used in hot path. |

### 2.8 — RetcodeTranslator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Translate MT5 retcode to ATLAS_FILL_* + retryable flag. |
| **Owned data** | None. |
| **Public API** | `int Translate(const int retcode) const`, `bool IsRetryable(const int retcode) const`, `string RetcodeToString(const int retcode) const` |
| **Private helpers** | None (switch statement). |
| **Dependencies** | `ATLAS_FILL_*` constants, `TRADE_RETCODE_*` constants. |
| **Failure modes** | Unknown retcode → `ATLAS_FILL_REJECTED`, non-retryable. |
| **Performance limits** | O(1) |

### 2.9 — RetryManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Decide whether to retry and how long to wait. |
| **Owned data** | None. |
| **Public API** | `bool ShouldRetry(const int retcode, const int attempt, const int max_retries) const`, `int NextDelayMs(const int attempt, const int base_delay_ms) const`, `int MaxAttempts(const AtlasConfig &config) const` |
| **Private helpers** | None. |
| **Dependencies** | `AtlasConfig` |
| **Failure modes** | None — pure logic. |
| **Performance limits** | O(1) |

### 2.10 — SlippageCalculator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Compute slippage between requested and filled price. |
| **Owned data** | None. |
| **Public API** | `double Calculate(const double requested, const double filled, const int order_type) const`, `double ToPoints(const double slippage_price, const double point) const` |
| **Private helpers** | None. |
| **Dependencies** | None. |
| **Failure modes** | None — pure arithmetic. |
| **Performance limits** | O(1) |

### 2.11 — ExecutionStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track order counts, retcode frequency, latency, slippage. |
| **Owned data** | `ulong m_orders_sent`, `m_orders_filled`, `m_orders_rejected`, `m_orders_partial`, `m_total_retries`, `double m_total_latency_ms`, `m_peak_latency_ms`, `m_total_slippage_points`, `ulong m_retcode_count[32]` (per-retcode frequency) |
| **Public API** | `void RecordSend(const int retcode, const int fill_status, const double latency_ms, const double slippage_points, const int retries_used)`, `void Reset()`, `void LogSummary(ILogger *logger) const`, accessors |
| **Private helpers** | None. |
| **Dependencies** | `ILogger` |
| **Failure modes** | None — best-effort counters. |
| **Performance limits** | O(1) |

### 2.12 — ConnectionMonitor

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track connection state (connected, disconnected, trading disabled). |
| **Owned data** | `bool m_connected`, `bool m_trading_enabled`, `datetime m_last_check`, `ulong m_disconnect_count` |
| **Public API** | `void Update(ILogger *logger)`, `bool IsConnected() const`, `bool IsTradingEnabled() const`, `ulong DisconnectCount() const` |
| **Private helpers** | `bool CheckConnection() const`, `bool CheckTradingEnabled() const` |
| **Dependencies** | `ILogger`, MQL5 `TerminalInfoInteger` |
| **Failure modes** | None — best-effort. |
| **Performance limits** | O(1) |

---

# 3. Broker Interaction Pipeline

The order dispatch lifecycle (`SendOrder` method):

### Stage 1 — Receive OrderRequest

- Input: `const OrderRequest &req` (validated by ExecutionEngine).
- The request is treated as immutable.

### Stage 2 — Validate Request

- Check `req.volume > 0`, `req.entry_price > 0`, `req.stop_loss > 0`, `req.take_profit > 0`, `req.magic_number > 0`, `req.symbol` non-empty.
- On failure: log ERROR, return false. No event emitted (the request was invalid before it reached the broker).

### Stage 3 — Translate into Broker Request

- Call `BuildTradeRequest()` to convert `OrderRequest` → `MqlTradeRequest`.
- Map fields:
  - `action = TRADE_ACTION_DEALS`
  - `symbol = req.symbol`
  - `volume = req.volume`
  - `type = (ENUM_ORDER_TYPE)req.order_type`
  - `price = req.entry_price`
  - `sl = req.stop_loss`
  - `tp = req.take_profit`
  - `deviation = (ulong)config.slippage_points`
  - `magic = (ulong)req.magic_number`
  - `comment = req.comment`
  - `type_filling = PickFillingMode(req.symbol)` (probe `SYMBOL_FILLING_MODE`)

### Stage 4 — Broker Communication (OrderSend)

- Loop: attempt = 0 to `max_retries`:
  1. `ZeroMemory(mt_res)`.
  2. `bool sent = OrderSend(mt_req, mt_res)`.
  3. `int retcode = (int)mt_res.retcode`.
  4. If `sent && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)`:
     - Success. Break loop.
  5. If `!RetryManager.ShouldRetry(retcode, attempt, max_retries)`:
     - Non-retryable or exhausted. Break loop.
  6. If retryable:
     - Refresh price if REQUOTE/PRICE_OFF/PRICE_CHANGED (re-read bid/ask).
     - `Sleep(config.retry_delay_ms)`.
     - Increment retry counter.
     - Continue loop.

### Stage 5 — Receive Broker Response

- `mt_res` contains: `retcode`, `deal`, `order`, `volume`, `price`, `bid`, `ask`, `comment`, `request_id`, `retcode_external`.

### Stage 6 — Translate Broker Response

- Call `RetcodeTranslator.Translate(retcode)` → `fill_status`.
- Call `SlippageCalculator.Calculate(mt_req.price, mt_res.price, mt_req.type)` → slippage.

### Stage 7 — Generate ExecutionEvent

- Build `ExecutionEvent`:
  - `event_id` = generated (not used in this phase — the AtlasEvent envelope has its own ID)
  - `request_id` = `req.request_id`
  - `fill_status` = translated status
  - `mql_error` = retcode
  - `filled_volume` = `mt_res.volume`
  - `fill_price` = `mt_res.price`
  - `commission` = 0.0 (not available from `MqlTradeResult`; queried from deals in future phase)
  - `swap` = 0.0 (same)
  - `execution_time` = `TimeCurrent()`

### Stage 8 — Notify Core Engine

- Emit `EV_TRADE_EXECUTED` event:
  - If filled or partial: `EmitPriorityEvent` (risk state must update immediately).
  - If rejected or timeout: `EmitEvent` (normal priority).

### Stage 9 — Store Execution Metadata

- `ExecutionStatistics.RecordSend(retcode, fill_status, latency_ms, slippage, retries_used)`.
- Update `ConnectionMonitor` if the error was connection-related.

### Stage 10 — Return

- Return `true` if filled (DONE or DONE_PARTIAL).
- Return `false` if rejected, timeout, or all retries exhausted.

---

# 4. Tick Pipeline

The tick capture lifecycle (called from CoreEngine OnTick):

### Stage 1 — OnTick Trigger

- CoreEngine calls `IBrokerAdapter::CaptureTick()` at the start of each `OnTick()`.

### Stage 2 — Capture Tick

- `TickCapture.Capture()` calls `SymbolInfoTick(config.symbol, mt_tick)`.
- If `SymbolInfoTick` returns false: return zeroed `RawTick` with `timestamp=0`.

### Stage 3 — Validation

- No validation in the adapter (the MarketEngine's `TickValidator` handles validation).
- The adapter returns raw data; validation is a separation-of-concerns.

### Stage 4 — Timestamp

- `mt_tick.time` is a `datetime` (seconds since epoch).
- Copied directly to `RawTick.timestamp`.

### Stage 5 — Spread Calculation

- Not calculated in the adapter (MarketEngine computes `spread = ask - bid`).
- The adapter returns raw `bid` and `ask`.

### Stage 6 — Bid / Ask / Volume

- `bid = mt_tick.bid`
- `ask = mt_tick.ask`
- `last = mt_tick.last`
- `volume = (long)mt_tick.volume`

### Stage 7 — RawTick Creation

```
RawTick tick;
tick.bid       = mt_tick.bid;
tick.ask       = mt_tick.ask;
tick.last      = mt_tick.last;
tick.volume    = (long)mt_tick.volume;
tick.timestamp = mt_tick.time;
return tick;
```

### Stage 8 — Delivery to Core Engine

- The `RawTick` is returned to CoreEngine.
- CoreEngine passes it to `MarketEngine.ProcessTick()` for validation and processing.

---

# 5. Trade Transaction Pipeline

The trade event lifecycle (triggered by `OnTrade()`):

### Stage 1 — Broker Execution

- The broker executes an order (fill, partial fill, close, modify, cancel, or reject).
- The terminal fires `OnTrade()`.

### Stage 2 — OnTrade Callback

- CoreEngine calls `MT5Adapter::CaptureTrade()`.

### Stage 3 — Event Emission

- `TradeTransactionListener.OnTradeEvent()` emits `EV_TRADE_EXECUTED` as a priority event.
- No reconciliation here — CoreEngine handles reconciliation by calling `QueryBrokerPositions()`.

### Stage 4 — Fill Types

The adapter does NOT differentiate fill types in `OnTrade()`. It simply signals that a trade event occurred. The CoreEngine then queries positions to determine what changed:

| Fill Type | Detection (by CoreEngine) |
|-----------|---------------------------|
| **Full fill** | New position appears OR existing position volume goes to 0 |
| **Partial fill** | Existing position volume changes but ≠ 0 |
| **Close** | Position disappears from `QueryBrokerPositions()` |
| **Modify** | Position SL/TP changed (detected by comparing to previous snapshot) |
| **Cancel** | No position change (order was cancelled before execution) |
| **Reject** | No position change (order was rejected) |
| **Error** | No position change + retcode indicates error |

### Stage 5 — Deal Creation

- Deals are created by the broker on fill. The adapter does NOT query deals in this phase (deferred to HistoryQuery in a future phase).

### Stage 6 — History Update

- The terminal maintains deal/order history. The adapter does NOT read it in this phase.

### Stage 7 — ExecutionEvent Generation

- The `ExecutionEvent` is generated in `SendOrder()` (Stage 7 of Section 3), NOT in `OnTrade()`.
- `OnTrade()` emits a generic `EV_TRADE_EXECUTED` event. The detailed `ExecutionEvent` (with retcode, fill_price, etc.) is emitted by `SendOrder()` immediately after the `OrderSend` call returns.

---

# 6. OrderSend Policy

### 6.1 — Allowed Order Types

| Order Type | Supported in This Phase |
|------------|------------------------|
| `ORDER_TYPE_BUY` (market buy) | ✅ Yes |
| `ORDER_TYPE_SELL` (market sell) | ✅ Yes |
| `ORDER_TYPE_BUY_LIMIT` | ❌ No |
| `ORDER_TYPE_SELL_LIMIT` | ❌ No |
| `ORDER_TYPE_BUY_STOP` | ❌ No |
| `ORDER_TYPE_SELL_STOP` | ❌ No |
| `ORDER_TYPE_BUY_STOP_LIMIT` | ❌ No |
| `ORDER_TYPE_SELL_STOP_LIMIT` | ❌ No |

All orders are market orders (`TRADE_ACTION_DEALS`).

### 6.2 — Filling Modes

The adapter probes `SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE)` and picks:

1. If `SYMBOL_FILLING_FOK` is supported → `ORDER_FILLING_FOK` (Fill or Kill).
2. Else if `SYMBOL_FILLING_IOC` is supported → `ORDER_FILLING_IOC` (Immediate or Cancel).
3. Else → `ORDER_FILLING_RETURN` (Return — for symbols that don't support FOK/IOC).

### 6.3 — Expiration

- Not applicable for market orders. `type_time = ORDER_TIME_GTC`.

### 6.4 — Deviation

- `deviation = (ulong)config.slippage_points` (default 20 points).
- Applied to market orders to allow price tolerance.

### 6.5 — Retry Conditions

Retryable retcodes (see Section 8 for full table):
- `TRADE_RETCODE_REQUOTE` (10004)
- `TRADE_RETCODE_PRICE_OFF` (10020)
- `TRADE_RETCODE_PRICE_CHANGED` (10021)
- `TRADE_RETCODE_TIMEOUT` (10008)
- `TRADE_RETCODE_CONNECTION` (10026) [if `sent` was false]
- `TRADE_RETCODE_ERROR` (10006) [if `sent` was false]

### 6.6 — Retry Limits

- `max_retries = config.max_retries` (default 3).
- Total attempts = 1 + max_retries = 4.

### 6.7 — Timeout

- No explicit timeout (MQL5 `OrderSend` is synchronous and blocks until the broker responds).
- Implicit timeout: `max_retries × retry_delay_ms` (default 3 × 200ms = 600ms worst case).

### 6.8 — Cancellation

- Not applicable for market orders (they execute immediately or fail).

### 6.9 — Duplicate Prevention

- The ExecutionEngine's `IdempotencyGuard` prevents duplicate `OrderRequest` construction.
- The adapter does NOT add its own duplicate prevention (it trusts that the ExecutionEngine has already checked).

---

# 7. Retry Policy

### 7.1 — Retryable Errors

| Retcode | Constant | Reason | Action |
|---------|----------|--------|--------|
| 10004 | `TRADE_RETCODE_REQUOTE` | No price for the request | Refresh price, retry |
| 10020 | `TRADE_RETCODE_PRICE_OFF` | No prices | Refresh price, retry |
| 10021 | `TRADE_RETCODE_PRICE_CHANGED` | Price changed | Refresh price, retry |
| 10008 | `TRADE_RETCODE_TIMEOUT` | Request timed out | Retry without price refresh |
| 10026 | `TRADE_RETCODE_CONNECTION` | No connection | Retry (if `sent` was false) |
| 10006 | `TRADE_RETCODE_ERROR` | Generic error | Retry (if `sent` was false) |

### 7.2 — Non-Retryable Errors

| Retcode | Constant | Reason |
|---------|----------|--------|
| 10000 | `TRADE_RETCODE_DONE` | Success (not an error) |
| 10001 | `TRADE_RETCODE_DONE_PARTIAL` | Partial fill (not an error) |
| 10002 | `TRADE_RETCODE_ERROR` | Generic error (if `sent` was true — real error) |
| 10003 | `TRADE_RETCODE_INVALID` | Invalid request |
| 10005 | `TRADE_RETCODE_INVALID_VOLUME` | Invalid volume |
| 10007 | `TRADE_RETCODE_INVALID_PRICE` | Invalid price |
| 10009 | `TRADE_RETCODE_INVALID_STOPS` | Invalid stops |
| 10010 | `TRADE_RETCODE_INVALID_VOLUME` | Invalid volume (duplicate code) |
| 10011 | `TRADE_RETCODE_INVALID_REQUEST` | Invalid request |
| 10012 | `TRADE_RETCODE_POSITION_BUSY` | Position locked |
| 10013 | `TRADE_RETCODE_REQUOTE` | Requote (if already retried) |
| 10014 | `TRADE_RETCODE_PRICE_OFF` | No prices (if already retried) |
| 10015 | `TRADE_RETCODE_INVALID_FILL` | Invalid fill type |
| 10016 | `TRADE_RETCODE_CONNECTION` | No connection (if `sent` was true) |
| 10017 | `TRADE_RETCODE_NOTIMPLEMENTED` | Not implemented |
| 10018 | `TRADE_RETCODE_ONLY_MARKET` | Market orders only |
| 10019 | `TRADE_RETCODE_LIMIT_POSITIONS` | Too many positions |
| 10022 | `TRADE_RETCODE_INVALID_PRICE` | Invalid price (duplicate) |
| 10023 | `TRADE_RETCODE_INVALID_STOPS` | Invalid stops (duplicate) |
| 10024 | `TRADE_RETCODE_NO_MONEY` | Insufficient funds |
| 10025 | `TRADE_RETCODE_DISABLED` | Trading disabled |
| 10027 | `TRADE_RETCODE_PRICE_DISABLED` | Price disabled |
| 10028 | `TRADE_RETCODE_INVALID_EXPIRATION` | Invalid expiration |
| 10029 | `TRADE_RETCODE_INVALID_ORDER` | Invalid order |
| 10030 | `TRADE_RETCODE_POSITION_ONLY` | Position-only mode |
| 10031 | `TRADE_RETCODE_UNKNOWN` | Unknown error |

### 7.3 — Backoff

- **Fixed delay** (not exponential): `config.retry_delay_ms` (default 200ms) between every retry.
- Rationale: predictable, bounded latency. Exponential backoff would make the total unpredictable within the 50ms tick budget.

### 7.4 — Maximum Retries

- `config.max_retries` (default 3).
- Total attempts: 4 (1 initial + 3 retries).

### 7.5 — Abort Conditions

- Non-retryable retcode → abort immediately.
- Attempt ≥ `max_retries` → abort.
- `sent == false` (OrderSend itself failed, not just a bad retcode) → check if retryable (connection error).

### 7.6 — Logging

- Each retry: log WARN with retcode and attempt number.
- Final failure: log ERROR with retcode and total attempts.
- Success: log DEBUG (not INFO — hot path).

### 7.7 — Recovery

- No automatic recovery beyond retries. If all retries fail, the order is lost (the ExecutionEvent records the failure).
- The operator must investigate (check connection, account, symbol).

---

# 8. Broker Error Translation

| MT5 Retcode | Constant | Atlas Fill Status | Retryable | Severity | Recovery Action | Log Level |
|-------------|----------|-------------------|-----------|----------|-----------------|-----------|
| 10000 | `TRADE_RETCODE_DONE` | `ATLAS_FILL_FILLED` | No | INFO | None | DEBUG |
| 10001 | `TRADE_RETCODE_DONE_PARTIAL` | `ATLAS_FILL_PARTIAL` | No | INFO | None | DEBUG |
| 10002 | `TRADE_RETCODE_ERROR` | `ATLAS_FILL_REJECTED` | Conditional | ERROR | Retry if `sent==false` | ERROR |
| 10003 | `TRADE_RETCODE_INVALID` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10004 | `TRADE_RETCODE_REQUOTE` | `ATLAS_FILL_REJECTED` | Yes | WARN | Refresh price, retry | WARN |
| 10005 | `TRADE_RETCODE_INVALID_VOLUME` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10006 | `TRADE_RETCODE_ERROR` | `ATLAS_FILL_REJECTED` | Conditional | ERROR | Retry if `sent==false` | ERROR |
| 10007 | `TRADE_RETCODE_INVALID_PRICE` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10008 | `TRADE_RETCODE_TIMEOUT` | `ATLAS_FILL_TIMEOUT` | Yes | WARN | Retry | WARN |
| 10009 | `TRADE_RETCODE_INVALID_STOPS` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10010 | `TRADE_RETCODE_INVALID_VOLUME` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10011 | `TRADE_RETCODE_INVALID_REQUEST` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10012 | `TRADE_RETCODE_POSITION_BUSY` | `ATLAS_FILL_REJECTED` | No | WARN | None | WARN |
| 10013 | `TRADE_RETCODE_REQUOTE` | `ATLAS_FILL_REJECTED` | Yes | WARN | Refresh price, retry | WARN |
| 10014 | `TRADE_RETCODE_PRICE_OFF` | `ATLAS_FILL_REJECTED` | Yes | WARN | Refresh price, retry | WARN |
| 10015 | `TRADE_RETCODE_INVALID_FILL` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10016 | `TRADE_RETCODE_CONNECTION` | `ATLAS_FILL_REJECTED` | Conditional | ERROR | Retry if `sent==false` | ERROR |
| 10017 | `TRADE_RETCODE_NOTIMPLEMENTED` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10018 | `TRADE_RETCODE_ONLY_MARKET` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10019 | `TRADE_RETCODE_LIMIT_POSITIONS` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10020 | `TRADE_RETCODE_PRICE_OFF` | `ATLAS_FILL_REJECTED` | Yes | WARN | Refresh price, retry | WARN |
| 10021 | `TRADE_RETCODE_PRICE_CHANGED` | `ATLAS_FILL_REJECTED` | Yes | WARN | Refresh price, retry | WARN |
| 10022 | `TRADE_RETCODE_INVALID_PRICE` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10023 | `TRADE_RETCODE_INVALID_STOPS` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10024 | `TRADE_RETCODE_NO_MONEY` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10025 | `TRADE_RETCODE_DISABLED` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10026 | `TRADE_RETCODE_CONNECTION` | `ATLAS_FILL_REJECTED` | Conditional | ERROR | Retry if `sent==false` | ERROR |
| 10027 | `TRADE_RETCODE_PRICE_DISABLED` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10028 | `TRADE_RETCODE_INVALID_EXPIRATION` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10029 | `TRADE_RETCODE_INVALID_ORDER` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10030 | `TRADE_RETCODE_POSITION_ONLY` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| 10031 | `TRADE_RETCODE_UNKNOWN` | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |
| Other | (unknown) | `ATLAS_FILL_REJECTED` | No | ERROR | None | ERROR |

**Fatal vs Non-Fatal:**
- All retcodes are non-fatal (the EA continues running).
- Fatal conditions (EA shutdown) are NOT triggered by retcodes. Only the Risk Engine kill switch can halt trading.

---

# 9. Broker Queries

### 9.1 — Account Queries

| Method | MT5 API | Returns |
|--------|---------|---------|
| `AccountEquity()` | `AccountInfoDouble(ACCOUNT_EQUITY)` | double |
| `AccountBalance()` | `AccountInfoDouble(ACCOUNT_BALANCE)` | double |
| `AccountMargin()` | `AccountInfoDouble(ACCOUNT_MARGIN)` | double |
| `AccountMarginLevel()` | `AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)` | double (percent, 0 if no margin) |

### 9.2 — Position Queries

| Method | MT5 API | Returns |
|--------|---------|---------|
| `QueryBrokerPositions()` | `PositionsTotal()` + `PositionGetTicket()` + `PositionSelectByTicket()` + `PositionGet*()` | `PositionSnapshotEvent` |
| `CountPositionsForMagic()` | `PositionsTotal()` + filter | int |
| `CloseAllPositionsForMagic()` | Loop: `PositionGetTicket()` + `OrderSend(close)` | int (count closed) |

### 9.3 — Order Queries

- Not implemented in this phase. MT5 uses "positions" (hedging) or netting; the adapter queries positions, not pending orders.

### 9.4 — History Queries

| Method | MT5 API | Returns |
|--------|---------|---------|
| `HistoryQueryDeals()` (future) | `HistorySelect()` + `HistoryDealsTotal()` + `HistoryDealGetTicket()` + `HistoryDealGet*()` | `MqlDealInfo[]` |
| `HistoryQueryOrders()` (future) | `HistorySelect()` + `HistoryOrdersTotal()` + `HistoryOrderGetTicket()` + `HistoryOrderGet*()` | `MqlOrderInfo[]` |

Not implemented in this phase. Deferred to a future recovery/reconciliation phase.

### 9.5 — Symbol Queries

| Method | MT5 API | Returns |
|--------|---------|---------|
| `SymbolPoint()` | `SymbolInfoDouble(symbol, SYMBOL_POINT)` | double |
| `SymbolDigits()` | `SymbolInfoInteger(symbol, SYMBOL_DIGITS)` | int |
| `SymbolBid()` | `SymbolInfoDouble(symbol, SYMBOL_BID)` | double |
| `SymbolAsk()` | `SymbolInfoDouble(symbol, SYMBOL_ASK)` | double |
| `SymbolVolumeMin()` | `SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN)` | double |
| `SymbolVolumeMax()` | `SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX)` | double |
| `SymbolVolumeStep()` | `SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP)` | double |
| `SymbolStopsLevel()` | `SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL)` | long |
| `SymbolContractSize()` | `SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE)` | double |
| `SymbolFillingMode()` | `SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE)` | long |

### 9.6 — Market Information

| Method | MT5 API | Returns |
|--------|---------|---------|
| `CaptureTick()` | `SymbolInfoTick(symbol, tick)` | `RawTick` |
| `SymbolBid()` | `SymbolInfoDouble` | double |
| `SymbolAsk()` | `SymbolInfoDouble` | double |

### 9.7 — Margin Information

- Not directly queried. `AccountMargin()` and `AccountMarginLevel()` cover margin queries.
- Free margin check: `AccountInfoDouble(ACCOUNT_MARGIN_FREE)` — available but not exposed in this phase.

### 9.8 — Session Information

- Not queried by the adapter. Session detection is in `MarketEngine::SessionDetector` (uses `TimeCurrent` + day_of_week).
- The adapter does NOT check if the market is open — it sends orders regardless. If the market is closed, the broker returns an error retcode which is handled by the retry/translation logic.

---

# 10. Connection Monitoring

### 10.1 — States

| State | Description |
|-------|-------------|
| **CONNECTED** | Terminal is connected to the trade server. |
| **DISCONNECTED** | Terminal is not connected. Orders will fail with `TRADE_RETCODE_CONNECTION`. |
| **RECONNECTING** | Terminal is attempting to reconnect (automatic in MT5). |
| **TRADING_DISABLED** | Connected but trading is disabled (auto-trading button off or server-side disable). |

### 10.2 — Detection

| Check | MT5 API | True When |
|-------|---------|-----------|
| `CheckConnection()` | `TerminalInfoInteger(TERMINAL_CONNECTED)` | Returns non-zero |
| `CheckTradingEnabled()` | `TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)` | Returns non-zero |
| `IsMarketClosed()` | `SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE)` | Returns `SYMBOL_TRADE_MODE_DISABLED` |

### 10.3 — Update Frequency

- `ConnectionMonitor.Update()` is called on every `OnTick()` and `OnTimer()`.
- O(1) per call.

### 10.4 — Heartbeat

- No explicit heartbeat ping to the server (MT5 manages connection internally).
- The `EV_HEARTBEAT` event from CoreEngine serves as the application-level heartbeat.

### 10.5 — Server Busy

- Not explicitly detected. If the server is busy, `OrderSend` returns `TRADE_RETCODE_TIMEOUT` which is retried.

### 10.6 — Market Closed

- Detected via `SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE)`. If mode is `SYMBOL_TRADE_MODE_DISABLED`, log WARN and skip `OrderSend`.
- The adapter does NOT prevent order submission — it logs and lets the broker reject (defensive). This ensures the ExecutionEvent records the actual broker response.

### 10.7 — Synchronization

- MT5 handles server synchronization internally. The adapter does NOT implement custom sync logic.

---

# 11. ExecutionEvent Specification

The `ExecutionEvent` struct is defined in `Contracts/Events.mqh`.

### Field: `event_id`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Unique identifier for this execution event. |
| **Type** | `string` |
| **Allowed values** | Non-empty. Currently unused (the AtlasEvent envelope carries the event). Reserved for future use. |
| **Default** | "" |
| **Ownership** | Set by OrderSender. |
| **Immutability** | Immutable after construction. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | Not persisted (transient event). |

### Field: `request_id`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Correlation to the OrderRequest that triggered this execution. |
| **Type** | `string` |
| **Allowed values** | Non-empty. Copied from `OrderRequest.request_id`. |
| **Default** | "" |
| **Ownership** | Copied from OrderRequest. |
| **Immutability** | Immutable. |
| **Serialization** | Length-prefixed string. |
| **Memory layout** | MQL5 string. |
| **Recovery** | Not persisted. |

### Field: `fill_status`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Broker fill outcome. |
| **Type** | `int` |
| **Allowed values** | `ATLAS_FILL_PENDING (0)`, `ATLAS_FILL_FILLED (1)`, `ATLAS_FILL_PARTIAL (2)`, `ATLAS_FILL_REJECTED (3)`, `ATLAS_FILL_TIMEOUT (4)`. |
| **Default** | `ATLAS_FILL_PENDING (0)`. |
| **Validation** | Must be in [0, 4]. |
| **Ownership** | Set by RetcodeTranslator.Translate(). |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Recovery** | Not persisted (transient). |

### Field: `mql_error`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Raw MT5 retcode from `MqlTradeResult.retcode`. |
| **Type** | `int` |
| **Allowed values** | 0 to 10031 (MT5 retcode range). |
| **Default** | 0. |
| **Validation** | None (raw value). |
| **Ownership** | Copied from `MqlTradeResult.retcode`. |
| **Immutability** | Immutable. |
| **Serialization** | 4 bytes. |
| **Memory layout** | 4 bytes. |
| **Recovery** | Not persisted. |

### Field: `filled_volume`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Volume actually filled by the broker. |
| **Type** | `double` |
| **Allowed values** | ≥ 0.0. Equals `OrderRequest.volume` for full fills, less for partial fills, 0 for rejections. |
| **Default** | 0.0. |
| **Validation** | Must not be NaN. Must be ≥ 0. |
| **Ownership** | Copied from `MqlTradeResult.volume`. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | Not persisted. |

### Field: `fill_price`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Price at which the order was filled. |
| **Type** | `double` |
| **Allowed values** | > 0.0 for fills, 0.0 for rejections. |
| **Default** | 0.0. |
| **Validation** | Must not be NaN. |
| **Ownership** | Copied from `MqlTradeResult.price`. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | Not persisted. |

### Field: `commission`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Commission charged by the broker. |
| **Type** | `double` |
| **Allowed values** | ≥ 0.0. |
| **Default** | 0.0 (not available from `MqlTradeResult`; requires deal query — deferred). |
| **Validation** | Must not be NaN. |
| **Ownership** | Set by OrderSender (currently 0.0). |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | Not persisted. |

### Field: `swap`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Swap charged/credited. |
| **Type** | `double` |
| **Allowed values** | Any (can be negative). |
| **Default** | 0.0 (not available from `MqlTradeResult`; requires deal query — deferred). |
| **Validation** | Must not be NaN. |
| **Ownership** | Set by OrderSender (currently 0.0). |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | Not persisted. |

### Field: `execution_time`

| Attribute | Value |
|-----------|-------|
| **Meaning** | Timestamp of execution. |
| **Type** | `datetime` |
| **Allowed values** | > 0. |
| **Default** | 0. |
| **Validation** | Must be > 0. |
| **Ownership** | Set to `TimeCurrent()` by OrderSender. |
| **Immutability** | Immutable. |
| **Serialization** | 8 bytes. |
| **Memory layout** | 8 bytes. |
| **Recovery** | Not persisted. |

---

# 12. Performance Budget

### 12.1 — Maximum OrderSend Latency

| Operation | Budget |
|-----------|--------|
| Single `OrderSend` call | ≤ 5 ms (broker round-trip) |
| Retry delay (per retry) | ≤ `retry_delay_ms` (default 200 ms) |
| Total `SendOrder` (worst case) | ≤ 5 + 200 + 5 + 200 + 5 + 200 + 5 = 615 ms |
| **Note** | The 615ms worst case exceeds the 50ms tick budget. This is acceptable because `SendOrder` is called from `PhaseScheduler` which measures total tick time. If the budget is exceeded, the `TimeBudgetRunner` logs a WARN but does not abort the order. |

### 12.2 — Maximum OnTick Latency

- `CaptureTick()`: ≤ 0.05 ms.
- The adapter is NOT the bottleneck in OnTick (MarketEngine indicator refresh is more expensive).

### 12.3 — Maximum Query Latency

| Query | Budget |
|-------|--------|
| `QueryBrokerPositions()` | ≤ 0.1 ms (64 positions) |
| `CountPositionsForMagic()` | ≤ 0.1 ms |
| `AccountEquity()` etc. | ≤ 0.01 ms each |
| `SymbolPoint()` etc. | ≤ 0.01 ms each |
| `CopyBuffer()` | ≤ 0.1 ms (small counts) |

### 12.4 — Maximum Retry Latency

- Per retry: `retry_delay_ms` (200 ms) + `OrderSend` (5 ms) = 205 ms.
- Total for 3 retries: 615 ms (see 12.1).

### 12.5 — Maximum Broker Timeout

- No explicit timeout. MQL5 `OrderSend` blocks until the broker responds.
- If the broker is unresponsive, the terminal eventually returns `TRADE_RETCODE_TIMEOUT` (typically 10-30 seconds).

### 12.6 — Memory Limits

- Total memory: stack-allocated. No heap allocation in hot path.
- `ExecutionStatistics`: ~512 bytes (counters + retcode array).
- `ConnectionMonitor`: ~32 bytes.
- Local variables: ~128 bytes.
- Total: ~700 bytes stack.

### 12.7 — No Dynamic Allocation

- `new` and `delete` are FORBIDDEN in `SendOrder`, `CaptureTick`, `QueryBrokerPositions`.
- String operations (event emission) are unavoidable but minimal.

---

# 13. Metrics

The `ExecutionStatistics` component collects:

| Metric | Type | Description |
|--------|------|-------------|
| `orders_sent` | `ulong` | Total `SendOrder` calls. |
| `orders_filled` | `ulong` | Orders with `ATLAS_FILL_FILLED`. |
| `orders_partial` | `ulong` | Orders with `ATLAS_FILL_PARTIAL`. |
| `orders_rejected` | `ulong` | Orders with `ATLAS_FILL_REJECTED`. |
| `orders_timeout` | `ulong` | Orders with `ATLAS_FILL_TIMEOUT`. |
| `total_retries` | `ulong` | Total retry attempts across all orders. |
| `total_latency_ms` | `double` | Sum of all `SendOrder` latencies. |
| `peak_latency_ms` | `double` | Maximum single-order latency. |
| `average_latency_ms` | `double` | `total_latency_ms / orders_sent`. |
| `total_slippage_points` | `double` | Sum of slippage in points. |
| `average_slippage_points` | `double` | `total_slippage_points / orders_filled`. |
| `retcode_frequency[32]` | `ulong[32]` | Count per retcode (indexed by retcode - 10000, clamped). |
| `connection_uptime_sec` | `long` | Seconds since last disconnect (from `ConnectionMonitor`). |
| `execution_failure_rate` | `double` | `(orders_rejected + orders_timeout) / orders_sent`. |

---

# 14. Logging

All logging through `ILogger`. `Print()` is FORBIDDEN.

### 14.1 — Log Categories

| Level | Category | When |
|-------|----------|------|
| **DEBUG** | Tick captured | "Tick: bid={b} ask={a} vol={v}" (only if `log_level <= DEBUG`) |
| **DEBUG** | Order sent (success) | "Order filled: req={id} vol={v} price={p} attempts={n}" |
| **DEBUG** | Position query | "Queried {n} positions for magic {m}" |
| **INFO** | Initialization | "MT5Adapter initialized: symbol={s} magic={m}" |
| **INFO** | Shutdown | "MT5Adapter shutdown. Sent={n} Filled={f}" |
| **INFO** | Diagnostics summary | On `LogDiagnostics()` (heartbeat only) |
| **WARN** | Retry | "Retry {n}/{max}: retcode={r} ({desc})" |
| **WARN** | Price refresh | "Price refreshed for retry: old={o} new={n}" |
| **WARN** | Partial fill | "Partial fill: requested={r} filled={f}" |
| **WARN** | Connection lost | "Connection lost. Retrying orders may fail." |
| **WARN** | Trading disabled | "Auto-trading disabled. Orders will fail." |
| **WARN** | Market closed | "Market appears closed for {symbol}" |
| **WARN** | SymbolInfo failure | "SymbolInfoDouble failed for {symbol} {property}" |
| **ERROR** | OrderSend failed | "OrderSend failed: req={id} retcode={r} ({desc}) attempts={n}" |
| **ERROR** | Invalid request | "Invalid OrderRequest: {reason}" |
| **ERROR** | Position select failed | "PositionSelectByTicket failed for {ticket}" |
| **ERROR** | Close position failed | "Failed to close {ticket}: retcode={r}" |
| **ERROR** | SymbolInfoTick failed | "SymbolInfoTick failed for {symbol}" |
| **ERROR** | Event bus NULL | "Cannot emit event: bus is NULL" |
| **CRITICAL** | Not used | N/A (critical conditions are handled by kill switch, not adapter) |

### 14.2 — Hot Path Logging Policy

**No INFO/WARN/ERROR logging on the success path of `CaptureTick` or `QueryBrokerPositions`.** Only DEBUG is allowed (and only if `log_level <= ATLAS_LOG_DEBUG`).

`SendOrder` logs:
- Success: DEBUG
- Retry: WARN
- Failure: ERROR

### 14.3 — Broker Logs

- All broker retcodes are logged via the adapter (not directly by the terminal).
- The adapter translates retcodes to human-readable strings via `RetcodeTranslator.RetcodeToString()`.

### 14.4 — Performance Logs

- `ExecutionStatistics.LogSummary()` is called on heartbeat (every 10 seconds by default).
- Includes: orders sent, filled, rejected, average latency, peak latency, slippage, retcode frequency.

---

# 15. Edge Cases

| # | Edge Case | Adapter Behavior |
|---|-----------|------------------|
| EC1 | Broker disconnected (`TERMINAL_CONNECTED == 0`) | `OrderSend` will fail with `TRADE_RETCODE_CONNECTION`. Retry if `sent==false`. Log WARN. |
| EC2 | Market closed (`SYMBOL_TRADE_MODE_DISABLED`) | `OrderSend` will fail. Log WARN. Do NOT pre-check (let broker reject for audit trail). |
| EC3 | No connection | Same as EC1. |
| EC4 | Trade disabled (`TERMINAL_TRADE_ALLOWED == 0`) | `OrderSend` will fail. Log WARN. |
| EC5 | No prices (`SymbolInfoTick` returns false) | Return zeroed `RawTick`. Log ERROR. MarketEngine will reject the tick. |
| EC6 | Invalid symbol | `SymbolInfo*` returns 0. Log WARN. Return 0. |
| EC7 | Invalid stops (SL/TP too close) | `OrderSend` returns `TRADE_RETCODE_INVALID_STOPS`. Non-retryable. Log ERROR. |
| EC8 | Invalid volume | `OrderSend` returns `TRADE_RETCODE_INVALID_VOLUME`. Non-retryable. Log ERROR. |
| EC9 | Off quotes (`TRADE_RETCODE_PRICE_OFF`) | Retryable. Refresh price. Retry. |
| EC10 | Requote (`TRADE_RETCODE_REQUOTE`) | Retryable. Refresh price. Retry. |
| EC11 | Timeout (`TRADE_RETCODE_TIMEOUT`) | Retryable. Retry without price refresh. |
| EC12 | Duplicate order (same request_id) | NOT detected by adapter. ExecutionEngine's IdempotencyGuard handles this. |
| EC13 | Partial fill (`TRADE_RETCODE_DONE_PARTIAL`) | Non-retryable. Treated as success. Log WARN. Emit event with `ATLAS_FILL_PARTIAL`. |
| EC14 | Unknown retcode | Treat as `ATLAS_FILL_REJECTED`, non-retryable. Log ERROR with retcode value. |
| EC15 | History unavailable | Not queried in this phase. N/A. |
| EC16 | Clock drift | Not handled by adapter. MT5 syncs time with server. `TimeCurrent()` returns server time. |
| EC17 | No margin (`TRADE_RETCODE_NO_MONEY`) | Non-retryable. Log ERROR. (Risk Engine should have caught this — indicates margin check failure.) |
| EC18 | Too many positions (`TRADE_RETCODE_LIMIT_POSITIONS`) | Non-retryable. Log ERROR. |
| EC19 | Position busy (`TRADE_RETCODE_POSITION_BUSY`) | Non-retryable. Log WARN. (Position is locked by another operation.) |
| EC20 | Invalid fill type (`TRADE_RETCODE_INVALID_FILL`) | Non-retryable. Log ERROR. (Filling mode probe failed — should not happen.) |
| EC21 | `OrderSend` returns false but retcode is 0 | Treat as error. Log ERROR. Emit `ATLAS_FILL_REJECTED`. |
| EC22 | `MqlTradeResult` has zero volume on success | Log WARN. Treat as partial fill with 0 volume (unusual but defensive). |
| EC23 | Event bus NULL | Log ERROR. Do NOT fail the order — the order was sent, just can't notify. |
| EC24 | Logger NULL | Proceed with best-effort. No logging. |
| EC25 | Config corruption (magic = 0) | `OrderSend` will use magic=0. Positions won't be filtered correctly. Log ERROR (detected in validation). |
| EC26 | Close position fails during kill switch | Log ERROR. Continue with next position. Kill switch remains active. |
| EC27 | `SymbolInfoTick` returns bid=0 or ask=0 | Return the RawTick anyway (MarketEngine will reject it). Log WARN. |
| EC28 | Broker returns retcode > 10031 | Treat as unknown. Log ERROR. `ATLAS_FILL_REJECTED`. |
| EC29 | Sleep is interrupted | MQL5 `Sleep` is not interruptible. N/A. |
| EC30 | Adapter not initialized | All methods return default values. Log ERROR. |

---

# 16. Validation Matrix

| Field | Validation | Severity | Recovery | Action |
|-------|------------|----------|----------|--------|
| `req.volume` | Must be > 0 | ERROR | None | Abort send |
| `req.entry_price` | Must be > 0 | ERROR | None | Abort send |
| `req.stop_loss` | Must be > 0 | ERROR | None | Abort send |
| `req.take_profit` | Must be > 0 | ERROR | None | Abort send |
| `req.magic_number` | Must be > 0 | ERROR | None | Abort send |
| `req.symbol` | Must be non-empty | ERROR | None | Abort send |
| `req.order_type` | Must be BUY or SELL | ERROR | None | Abort send |
| `mt_req.type_filling` | Must be valid for symbol | None | Auto-pick | Probe SYMBOL_FILLING_MODE |
| `retcode` | Translate to fill_status | None | None | Use RetcodeTranslator |
| Retryable retcode | Attempt < max_retries | WARN | Retry | Refresh price, Sleep, retry |
| Non-retryable retcode | N/A | ERROR | None | Abort, emit event |
| `SymbolInfoTick` failure | Returns false | ERROR | None | Return zeroed RawTick |
| `PositionSelectByTicket` failure | Returns false | WARN | Skip position | Continue scan |
| `AccountInfoDouble` failure | Returns 0 | WARN | None | Return 0.0 |
| `SymbolInfoDouble` failure | Returns 0 | WARN | None | Return 0.0 |
| Event bus NULL | Cannot emit | ERROR | None | Log, continue (order still sent) |
| Connection lost | `TERMINAL_CONNECTED == 0` | WARN | None | Log, let OrderSend fail |
| Trading disabled | `TERMINAL_TRADE_ALLOWED == 0` | WARN | None | Log, let OrderSend fail |

---

# 17. State Machine

The MT5 Adapter itself does not have a complex state machine — it is stateless between calls (all state is in `ExecutionStatistics` and `ConnectionMonitor`). However, the connection state and each `SendOrder` call transition through states:

### Connection State Machine

```
    DISCONNECTED ──reconnect──► CONNECTING ──success──► CONNECTED
         ▲                          │                       │
         │                          │ fail                  │ disconnect
         │                          ▼                       │
         └──────────────────── DISCONNECTED ◄───────────────┘

    CONNECTED ──trading disabled──► TRADING_DISABLED
    TRADING_DISABLED ──trading enabled──► CONNECTED
```

### SendOrder State Machine

```
    READY (entry)
       │
       ▼
    [Validate request]
       │
       ├── invalid ──► FAILED ──► return false
       │
       ▼ (valid)
    EXECUTING
       │
       [OrderSend]
       │
       ├── success (DONE/DONE_PARTIAL) ──► COMPLETED ──► emit event ──► return true
       │
       ├── retryable error ──► RETRYING ──► WAITING (Sleep) ──► back to EXECUTING
       │                                                          │
       │                                                          └── attempt ≥ max ──► FAILED
       │
       └── non-retryable error ──► FAILED ──► emit event ──► return false
```

### State Definitions

| State | Description | Entry | Exit |
|-------|-------------|-------|------|
| **DISCONNECTED** | Terminal not connected to server. | Connection lost. | Terminal reconnects. |
| **CONNECTING** | Terminal attempting to connect. | Auto by MT5. | Connection established. |
| **CONNECTED** | Terminal connected, trading allowed. | Connection established. | Connection lost or trading disabled. |
| **TRADING_DISABLED** | Connected but auto-trading off. | `TERMINAL_TRADE_ALLOWED == 0`. | Auto-trading re-enabled. |
| **READY** | SendOrder entry. | Method called. | Validation done. |
| **EXECUTING** | OrderSend in progress. | Request validated. | Broker responds. |
| **WAITING** | Sleeping between retries. | Retryable error. | Sleep completes. |
| **RETRYING** | Preparing next attempt. | Sleep completes. | Next OrderSend. |
| **COMPLETED** | Order filled. | DONE/DONE_PARTIAL. | Return true. |
| **FAILED** | Order failed. | Non-retryable or retries exhausted. | Return false. |
| **RECOVERING** | Not applicable (stateless between calls). | N/A. | N/A. |

---

# 18. Security Constraints

### 18.1 — MT5 Adapter MUST NEVER Generate Trading Signals

The adapter receives `OrderRequest` from the CoreEngine (which received it from the ExecutionEngine, which received it from the RiskEngine). The adapter does NOT decide what to trade, when to trade, or how much to trade. It only executes what it's told.

### 18.2 — MT5 Adapter MUST NEVER Modify RiskDecision

The adapter does not see the `RiskDecision`. It only sees the `OrderRequest`. It cannot modify a decision.

### 18.3 — MT5 Adapter MUST NEVER Modify OrderRequest

The `OrderRequest` is `const` in `SendOrder()`. The adapter reads from it but cannot modify any field. The `MqlTradeRequest` is a separate struct built FROM the `OrderRequest`.

### 18.4 — MT5 Adapter MUST NEVER Modify PositionState

The adapter READS positions (via `QueryBrokerPositions`) but returns them as a `PositionSnapshotEvent`. It does NOT modify the broker's positions (except via `CloseAllPositionsForMagic` which is an explicit kill-switch action).

### 18.5 — MT5 Adapter MUST NEVER Modify MarketState

The adapter does not see `MarketState`. It captures `RawTick` and returns it. The MarketEngine builds `MarketState` from the tick.

### 18.6 — MT5 Adapter MUST NEVER Bypass Core Engine

The adapter does NOT call `OrderSend` on its own initiative. It only sends orders when `SendOrder()` is called by the CoreEngine. The `CaptureTrade()` method only emits an event — it does not send orders.

### 18.7 — MT5 Adapter MUST NEVER Approve Trades

The adapter has no concept of approval. It receives a fully-approved `OrderRequest` and sends it. If the `OrderRequest` is invalid, it returns false (a mechanical failure, not a risk rejection).

### 18.8 — MT5 Adapter MUST NEVER Reject Strategy Logic

The adapter does not see strategy information. It cannot reject based on strategy.

### 18.9 — MT5 Adapter MUST NEVER Own Business Rules

The adapter has NO business rules. It does not check drawdown, exposure, margin, confidence, or any risk metric. It only checks mechanical validity (volume > 0, prices > 0) and broker constraints (retcodes). All business rules live in the Risk Engine.

### 18.10 — MT5 Adapter is the ONLY Module That Calls MT5 APIs

No other module may call `SymbolInfoTick`, `OrderSend`, `PositionsTotal`, `PositionGet*`, `AccountInfoDouble`, `iATR`, `CopyBuffer`, etc. All MT5 API access is funneled through the adapter. This is enforced by architecture (only the adapter includes the necessary MQL5 functions; other modules use interfaces).

---

# 19. Production Checklist

### 19.1 — Contract Alignment

- [ ] `ExecutionEvent` struct fields match `Contracts/Events.mqh` exactly (9 fields).
- [ ] `OrderRequest` struct consumed from `Contracts/RiskDecision.mqh`.
- [ ] `RawTick`, `PositionState`, `PositionSnapshotEvent` consumed from `Contracts/`.
- [ ] `IBrokerAdapter` interface matches `Interfaces/IBrokerAdapter.mqh` exactly (all methods).
- [ ] Constants: `ATLAS_FILL_*`, `ATLAS_ORDER_*`, `ATLAS_MODULE_MT5`.

### 19.2 — Dependency Alignment

- [ ] `IEventBus` available (for event emission).
- [ ] `ILogger` available.
- [ ] `AtlasConfig` available (for `magic_number`, `symbol`, `max_retries`, `retry_delay_ms`, `slippage_points`).
- [ ] NO dependency on `IContextStore`, `IMarketDataSource`, `IStrategySet`, `IRiskEvaluator`, `IOrderBuilder`, `IPositionStore`, `IStateStore` (the adapter is a leaf module — it depends on nothing except contracts and interfaces).

### 19.3 — File Structure

- [ ] Main file: `Infrastructure/MT5Adapter.mqh` (implements `IBrokerAdapter`).
- [ ] Internal helpers under `Infrastructure/MT5Adapter/`:
  - `TickCapture.mqh`
  - `OrderSender.mqh`
  - `TradeTransactionListener.mqh`
  - `PositionQuery.mqh`
  - `AccountQuery.mqh`
  - `SymbolQuery.mqh`
  - `HistoryQuery.mqh` (stub for future phase)
  - `RetcodeTranslator.mqh`
  - `RetryManager.mqh`
  - `SlippageCalculator.mqh`
  - `ExecutionStatistics.mqh`
  - `ConnectionMonitor.mqh`

### 19.4 — Performance Verification

- [ ] No `new` or `delete` in hot path methods.
- [ ] No `Print()` anywhere.
- [ ] All MT5 API calls go through the adapter (no other module calls them).
- [ ] No recursion.
- [ ] All arrays fixed-size.
- [ ] Total stack usage < 1 KB.
- [ ] `CaptureTick` ≤ 0.05 ms.
- [ ] `QueryBrokerPositions` ≤ 0.1 ms.
- [ ] `SendOrder` (single attempt) ≤ 5 ms.

### 19.5 — MQL5 Compliance

- [ ] Include guards on every file.
- [ ] No `#pragma once`.
- [ ] No `->` (use `.`).
- [ ] No STL.
- [ ] No dynamic arrays in structs.
- [ ] `Sleep()` used only in retry loop (bounded by `retry_delay_ms × max_retries`).

### 19.6 — Retcode Translation Verification

- [ ] All 32 MT5 retcodes (10000-10031) mapped.
- [ ] Unknown retcodes handled (default to `ATLAS_FILL_REJECTED`).
- [ ] Retryable vs non-retryable classification correct.
- [ ] `RetcodeToString()` implemented for all known retcodes.

### 19.7 — Retry Verification

- [ ] Retry only on retryable retcodes.
- [ ] Price refresh on REQUOTE/PRICE_OFF/PRICE_CHANGED.
- [ ] No price refresh on TIMEOUT/CONNECTION.
- [ ] `max_retries` respected.
- [ ] Fixed delay (not exponential).

### 19.8 — Filling Mode Verification

- [ ] `PickFillingMode()` probes `SYMBOL_FILLING_MODE`.
- [ ] FOK preferred, IOC fallback, RETURN last resort.
- [ ] Same logic used for `SendOrder` and `CloseAllPositionsForMagic`.

### 19.9 — Error Handling

- [ ] NULL pointer checks on all dependencies (bus, logger).
- [ ] All edge cases from Section 15 covered.
- [ ] `OrderSend` returning false handled (check `sent` before checking retcode).

### 19.10 — Documentation

- [ ] Doxygen comments on every class.
- [ ] Doxygen comments on every public method.
- [ ] Doxygen comments on every public member.
- [ ] Every file has a header comment block.

### 19.11 — Integration Points

- [ ] `MT5Adapter::SetDependencies()` signature matches what CoreEngine will call.
- [ ] `CaptureTick()` returns `RawTick` by value.
- [ ] `SendOrder()` returns `bool`.
- [ ] `QueryBrokerPositions()` returns `PositionSnapshotEvent` by value.
- [ ] `CloseAllPositionsForMagic()` returns `int` (count).
- [ ] Implements ALL methods of `IBrokerAdapter` (tick, order, position, account, symbol, indicator, lifecycle).

### 19.12 — Versioning

- [ ] File header: `AtlasEA v0.1.5.0` (MT5 Adapter phase).

---

**End of Specification.**

This document is implementation-ready. GLM can implement the entire MT5 Adapter from this specification alone without making any architectural decisions. All design choices are fixed. All edge cases are enumerated. All validation rules are specified. All performance budgets are defined. The MT5 Adapter is the sole broker boundary — no other module may call MT5 APIs.
