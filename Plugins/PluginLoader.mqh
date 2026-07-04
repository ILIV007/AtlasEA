//+------------------------------------------------------------------+
//|                     Plugins/PluginLoader.mqh                    |
//|       AtlasEA v0.1.17.0 - Plugin Loader                           |
//+------------------------------------------------------------------+
#ifndef ATLAS_PLUGIN_LOADER_MQH
#define ATLAS_PLUGIN_LOADER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"
#include "../Interfaces/IStrategyFactory.mqh"
#include "../Interfaces/ILogger.mqh"
#include "PluginRegistry.mqh"
#include "PluginValidator.mqh"

/**
 * @brief Maximum factories registered.
 */
#define ATLAS_FACTORY_MAX 32

/**
 * @class PluginLoader
 * @brief Handles plugin registration, validation, and dependency checks.
 *
 * Responsibilities:
 *   - Register factories (for plugin creation by ID)
 *   - Create plugins from factories
 *   - Validate plugins before registration
 *   - Check for duplicates
 *   - Register valid plugins in the PluginRegistry
 *
 * The loader does NOT own plugins — the caller (PluginManager) owns them.
 */
class PluginLoader
{
private:
    ILogger           *m_logger;
    PluginValidator    m_validator;
    IStrategyFactory  *m_factories[ATLAS_FACTORY_MAX];
    int                m_factory_count;

public:
    /**
     * @brief Constructor.
     */
    PluginLoader(void)
    {
        m_logger        = NULL;
        m_factory_count = 0;
        for(int i = 0; i < ATLAS_FACTORY_MAX; i++)
            m_factories[i] = NULL;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_validator.SetLogger(logger);
    }

    /**
     * @brief Register a factory.
     * @param factory The factory to register.
     * @return true if registered, false if full or duplicate.
     */
    bool RegisterFactory(IStrategyFactory *factory)
    {
        if(factory == NULL) return false;
        if(m_factory_count >= ATLAS_FACTORY_MAX) return false;

        //--- Check for duplicate
        for(int i = 0; i < m_factory_count; i++)
        {
            if(m_factories[i] != NULL && m_factories[i].GetPluginId() == factory.GetPluginId())
            {
                if(m_logger != NULL)
                    m_logger.Warn("PluginLoader", "Duplicate factory for plugin_id=" +
                                 IntegerToString(factory.GetPluginId()));
                return false;
            }
        }

        m_factories[m_factory_count] = factory;
        m_factory_count++;

        if(m_logger != NULL)
            m_logger.Info("PluginLoader", "Factory registered: " + factory.GetPluginName());
        return true;
    }

    /**
     * @brief Create and register a plugin by ID.
     * @param registry The registry to register into.
     * @param plugin_id The plugin ID to create.
     * @return Pointer to the created plugin, or NULL on failure.
     */
    IStrategyPlugin *CreateAndRegister(PluginRegistry &registry, const int plugin_id)
    {
        //--- Find the factory
        IStrategyFactory *factory = NULL;
        for(int i = 0; i < m_factory_count; i++)
        {
            if(m_factories[i] != NULL && m_factories[i].GetPluginId() == plugin_id)
            {
                factory = m_factories[i];
                break;
            }
        }

        if(factory == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "No factory for plugin_id=" + IntegerToString(plugin_id));
            return NULL;
        }

        //--- Create the plugin
        IStrategyPlugin *plugin = factory.Create();
        if(plugin == NULL)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Factory returned NULL for plugin_id=" + IntegerToString(plugin_id));
            return NULL;
        }

        //--- Validate
        ValidationResult vr = m_validator.Validate(*plugin);
        if(!vr.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Validation failed: " + vr.reason);
            factory.Destroy(plugin);
            return NULL;
        }

        //--- Register
        if(!registry.Register(plugin))
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Registration failed for plugin_id=" + IntegerToString(plugin_id));
            factory.Destroy(plugin);
            return NULL;
        }

        //--- Initialize
        if(!plugin.Initialize())
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Initialize failed for plugin_id=" + IntegerToString(plugin_id));
            registry.Unregister(plugin_id);
            factory.Destroy(plugin);
            return NULL;
        }

        if(m_logger != NULL)
            m_logger.Info("PluginLoader",
                "Plugin created and registered: " + plugin.Name() + " v" + plugin.Version());

        return plugin;
    }

    /**
     * @brief Load a pre-created plugin (validate + register).
     * @param registry The registry.
     * @param plugin The plugin to load.
     * @return true if loaded successfully.
     */
    bool LoadPlugin(PluginRegistry &registry, IStrategyPlugin *plugin)
    {
        if(plugin == NULL) return false;

        //--- Validate
        ValidationResult vr = m_validator.Validate(*plugin);
        if(!vr.valid)
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Validation failed: " + vr.reason);
            return false;
        }

        //--- Register
        if(!registry.Register(plugin))
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Registration failed");
            return false;
        }

        //--- Initialize
        if(!plugin.Initialize())
        {
            if(m_logger != NULL)
                m_logger.Error("PluginLoader", "Initialize failed");
            registry.Unregister(plugin.GetMetadata().plugin_id);
            return false;
        }

        return true;
    }

    /**
     * @brief Unload a plugin (unregister + shutdown).
     * Does NOT delete the plugin (caller owns lifetime).
     */
    bool UnloadPlugin(PluginRegistry &registry, const int plugin_id)
    {
        IStrategyPlugin *plugin = registry.Find(plugin_id);
        if(plugin == NULL) return false;

        plugin.Shutdown();
        registry.Unregister(plugin_id);
        return true;
    }

    /**
     * @brief Get factory count.
     */
    int FactoryCount(void) const { return m_factory_count; }

    /**
     * @brief Get the validator (for direct access).
     */
    PluginValidator& GetValidator(void) { return m_validator; }
};

#endif // ATLAS_PLUGIN_LOADER_MQH
//+------------------------------------------------------------------+
