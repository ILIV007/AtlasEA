//+------------------------------------------------------------------+
//|                      Interfaces/IEventStore.mqh                 |
//|       AtlasEA v0.1.19.0 - Event Store Interface                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_IEVENT_STORE_MQH
#define ATLAS_IEVENT_STORE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Event query filter codes.
 */
#define ATLAS_EVENT_FILTER_NONE        0
#define ATLAS_EVENT_FILTER_TYPE        1
#define ATLAS_EVENT_FILTER_SNAPSHOT    2
#define ATLAS_EVENT_FILTER_CORRELATION 3
#define ATLAS_EVENT_FILTER_REQUEST     4
#define ATLAS_EVENT_FILTER_STRATEGY    5
#define ATLAS_EVENT_FILTER_SYMBOL      6
#define ATLAS_EVENT_FILTER_TIME        7

/**
 * @struct EventQuery
 * @brief Query parameters for reading events.
 */
struct EventQuery
{
    int      filter_type;     ///< ATLAS_EVENT_FILTER_*
    int      event_type;      ///< For FILTER_TYPE
    long     snapshot_id;     ///< For FILTER_SNAPSHOT
    string   correlation_id;  ///< For FILTER_CORRELATION
    string   request_id;      ///< For FILTER_REQUEST
    int      strategy_id;     ///< For FILTER_STRATEGY
    string   symbol;          ///< For FILTER_SYMBOL
    datetime from_time;       ///< For FILTER_TIME (inclusive)
    datetime to_time;         ///< For FILTER_TIME (inclusive)
    long     from_sequence;   ///< Read range start (inclusive)
    long     to_sequence;     ///< Read range end (inclusive)
    int      max_results;     ///< Max events to return (0 = unlimited)
};

/**
 * @class IEventStore
 * @brief Append-only event store interface.
 *
 * The event store is the single source of truth for all state transitions.
 * Events are immutable once appended. The store supports:
 *   - Sequential append (O(1))
 *   - Query by type, snapshot, correlation, request, strategy, symbol, time
 *   - Range reads by sequence number
 *   - Count
 *
 * Thread model: single-threaded (MQL5).
 * Performance: append is O(1), reads are O(N) scan (N ≤ buffer size).
 */
class IEventStore
{
public:
    /// @brief Append an event to the store. O(1).
    virtual bool Append(const AtlasEvent &event) = 0;

    /// @brief Read a single event by sequence number.
    virtual bool Read(const long sequence, AtlasEvent &out) const = 0;

    /// @brief Read events in a sequence range [from, to].
    virtual int ReadRange(const long from_seq, const long to_seq,
                           AtlasEvent out_events[], const int max_count) const = 0;

    /// @brief Read events matching a query filter.
    virtual int ReadByQuery(const EventQuery &query,
                             AtlasEvent out_events[], const int max_count) const = 0;

    /// @brief Count total events in the store.
    virtual long Count(void) const = 0;

    /// @brief Get the current sequence number (next to be assigned).
    virtual long GetNextSequence(void) const = 0;

    /// @brief Clear all events (for testing/reset).
    virtual void Clear(void) = 0;

    virtual ~IEventStore(void) {}
};

#endif // ATLAS_IEVENT_STORE_MQH
//+------------------------------------------------------------------+
