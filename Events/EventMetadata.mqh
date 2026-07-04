//+------------------------------------------------------------------+
//|                    Events/EventMetadata.mqh                     |
//|       AtlasEA v0.1.19.0 - Event Metadata Extension              |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_METADATA_MQH
#define ATLAS_EVENT_METADATA_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @struct EventMetadata
 * @brief Extended metadata for an event.
 *
 * The base AtlasEvent (from Contracts) has: type, source_module,
 * timestamp, snapshot_id, payload, payload_size.
 *
 * EventMetadata adds the fields required for event sourcing:
 *   - EventId (unique per event)
 *   - CorrelationId (links related events)
 *   - RequestId (links to an order request)
 *   - Sequence (monotonic sequence number)
 *   - EventVersion (schema version for this event type)
 *   - EngineVersion (AtlasEA version that produced this event)
 *   - Severity (info/warn/error/fatal)
 *   - Checksum (CRC32 of payload for integrity)
 */
struct EventMetadata
{
    long     sequence;         ///< Monotonic sequence number (assigned by store)
    string   event_id;         ///< Unique event ID (e.g., "EVT_12345")
    string   correlation_id;   ///< Links related events (e.g., vote → decision → order)
    string   request_id;       ///< Links to an order request (if applicable)
    int      event_version;    ///< Schema version for this event type
    int      engine_version;   ///< AtlasEA version that produced this event
    int      severity;         ///< ATLAS_LOG_* level
    uint     checksum;         ///< CRC32 of payload

    /**
     * @brief Default constructor.
     */
    EventMetadata(void)
    {
        sequence       = 0;
        event_id       = "";
        correlation_id = "";
        request_id     = "";
        event_version  = 1;
        engine_version = 1;
        severity       = ATLAS_LOG_INFO;
        checksum       = 0;
    }
};

/**
 * @struct SourcedEvent
 * @brief An AtlasEvent combined with its metadata.
 *
 * This is the full event record stored in the EventStore.
 */
struct SourcedEvent
{
    AtlasEvent    event;       ///< Base event (type, source, timestamp, payload)
    EventMetadata metadata;    ///< Extended metadata

    /**
     * @brief Default constructor.
     */
    SourcedEvent(void) {}

    /**
     * @brief Construct from base event + metadata.
     */
    SourcedEvent(const AtlasEvent &ev, const EventMetadata &meta)
    {
        event    = ev;
        metadata = meta;
    }
};

#endif // ATLAS_EVENT_METADATA_MQH
//+------------------------------------------------------------------+
