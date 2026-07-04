//+------------------------------------------------------------------+
//|                   Interfaces/IStrategyFactory.mqh               |
//|       AtlasEA v0.1.17.0 - Strategy Plugin Factory               |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISTRATEGY_FACTORY_MQH
#define ATLAS_ISTRATEGY_FACTORY_MQH

#include "../Config/Settings.mqh"
#include "IStrategyPlugin.mqh"

/**
 * @class IStrategyFactory
 * @brief Factory interface for creating strategy plugin instances.
 *
 * Each plugin type can provide a factory that creates instances.
 * This allows the PluginManager to create plugins by ID without
 * knowing the concrete class.
 *
 * MQL5 has no reflection, so factories must be registered manually
 * at startup.
 */
class IStrategyFactory
{
public:
    /**
     * @brief Create a new instance of the strategy plugin.
     * @return Pointer to the new plugin (caller owns lifetime), or NULL on failure.
     */
    virtual IStrategyPlugin *Create(void) = 0;

    /**
     * @brief Get the plugin ID this factory creates.
     */
    virtual int GetPluginId(void) const = 0;

    /**
     * @brief Get the plugin name this factory creates.
     */
    virtual string GetPluginName(void) const = 0;

    /**
     * @brief Destroy an instance created by this factory.
     * @param plugin The plugin to destroy.
     */
    virtual void Destroy(IStrategyPlugin *plugin) = 0;

    virtual ~IStrategyFactory(void) {}
};

#endif // ATLAS_ISTRATEGY_FACTORY_MQH
//+------------------------------------------------------------------+
