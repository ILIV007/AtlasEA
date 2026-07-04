//+------------------------------------------------------------------+
//|                  Interfaces/IPluginRegistry.mqh                 |
//|       AtlasEA v0.1.17.0 - Plugin Registry Interface             |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPLUGIN_REGISTRY_MQH
#define ATLAS_IPLUGIN_REGISTRY_MQH

#include "../Config/Settings.mqh"
#include "IStrategyPlugin.mqh"
#include "IPluginMetadata.mqh"

/**
 * @class IPluginRegistry
 * @brief Interface for the plugin registry.
 *
 * The registry manages plugin instances. CoreEngine and StrategyEngine
 * communicate with plugins ONLY through this interface.
 */
class IPluginRegistry
{
public:
    /**
     * @brief Register a plugin instance.
     * @param plugin The plugin to register (caller owns lifetime).
     * @return true if registered, false on duplicate ID or full.
     */
    virtual bool Register(IStrategyPlugin *plugin) = 0;

    /**
     * @brief Unregister a plugin by ID.
     * Does NOT delete the plugin (caller owns lifetime).
     */
    virtual bool Unregister(const int plugin_id) = 0;

    /**
     * @brief Find a plugin by ID.
     * @return Pointer to the plugin, or NULL if not found.
     */
    virtual IStrategyPlugin *Find(const int plugin_id) const = 0;

    /**
     * @brief Find plugins by category.
     * @param category ATLAS_PLUGIN_CAT_*
     * @param out_array Output array (caller-allocated, capacity >= 64).
     * @param out_count Output: number of plugins found.
     */
    virtual void FindByCategory(const int category,
                                 IStrategyPlugin *out_array[],
                                 int &out_count) const = 0;

    /**
     * @brief Find plugins by capability flag.
     * @param cap_flag ATLAS_CAP_* bit flag.
     * @param out_array Output array.
     * @param out_count Output count.
     */
    virtual void FindByCapability(const int cap_flag,
                                   IStrategyPlugin *out_array[],
                                   int &out_count) const = 0;

    /**
     * @brief Enable a plugin by ID.
     */
    virtual bool Enable(const int plugin_id) = 0;

    /**
     * @brief Disable a plugin by ID.
     */
    virtual bool Disable(const int plugin_id) = 0;

    /**
     * @brief Get all enabled plugins, sorted by priority.
     */
    virtual void GetEnabledSorted(IStrategyPlugin *out_array[],
                                   int &out_count) const = 0;

    /**
     * @brief Number of registered plugins.
     */
    virtual int Count(void) const = 0;

    /**
     * @brief Number of enabled plugins.
     */
    virtual int EnabledCount(void) const = 0;

    /**
     * @brief Get metadata for a plugin.
     */
    virtual const PluginMetadata* GetMetadata(const int plugin_id) const = 0;

    /**
     * @brief Clear all registrations (does NOT delete plugins).
     */
    virtual void Clear(void) = 0;

    virtual ~IPluginRegistry(void) {}
};

#endif // ATLAS_IPLUGIN_REGISTRY_MQH
//+------------------------------------------------------------------+
