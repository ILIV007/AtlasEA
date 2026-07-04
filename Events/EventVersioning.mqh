//+------------------------------------------------------------------+
//|                   Events/EventVersioning.mqh                    |
//|       AtlasEA v0.1.19.0 - Event Version Management              |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_VERSIONING_MQH
#define ATLAS_EVENT_VERSIONING_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "EventMetadata.mqh"

/**
 * @brief Current event schema version.
 */
#define ATLAS_EVENT_SCHEMA_VERSION 1

/**
 * @brief Event type version mapping.
 * Each event type has its own version. This table defines the current
 * version for each type. Older versions can be upgraded.
 */
static const int EVENT_TYPE_VERSIONS[13] = {
    1,  // EV_TICK_RECEIVED
    1,  // EV_MARKET_STATE_UPDATED
    1,  // EV_STRATEGY_VOTE_SUBMITTED
    1,  // EV_VOTES_AGGREGATED
    1,  // EV_RISK_DECISION_RENDERED
    1,  // EV_ORDER_REQUESTED
    1,  // EV_ORDER_DISPATCHED
    1,  // EV_TRADE_EXECUTED
    1,  // EV_ERROR_OCCURRED
    1,  // EV_HEARTBEAT
    1,  // EV_STATE_PERSISTED
    1,  // EV_SYSTEM_SHUTDOWN
    1   // EV_KILL_SWITCH_ACTIVATED
};

/**
 * @brief Deprecated event types (still readable but not produced).
 */
static const int DEPRECATED_EVENT_TYPES[] = {
    //--- None currently
    -1
};

/**
 * @class EventVersioning
 * @brief Manages event version compatibility.
 */
class EventVersioning
{
public:
    /**
     * @brief Get the current schema version for an event type.
     */
    static int GetCurrentVersion(const int event_type)
    {
        if(event_type < 0 || event_type >= 13) return 1;
        return EVENT_TYPE_VERSIONS[event_type];
    }

    /**
     * @brief Check if an event type is deprecated.
     */
    static bool IsDeprecated(const int event_type)
    {
        for(int i = 0; i < ArraySize(DEPRECATED_EVENT_TYPES); i++)
        {
            if(DEPRECATED_EVENT_TYPES[i] == event_type)
                return true;
        }
        return false;
    }

    /**
     * @brief Check if an event version is compatible with current.
     * A version is compatible if it's <= current version.
     */
    static bool IsCompatible(const int event_type, const int version)
    {
        int current = GetCurrentVersion(event_type);
        return (version <= current);
    }

    /**
     * @brief Upgrade an event's metadata to the current version.
     * In this phase, all events are v1, so this is a no-op.
     * Future versions would transform old payloads here.
     * @return true if upgrade succeeded (or no upgrade needed).
     */
    static bool Upgrade(SourcedEvent &sourced)
    {
        int current = GetCurrentVersion((int)sourced.event.type);
        if(sourced.metadata.event_version >= current)
            return true;  //--- Already current

        //--- Future: transform payload from old version to new
        //--- For now, just update the version field
        sourced.metadata.event_version = current;
        return true;
    }

    /**
     * @brief Handle an unknown event type (from a newer engine version).
     * @return true if the event should be kept, false if it should be dropped.
     */
    static bool HandleUnknown(const SourcedEvent &sourced)
    {
        //--- Unknown events are kept but logged at WARN level.
        //--- They are not replayed (the replay engine skips them).
        return true;
    }

    /**
     * @brief Get the schema version.
     */
    static int GetSchemaVersion(void) { return ATLAS_EVENT_SCHEMA_VERSION; }
};

#endif // ATLAS_EVENT_VERSIONING_MQH
//+------------------------------------------------------------------+
