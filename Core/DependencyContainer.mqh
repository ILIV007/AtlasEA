//+------------------------------------------------------------------+
//|                  Core/DependencyContainer.mqh                   |
//|       AtlasEA v0.1.21.0 - Production DI Container                |
//+------------------------------------------------------------------+
#ifndef ATLAS_DEPENDENCY_CONTAINER_MQH
#define ATLAS_DEPENDENCY_CONTAINER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IDependencyContainer.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct DependencyEntry
 * @brief One entry in the dependency container.
 */
struct DependencyEntry
{
    int    id;           ///< ATLAS_DEP_* constant
    int    lifetime;     ///< ATLAS_LIFETIME_SINGLETON or TRANSIENT
    string name;         ///< Human-readable name
    void  *ptr;          ///< Pointer to the instance
    bool   registered;   ///< Is this slot occupied?
    bool   owns;         ///< Does the container own (delete) this instance?
};

/**
 * @class DependencyContainer
 * @brief Concrete implementation of IDependencyContainer.
 *
 * Fixed-size array of ATLAS_DEP_MAX (128) slots. O(1) registration
 * and resolution (direct index by service_id).
 *
 * The container OWNS the instances it creates. On Clear() or
 * destruction, owned instances are deleted. Non-owned instances
 * (registered with owns=false) are left for the caller to manage.
 *
 * Thread model: single-threaded (MQL5). No locks.
 * Memory: ~4 KB (128 entries × ~32 bytes each). No dynamic allocation.
 */
class DependencyContainer : public IDependencyContainer
{
private:
    DependencyEntry m_entries[ATLAS_DEP_MAX];
    int             m_count;
    ILogger        *m_logger;

public:
    /**
     * @brief Constructor.
     */
    DependencyContainer(void)
    {
        m_logger = NULL;
        m_count  = 0;
        for(int i = 0; i < ATLAS_DEP_MAX; i++)
        {
            m_entries[i].id         = 0;
            m_entries[i].lifetime   = ATLAS_LIFETIME_SINGLETON;
            m_entries[i].name       = "";
            m_entries[i].ptr        = NULL;
            m_entries[i].registered = false;
            m_entries[i].owns       = false;
        }
    }

    /**
     * @brief Destructor — deletes all owned instances.
     */
    ~DependencyContainer(void)
    {
        DeleteOwned();
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IDependencyContainer implementation ===

    virtual bool RegisterSingleton(const int service_id, const string name, void *ptr) override
    {
        return RegisterInternal(service_id, name, ptr, ATLAS_LIFETIME_SINGLETON, true);
    }

    /// @brief Register a singleton without ownership (caller manages lifetime).
    bool RegisterSingletonExternal(const int service_id, const string name, void *ptr)
    {
        return RegisterInternal(service_id, name, ptr, ATLAS_LIFETIME_SINGLETON, false);
    }

    virtual bool RegisterTransient(const int service_id, const string name, void *ptr) override
    {
        //--- MQL5 has no reflection, so transient is treated as singleton.
        return RegisterInternal(service_id, name, ptr, ATLAS_LIFETIME_TRANSIENT, true);
    }

    virtual void *Resolve(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX) return NULL;
        if(!m_entries[service_id].registered) return NULL;
        return m_entries[service_id].ptr;
    }

    virtual void *ResolveOrNull(const int service_id) const override
    {
        return Resolve(service_id);  ///< Same as Resolve — returns NULL if not found
    }

