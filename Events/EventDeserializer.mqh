//+------------------------------------------------------------------+
//|                 Events/EventDeserializer.mqh                    |
//|       AtlasEA v0.1.19.0 - Event Deserializer                     |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_DESERIALIZER_MQH
#define ATLAS_EVENT_DESERIALIZER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "EventMetadata.mqh"
#include "EventSerializer.mqh"

/**
 * @class EventDeserializer
 * @brief Deserializes SourcedEvents from CSV strings.
 */
class EventDeserializer
{
public:
    /**
     * @brief Deserialize a CSV line into a SourcedEvent.
     */
    static bool FromCSV(const string line, SourcedEvent &out)
    {
        //--- Parse comma-separated fields
        string parts[16];
        int count = StringSplit(line, ',', parts);
        if(count < 12) return false;

        out.event.type          = (ENUM_ATLAS_EVENT_TYPE)(int)StringToInteger(parts[0]);
        out.event.timestamp     = (datetime)StringToInteger(parts[1]);
        out.event.snapshot_id   = StringToInteger(parts[2]);
        out.event.source_module = parts[3];
        out.metadata.sequence       = StringToInteger(parts[4]);
        out.metadata.event_id       = parts[5];
        out.metadata.correlation_id = parts[6];
        out.metadata.request_id     = parts[7];
        out.metadata.event_version  = (int)StringToInteger(parts[8]);
        out.metadata.severity       = (int)StringToInteger(parts[9]);
        out.metadata.checksum       = (uint)StringToInteger(parts[10]);
        out.event.payload_size      = (int)StringToInteger(parts[11]);

        return true;
    }
};

#endif // ATLAS_EVENT_DESERIALIZER_MQH
//+------------------------------------------------------------------+
