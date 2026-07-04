//+------------------------------------------------------------------+
//|                     Interfaces/IServiceContainer.mqh            |
//|       AtlasEA v0.1.16.0 - Service Container Interface           |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISERVICE_CONTAINER_MQH
#define ATLAS_ISERVICE_CONTAINER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Service lifetime codes.
 */
#define ATLAS_LIFETIME_SINGLETON  0   ///< One instance for the entire application
#define ATLAS_LIFETIME_TRANSIENT  1   ///< New instance on every Resolve

/**
 * @brief Service ID constants (compile-time integer keys).
 * Using integers instead of strings for O(1) lookup and zero allocation.
 */
#define ATLAS_SVC_LOGGER          1
#define ATLAS_SVC_CLOCK           2
#define ATLAS_SVC_UUID            3
#define ATLAS_SVC_METRICS         4
#define ATLAS_SVC_HEALTH          5
#define ATLAS_SVC_ERROR_MANAGER   6
#define ATLAS_SVC_CONFIG_PROVIDER 7
#define ATLAS_SVC_BROKER          8
#define ATLAS_SVC_PERSISTENCE     9
#define ATLAS_SVC_TRADE_MANAGER   10
#define ATLAS_SVC_MARKET_ENGINE   11
#define ATLAS_SVC_STRATEGY_ENGINE 12
#define ATLAS_SVC_RISK_ENGINE     13
#define ATLAS_SVC_EXECUTION_ENGINE 14
#define ATLAS_SVC_CORE_ENGINE     15
#define ATLAS_SVC_EVENT_BUS       16
#define ATLAS_SVC_RECOVERY        17
#define ATLAS_SVC_METRICS_EXPORTER 18
#define ATLAS_SVC_MAX             128   ///< Maximum services in container

/**
 * @class IServiceContainer
 * @brief Interface for a dependency injection service container.
 *
 * The container stores service instances by integer ID. Services can
 * be registered as Singleton (one instance) or Transient (new each
 * resolve — not fully implemented in MQL5 due to no reflection).
 *
 * The container does NOT own the instances — the caller (Bootstrap)
 * owns them. The container only maps IDs to pointers.
 */
class IServiceContainer
{
public:
    /**
     * @brief Register a service as a singleton.
     * @param service_id  ATLAS_SVC_* constant.
     * @param name        Human-readable name (for diagnostics).
     * @param ptr         Pointer to the service instance.
     * @return true if registered, false if duplicate or full.
     */
    virtual bool RegisterSingleton(const int service_id, const string name, void *ptr) = 0;

    /**
     * @brief Register a service as transient (placeholder — MQL5 has
     * no reflection, so transient is treated as singleton).
     */
    virtual bool RegisterTransient(const int service_id, const string name, void *ptr) = 0;

    /**
     * @brief Resolve a service by ID.
     * @param service_id ATLAS_SVC_* constant.
     * @return Pointer to the service, or NULL if not registered.
     */
    virtual void *Resolve(const int service_id) const = 0;

    /**
     * @brief Check if a service is registered.
     */
    virtual bool Contains(const int service_id) const = 0;

    /**
     * @brief Get the name of a registered service.
     */
    virtual string GetName(const int service_id) const = 0;

    /**
     * @brief Get the lifetime of a registered service.
     */
    virtual int GetLifetime(const int service_id) const = 0;

    /**
     * @brief Count of registered services.
     */
    virtual int Count(void) const = 0;

    /**
     * @brief Clear all registrations (does NOT delete instances).
     */
    virtual void Clear(void) = 0;

    /**
     * @brief Validate that all required services are registered.
     * @return true if all essential services present.
     */
    virtual bool ValidateAll(void) const = 0;

    /**
     * @brief Log the container status.
     */
    virtual void LogStatus(void) const = 0;

    virtual ~IServiceContainer(void) {}
};

#endif // ATLAS_ISERVICE_CONTAINER_MQH
//+------------------------------------------------------------------+
