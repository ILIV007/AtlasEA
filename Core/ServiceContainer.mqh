//+------------------------------------------------------------------+
//|                       Core/ServiceContainer.mqh                 |
//|       AtlasEA v0.1.16.0 - DI Service Container                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_SERVICE_CONTAINER_MQH
#define ATLAS_SERVICE_CONTAINER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IServiceContainer.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct ServiceEntry
 * @brief One entry in the service container.
 */
struct ServiceEntry
{
    int    id;           ///< ATLAS_SVC_* constant
    int    lifetime;     ///< ATLAS_LIFETIME_SINGLETON or TRANSIENT
    string name;         ///< Human-readable name
    void  *ptr;          ///< Pointer to the instance
    bool   registered;   ///< Is this slot occupied?
};

/**
 * @class ServiceContainer
 * @brief Concrete implementation of IServiceContainer.
 *
 * Fixed-size array of ATLAS_SVC_MAX (128) slots. No dynamic allocation.
 * O(1) registration and resolution (direct index by service_id, if < MAX).
 *
 * The container does NOT own the instances. The caller (Bootstrap) owns
 * them and must delete them on shutdown.
 *
 * Thread model: single-threaded (MQL5). No locks.
 */
class ServiceContainer : public IServiceContainer
{
private:
    ServiceEntry m_entries[ATLAS_SVC_MAX];
    int          m_count;
    ILogger     *m_logger;

public:
    /**
     * @brief Constructor.
     */
    ServiceContainer(void)
    {
        m_logger = NULL;
        m_count  = 0;
        for(int i = 0; i < ATLAS_SVC_MAX; i++)
        {
            m_entries[i].id         = 0;
            m_entries[i].lifetime   = ATLAS_LIFETIME_SINGLETON;
            m_entries[i].name       = "";
            m_entries[i].ptr        = NULL;
            m_entries[i].registered = false;
        }
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IServiceContainer implementation ===

    virtual bool RegisterSingleton(const int service_id, const string name, void *ptr) override
    {
        return RegisterInternal(service_id, name, ptr, ATLAS_LIFETIME_SINGLETON);
    }

    virtual bool RegisterTransient(const int service_id, const string name, void *ptr) override
    {
        return RegisterInternal(service_id, name, ptr, ATLAS_LIFETIME_TRANSIENT);
    }

    virtual void *Resolve(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_SVC_MAX) return NULL;
        if(!m_entries[service_id].registered) return NULL;
        return m_entries[service_id].ptr;
    }

    virtual bool Contains(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_SVC_MAX) return false;
        return m_entries[service_id].registered;
    }

    virtual string GetName(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_SVC_MAX) return "";
        if(!m_entries[service_id].registered) return "";
        return m_entries[service_id].name;
    }

    virtual int GetLifetime(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_SVC_MAX) return ATLAS_LIFETIME_SINGLETON;
        return m_entries[service_id].lifetime;
    }

    virtual int Count(void) const override { return m_count; }

    virtual void Clear(void) override
    {
        for(int i = 0; i < ATLAS_SVC_MAX; i++)
        {
            m_entries[i].id         = 0;
            m_entries[i].lifetime   = ATLAS_LIFETIME_SINGLETON;
            m_entries[i].name       = "";
            m_entries[i].ptr        = NULL;
            m_entries[i].registered = false;
        }
        m_count = 0;
    }

    virtual bool ValidateAll(void) const override
    {
        //--- Check essential services
        int essential[] = {
            ATLAS_SVC_LOGGER, ATLAS_SVC_BROKER, ATLAS_SVC_PERSISTENCE,
            ATLAS_SVC_MARKET_ENGINE, ATLAS_SVC_STRATEGY_ENGINE,
            ATLAS_SVC_RISK_ENGINE, ATLAS_SVC_EXECUTION_ENGINE,
            ATLAS_SVC_CORE_ENGINE
        };

        for(int i = 0; i < ArraySize(essential); i++)
        {
            if(!Contains(essential[i]))
            {
                if(m_logger != NULL)
                    m_logger.Error("ServiceContainer",
                        "Missing essential service: " + IntegerToString(essential[i]));
                return false;
            }
        }
        return true;
    }

    virtual void LogStatus(void) const override
    {
        if(m_logger == NULL) return;
        m_logger.Info("ServiceContainer",
            "Registered services: " + IntegerToString(m_count) + "/" + IntegerToString(ATLAS_SVC_MAX));
        for(int i = 0; i < ATLAS_SVC_MAX; i++)
        {
            if(m_entries[i].registered)
            {
                string life = (m_entries[i].lifetime == ATLAS_LIFETIME_SINGLETON) ? "Singleton" : "Transient";
                m_logger.Info("ServiceContainer",
                    "  [" + IntegerToString(i) + "] " + m_entries[i].name + " (" + life + ")");
            }
        }
    }

private:
    bool RegisterInternal(const int service_id, const string name, void *ptr, const int lifetime)
    {
        if(service_id < 0 || service_id >= ATLAS_SVC_MAX)
        {
            if(m_logger != NULL)
                m_logger.Error("ServiceContainer", "Register: ID out of range: " + IntegerToString(service_id));
            return false;
        }

        if(m_entries[service_id].registered)
        {
            if(m_logger != NULL)
                m_logger.Warn("ServiceContainer",
                    "Register: " + m_entries[service_id].name + " already registered at slot " +
                    IntegerToString(service_id));
            return false;
        }

        if(ptr == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("ServiceContainer", "Register: " + name + " pointer is NULL");
            return false;
        }

        m_entries[service_id].id         = service_id;
        m_entries[service_id].lifetime   = lifetime;
        m_entries[service_id].name       = name;
        m_entries[service_id].ptr        = ptr;
        m_entries[service_id].registered = true;
        m_count++;

        return true;
    }
};

#endif // ATLAS_SERVICE_CONTAINER_MQH
//+------------------------------------------------------------------+
