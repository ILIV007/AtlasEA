//+------------------------------------------------------------------+
//|                  Events/EventSerializer.mqh                     |
//|       AtlasEA v0.1.19.0 - Event Serializer                       |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_SERIALIZER_MQH
#define ATLAS_EVENT_SERIALIZER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "EventMetadata.mqh"

/**
 * @class EventSerializer
 * @brief Serializes SourcedEvents to string format.
 */
class EventSerializer
{
public:
    /**
     * @brief Serialize a SourcedEvent to CSV (one line).
     */
    static string ToCSV(const SourcedEvent &sourced)
    {
        const AtlasEvent &ev = sourced.event;
        const EventMetadata &meta = sourced.metadata;

        return IntegerToString((int)ev.type) + "," +
               IntegerToString((long)ev.timestamp) + "," +
               IntegerToString(ev.snapshot_id) + "," +
               ev.source_module + "," +
               IntegerToString(meta.sequence) + "," +
               meta.event_id + "," +
               meta.correlation_id + "," +
               meta.request_id + "," +
               IntegerToString(meta.event_version) + "," +
               IntegerToString(meta.severity) + "," +
               IntegerToString((long)meta.checksum) + "," +
               IntegerToString(ev.payload_size);
    }

    /**
     * @brief Serialize to JSON-like format.
     */
    static string ToJSON(const SourcedEvent &sourced)
    {
        const AtlasEvent &ev = sourced.event;
        const EventMetadata &meta = sourced.metadata;

        string out = "{";
        out += "\"type\":" + IntegerToString((int)ev.type);
        out += ",\"ts\":" + IntegerToString((long)ev.timestamp);
        out += ",\"snap\":" + IntegerToString(ev.snapshot_id);
        out += ",\"src\":\"" + ev.source_module + "\"";
        out += ",\"seq\":" + IntegerToString(meta.sequence);
        out += ",\"id\":\"" + meta.event_id + "\"";
        out += ",\"corr\":\"" + meta.correlation_id + "\"";
        out += ",\"req\":\"" + meta.request_id + "\"";
        out += ",\"ver\":" + IntegerToString(meta.event_version);
        out += ",\"sev\":" + IntegerToString(meta.severity);
        out += "}";
        return out;
    }

    /**
     * @brief Serialize to memory snapshot (single-line summary).
     */
    static string ToMemory(const SourcedEvent &sourced)
    {
        const AtlasEvent &ev = sourced.event;
        const EventMetadata &meta = sourced.metadata;

        return "seq=" + IntegerToString(meta.sequence) +
               " type=" + IntegerToString((int)ev.type) +
               " src=" + ev.source_module +
               " snap=" + IntegerToString(ev.snapshot_id);
    }
};

#endif // ATLAS_EVENT_SERIALIZER_MQH
//+------------------------------------------------------------------+
