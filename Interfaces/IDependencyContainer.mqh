//+------------------------------------------------------------------+
//|                 Interfaces/IDependencyContainer.mqh             |
//|       AtlasEA v0.1.21.0 - Dependency Container Interface        |
//+------------------------------------------------------------------+
#ifndef ATLAS_IDEPENDENCY_CONTAINER_MQH
#define ATLAS_IDEPENDENCY_CONTAINER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Service lifetime codes.
 */
#define ATLAS_LIFETIME_SINGLETON  0
#define ATLAS_LIFETIME_TRANSIENT  1

/**
 * @brief Service type IDs (compile-time integer keys).
 * Using integers for O(1) lookup and zero allocation.
 */
#define ATLAS_DEP_LOGGER           1
#define ATLAS_DEP_CLOCK            2
#define ATLAS_DEP_UUID             3
#define ATLAS_DEP_METRICS          4
#define ATLAS_DEP_HEALTH           5
#define ATLAS_DEP_ERROR_MANAGER    6
#define ATLAS_DEP_CONFIG_PROVIDER  7
#define ATLAS_DEP_BROKER           8
#define ATLAS_DEP_PERSISTENCE      9
#define ATLAS_DEP_TRADE_MANAGER   10
#define ATLAS_DEP_MARKET_ENGINE   11
#define ATLAS_DEP_STRATEGY_ENGINE 12
#define ATLAS_DEP_RISK_ENGINE     13
#define ATLAS_DEP_EXECUTION_ENGINE 14
#define ATLAS_DEP_CORE_ENGINE     15
#define ATLAS_DEP_EVENT_BUS       16
#define ATLAS_DEP_RECOVERY        17
#define ATLAS_DEP_METRICS_EXPORTER 18
#define ATLAS_DEP_MAX             128

/**
 * @class IDependencyContainer
 * @brief Type-safe dependency injection container interface.
 *
 * The container is the ONLY object allowed to own implementations.
 * All modules resolve their dependencies through this interface.
 *
 * Thread model: single-threaded (MQL5). No locks.
 */
class IDependencyContainer
{
public:
    /// @brief Register a singleton (one instance for the application).
    virtual bool RegisterSingleton(const int service_id, const string name, void *ptr) = 0;

    /// @brief Register a transient (new instance per resolve — treated as singleton in MQL5).
    virtual bool RegisterTransient(const int service_id, const string name, void *ptr) = 0;

    /// @brief Resolve a service by ID. Returns NULL if not found.
    virtual void *Resolve(const int service_id) const = 0;

    /// @brief Resolve or return NULL (explicit null-safe variant).
    virtual void *ResolveOrNull(const int service_id) const = 0;

    /// @brief Check if a service is registered.
    virtual bool Exists(const int service_id) const = 0;

    /// @brief Remove a service (does NOT delete the instance).
    virtual bool Remove(const int service_id) = 0;

    /// @brief Clear all registrations (does NOT delete instances).
    virtual void Clear(void) = 0;

    /// @brief Validate the dependency graph (no missing deps, no cycles).
    virtual bool ValidateGraph(void) const = 0;

    /// @brief Get the service name.
    virtual string GetName(const int service_id) const = 0;

    /// @brief Get the lifetime.
    virtual int GetLifetime(const int service_id) const = 0;

    /// @brief Count of registered services.
    virtual int Count(void) const = 0;

    virtual ~IDependencyContainer(void) {}
};

#endif // ATLAS_IDEPENDENCY_CONTAINER_MQH
//+------------------------------------------------------------------+
