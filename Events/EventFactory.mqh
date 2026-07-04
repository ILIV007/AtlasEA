//+------------------------------------------------------------------+
//|                    Events/EventFactory.mqh                      |
//|       AtlasEA v0.1.19.0 - Event Factory                          |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_FACTORY_MQH
#define ATLAS_EVENT_FACTORY_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "EventMetadata.mqh"

/**
 * @class EventFactory
 * @brief Creates AtlasEvent and EventMetadata instances.
 *
 * Provides factory methods for creating events with proper metadata.
 * Assigns event IDs and generates correlation IDs.
 */
class EventFactory
{
private:
    static long s_event_counter;

    /// @brief Generate a unique event ID.
    static string GenerateEventId(void)
    {
        s_event_counter++;
        return "EVT_" + IntegerToString((long)TimeCurrent()) + "_" + IntegerToString(s_event_counter);
    }

    /// @brief Simple CRC32-like checksum (simplified for MQL5).
    static uint ComputeChecksum(const uchar &payload[], const int size)
    {
        uint crc = 0xFFFFFFFF;
        for(int i = 0; i < size; i++)
        {
            crc = crc ^ (uint)payload[i];
            for(int j = 0; j < 8; j++)
            {
                if((crc & 1) != 0)
                    crc = (crc >> 1) ^ 0xEDB88320;
                else
                    crc = crc >> 1;
            }
        }
        return crc ^ 0xFFFFFFFF;
    }

public:
    /**
     * @brief Create a base AtlasEvent.
     */
    static AtlasEvent CreateEvent(const ENUM_ATLAS_EVENT_TYPE type,
                                   const string source_module,
                                   const long snapshot_id)
    {
        AtlasEvent ev;
        ev.type          = type;
        ev.source_module = source_module;
        ev.timestamp     = TimeCurrent();
        ev.snapshot_id   = snapshot_id;
        ev.payload_size  = 0;
        for(int i = 0; i < ATLAS_PAYLOAD_MAX_SIZE; i++)
            ev.payload[i] = 0;
        return ev;
    }

    /**
     * @brief Create full metadata for an event.
     */
    static EventMetadata CreateMetadata(const AtlasEvent &event,
                                         const string correlation_id = "",
                                         const string request_id = "",
                                         const int severity = ATLAS_LOG_INFO)
    {
        EventMetadata meta;
        meta.event_id       = GenerateEventId();
        meta.correlation_id = correlation_id;
        meta.request_id     = request_id;
        meta.event_version  = 1;
        meta.engine_version = ATLAS_EVENT_SCHEMA_VERSION;
        meta.severity       = severity;
        meta.checksum       = (event.payload_size > 0)
                              ? ComputeChecksum(event.payload, event.payload_size)
                              : 0;
        return meta;
    }

    /**
     * @brief Create a complete SourcedEvent.
     */
    static SourcedEvent CreateSourcedEvent(const ENUM_ATLAS_EVENT_TYPE type,
                                            const string source_module,
                                            const long snapshot_id,
                                            const string correlation_id = "",
                                            const string request_id = "",
                                            const int severity = ATLAS_LOG_INFO)
    {
        AtlasEvent ev = CreateEvent(type, source_module, snapshot_id);
        EventMetadata meta = CreateMetadata(ev, correlation_id, request_id, severity);
        return SourcedEvent(ev, meta);
    }

    /**
     * @brief Generate a correlation ID for linking events.
     */
    static string GenerateCorrelationId(void)
    {
        return "COR_" + IntegerToString((long)TimeCurrent()) + "_" +
               IntegerToString(s_event_counter);
    }

    /**
     * @brief Reset the event counter (for testing).
     */
    static void ResetCounter(void) { s_event_counter = 0; }

    /**
     * @brief Get the total events created.
     */
    static long GetTotalCreated(void) { return s_event_counter; }
};

//--- Static member initialization
long EventFactory::s_event_counter = 0;

#endif // ATLAS_EVENT_FACTORY_MQH
//+------------------------------------------------------------------+
