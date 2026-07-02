# AtlasEA v1.0 — Persistence Manager Production Specification

**Document version:** 1.0
**Target module:** `Infrastructure/PersistenceManager.mqh` (+ internal helpers under `Infrastructure/PersistenceManager/`)
**Interface implemented:** `IStateStore` (defined in `Interfaces/IStateStore.mqh`)
**Contracts consumed:** `AtlasContext` (from `Core/AtlasContext.mqh`), `AtlasEvent` (from `Contracts/Events.mqh`)
**Constants available:**
- Capacities: `ATLAS_EVENT_LOG_BUFFER = 64`, `ATLAS_MAX_POSITIONS = 64`, `ATLAS_IDEMPOTENCY_SLOTS = 32`
- Module ID: `ATLAS_MODULE_PERSISTENCE = 8`
- Config fields: `symbol`, `snapshot_interval_sec`

---

# 1. Responsibilities

The Persistence Manager is the **sole owner of file I/O** in AtlasEA. No other module may call `FileOpen`, `FileWrite`, `FileRead`, `FileClose`, `FileSeek`, or `FileDelete`. The Persistence Manager writes context snapshots to disk, appends events to a rolling log, and recovers state on startup. It never modifies business logic — it serializes and deserializes the shared context verbatim.

### R1.1 — Snapshot Writing

| Attribute | Value |
|-----------|-------|
| **Purpose** | Serialize the `AtlasContext` to a daily snapshot file for crash recovery. |
| **Owner** | `SnapshotManager` (internal component) |
| **Inputs** | `const AtlasContext &ctx`, `const long snapshot_id` |
| **Outputs** | Boolean: success or failure. Side effect: a `.snap` file written to the MQL5 `MQL5/Files` directory. |
| **Performance limits** | O(1) — fixed-size serialization. ≤ 5 ms per write (file I/O bound). Called on a timer (every `snapshot_interval_sec`, default 300s), never on the hot path. |
| **Failure handling** | If `FileOpen` fails, log ERROR and return false. If `FileWrite` fails mid-write, close the file and return false. The old snapshot (if any) remains intact (write-to-temp-then-rename pattern is NOT available in MQL5 — we overwrite in place, accepting partial-write risk; see Section 9). |
| **Forbidden behaviors** | Must NOT call any MT5 broker API. Must NOT modify the context. Must NOT allocate memory (`new`/`delete`). Must NOT block on network (MQL5 files are local). |

### R1.2 — Event Log Appending

| Attribute | Value |
|-----------|-------|
| **Purpose** | Append `AtlasEvent` structs to a rolling event log for audit and replay. |
| **Owner** | `EventLogWriter` (internal component) |
| **Inputs** | `const AtlasEvent &ev` |
| **Outputs** | Boolean: success or failure. Events are buffered in a fixed-size ring and flushed periodically. |
| **Performance limits** | O(1) for buffer append (≤ 0.001 ms). Flush is O(N) where N = buffer size (≤ 64), called on timer or shutdown. |
| **Failure handling** | If the buffer is full, the oldest event is evicted (FIFO) and a WARN is logged. If flush fails (disk full, permission), the buffer retains its contents and retries on the next flush. |
| **Forbidden behaviors** | Must NOT flush on every append (would stall the hot path). Must NOT lose events silently — evictions are logged. |

### R1.3 — State Recovery

| Attribute | Value |
|-----------|-------|
| **Purpose** | On startup, load the latest snapshot and replay any events logged after the snapshot. |
| **Owner** | `RecoveryEngine` (internal component) |
| **Inputs** | `AtlasContext &ctx` (mutated in place) |
| **Outputs** | Boolean: true if a snapshot was found and loaded, false on cold start. |
| **Performance limits** | O(1) for snapshot load. O(N) for event replay (N = events in log). ≤ 50 ms total (called once at startup). |
| **Failure handling** | If no snapshot exists (cold start), return false and leave the context at defaults. If the snapshot is corrupted, log ERROR and fall back to cold start. If event replay fails partway, log WARN and use the partially-reconstructed state (best-effort). |
| **Forbidden behaviors** | Must NOT crash on corruption. Must NOT skip recovery silently. Must NOT modify the context beyond the fields present in the snapshot. |

### R1.4 — Buffer Flushing

| Attribute | Value |
|-----------|-------|
| **Purpose** | Flush the event log buffer to disk. |
| **Owner** | `EventLogWriter` |
| **Inputs** | None |
| **Outputs** | Boolean: success or failure. |
| **Performance limits** | O(N), N ≤ `ATLAS_EVENT_LOG_BUFFER` (64). ≤ 5 ms. |
| **Failure handling** | If flush fails, retain the buffer and retry on the next flush call. Log WARN. |
| **Forbidden behaviors** | Must NOT flush if the buffer is empty. Must NOT flush inside `OnTick`. |

### R1.5 — File Rotation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Create new snapshot and event log files at the start of each trading day. |
| **Owner** | `FileRotationManager` (internal component) |
| **Inputs** | Current date |
| **Outputs** | New filename for the current day. |
| **Performance limits** | O(1) — filename generation only. |
| **Failure handling** | If the filename already exists (same-day restart), append to the existing file (event log) or overwrite (snapshot). |
| **Forbidden behaviors** | Must NOT delete old files automatically (retention is manual in this phase). |

### R1.6 — Integrity Verification

| Attribute | Value |
|-----------|-------|
| **Purpose** | Verify that written files are not corrupted. |
| **Owner** | `ChecksumManager` (internal component) |
| **Inputs** | Raw byte buffer |
| **Outputs** | 32-bit checksum (CRC32-style) |
| **Performance limits** | O(N) where N = buffer size. ≤ 0.1 ms for a typical snapshot. |
| **Failure handling** | If the stored checksum does not match the computed checksum on read, the file is declared corrupt. |
| **Forbidden behaviors** | Must NOT use cryptographic hashes (SHA/MD5) — too slow for MQL5. CRC32 is sufficient for corruption detection, not security. |

### R1.7 — Storage Statistics

| Attribute | Value |
|-----------|-------|
| **Purpose** | Track snapshot count, event count, flush count, failure count. |
| **Owner** | `StorageStatistics` (internal component) |
| **Inputs** | Per-operation: operation type, success/failure, bytes written |
| **Outputs** | Counters accessible via accessors |
| **Performance limits** | O(1) per update |

---

# 2. Internal Components

The Persistence Manager is decomposed into 9 internal components. All are stack-allocated. All live under `Infrastructure/PersistenceManager/`.

