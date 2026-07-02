//+------------------------------------------------------------------+
//|                                       Core/ServiceRegistry.mqh   |
//|                AtlasEA v0.1.8.0 - Lightweight Service Registry    |
//+------------------------------------------------------------------+
#ifndef ATLAS_SERVICE_REGISTRY_MQH
#define ATLAS_SERVICE_REGISTRY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Service type identifiers (compile-time constants).
 *
 * The registry uses an integer key instead of strings for O(1) lookup
 * and zero allocation. Each cross-cutting singleton service has a unique ID.
 */
#define ATLAS_SERVICE_LOGGER          1
#define ATLAS_SERVICE_CLOCK           2
#define ATLAS_SERVICE_UUID_GENERATOR  3
#define ATLAS_SERVICE_METRICS         4
#define ATLAS_SERVICE_HEALTH_MONITOR  5
#define ATLAS_SERVICE_ERROR_MANAGER   6
#define ATLAS_SERVICE_CONFIG_PROVIDER 7
#define ATLAS_SERVICE_MAX             8

/**
 * @class ServiceRegistry
 * @brief Resolves shared singleton services by integer ID.
 *
 * Ownership: the registry does NOT own the services. It holds pointers.
 * The Bootstrap layer owns the concrete instances and registers them.
 * On shutdown, Bootstrap unregisters and deletes them.
 *
 * Thread model: single-threaded (MQL5). No locks.
 *
 * Memory: fixed-size array of 8 slots. Zero dynamic allocation.
 *
 * This is NOT a general-purpose IoC container. It resolves only the
 * cross-cutting singletons listed above. Engines and infra modules
 * are constructed by Bootstrap and injected directly — they do NOT
 * go through the registry.
 */
class ServiceRegistry
{
private:
    /// Service slots: m_services[id] = pointer (or NULL)
    void    *m_services[ATLAS_SERVICE_MAX];
    /// Whether a slot is occupied
    bool     m_registered[ATLAS_SERVICE_MAX];
    /// Human-readable names for diagnostics
    string   m_names[ATLAS_SERVICE_MAX];
    ILogger *m_logger;

public:
    /**
     * @brief Constructor — initializes empty registry.
     */
    ServiceRegistry(void);

    /**
     * @brief Set the logger for registry diagnostics.
     * @param logger Logger (may be NULL).
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a service by ID.
     * @param service_id  ATLAS_SERVICE_* constant.
     * @param name        Human-readable name (for diagnostics).
     * @param ptr         Pointer to the service instance.
     * @return true if registered, false if ID out of range or already registered.
     */
    bool Register(const int service_id, const string name, void *ptr);

    /**
     * @brief Unregister a service (does NOT delete it — Bootstrap owns lifetime).
     * @param service_id ATLAS_SERVICE_* constant.
     * @return true if unregistered, false if not found.
     */
    bool Unregister(const int service_id);

    /**
     * @brief Resolve a service by ID.
     * @param service_id ATLAS_SERVICE_* constant.
     * @return Pointer to the service, or NULL if not registered.
     */
    void *Resolve(const int service_id) const;

    /**
     * @brief Check if a service is registered.
     */
    bool IsRegistered(const int service_id) const;

    /**
     * @brief Get the name of a registered service.
     */
    string GetName(const int service_id) const;

    /**
     * @brief Count of registered services.
     */
    int Count(void) const;

    /**
     * @brief Clear all registrations (called on shutdown).
     * Does NOT delete instances — Bootstrap handles deletion.
     */
    void Clear(void);

    /**
     * @brief Validate that all required services are registered.
     * @return true if all ATLAS_SERVICE_* slots (1..7) are filled.
     */
    bool ValidateAll(void) const;

    /**
     * @brief Log the registry status.
     */
    void LogStatus(void) const;
};

//+------------------------------------------------------------------+
//| ServiceRegistry implementation                                    |
//+------------------------------------------------------------------+

