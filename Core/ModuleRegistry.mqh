//+------------------------------------------------------------------+
//|                      Core/ModuleRegistry.mqh                    |
//|       AtlasEA v0.1.21.0 - Module Registry (upgraded v2)        |
//+------------------------------------------------------------------+
#ifndef ATLAS_MODULE_REGISTRY_MQH
#define ATLAS_MODULE_REGISTRY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IModuleRegistry.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum registered modules.
 */
#define ATLAS_MODULE_MAX 32

/**
 * @class ModuleRegistry
 * @brief Concrete implementation of IModuleRegistry.
 *
 * Tracks module registration, startup/shutdown order, health, versions,
 * and dependency lists.
 *
 * Fixed-size arrays. No dynamic allocation.
 */
class ModuleRegistry : public IModuleRegistry
{
private:
    ModuleInfo m_modules[ATLAS_MODULE_MAX];
    int        m_count;
    ILogger   *m_logger;

    int FindIndex(const int module_id) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_modules[i].module_id == module_id)
                return i;
        }
        return -1;
    }

public:
    /**
     * @brief Constructor.
     */
    ModuleRegistry(void)
    {
        m_logger = NULL;
        m_count  = 0;
        for(int i = 0; i < ATLAS_MODULE_MAX; i++)
        {
            m_modules[i].module_id        = 0;
            m_modules[i].name             = "";
            m_modules[i].version          = "";
            m_modules[i].health           = ATLAS_MODULE_HEALTH_UNKNOWN;
            m_modules[i].startup_order    = 999;
            m_modules[i].shutdown_order   = 999;
            m_modules[i].dependency_count = 0;
            m_modules[i].initialized      = false;
            m_modules[i].init_time        = 0;
            m_modules[i].failure_reason   = "";
            for(int j = 0; j < 8; j++)
                m_modules[i].dependencies[j] = 0;
        }
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IModuleRegistry implementation ===

    virtual bool Register(const int module_id, const string name, const string version,
                           const int startup_order, const int shutdown_order) override
    {
        if(module_id <= 0)
        {
            if(m_logger != NULL)
                m_logger.Error("ModuleRegistry", "Register: invalid module_id");
            return false;
        }

        if(FindIndex(module_id) >= 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("ModuleRegistry",
                    "Register: " + name + " already registered");
            return false;
        }

        if(m_count >= ATLAS_MODULE_MAX)
        {
            if(m_logger != NULL)
                m_logger.Error("ModuleRegistry", "Register: registry full");
            return false;
        }

        m_modules[m_count].module_id        = module_id;
        m_modules[m_count].name             = name;
        m_modules[m_count].version          = version;
        m_modules[m_count].health           = ATLAS_MODULE_HEALTH_UNKNOWN;
        m_modules[m_count].startup_order    = startup_order;
        m_modules[m_count].shutdown_order   = shutdown_order;
        m_modules[m_count].dependency_count = 0;
        m_modules[m_count].initialized      = false;
        m_modules[m_count].init_time        = 0;
        m_modules[m_count].failure_reason   = "";
        for(int j = 0; j < 8; j++)
            m_modules[m_count].dependencies[j] = 0;

        m_count++;

        if(m_logger != NULL)
            m_logger.Info("ModuleRegistry",
                "Registered: " + name + " v" + version +
                " (startup=" + IntegerToString(startup_order) +
                " shutdown=" + IntegerToString(shutdown_order) + ")");
        return true;
    }

    virtual bool MarkInitialized(const int module_id) override
    {
        int idx = FindIndex(module_id);
        if(idx < 0) return false;
        m_modules[idx].initialized = true;
        m_modules[idx].init_time   = TimeCurrent();
        m_modules[idx].health      = ATLAS_MODULE_HEALTH_HEALTHY;
        if(m_logger != NULL)
            m_logger.Info("ModuleRegistry", "Initialized: " + m_modules[idx].name);
        return true;
    }

    virtual bool MarkFailed(const int module_id, const string reason) override
    {
        int idx = FindIndex(module_id);
        if(idx < 0) return false;
        m_modules[idx].health         = ATLAS_MODULE_HEALTH_FAILED;
        m_modules[idx].failure_reason = reason;
        if(m_logger != NULL)
            m_logger.Error("ModuleRegistry",
                "Failed: " + m_modules[idx].name + " — " + reason);
        return true;
    }

    virtual void SetHealth(const int module_id, const int health) override
    {
        int idx = FindIndex(module_id);
        if(idx < 0) return;
        m_modules[idx].health = health;
    }

    virtual bool AddDependency(const int module_id, const int depends_on) override
    {
        int idx = FindIndex(module_id);
        if(idx < 0) return false;
        if(m_modules[idx].dependency_count >= 8) return false;
        m_modules[idx].dependencies[m_modules[idx].dependency_count] = depends_on;
        m_modules[idx].dependency_count++;
        return true;
    }

    virtual bool Find(const int module_id, ModuleInfo &out) const override
    {
        int idx = FindIndex(module_id);
        if(idx < 0) return false;
        out = m_modules[idx];
        return true;
    }

    virtual int GetStartupOrder(int out_ids[], const int max_count) const override
    {
        //--- Collect all module IDs
        int ids[ATLAS_MODULE_MAX];
        int orders[ATLAS_MODULE_MAX];
        int n = 0;

        for(int i = 0; i < m_count; i++)
        {
            ids[n]    = m_modules[i].module_id;
            orders[n] = m_modules[i].startup_order;
            n++;
        }

        //--- Sort by startup_order (ascending) — insertion sort
        for(int i = 1; i < n; i++)
        {
            int key_id    = ids[i];
            int key_order = orders[i];
            int j = i - 1;
            while(j >= 0 && orders[j] > key_order)
            {
                ids[j+1]    = ids[j];
                orders[j+1] = orders[j];
                j--;
            }
            ids[j+1]    = key_id;
            orders[j+1] = key_order;
        }

        int result = (n < max_count) ? n : max_count;
        for(int i = 0; i < result; i++)
            out_ids[i] = ids[i];
        return result;
    }

    virtual int GetShutdownOrder(int out_ids[], const int max_count) const override
    {
        //--- Same as startup but reversed
        int ids[ATLAS_MODULE_MAX];
        int orders[ATLAS_MODULE_MAX];
        int n = 0;

        for(int i = 0; i < m_count; i++)
        {
            ids[n]    = m_modules[i].module_id;
            orders[n] = m_modules[i].shutdown_order;
            n++;
        }

        //--- Sort by shutdown_order (ascending)
        for(int i = 1; i < n; i++)
        {
            int key_id    = ids[i];
            int key_order = orders[i];
            int j = i - 1;
            while(j >= 0 && orders[j] > key_order)
            {
                ids[j+1]    = ids[j];
                orders[j+1] = orders[j];
                j--;
            }
            ids[j+1]    = key_id;
            orders[j+1] = key_order;
        }

        int result = (n < max_count) ? n : max_count;
        for(int i = 0; i < result; i++)
            out_ids[i] = ids[i];
        return result;
    }

    virtual int Count(void) const override { return m_count; }

    virtual int InitializedCount(void) const override
    {
        int c = 0;
        for(int i = 0; i < m_count; i++)
            if(m_modules[i].initialized) c++;
        return c;
    }

    virtual bool AllInitialized(void) const override
    {
        if(m_count == 0) return false;
        for(int i = 0; i < m_count; i++)
            if(!m_modules[i].initialized) return false;
        return true;
    }

    virtual void Clear(void) override
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_MODULE_MAX; i++)
        {
            m_modules[i].module_id        = 0;
            m_modules[i].name             = "";
            m_modules[i].version          = "";
            m_modules[i].health           = ATLAS_MODULE_HEALTH_UNKNOWN;
            m_modules[i].startup_order    = 999;
            m_modules[i].shutdown_order   = 999;
            m_modules[i].dependency_count = 0;
            m_modules[i].initialized      = false;
            m_modules[i].init_time        = 0;
            m_modules[i].failure_reason   = "";
        }
    }

    /**
     * @brief Log all module statuses.
     */
    void LogStatus(void) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("ModuleRegistry",
            "Modules: " + IntegerToString(m_count) +
            " Initialized: " + IntegerToString(InitializedCount()));
        for(int i = 0; i < m_count; i++)
        {
            string health_str;
            switch(m_modules[i].health)
            {
                case ATLAS_MODULE_HEALTH_UNKNOWN:  health_str = "UNKNOWN";  break;
                case ATLAS_MODULE_HEALTH_HEALTHY:  health_str = "HEALTHY";  break;
                case ATLAS_MODULE_HEALTH_DEGRADED: health_str = "DEGRADED"; break;
                case ATLAS_MODULE_HEALTH_FAILED:   health_str = "FAILED";   break;
                default:                           health_str = "?";        break;
            }
            string init_str = m_modules[i].initialized ? "INIT" : "PENDING";
            m_logger.Info("ModuleRegistry",
                "  " + m_modules[i].name + " v" + m_modules[i].version +
                " [" + init_str + "] [" + health_str + "]");
        }
    }
};

#endif // ATLAS_MODULE_REGISTRY_MQH
//+------------------------------------------------------------------+