### 2.1 — SnapshotManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Serialize the context to a `.snap` file. Overwrite the daily snapshot. |
| **Owned data** | None (stateless between calls). |
| **Public interface** | `bool Write(const AtlasContext &ctx, const long id, ILogger *logger, const string symbol)`, `bool Read(AtlasContext &ctx, ILogger *logger, const string symbol)` |
| **Private helpers** | `string GenerateFilename(const string symbol) const`, `bool Serialize(const AtlasContext &ctx, uchar &buffer[], int &out_size) const`, `bool Deserialize(const uchar &buffer[], const int size, AtlasContext &ctx) const`, `void WriteFieldInt(int handle, const string key, const long value)`, `void WriteFieldDouble(int handle, const string key, const double value)`, `void WriteFieldString(int handle, const string key, const string value)`, `bool ReadField(const string line, const string &out_key, string &out_val) const` |
| **Dependencies** | `AtlasContext`, `ILogger`, `ChecksumManager` |
| **Failure modes** | `FileOpen` fails → return false. `FileWrite` fails → close, return false. Corruption on read → return false. |
| **Performance limits** | ≤ 5 ms per write/read. |

### 2.2 — EventLogWriter

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Buffer events in a fixed-size ring. Flush to a `.log` file on demand. |
| **Owned data** | `AtlasEvent m_buffer[ATLAS_EVENT_LOG_BUFFER]` (64 events), `int m_count`, `string m_current_filename` |
| **Public interface** | `bool Append(const AtlasEvent &ev, ILogger *logger)`, `bool Flush(ILogger *logger, const string symbol)`, `void Reset()`, `int BufferedCount() const` |
| **Private helpers** | `string GenerateFilename(const string symbol) const`, `bool OpenForAppend(int &out_handle, const string filename, ILogger *logger)`, `void WriteEventLine(int handle, const AtlasEvent &ev)`, `string EventToString(const AtlasEvent &ev) const` |
| **Dependencies** | `AtlasEvent`, `ILogger` |
| **Failure modes** | Buffer full → evict oldest, log WARN. Flush fails → retain buffer, log WARN. |
| **Performance limits** | Append: O(1). Flush: O(N), N ≤ 64. |

### 2.3 — EventLogReader

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Read events from a `.log` file for replay during recovery. |
| **Owned data** | None. |
| **Public interface** | `int ReadAll(const string filename, AtlasEvent &out_events[], const int max_count, ILogger *logger) const` |
| **Private helpers** | `bool ParseEventLine(const string line, AtlasEvent &out) const` |
| **Dependencies** | `AtlasEvent`, `ILogger` |
| **Failure modes** | File not found → return 0. Parse error → skip line, log WARN, continue. |
| **Performance limits** | O(N) where N = lines in file. ≤ 10 ms for typical log. |

### 2.4 — RecoveryEngine

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Orchestrate startup recovery: load snapshot, replay events, verify consistency. |
| **Owned data** | None. |
| **Public interface** | `bool Recover(AtlasContext &ctx, ILogger *logger, const string symbol, RecoveryStatistics &out_stats)` |
| **Private helpers** | `bool LoadLatestSnapshot(AtlasContext &ctx, ILogger *logger, const string symbol)`, `int ReplayEventLog(AtlasContext &ctx, ILogger *logger, const string symbol, const long last_snapshot_id)`, `bool VerifyConsistency(const AtlasContext &ctx, ILogger *logger) const` |
| **Dependencies** | `SnapshotManager`, `EventLogReader`, `AtlasContext`, `ILogger`, `RecoveryStatistics` |
| **Failure modes** | No snapshot → cold start (return false). Corrupt snapshot → cold start. Event log missing → use snapshot only. Event replay partial → best-effort. |
| **Performance limits** | ≤ 50 ms total. |

### 2.5 — SnapshotValidator

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Validate a deserialized context for internal consistency. |
| **Owned data** | None. |
| **Public interface** | `bool Validate(const AtlasContext &ctx, string &out_reason) const` |
| **Private helpers** | `bool ValidateNumericRanges(const AtlasContext &ctx, string &out_reason) const`, `bool ValidateTimestamps(const AtlasContext &ctx, string &out_reason) const`, `bool ValidateVersion(const AtlasContext &ctx, string &out_reason) const` |
| **Dependencies** | `AtlasContext` |
| **Failure modes** | Returns false with reason on any inconsistency. |
| **Performance limits** | O(1) |

### 2.6 — FileRotationManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Generate daily filenames. Detect day rollover. |
| **Owned data** | `datetime m_current_day_start` |
| **Public interface** | `string SnapshotFilename(const string symbol) const`, `string EventLogFilename(const string symbol) const`, `bool IsNewDay() const`, `void UpdateDayMarker()` |
| **Private helpers** | `string FormatDate(const datetime t) const` |
| **Dependencies** | None. |
| **Failure modes** | None — pure string generation. |
| **Performance limits** | O(1) |

### 2.7 — ChecksumManager

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Compute and verify CRC32 checksums for data integrity. |
| **Owned data** | `uint m_crc_table[256]` (precomputed lookup table) |
| **Public interface** | `uint Compute(const uchar &buffer[], const int size) const`, `bool Verify(const uchar &buffer[], const int size, const uint expected) const` |
| **Private helpers** | `void InitTable()`, `uint Reflect(uint ref, char ch) const` |
| **Dependencies** | None. |
| **Failure modes** | None — pure arithmetic. |
| **Performance limits** | O(N), N = buffer size. ≤ 0.1 ms for typical snapshot. |

### 2.8 — StorageStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track persistence operation counts and latencies. |
| **Owned data** | `ulong m_snapshots_written`, `m_snapshots_restored`, `m_events_logged`, `m_events_flushed`, `m_flush_failures`, `m_corruption_count`, `m_checksum_failures`, `double m_total_snapshot_ms`, `m_total_recovery_ms` |
| **Public interface** | `void RecordSnapshotWrite(const bool success, const double ms)`, `void RecordSnapshotRestore(const bool success, const double ms)`, `void RecordEventAppended()`, `void RecordEventFlushed(const int count)`, `void RecordFlushFailure()`, `void RecordCorruption()`, `void RecordChecksumFailure()`, `void Reset()`, `void LogSummary(ILogger *logger) const`, accessors |
| **Private helpers** | None. |
| **Dependencies** | `ILogger` |
| **Failure modes** | None — best-effort counters. |
| **Performance limits** | O(1) |

