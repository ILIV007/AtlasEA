# AtlasEA — Threading Model

**Version:** v0.1.14.0
**Date:** 2025-07-02

## 1. Threading Model

AtlasEA assumes **MetaTrader 5 single-thread execution**.

### 1.1 What This Means

- One EA instance per chart runs on a single thread.
- `OnInit`, `OnTick`, `OnTrade`, `OnTimer`, `OnDeinit` are all called on the same thread.
- No two callbacks run concurrently.
- No preemption within a callback.

### 1.2 Consequences

| Concern | AtlasEA Approach |
|---------|------------------|
| Race conditions | Impossible (single thread) |
| Mutexes / locks | NOT used |
| Atomic primitives | NOT used |
| Memory barriers | NOT needed |
| Thread-safe collections | NOT needed |
| Concurrent access | NOT possible |

## 2. No Synchronization Primitives

AtlasEA does NOT use:
- `CriticalSection` (MQL5 doesn't have one)
- `Event` objects for synchronization
- `Sleep` for polling (except in MT5Adapter retry — bounded, documented)
- `Semaphore` / `Mutex` (not applicable)

## 3. Single-Threaded Guarantees

### 3.1 Event Queue

`EventQueue` is a ring buffer. In a single-threaded model:
- `Enqueue` and `Dequeue` never run concurrently.
- No atomic head/tail pointers needed.
- `EventRingBuffer` uses plain `int` indices.

### 3.2 AtlasContext

`AtlasContext` is the shared mutable state. In a single-threaded model:
- Multiple modules read/write, but never simultaneously.
- `ContextGuardian` enforces logical single-writer (catches bugs, not races).
- No locks needed.

### 3.3 Service Registry

`ServiceRegistry` holds service pointers. In a single-threaded model:
- Registration happens at startup (`Initialize`).
- Lookup happens during operation.
- No concurrent access.

## 4. Callback Ordering

MT5 guarantees callback ordering within a single chart:

```
OnInit() → (OnTick / OnTrade / OnTimer interleaved) → OnDeinit()
```

- `OnTick` and `OnTimer` do NOT run simultaneously.
- `OnTrade` may interrupt `OnTick`? **No** — MT5 queues events and processes them sequentially.

## 5. Future Multi-Thread Migration Considerations

If AtlasEA were ever to run in a multi-threaded environment (e.g., a future MQL5 update, or a port to another platform), the following changes would be required:

### 5.1 Event Queue

- `m_head` and `m_tail` must become `atomic<int>` or use a lock-free algorithm.
- Alternatively, use a mutex around `Enqueue`/`Dequeue`.

### 5.2 AtlasContext

- Every getter/setter needs synchronization (reader-writer lock).
- `ContextGuardian` becomes a real lock, not just a logic guard.
- Consider `shared_mutex` (multiple readers, single writer).

### 5.3 Service Registry

- Registration at startup is safe (single-threaded).
- Runtime lookup needs synchronization (reader lock).

### 5.4 Logger

- Sinks need synchronization (file writes are not atomic).
- `MemoryRingSink` ring buffer needs atomic indices.
- Consider a lock-free SPSC ring per sink.

### 5.5 Performance Profiler

- `Start`/`Stop` per phase needs per-CPU timers or thread-local storage.
- Aggregation across threads needs synchronization.

### 5.6 MT5Adapter

- `OrderSend` is inherently synchronous — no change needed.
- `CaptureTick` is read-only — needs synchronization on the tick cache.

## 6. Current Design Decisions

The single-threaded assumption allows AtlasEA to:
- Use plain `int` / `ulong` counters (no atomics)
- Use plain arrays (no concurrent collections)
- Use plain pointers (no smart pointers needed for thread safety)
- Avoid lock overhead (zero synchronization cost)
- Keep the code simple and deterministic

This is the correct design for MQL5. The day MT5 adds multi-threading, the changes above would be required — but that day has not come.

## 7. Sleep() Usage

The only `Sleep()` call in AtlasEA is in `MT5Adapter::SendOrder()` for retry backoff. This is:
- Bounded (`retry_delay_ms × max_retries`)
- Not for synchronization (for broker rate-limiting)
- Documented in the MT5Adapter spec

No other module uses `Sleep()`.

## 8. Conclusion

AtlasEA is designed for MQL5's single-threaded model. No mutexes, locks, atomics, or concurrent access patterns are used. This keeps the code simple, deterministic, and zero-overhead. A future multi-thread migration would require adding synchronization to the Event Queue, AtlasContext, Service Registry, Logger, and Performance Profiler.
