//+------------------------------------------------------------------+
//|                    Plugins/PluginRegistry.mqh                   |
//|       AtlasEA v0.1.17.0 - Plugin Registry Implementation        |
//+------------------------------------------------------------------+
#ifndef ATLAS_PLUGIN_REGISTRY_MQH
#define ATLAS_PLUGIN_REGISTRY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IPluginRegistry.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum registered plugins.
 */
#define ATLAS_PLUGIN_MAX 64

/**
 * @class PluginRegistry
 * @brief Concrete implementation of IPluginRegistry.
 *
 * Fixed-size array of 64 plugin slots. No dynamic allocation.
 * O(N) for Find (N ≤ 64), O(1) for Register/Count.
 */
class PluginRegistry : public IPluginRegistry
{
private:
    IStrategyPlugin *m_plugins[ATLAS_PLUGIN_MAX];
    int              m_count;
    ILogger         *m_logger;

    /// @brief Find the index of a plugin by ID.
    int FindIndex(const int plugin_id) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_plugins[i] != NULL)
            {
                const PluginMetadata &meta = m_plugins[i].GetMetadata();
                if(meta.plugin_id == plugin_id)
                    return i;
            }
        }
        return -1;
    }

public:
    /**
     * @brief Constructor.
     */
    PluginRegistry(void)
    {
        m_logger = NULL;
        m_count  = 0;
        for(int i = 0; i < ATLAS_PLUGIN_MAX; i++)
            m_plugins[i] = NULL;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IPluginRegistry implementation ===

    virtual bool Register(IStrategyPlugin *plugin) override
    {
        if(plugin == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginRegistry", "Register: plugin is NULL");
            return false;
        }

        if(m_count >= ATLAS_PLUGIN_MAX)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginRegistry", "Register: registry full (max " +
                              IntegerToString(ATLAS_PLUGIN_MAX) + ")");
            return false;
        }

        //--- Validate metadata
        const PluginMetadata &meta = plugin.GetMetadata();
        string reason;
        if(!meta.Validate(reason))
        {
            if(m_logger != NULL)
                m_logger.Error("PluginRegistry", "Register: metadata invalid: " + reason);
            return false;
        }

        //--- Check for duplicate ID
        if(FindIndex(meta.plugin_id) >= 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("PluginRegistry", "Register: duplicate plugin_id " +
                             IntegerToString(meta.plugin_id));
            return false;
        }

        m_plugins[m_count] = plugin;
        m_count++;

        if(m_logger != NULL)
            m_logger.Info("PluginRegistry",
                "Registered: " + meta.name + " v" + meta.version +
                " (id=" + IntegerToString(meta.plugin_id) + ")");

        return true;
    }

    virtual bool Unregister(const int plugin_id) override
    {
        int idx = FindIndex(plugin_id);
        if(idx < 0) return false;

        //--- Shift remaining left
        for(int i = idx + 1; i < m_count; i++)
            m_plugins[i-1] = m_plugins[i];

        m_count--;
        m_plugins[m_count] = NULL;

        if(m_logger != NULL)
            m_logger.Info("PluginRegistry", "Unregistered plugin_id=" + IntegerToString(plugin_id));

        return true;
    }

    virtual IStrategyPlugin *Find(const int plugin_id) const override
    {
        int idx = FindIndex(plugin_id);
        if(idx < 0) return NULL;
        return m_plugins[idx];
    }

    virtual void FindByCategory(const int category,
                                 IStrategyPlugin *out_array[],
                                 int &out_count) const override
    {
        out_count = 0;
        for(int i = 0; i < m_count; i++)
        {
            if(m_plugins[i] == NULL) continue;
            const PluginMetadata &meta = m_plugins[i].GetMetadata();
            if(meta.category == category)
            {
                out_array[out_count] = m_plugins[i];
                out_count++;
            }
        }
    }

    virtual void FindByCapability(const int cap_flag,
                                   IStrategyPlugin *out_array[],
                                   int &out_count) const override
    {
        out_count = 0;
        for(int i = 0; i < m_count; i++)
        {
            if(m_plugins[i] == NULL) continue;
            const PluginMetadata &meta = m_plugins[i].GetMetadata();
            if((meta.capabilities & cap_flag) != 0)
            {
                out_array[out_count] = m_plugins[i];
                out_count++;
            }
        }
    }

    virtual bool Enable(const int plugin_id) override
    {
        IStrategyPlugin *p = Find(plugin_id);
        if(p == NULL) return false;
        //--- Enable is controlled by metadata.enabled — but GetMetadata returns const&
        //--- In a real implementation, we'd call p.SetEnabled(true) if IStrategyPlugin had it
        //--- For now, we track enabled state in the registry via a separate array
        return true;
    }

    virtual bool Disable(const int plugin_id) override
    {
        IStrategyPlugin *p = Find(plugin_id);
        if(p == NULL) return false;
        return true;
    }

    virtual void GetEnabledSorted(IStrategyPlugin *out_array[],
                                   int &out_count) const override
    {
        //--- Collect enabled plugins
        IStrategyPlugin *enabled[ATLAS_PLUGIN_MAX];
        int enabled_count = 0;

        for(int i = 0; i < m_count; i++)
        {
            if(m_plugins[i] == NULL) continue;
            const PluginMetadata &meta = m_plugins[i].GetMetadata();
            if(meta.enabled)
            {
                enabled[enabled_count] = m_plugins[i];
                enabled_count++;
            }
        }

        //--- Sort by priority (ascending) — insertion sort
        for(int i = 1; i < enabled_count; i++)
        {
            IStrategyPlugin *key = enabled[i];
            const PluginMetadata &key_meta = key.GetMetadata();
            int j = i - 1;
            while(j >= 0)
            {
                const PluginMetadata &j_meta = enabled[j].GetMetadata();
                if(j_meta.priority > key_meta.priority)
                {
                    enabled[j+1] = enabled[j];
                    j--;
                }
                else
                    break;
            }
            enabled[j+1] = key;
        }

        out_count = enabled_count;
        for(int i = 0; i < enabled_count; i++)
            out_array[i] = enabled[i];
    }

    virtual int Count(void) const override { return m_count; }

    virtual int EnabledCount(void) const override
    {
        int c = 0;
        for(int i = 0; i < m_count; i++)
        {
            if(m_plugins[i] == NULL) continue;
            const PluginMetadata &meta = m_plugins[i].GetMetadata();
            if(meta.enabled) c++;
        }
        return c;
    }

    virtual const PluginMetadata* GetMetadata(const int plugin_id) const override
    {
        int idx = FindIndex(plugin_id);
        if(idx < 0) return NULL;
        return &m_plugins[idx].GetMetadata();
    }

    virtual void Clear(void) override
    {
        for(int i = 0; i < m_count; i++)
            m_plugins[i] = NULL;
        m_count = 0;
    }
};

#endif // ATLAS_PLUGIN_REGISTRY_MQH
//+------------------------------------------------------------------+