### 2.9 — RecoveryStatistics

| Attribute | Value |
|-----------|-------|
| **Responsibilities** | Track a single recovery operation's results. |
| **Owned data** | `bool m_snapshot_found`, `bool m_snapshot_valid`, `int m_events_replayed`, `int m_events_skipped`, `double m_recovery_ms`, `string m_failure_reason` |
| **Public interface** | `void Reset()`, `void SetSnapshotFound(const bool found)`, `void SetSnapshotValid(const bool valid)`, `void SetEventsReplayed(const int count)`, `void SetEventsSkipped(const int count)`, `void SetRecoveryMs(const double ms)`, `void SetFailureReason(const string reason)`, `void LogReport(ILogger *logger) const` |
| **Private helpers** | None. |
| **Dependencies** | `ILogger` |
| **Failure modes** | None — data holder. |
| **Performance limits** | O(1) |

---

# 3. Snapshot Lifecycle

### 3.1 — Snapshot Scheduling

- Snapshots are scheduled by `CoreEngine::OnTimer()`.
- Interval: `config.snapshot_interval_sec` (default 300 seconds = 5 minutes).
- The `SnapshotManager.IsSnapshotDue(now)` check in `CoreEngine` determines if a snapshot is due.
- Snapshots are NOT written on the hot path (`OnTick`).

### 3.2 — Snapshot Creation

1. `CoreEngine` calls `IStateStore::WriteSnapshot(ctx, snapshot_id)`.
2. `PersistenceManager::WriteSnapshot()` delegates to `SnapshotManager.Write()`.
3. The `AtlasContext` is serialized into a key=value text format (human-readable for debugging).

### 3.3 — Serialization

The snapshot is a text file with one `key=value` pair per line. Fields serialized:

| Key | Type | Source Field |
|-----|------|-------------|
| `version` | int | `1` (snapshot format version) |
| `snapshot_id` | long | `ctx.GetSnapshotId()` |
| `trading_day_start` | long | `ctx.GetTradingDayStart()` |
| `daily_start_equity` | double | `ctx.GetDailyStartEquity()` |
| `daily_peak_equity` | double | `ctx.GetDailyPeakEquity()` |
| `daily_drawdown_pct` | double | `ctx.GetDailyDrawdownPct()` |
| `daily_realized_pnl` | double | `ctx.GetDailyRealizedPnl()` |
| `daily_trade_count` | int | `ctx.GetDailyTradeCount()` |
| `daily_loss_count` | int | `ctx.GetDailyLossCount()` |
| `consecutive_losses` | int | `ctx.GetConsecutiveLosses()` |
| `kill_switch_active` | int | `ctx.IsKillSwitchActive() ? 1 : 0` |
| `kill_switch_reason` | string | `ctx.GetKillSwitchReason()` |
| `kill_switch_time` | long | `ctx.GetKillSwitchTime()` |
| `cooldown_until` | long | `ctx.GetCooldownUntil()` |
| `last_trade_time` | long | `ctx.GetLastTradeTime()` |
| `current_exposure_pct` | double | `ctx.GetCurrentExposurePct()` |
| `total_floating_pnl` | double | `ctx.GetTotalFloatingPnl()` |
| `total_ticks_processed` | long | `ctx.GetTotalTicksProcessed()` |
| `total_events_emitted` | long | `ctx.GetTotalEventsEmitted()` |
| `total_orders_sent` | long | `ctx.GetTotalOrdersSent()` |
| `total_orders_filled` | long | `ctx.GetTotalOrdersFilled()` |
| `context_version` | long | `ctx.GetContextVersion()` |
| `checksum` | uint | CRC32 of all preceding lines |

### 3.4 — Compression

- No compression in this phase. The snapshot is small (~2 KB uncompressed). Compression adds complexity and CPU cost without meaningful benefit.
- Future phase may add zlib compression if snapshot size grows.

### 3.5 — Checksum

- A CRC32 checksum is computed over all serialized lines (excluding the checksum line itself).
- The checksum is written as the last line: `checksum=<uint>`.
- On read, the checksum is recomputed and compared. Mismatch → corruption detected.

### 3.6 — Writing

1. Generate filename: `AtlasEA_{symbol}_{YYYYMMDD}.snap`.
2. `FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI)`.
3. Write each `key=value\n` line via `FileWriteString`.
4. Compute CRC32 over all written bytes.
5. Write `checksum=<crc32>\n`.
6. `FileClose`.

### 3.7 — Verification

- Verification happens on READ (during recovery), not on write.
- After writing, the file is NOT re-read to verify (would double the I/O cost). The checksum is trusted until the next recovery.

### 3.8 — Retention

- One snapshot file per trading day per symbol.
- Old snapshot files are NOT automatically deleted (manual retention in this phase).
- Future phase may add `RetentionManager` to delete files older than N days.

### 3.9 — Deletion

- No automatic deletion. The operator may manually delete old `.snap` files from `MQL5/Files/`.

### 3.10 — Recovery

1. On startup, `RecoveryEngine.Recover()` is called.
2. `SnapshotManager.Read()` attempts to open `AtlasEA_{symbol}_{YYYYMMDD}.snap`.
3. If the file exists, deserialize line by line.
4. Verify the checksum.
5. If valid, populate `AtlasContext` via its setters.
6. If invalid (corrupt or missing), fall back to cold start.

---

# 4. Event Log Lifecycle

### 4.1 — Event Append

1. `CoreEngine` (via `EventDispatcher` or directly) calls `IStateStore::AppendEvent(ev)`.
2. `PersistenceManager::AppendEvent()` delegates to `EventLogWriter.Append()`.
3. If the buffer is not full, the event is copied into the ring.
4. If the buffer is full, the oldest event is evicted (FIFO), and the new event is appended. A WARN is logged.

### 4.2 — Buffering

- The buffer is a fixed-size array: `AtlasEvent m_buffer[ATLAS_EVENT_LOG_BUFFER]` (64 events).
- No dynamic allocation. Eviction is FIFO (shift-left or ring index).
- Buffering decouples the hot path (append) from the slow path (file I/O).

### 4.3 — Flush

1. `CoreEngine::OnTimer()` or `CoreEngine::Shutdown()` calls `IStateStore::FlushEventBuffer()`.
2. `EventLogWriter.Flush()` opens the log file for append.
3. Each buffered event is written as a CSV line: `type,timestamp,snapshot_id,source_module`.
4. The buffer is cleared (count = 0).
5. The file is closed.

### 4.4 — Rotation

