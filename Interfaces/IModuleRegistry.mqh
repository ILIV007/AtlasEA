//+------------------------------------------------------------------+
//|                  Interfaces/IModuleRegistry.mqh                 |
//|       AtlasEA v0.1.21.0 - Module Registry Interface             |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMODULE_REGISTRY_MQH
#define ATLAS_IMODULE_REGISTRY_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Module health states.
 */
#define ATLAS_MODULE_HEALTH_UNKNOWN   0
#define ATLAS_MODULE_HEALTH_HEALTHY   1
#define ATLAS_MODULE_HEALTH_DEGRADED  2
#define ATLAS_MODULE_HEALTH_FAILED    3

/**
 * @struct ModuleInfo
 * @brief Information about a registered module.
 */
struct ModuleInfo
{
    int      module_id;       ///< ATLAS_MODULE_* constant
    string   name;            ///< Human-readable name
    string   version;         ///< Version string
    int      health;          ///< ATLAS_MODULE_HEALTH_*
    int      startup_order;   ///< Position in startup sequence (0 = first)
    int      shutdown_order;  ///< Position in shutdown sequence (0 = first)
    int      dependencies[8]; ///< Dependency module IDs
    int      dependency_count;
    bool     initialized;
    datetime init_time;
    string   failure_reason;
};

/**
 * @class IModuleRegistry
 * @brief Interface for module registration and discovery.
 */
class IModuleRegistry
{
public:
    /// @brief Register a module.
    virtual bool Register(const int module_id, const string name, const string version,
                           const int startup_order, const int shutdown_order) = 0;

    /// @brief Mark a module as initialized.
    virtual bool MarkInitialized(const int module_id) = 0;

    /// @brief Mark a module as failed.
    virtual bool MarkFailed(const int module_id, const string reason) = 0;

    /// @brief Set module health.
    virtual void SetHealth(const int module_id, const int health) = 0;

    /// @brief Add a dependency to a module.
    virtual bool AddDependency(const int module_id, const int depends_on) = 0;

    /// @brief Find a module by ID.
    virtual bool Find(const int module_id, ModuleInfo &out) const = 0;

    /// @brief Get all modules in startup order.
    virtual int GetStartupOrder(int out_ids[], const int max_count) const = 0;

    /// @brief Get all modules in shutdown order.
    virtual int GetShutdownOrder(int out_ids[], const int max_count) const = 0;

    /// @brief Count of registered modules.
    virtual int Count(void) const = 0;

    /// @brief Count of initialized modules.
    virtual int InitializedCount(void) const = 0;

    /// @brief Are all modules initialized?
    virtual bool AllInitialized(void) const = 0;

    /// @brief Clear all registrations.
    virtual void Clear(void) = 0;

    virtual ~IModuleRegistry(void) {}
};

#endif // ATLAS_IMODULE_REGISTRY_MQH
//+------------------------------------------------------------------+
