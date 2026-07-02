//+------------------------------------------------------------------+
//|                                      Core/EventRouteTable.mqh    |
//|                AtlasEA v0.1.8.0 - Event Routing Table             |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_ROUTE_TABLE_MQH
#define ATLAS_EVENT_ROUTE_TABLE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Route handler function pointer.
 *
 * Each route maps an event type to a handler function.
 * The handler receives the event and a user-data pointer
 * (typically the module that owns the handler).
 *
 * Signature: void Handler(const AtlasEvent &event, void *user_data)
 */
typedef void (*EventRouteHandler)(const AtlasEvent &event, void *user_data);

/**
 * @struct EventRoute
 * @brief One entry in the route table.
 */
struct EventRoute
{
    int                event_type;   ///< ENUM_ATLAS_EVENT_TYPE
    EventRouteHandler  handler;      ///< Function pointer
    void              *user_data;    ///< Module instance pointer
    string             handler_name; ///< Human-readable name for diagnostics
    bool               enabled;      ///< Can be toggled at runtime
};

/**
 * @class EventRouteTable
 * @brief Declarative routing table for events.
 *
 * Replaces the long switch statement in EventDispatcher. Each event type
 * maps to zero or one handler. The dispatcher iterates the table on each
 * event and calls the matching handler.
 *
 * Capacity: fixed at 32 routes (enough for all 13 event types + future
 * expansion). Zero dynamic allocation.
 *
 * Thread model: single-threaded. Routes are registered at startup and
 * read on every dispatch. No locks.
 */
class EventRouteTable
{
private:
    static const int MAX_ROUTES = 32;

    EventRoute m_routes[MAX_ROUTES];
    int        m_count;
    ILogger   *m_logger;

    /// @brief Find the index of a route by event type.
    int FindIndex(const int event_type) const;

public:
    /**
     * @brief Constructor.
     */
    EventRouteTable(void);

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a route.
     * @param event_type   ENUM_ATLAS_EVENT_TYPE.
     * @param handler      Function pointer to the handler.
     * @param user_data    Module instance (passed back to handler).
     * @param handler_name Human-readable name for diagnostics.
     * @return true if registered, false if table full or duplicate.
     */
    bool Register(const int event_type, EventRouteHandler handler,
                  void *user_data, const string handler_name);

    /**
     * @brief Unregister a route by event type.
     */
    bool Unregister(const int event_type);

    /**
     * @brief Enable/disable a route without removing it.
     */
    bool SetEnabled(const int event_type, const bool enabled);

    /**
     * @brief Dispatch an event to its registered handler.
     * @param event The event to dispatch.
     * @return true if a handler was called, false if no route or disabled.
     */
    bool Dispatch(const AtlasEvent &event) const;

    /**
     * @brief Check if a route exists for the given event type.
     */
    bool HasRoute(const int event_type) const;

    /**
     * @brief Number of registered routes.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Clear all routes.
     */
    void Clear(void);

    /**
     * @brief Log all registered routes.
     */
    void LogRoutes(void) const;
};

//+------------------------------------------------------------------+
//| EventRouteTable implementation                                    |
//+------------------------------------------------------------------+

EventRouteTable::EventRouteTable(void)
{
    m_logger = NULL;
    m_count  = 0;
    for(int i = 0; i < MAX_ROUTES; i++)
    {
        m_routes[i].event_type   = -1;
        m_routes[i].handler      = NULL;
        m_routes[i].user_data    = NULL;
        m_routes[i].handler_name = "";
        m_routes[i].enabled      = false;
    }
}

//+------------------------------------------------------------------+
int EventRouteTable::FindIndex(const int event_type) const
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_routes[i].event_type == event_type)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
bool EventRouteTable::Register(const int event_type, EventRouteHandler handler,
                               void *user_data, const string handler_name)
{
    if(handler == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("EventRouteTable", "Register: handler is NULL for type " + IntegerToString(event_type));
        return false;
    }

    if(FindIndex(event_type) >= 0)
    {
        if(m_logger != NULL)
            m_logger.Warn("EventRouteTable", "Register: type " + IntegerToString(event_type) + " already routed");
        return false;
    }

    if(m_count >= MAX_ROUTES)
    {
        if(m_logger != NULL)
            m_logger.Error("EventRouteTable", "Register: table full");
        return false;
    }

    m_routes[m_count].event_type   = event_type;
    m_routes[m_count].handler      = handler;
    m_routes[m_count].user_data    = user_data;
    m_routes[m_count].handler_name = handler_name;
    m_routes[m_count].enabled      = true;
    m_count++;

    if(m_logger != NULL)
        m_logger.Debug("EventRouteTable", "Route registered: type=" + IntegerToString(event_type) + " -> " + handler_name);
    return true;
}

//+------------------------------------------------------------------+
bool EventRouteTable::Unregister(const int event_type)
{
    int idx = FindIndex(event_type);
    if(idx < 0) return false;

    //--- Shift remaining routes left
    for(int i = idx + 1; i < m_count; i++)
        m_routes[i-1] = m_routes[i];

    m_count--;
    m_routes[m_count].event_type   = -1;
    m_routes[m_count].handler      = NULL;
    m_routes[m_count].user_data    = NULL;
    m_routes[m_count].handler_name = "";
    m_routes[m_count].enabled      = false;
    return true;
}

//+------------------------------------------------------------------+
bool EventRouteTable::SetEnabled(const int event_type, const bool enabled)
{
    int idx = FindIndex(event_type);
    if(idx < 0) return false;
    m_routes[idx].enabled = enabled;
    return true;
}

//+------------------------------------------------------------------+
bool EventRouteTable::Dispatch(const AtlasEvent &event) const
{
    int idx = FindIndex((int)event.type);
    if(idx < 0)
    {
        //--- No route registered for this event type — not an error,
        //--- the event is simply a flow signal that no module needs to handle.
        return false;
    }

    if(!m_routes[idx].enabled)
        return false;

    if(m_routes[idx].handler == NULL)
        return false;

    //--- Call the handler function pointer
    m_routes[idx].handler(event, m_routes[idx].user_data);
    return true;
}

//+------------------------------------------------------------------+
bool EventRouteTable::HasRoute(const int event_type) const
{
    return (FindIndex(event_type) >= 0);
}

//+------------------------------------------------------------------+
void EventRouteTable::Clear(void)
{
    for(int i = 0; i < MAX_ROUTES; i++)
    {
        m_routes[i].event_type   = -1;
        m_routes[i].handler      = NULL;
        m_routes[i].user_data    = NULL;
        m_routes[i].handler_name = "";
        m_routes[i].enabled      = false;
    }
    m_count = 0;
}

//+------------------------------------------------------------------+
void EventRouteTable::LogRoutes(void) const
{
    if(m_logger == NULL) return;
    for(int i = 0; i < m_count; i++)
    {
        string status = m_routes[i].enabled ? "ENABLED" : "DISABLED";
        m_logger.Info("EventRouteTable",
            "  type=" + IntegerToString(m_routes[i].event_type) +
            " -> " + m_routes[i].handler_name + " [" + status + "]");
    }
}

#endif // ATLAS_EVENT_ROUTE_TABLE_MQH
//+------------------------------------------------------------------+