- A new log file is created at the start of each trading day: `AtlasEA_{symbol}_{YYYYMMDD}.log`.
- `FileRotationManager.IsNewDay()` detects the rollover.
- On rollover, the next flush writes to the new file. The old file is NOT closed explicitly (it was closed after the last flush).

### 4.5 — Verification

- Event log lines are NOT checksummed individually (too much overhead).
- The entire log file's integrity is verified by the `EventLogReader` during recovery: lines that fail to parse are skipped with a WARN.

### 4.6 — Recovery

- On startup, `RecoveryEngine` reads the event log for the current day.
- Events with `timestamp > last_snapshot_time` are "replayed" (their effect is already captured in the context snapshot, so replay is informational — it logs the events but does NOT re-apply them, since the snapshot already contains the final state).
- True event-sourcing replay (rebuilding state from events) is deferred to a future phase. In this phase, the snapshot is the source of truth; the event log is for audit only.

### 4.7 — Replay

- Replay in this phase = reading the event log and counting events for statistics.
- The context is NOT mutated during replay (the snapshot already has the final state).
- Future phase may implement true event sourcing (rebuild context from a base snapshot + event diff).

### 4.8 — Truncation Protection

- MQL5 `FileOpen(FILE_WRITE | FILE_READ)` opens for read-write without truncation.
- `FileSeek(handle, 0, SEEK_END)` positions at the end for appending.
- The file is NEVER truncated during normal operation.
- On corruption, the file is NOT repaired — it is logged and skipped.

### 4.9 — Corruption Handling