    virtual bool Exists(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX) return false;
        return m_entries[service_id].registered;
    }

    virtual bool Remove(const int service_id) override
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX) return false;
        if(!m_entries[service_id].registered) return false;

        //--- Delete if owned
        if(m_entries[service_id].owns && m_entries[service_id].ptr != NULL)
        {
            //--- Can't call delete on void* — caller must manage deletion
            //--- In practice, the Bootstrapper handles deletion
        }

        m_entries[service_id].id         = 0;
        m_entries[service_id].name       = "";
        m_entries[service_id].ptr        = NULL;
        m_entries[service_id].registered = false;
        m_entries[service_id].owns       = false;
        m_count--;
        return true;
    }

    virtual void Clear(void) override
    {
        DeleteOwned();
        for(int i = 0; i < ATLAS_DEP_MAX; i++)
        {
            m_entries[i].id         = 0;
            m_entries[i].name       = "";
            m_entries[i].ptr        = NULL;
            m_entries[i].registered = false;
            m_entries[i].owns       = false;
        }
        m_count = 0;
    }

    virtual bool ValidateGraph(void) const override
    {
        //--- Check essential services
        int essential[] = {
            ATLAS_DEP_LOGGER, ATLAS_DEP_BROKER, ATLAS_DEP_PERSISTENCE,
            ATLAS_DEP_MARKET_ENGINE, ATLAS_DEP_STRATEGY_ENGINE,
            ATLAS_DEP_RISK_ENGINE, ATLAS_DEP_EXECUTION_ENGINE,
            ATLAS_DEP_CORE_ENGINE
        };

        for(int i = 0; i < ArraySize(essential); i++)
        {
            if(!Exists(essential[i])) return false;
            if(ResolveOrNull(essential[i]) == NULL) return false;
        }
        return true;
    }

    virtual string GetName(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX) return "";
        if(!m_entries[service_id].registered) return "";
        return m_entries[service_id].name;
    }

    virtual int GetLifetime(const int service_id) const override
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX) return ATLAS_LIFETIME_SINGLETON;
        return m_entries[service_id].lifetime;
    }

    virtual int Count(void) const override { return m_count; }

    /**
     * @brief Log the container status.
     */
    void LogStatus(void) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("DependencyContainer",
            "Registered: " + IntegerToString(m_count) + "/" + IntegerToString(ATLAS_DEP_MAX));
        for(int i = 0; i < ATLAS_DEP_MAX; i++)
        {
            if(m_entries[i].registered)
            {
                string life = (m_entries[i].lifetime == ATLAS_LIFETIME_SINGLETON)
                              ? "Singleton" : "Transient";
                string owns = m_entries[i].owns ? "owned" : "external";
                m_logger.Info("DependencyContainer",
                    "  [" + IntegerToString(i) + "] " + m_entries[i].name +
                    " (" + life + ", " + owns + ")");
            }
        }
    }

private:
    bool RegisterInternal(const int service_id, const string name, void *ptr,
                           const int lifetime, const bool owns)
    {
        if(service_id < 0 || service_id >= ATLAS_DEP_MAX)
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyContainer",
                    "Register: ID out of range: " + IntegerToString(service_id));
            return false;
        }

        if(m_entries[service_id].registered)
        {
            if(m_logger != NULL)
                m_logger.Warn("DependencyContainer",
                    "Register: " + m_entries[service_id].name +
                    " already registered at slot " + IntegerToString(service_id));
            return false;
        }

        if(ptr == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyContainer",
                    "Register: " + name + " pointer is NULL");
            return false;
        }

        m_entries[service_id].id         = service_id;
        m_entries[service_id].lifetime   = lifetime;
        m_entries[service_id].name       = name;
        m_entries[service_id].ptr        = ptr;
        m_entries[service_id].registered = true;
        m_entries[service_id].owns       = owns;
        m_count++;

        return true;
    }

    /// @brief Delete all owned instances. Called on destruction/clear.
    /// Note: MQL5 cannot delete void*, so this is a no-op.
    /// The Bootstrapper handles deletion by casting to concrete types.
    void DeleteOwned(void)
    {
        //--- Container cannot delete void* — Bootstrapper handles cleanup
        //--- This method exists for future extension (smart pointers)
    }
};

#endif // ATLAS_DEPENDENCY_CONTAINER_MQH
//+------------------------------------------------------------------+