ServiceRegistry::ServiceRegistry(void)
{
    m_logger = NULL;
    for(int i = 0; i < ATLAS_SERVICE_MAX; i++)
    {
        m_services[i]  = NULL;
        m_registered[i] = false;
        m_names[i]      = "";
    }
}

//+------------------------------------------------------------------+
bool ServiceRegistry::Register(const int service_id, const string name, void *ptr)
{
    if(service_id < 0 || service_id >= ATLAS_SERVICE_MAX)
    {
        if(m_logger != NULL)
            m_logger.Error("ServiceRegistry", "Register: invalid service_id " + IntegerToString(service_id));
        return false;
    }

    if(m_registered[service_id])
    {
        if(m_logger != NULL)
            m_logger.Warn("ServiceRegistry", "Register: " + m_names[service_id] + " already registered");
        return false;
    }

    if(ptr == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("ServiceRegistry", "Register: " + name + " pointer is NULL");
        return false;
    }

    m_services[service_id]  = ptr;
    m_registered[service_id] = true;
    m_names[service_id]      = name;

    if(m_logger != NULL)
        m_logger.Debug("ServiceRegistry", "Registered: " + name);
    return true;
}

//+------------------------------------------------------------------+
bool ServiceRegistry::Unregister(const int service_id)
{
    if(service_id < 0 || service_id >= ATLAS_SERVICE_MAX)
        return false;

    if(!m_registered[service_id])
        return false;

    m_services[service_id]  = NULL;
    m_registered[service_id] = false;
    m_names[service_id]      = "";
    return true;
}

//+------------------------------------------------------------------+
void *ServiceRegistry::Resolve(const int service_id) const
{
    if(service_id < 0 || service_id >= ATLAS_SERVICE_MAX)
        return NULL;
    if(!m_registered[service_id])
        return NULL;
    return m_services[service_id];
}

//+------------------------------------------------------------------+
bool ServiceRegistry::IsRegistered(const int service_id) const
{
    if(service_id < 0 || service_id >= ATLAS_SERVICE_MAX)
        return false;
    return m_registered[service_id];
}

//+------------------------------------------------------------------+
string ServiceRegistry::GetName(const int service_id) const
{
    if(service_id < 0 || service_id >= ATLAS_SERVICE_MAX)
        return "";
    return m_names[service_id];
}

//+------------------------------------------------------------------+
int ServiceRegistry::Count(void) const
{
    int c = 0;
    for(int i = 0; i < ATLAS_SERVICE_MAX; i++)
        if(m_registered[i]) c++;
    return c;
}

//+------------------------------------------------------------------+
void ServiceRegistry::Clear(void)
{
    for(int i = 0; i < ATLAS_SERVICE_MAX; i++)
    {
        m_services[i]  = NULL;
        m_registered[i] = false;
        m_names[i]      = "";
    }
}

//+------------------------------------------------------------------+
bool ServiceRegistry::ValidateAll(void) const
{
    //--- Services 1..7 are required (0 is unused, ATLAS_SERVICE_MAX is the sentinel)
    for(int i = 1; i < ATLAS_SERVICE_MAX; i++)
    {
        if(!m_registered[i])
        {
            if(m_logger != NULL)
                m_logger.Error("ServiceRegistry", "Validation failed: service slot " + IntegerToString(i) + " not registered");
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
void ServiceRegistry::LogStatus(void) const
{
    if(m_logger == NULL) return;
    for(int i = 0; i < ATLAS_SERVICE_MAX; i++)
    {
        if(m_registered[i])
            m_logger.Info("ServiceRegistry", "  [" + IntegerToString(i) + "] " + m_names[i] + " = OK");
        else
            m_logger.Info("ServiceRegistry", "  [" + IntegerToString(i) + "] (empty)");
    }
}

#endif // ATLAS_SERVICE_REGISTRY_MQH
//+------------------------------------------------------------------+