- If `EventLogReader` encounters a line that does not parse (wrong field count, non-numeric values), the line is skipped with a WARN.
- The reader continues to the next line. Partial recovery is acceptable for the event log (it's audit-only).
- If the snapshot is corrupt (checksum mismatch), the entire recovery falls back to cold start.

---

# 5. Recovery Process

### 5.1 — Locate Latest Snapshot

1. `RecoveryEngine` calls `SnapshotManager.Read()`.
2. `SnapshotManager` generates the filename for the current day: `AtlasEA_{symbol}_{YYYYMMDD}.snap`.
3. `FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI)`.
4. If the file does not exist, return false (cold start).

### 5.2 — Validate Snapshot

1. Read all lines into a string array (fixed-size, max 64 lines).
2. Extract the `checksum` line.
3. Recompute CRC32 over all other lines.
4. Compare. If mismatch → corruption → return false.
5. Call `SnapshotValidator.Validate()` to check internal consistency (numeric ranges, timestamps, version).

### 5.3 — Load Snapshot

1. Parse each `key=value` line.
2. For each key, call the corresponding `AtlasContext` setter.
3. Do NOT call `ResetAll()` first — the context is already at defaults from construction.
4. After all fields are loaded, the context reflects the persisted state.

### 5.4 — Locate Event Logs

1. `EventLogReader` generates the filename: `AtlasEA_{symbol}_{YYYYMMDD}.log`.
2. `FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI)`.
3. If the file does not exist, skip event replay (snapshot-only recovery).

### 5.5 — Replay Events

1. Read the event log line by line.
2. Parse each line into an `AtlasEvent`.
3. Count events for statistics (`RecoveryStatistics.m_events_replayed`).
4. Do NOT mutate the context (the snapshot already has the final state).
5. Skip unparseable lines (`m_events_skipped`).

### 5.6 — Validate Reconstructed State

1. Call `SnapshotValidator.Validate()` on the loaded context.
2. If invalid, log WARN and proceed anyway (best-effort — the operator should investigate).

### 5.7 — Consistency Verification

1. Check `ctx.GetTradingDayStart()` — if it's from a previous day, the daily reset will be triggered by `CoreEngine` on the first tick.
2. Check `ctx.IsKillSwitchActive()` — if active, it remains active until `CoreEngine` detects a new day and calls `ResetDailyLimits()`.
3. Log a recovery report via `RecoveryStatistics.LogReport()`.

### 5.8 — Recovery Report Generation

The recovery report includes:
- Snapshot found: yes/no
- Snapshot valid: yes/no
- Checksum verified: yes/no
- Events replayed: N
- Events skipped: N
- Recovery duration: X ms
- Final state: snapshot_id, kill_switch_active, daily_drawdown_pct

### 5.9 — Fallback Strategy

| Condition | Fallback |
|-----------|----------|
| No snapshot file | Cold start (context at defaults) |
| Snapshot corrupt (checksum mismatch) | Cold start. Log ERROR. |
| Snapshot invalid (failed validation) | Cold start. Log ERROR. |
| Event log missing | Use snapshot only. Log INFO. |
| Event log corrupt (partial) | Use snapshot + skip corrupt events. Log WARN. |
| Event log fully corrupt | Use snapshot only. Log WARN. |
| All recovery fails | Cold start. Log ERROR. EA continues with fresh state. |

### 5.10 — Cold Start Behavior

- `AtlasContext` is at its constructor defaults (all zeros/empty).
- `CoreEngine::Initialize()` detects `ctx.GetTradingDayStart() == 0` and calls `ContextFactory.ResetDaily()`.
- The EA starts trading from a clean slate. No historical state is recovered.

---

# 6. Snapshot Specification

### 6.1 — File Naming

- Format: `AtlasEA_{symbol}_{YYYYMMDD}.snap`
- Example: `AtlasEA_EURUSD_20250701.snap`
- Location: MQL5 `MQL5/Files/` directory (terminal sandbox).
- One file per symbol per day.

### 6.2 — Version

- The first line of the snapshot is `version=1`.
- This is the snapshot format version, distinct from the EA version.
- Future format changes increment this number. The reader checks the version and rejects incompatible files.

### 6.3 — Header

- The header is the first two lines:
  - `version=1`
  - `symbol={symbol}`
- The reader validates that the symbol matches `config.symbol`. Mismatch → reject.

### 6.4 — Metadata

- After the header, metadata fields follow (one per line):
  - `snapshot_id`, `trading_day_start`, `timestamp` (when the snapshot was written).

### 6.5 — Payload

- The payload is the context state fields (see Section 3.3 for the full list).
- Each field is a `key=value` line.

### 6.6 — Checksum

- The last line is `checksum=<uint>` (CRC32).
- Computed over all bytes from the start of the file to the byte before the checksum line.

### 6.7 — Compression

- None in this phase. Uncompressed text.

### 6.8 — Compatibility

- Forward compatibility: a newer reader can read an older snapshot if new fields have defaults. The reader ignores unknown keys.
- Backward compatibility: an older reader cannot read a newer snapshot if required fields are missing. The reader logs ERROR and falls back to cold start.

### 6.9 — Forward Compatibility

- New fields can be added by appending new `key=value` lines before the checksum line.
- Old readers ignore unknown keys (defensive parsing).
- The version number MUST be incremented when the format changes in a breaking way.

### 6.10 — Backward Compatibility

- Old snapshots (version 1) are always readable by the current reader.
- If the version is > 1 and the reader only supports version 1, it rejects the snapshot and falls back to cold start.

---

# 7. Event Log Specification

### 7.1 — Record Format

- One event per line, CSV format:
  - `type,timestamp,snapshot_id,source_module`
- Example: `7,1750000000,42,MT5Adapter`

### 7.2 — Sequence Number

- Not stored. Events are ordered by their position in the file (append order).
- The `timestamp` field provides a secondary ordering key.

### 7.3 — Timestamp

- `datetime` as Unix epoch seconds (long).
- Set by the emitter (`CoreEngine::EmitEvent`) at event creation time.

### 7.4 — Snapshot Linkage

- The `snapshot_id` field links the event to the market snapshot it relates to.
- During recovery, events with `snapshot_id > last_snapshot_id` are considered "post-snapshot" and could be replayed (in a future event-sourcing phase).

### 7.5 — Payload

- The event `payload` (uchar array) is NOT written to the log in this phase (it would require binary encoding).
- Only the metadata (type, timestamp, snapshot_id, source) is logged.
- Future phase may add binary payload serialization.

### 7.6 — CRC

- No per-line CRC (overhead).
- No file-level CRC (the log is append-only; a CRC would need recomputation on every append).
- Integrity is verified by line parsing only: unparseable lines are skipped.

### 7.7 — Maximum Size

- No hard limit on file size (MQL5 handles large files).
- Practical limit: one trading day of events. At 8 events/tick × 1 tick/sec × 28800 sec/day = 230,400 events max. At ~50 bytes/line = ~11 MB. Acceptable.
- If the file exceeds 100 MB, log WARN (disk space concern).

### 7.8 — Rotation

- Daily rotation: a new file is created at the start of each trading day.
- `FileRotationManager.IsNewDay()` returns true when the calendar day changes.
- The old file is NOT modified after rotation.

### 7.9 — Retention

- No automatic retention. Old `.log` files accumulate.
- Future phase may add `RetentionManager` to delete files older than N days.

---

# 8. File Management

### 8.1 — Directory Layout

- All files are in the MQL5 `MQL5/Files/` directory (terminal sandbox).
- No subdirectories in this phase.
- Files are prefixed with `AtlasEA_` for easy identification.

### 8.2 — Naming Policy

| File Type | Pattern | Example |
|-----------|---------|---------|
| Snapshot | `AtlasEA_{symbol}_{YYYYMMDD}.snap` | `AtlasEA_EURUSD_20250701.snap` |
| Event Log | `AtlasEA_{symbol}_{YYYYMMDD}.log` | `AtlasEA_EURUSD_20250701.log` |

- `YYYYMMDD` is the server date (`TimeCurrent()`).
- Symbol is sanitized (non-alphanumeric characters removed).

### 8.3 — Rotation Policy

- Daily rotation for both snapshot and event log.
- Triggered by `FileRotationManager.IsNewDay()`.

### 8.4 — Cleanup Policy

- No automatic cleanup. Manual retention.
- The operator can delete old files from `MQL5/Files/`.

### 8.5 — Retention Policy

- No retention enforcement in this phase.
- Future phase: `RetentionManager` deletes files older than `config.retention_days`.

### 8.6 — Disk Space Monitoring

- Not implemented in this phase.
- MQL5 does not provide a direct "free disk space" API.
- If `FileOpen` fails (disk full), the error is logged. The EA continues running (persistence is best-effort).

### 8.7 — Maximum File Count

- 2 files per day (1 snapshot + 1 event log).
- Over a year: ~730 files. Acceptable.
- No hard limit enforced.

---

# 9. Integrity Verification

### 9.1 — Checksum

- CRC32 computed by `ChecksumManager`.
- Stored as the last line of the snapshot file.
- Verified on read. Mismatch → corruption → cold start.

### 9.2 — CRC

- CRC32 (polynomial 0xEDB88320, standard CRC-32).
- Precomputed 256-entry lookup table for O(N) computation.
- Not cryptographic — detects random corruption, not malicious tampering.

### 9.3 — Corruption Detection

| Detection Method | Scope | Action |
|------------------|-------|--------|
| CRC32 mismatch | Snapshot | Reject snapshot, cold start |
| Parse error | Event log line | Skip line, log WARN |
| Version mismatch | Snapshot | Reject snapshot, cold start |
| Symbol mismatch | Snapshot header | Reject snapshot, cold start |
| Missing checksum line | Snapshot | Reject snapshot, cold start |

### 9.4 — Partial Write Detection

- MQL5 `FileWrite` is synchronous. If the EA crashes mid-write, the file may be truncated.
- Detection: the file will be missing the `checksum=` line, OR the checksum will not match the partial content.
- Recovery: treat as corrupt → cold start.

### 9.5 — Interrupted Write Recovery

- If a snapshot write is interrupted (crash), the old snapshot is lost (overwritten in place).
- MQL5 does not support atomic file rename in the `MQL5/Files/` sandbox.
- Mitigation: the next snapshot (in `snapshot_interval_sec`) will write a fresh file. The EA operates without a valid snapshot until then.
- Future phase may use a write-to-temp-then-rename pattern if MQL5 adds atomic rename support.

### 9.6 — Version Mismatch

- If `version` line is missing or not 1, the snapshot is rejected.
- Log ERROR: "Snapshot version mismatch: expected 1, got {version}".

### 9.7 — Rollback Policy

- No rollback in this phase. A corrupt snapshot = cold start.
- Future phase may keep the last N snapshots and roll back to the previous one on corruption.

---

# 10. Performance Budget

### 10.1 — Maximum Snapshot Latency

- ≤ 5 ms per write (file I/O bound).
- ≤ 5 ms per read (during recovery).
- Called on timer (every 300s) or shutdown — NOT on the hot path.

### 10.2 — Maximum Recovery Latency

- ≤ 50 ms total (snapshot load + event log read).
- Called once at startup.

### 10.3 — Maximum Flush Latency

- ≤ 5 ms per flush (64 events × ~50 bytes = ~3 KB).
- Called on timer (every `heartbeat_interval_sec`, default 10s) or shutdown.

### 10.4 — Maximum Replay Speed

- O(N) where N = event log lines. ≤ 10 ms for a typical daily log (~10,000 events).

### 10.5 — Memory Limits

- Event log buffer: 64 × `AtlasEvent` (~120 bytes each) = ~7.7 KB.
- Snapshot read buffer: ~2 KB (text lines).
- `ChecksumManager` CRC table: 256 × 4 bytes = 1 KB.
- `StorageStatistics` + `RecoveryStatistics`: ~256 bytes.
- Total: ~11 KB stack.

### 10.6 — No Dynamic Allocation

- `new` and `delete` are FORBIDDEN in all persistence methods.
- All buffers are fixed-size stack arrays.
- String operations (filename generation, line parsing) are unavoidable but minimal.

---

# 11. Metrics

The `StorageStatistics` component collects:

| Metric | Type | Description |
|--------|------|-------------|
| `snapshots_written` | `ulong` | Total snapshot write calls. |
| `snapshots_restored` | `ulong` | Total snapshot read calls (recovery). |
| `events_logged` | `ulong` | Total events appended to the buffer. |
| `events_flushed` | `ulong` | Total events written to disk. |
| `flush_failures` | `ulong` | Total flush failures. |
| `corruption_count` | `ulong` | Total corruption detections. |
| `checksum_failures` | `ulong` | Total checksum mismatches. |
| `total_snapshot_ms` | `double` | Sum of all snapshot write latencies. |
| `total_recovery_ms` | `double` | Sum of all recovery latencies. |
| `average_snapshot_ms` | `double` | `total_snapshot_ms / snapshots_written`. |
| `average_recovery_ms` | `double` | `total_recovery_ms / snapshots_restored`. |

The `RecoveryStatistics` (per-recovery) collects:

| Metric | Type | Description |
|--------|------|-------------|
| `snapshot_found` | `bool` | Was a snapshot file found? |
| `snapshot_valid` | `bool` | Did the snapshot pass validation? |
| `events_replayed` | `int` | Number of events read from the log. |
| `events_skipped` | `int` | Number of unparseable events skipped. |
| `recovery_ms` | `double` | Total recovery duration. |
| `failure_reason` | `string` | Reason if recovery failed. |

---

# 12. Logging

All logging through `ILogger`. `Print()` is FORBIDDEN.

### 12.1 — Log Categories

| Level | Category | When |
|-------|----------|------|
| **DEBUG** | Event appended | "Event appended to buffer: type={t} count={n}" |
| **DEBUG** | Snapshot scheduled | "Snapshot due in {n}s" |
| **INFO** | Initialization | "PersistenceManager initialized: symbol={s}" |
| **INFO** | Shutdown | "PersistenceManager shutdown. Snapshots={n} Events={m}" |
| **INFO** | Snapshot written | "Snapshot {id} written to {filename} ({ms}ms)" |
| **INFO** | Snapshot restored | "Snapshot restored: id={id} kill_switch={ks} ({ms}ms)" |
| **INFO** | Recovery report | "Recovery: snapshot={found} events_replayed={n} duration={ms}ms" |
| **INFO** | Diagnostics summary | On `LogDiagnostics()` (heartbeat only) |
| **WARN** | Buffer full, event evicted | "Event buffer full: oldest event evicted" |
| **WARN** | Flush failed | "Flush failed: {error}. Buffer retained." |
| **WARN** | Event log line skipped | "Event log line {n} unparseable: {line}" |
| **WARN** | Disk space concern | "Event log exceeds 100 MB: {size} MB" |
| **ERROR** | Snapshot write failed | "Snapshot write failed: FileOpen error {err}" |
| **ERROR** | Snapshot read failed | "Snapshot read failed: FileOpen error {err}" |
| **ERROR** | Checksum mismatch | "Snapshot corrupt: checksum mismatch (expected={e} actual={a})" |
| **ERROR** | Version mismatch | "Snapshot version mismatch: expected 1, got {v}" |
| **ERROR** | Symbol mismatch | "Snapshot symbol mismatch: expected={e} got={g}" |
| **ERROR** | Recovery failed | "Recovery failed: {reason}. Falling back to cold start." |
| **CRITICAL** | Not used | N/A (persistence failures are non-fatal — EA continues) |

### 12.2 — Recovery Logs

- Recovery is logged at INFO on success, ERROR on failure.
- The recovery report is always logged (even on cold start).

### 12.3 — Storage Logs

- Snapshot writes are logged at INFO (not DEBUG — they're infrequent and important).
- Event flushes are logged at DEBUG (frequent).
- Corruption is logged at ERROR.

### 12.4 — Hot Path Logging Policy

- `AppendEvent` (called on the hot path) logs at DEBUG only.
- No INFO/WARN/ERROR logging in `AppendEvent` unless the buffer is full (WARN).

---

# 13. Edge Cases

| # | Edge Case | Behavior |
|---|-----------|----------|
| EC1 | Power failure during snapshot write | Snapshot file is truncated/corrupt. On next startup, checksum mismatch → cold start. |
| EC2 | Power failure during event write | Event log file is truncated. On recovery, partial lines are skipped. |
| EC3 | Corrupted snapshot (random bytes) | Checksum mismatch → cold start. Log ERROR. |
| EC4 | Corrupted event log | Unparseable lines skipped. Log WARN per line. Recovery continues. |
| EC5 | Missing snapshot (first run) | Cold start. Log INFO: "No snapshot found — cold start." |
| EC6 | Missing event log | Snapshot-only recovery. Log INFO. |
| EC7 | Version mismatch (snapshot v2, reader v1) | Reject snapshot. Cold start. Log ERROR. |
| EC8 | Disk full | `FileOpen` or `FileWrite` fails. Log ERROR. EA continues (persistence is best-effort). Buffer retained for retry. |
| EC9 | Read failure (I/O error) | `FileRead` returns 0. Log ERROR. Cold start. |
| EC10 | Write failure (I/O error) | `FileWrite` returns 0. Log ERROR. Return false. |
| EC11 | Permission failure | `FileOpen` returns `INVALID_HANDLE`. Log ERROR. Cold start (read) or skip (write). |
| EC12 | Interrupted replay | Partial recovery. Log WARN. Use partially-reconstructed state. |
| EC13 | Snapshot from previous day | Loaded as-is. `CoreEngine` detects new day and triggers `ResetDailyLimits()`. |
| EC14 | Kill switch active in snapshot | Loaded as-is. Kill switch remains active until daily reset. |
| EC15 | Empty snapshot file (0 bytes) | No checksum line → corrupt → cold start. Log ERROR. |
| EC16 | Empty event log file | 0 events replayed. Log INFO. |
| EC17 | Event log with only partial line | Skipped. Log WARN. |
| EC18 | Symbol change (config.symbol differs from snapshot) | Snapshot rejected. Cold start. Log ERROR. |
| EC19 | Multiple snapshot files (same day) | Not possible — filename is deterministic by date. Overwrite. |
| EC20 | `FileOpen` returns `INVALID_HANDLE` | Log ERROR with `GetLastError()`. Return false. |
| EC21 | Checksum line missing | Treat as corrupt. Cold start. Log ERROR. |
| EC22 | Checksum line present but empty | Treat as corrupt. Cold start. Log ERROR. |
| EC23 | Negative values in snapshot | `SnapshotValidator` catches. Reject. Cold start. |
| EC24 | NaN values in snapshot | `SnapshotValidator` catches (via `MathIsValidNumber`). Reject. Cold start. |
| EC25 | Context version 0 in snapshot | Acceptable (first snapshot after cold start). Load as-is. |
| EC26 | Very large event log (>100 MB) | Log WARN. Continue reading (may be slow). |
| EC27 | `FlushEventBuffer` called with empty buffer | Return true immediately. No file I/O. |
| EC28 | `WriteSnapshot` called during recovery | Not possible — recovery is synchronous in `Initialize()`. |
| EC29 | Concurrent access (two EAs, same symbol) | Not prevented. Both write to the same file. Corruption likely. Operator must ensure only one EA per symbol. |
| EC30 | Terminal sandbox path change | MQL5 always uses `MQL5/Files/`. If the terminal moves, files are not found → cold start. |

---

# 14. Validation Matrix

| Field | Validation | Severity | Recovery | Action |
|-------|------------|----------|----------|--------|
| `version` | Must be 1 | ERROR | Cold start | Reject snapshot |
| `symbol` | Must match config | ERROR | Cold start | Reject snapshot |
| `checksum` | Must match computed CRC32 | ERROR | Cold start | Reject snapshot |
| `snapshot_id` | Must be > 0 | WARN | None | Load anyway (may be first snapshot) |
| `daily_start_equity` | Must not be NaN | ERROR | Cold start | Reject |
| `daily_peak_equity` | Must not be NaN | ERROR | Cold start | Reject |
| `daily_drawdown_pct` | Must be ≥ 0 | WARN | None | Load (may be 0) |
| `kill_switch_active` | Must be 0 or 1 | ERROR | Cold start | Reject |
| `consecutive_losses` | Must be ≥ 0 | WARN | None | Load |
| `cooldown_until` | Must be ≥ 0 | WARN | None | Load |
| `trading_day_start` | Must be > 0 (if not cold start) | WARN | None | Load |
| `total_ticks_processed` | Must be ≥ 0 | WARN | None | Load |
| `context_version` | Must be ≥ 0 | WARN | None | Load |
| Event log line format | Must have 4 CSV fields | WARN | Skip line | Continue |
| Event `type` | Must be in [0, 12] | WARN | Skip event | Continue |
| Event `timestamp` | Must be > 0 | WARN | Skip event | Continue |
| Event `snapshot_id` | Must be ≥ 0 | WARN | Skip event | Continue |
| Event `source_module` | Must be non-empty | WARN | Skip event | Continue |

---

# 15. State Machine

The Persistence Manager is mostly stateless between calls. The event log buffer has a simple state, and recovery has its own state machine.

### Buffer State Machine

```
    IDLE (buffer empty)
       │
       │ AppendEvent()
       ▼
    BUFFERING (1..63 events)
       │
       ├── AppendEvent() ──► BUFFERING (or evict if full)
       │
       └── FlushEventBuffer()
              │
              ▼
           WRITING (flushing to disk)
              │
              ├── success ──► IDLE (buffer cleared)
              │
              └── failure ──► BUFFERING (buffer retained)
```

### Recovery State Machine

```
    IDLE (entry)
       │
       ▼
    RECOVERING
       │
       ├── no snapshot ──► READY (cold start)
       │
       ▼ (snapshot found)
    VERIFYING (checksum + validation)
       │
       ├── corrupt/invalid ──► FAILED ──► READY (cold start)
       │
       ▼ (valid)
    LOADING (populate context)
       │
       ▼
    [Read event log]
       │
       ├── no log ──► READY (snapshot only)
       │
       ▼ (log found)
    REPLAYING (read events)
       │
       ▼
    READY (recovery complete)
```

### State Definitions

| State | Description | Entry | Exit |
|-------|-------------|-------|------|
| **IDLE** | Buffer empty, no operation in progress. | Initial state. | `AppendEvent` or `FlushEventBuffer`. |
| **BUFFERING** | Events in buffer, waiting for flush. | `AppendEvent`. | `FlushEventBuffer` or shutdown. |
| **WRITING** | Flush in progress (file I/O). | `FlushEventBuffer`. | Flush completes (success → IDLE, failure → BUFFERING). |
| **VERIFYING** | Snapshot checksum + validation. | Recovery start. | Valid → LOADING. Invalid → FAILED. |
| **LOADING** | Populating context from snapshot. | Snapshot valid. | All fields loaded → read event log. |
| **REPLAYING** | Reading event log. | Event log found. | All lines read → READY. |
| **RECOVERING** | Umbrella state for the entire recovery process. | `Recover()` called. | Recovery complete → READY. |
| **READY** | Recovery complete (or cold start). Normal operation. | Recovery finishes. | Next `WriteSnapshot` or `AppendEvent`. |
| **FAILED** | Recovery failed (corrupt snapshot). | Verification fails. | Fall back to cold start → READY. |
| **ROTATING** | Day rollover detected, new file generated. | `IsNewDay()` returns true. | New filename set → IDLE. |

---

# 16. Security Constraints

### 16.1 — Persistence Manager MUST NEVER Modify Business Logic

The Persistence Manager serializes and deserializes the context. It does NOT interpret, validate, or modify the business meaning of any field. It is a pure storage layer.

### 16.2 — Persistence Manager MUST NEVER Modify Contracts

The `AtlasEvent`, `AtlasContext`, and all contracts are treated as opaque data. The manager reads/writes their fields via the public interface but does NOT change the struct definitions.

### 16.3 — Persistence Manager MUST NEVER Modify RiskDecision

The Persistence Manager does not see `RiskDecision`. It only sees `AtlasContext` (for snapshots) and `AtlasEvent` (for the event log).

### 16.4 — Persistence Manager MUST NEVER Modify MarketState

The Persistence Manager does not see `MarketState`. It persists the context (which contains risk state, not market state).

### 16.5 — Persistence Manager MUST NEVER Generate Events

The Persistence Manager does NOT emit events onto the event bus. It receives events (via `AppendEvent`) and stores them. It does not create new events. (The `CoreEngine` emits `EV_STATE_PERSISTED` after a successful snapshot — not the Persistence Manager.)

### 16.6 — Persistence Manager MUST NEVER Access Broker Directly

The Persistence Manager does NOT call any MT5 broker API (`SymbolInfoTick`, `OrderSend`, `PositionsTotal`, etc.). It only uses MQL5 file I/O functions (`FileOpen`, `FileRead`, `FileWrite`, `FileClose`, `FileSeek`, `FileIsEnding`).

### 16.7 — Persistence Manager is the Sole Owner of File I/O

No other module may call `FileOpen`, `FileWrite`, `FileRead`, `FileClose`, `FileSeek`, `FileDelete`, or `FileIsEnding`. All file access is funneled through the Persistence Manager.

### 16.8 — Persistence Manager MUST NEVER Block the Hot Path

`AppendEvent` is O(1) (buffer append only). `FlushEventBuffer` and `WriteSnapshot` are called on timer/shutdown, never on `OnTick`. The Persistence Manager never blocks the tick pipeline.

---

# 17. Production Checklist

### 17.1 — Contract Alignment

- [ ] `IStateStore` interface matches `Interfaces/IStateStore.mqh` exactly (6 methods: `WriteSnapshot`, `AppendEvent`, `FlushEventBuffer`, `RecoverState`, `Initialize`, `Shutdown`).
- [ ] `AtlasContext` consumed from `Core/AtlasContext.mqh`.
- [ ] `AtlasEvent` consumed from `Contracts/Events.mqh`.
- [ ] Constants: `ATLAS_EVENT_LOG_BUFFER`, `ATLAS_MODULE_PERSISTENCE`.

### 17.2 — Dependency Alignment

- [ ] `ILogger` available.
- [ ] `AtlasConfig` available (for `symbol`, `snapshot_interval_sec`).
- [ ] `AtlasContext` available (passed by reference to `RecoverState` and `WriteSnapshot`).
- [ ] NO dependency on `IBrokerAdapter`, `IEventBus`, `IContextStore` (the Persistence Manager is a leaf module — it depends only on contracts and the logger).

### 17.3 — File Structure

- [ ] Main file: `Infrastructure/PersistenceManager.mqh` (implements `IStateStore`).
- [ ] Internal helpers under `Infrastructure/PersistenceManager/`:
  - `SnapshotManager.mqh`
  - `EventLogWriter.mqh`
  - `EventLogReader.mqh`
  - `RecoveryEngine.mqh`
  - `SnapshotValidator.mqh`
  - `FileRotationManager.mqh`
  - `ChecksumManager.mqh`
  - `StorageStatistics.mqh`
  - `RecoveryStatistics.mqh`

### 17.4 — Performance Verification

- [ ] No `new` or `delete` in any method.
- [ ] No `Print()` anywhere.
- [ ] No MT5 broker API calls.
- [ ] No file I/O in `AppendEvent` (only in `FlushEventBuffer` and `WriteSnapshot`).
- [ ] No recursion.
- [ ] All arrays fixed-size.
- [ ] Total stack usage < 12 KB.
- [ ] `AppendEvent` ≤ 0.001 ms.
- [ ] `WriteSnapshot` ≤ 5 ms.
- [ ] `FlushEventBuffer` ≤ 5 ms.
- [ ] `RecoverState` ≤ 50 ms.

### 17.5 — MQL5 Compliance

- [ ] Include guards on every file.
- [ ] No `#pragma once`.
- [ ] No `->` (use `.`).
- [ ] No STL.
- [ ] No dynamic arrays in structs.
- [ ] File I/O uses `FILE_TXT | FILE_ANSI` (text mode, ASCII).

### 17.6 — Checksum Verification

- [ ] `ChecksumManager` implements CRC32 with a precomputed 256-entry table.
- [ ] Checksum is computed over all snapshot lines except the checksum line itself.
- [ ] Checksum is verified on read. Mismatch → cold start.

### 17.7 — Recovery Verification

- [ ] `RecoveryEngine.Recover()` handles: no snapshot, corrupt snapshot, valid snapshot, event log replay.
- [ ] Cold start path works (returns false, context at defaults).
- [ ] Recovery report is logged.
- [ ] Fallback strategy: any failure → cold start.

### 17.8 — File Naming Verification

- [ ] Snapshot: `AtlasEA_{symbol}_{YYYYMMDD}.snap`.
- [ ] Event log: `AtlasEA_{symbol}_{YYYYMMDD}.log`.
- [ ] `YYYYMMDD` from `TimeCurrent()` (server time).
- [ ] Symbol sanitized (non-alphanumeric removed).

### 17.9 — Error Handling

- [ ] NULL pointer checks on all dependencies (logger).
- [ ] All edge cases from Section 13 covered.
- [ ] `FileOpen` returning `INVALID_HANDLE` handled.
- [ ] `GetLastError()` logged on file failures.

### 17.10 — Documentation

- [ ] Doxygen comments on every class.
- [ ] Doxygen comments on every public method.
- [ ] Doxygen comments on every public member.
- [ ] Every file has a header comment block.

### 17.11 — Integration Points

- [ ] `PersistenceManager::SetDependencies()` signature matches what CoreEngine will call.
- [ ] `WriteSnapshot()` called by CoreEngine on timer.
- [ ] `AppendEvent()` called by CoreEngine (via EventDispatcher).
- [ ] `FlushEventBuffer()` called by CoreEngine on timer and shutdown.
- [ ] `RecoverState()` called by CoreEngine during `Initialize()`.

### 17.12 — Versioning

- [ ] File header: `AtlasEA v0.1.6.0` (Persistence Manager phase).
- [ ] Snapshot format version: 1 (stored in the `version=` line).

---

**End of Specification.**

This document is implementation-ready. GLM can implement the entire Persistence Manager from this specification alone without making any architectural decisions. All design choices are fixed. All edge cases are enumerated. All validation rules are specified. All performance budgets are defined. The Persistence Manager is the sole owner of file I/O — no other module may touch the filesystem.
