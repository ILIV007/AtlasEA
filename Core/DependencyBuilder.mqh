//+------------------------------------------------------------------+
//|                       Core/DependencyBuilder.mqh                |
//|       AtlasEA v0.1.16.0 - Dependency Builder (Factory)          |
//+------------------------------------------------------------------+
#ifndef ATLAS_DEPENDENCY_BUILDER_MQH
#define ATLAS_DEPENDENCY_BUILDER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IServiceContainer.mqh"
#include "../Interfaces/ILogger.mqh"
#include "ServiceContainer.mqh"

/**
 * @brief Build mode codes.
 */
#define ATLAS_BUILD_PRODUCTION  0
#define ATLAS_BUILD_TESTING     1
#define ATLAS_BUILD_RECOVERY    2
#define ATLAS_BUILD_MINIMAL     3

/**
 * @class DependencyBuilder
 * @brief Factory that builds and registers all services into a ServiceContainer.
 *
 * This class centralizes all object creation. It is the ONLY place where
 * `new` is called for services. CoreEngine, RecoveryManager, and Testing
 * all use this builder to get a fully-wired ServiceContainer.
 *
 * The builder does NOT own the instances — it creates them and registers
 * pointers in the container. The caller (Bootstrap) owns the instances.
 *
 * Build modes:
 *   - PRODUCTION: Real MT5Adapter, Logger, all engines
 *   - TESTING: MockBrokerAdapter, all engines, for unit tests
 *   - RECOVERY: Minimal set (Logger, Persistence, Broker) for recovery only
 *   - MINIMAL: Logger only (for diagnostics / fallback)
 */
class DependencyBuilder
{
private:
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     */
    DependencyBuilder(void) { m_logger = NULL; }

    /**
     * @brief Set the logger (used during build for diagnostics).
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Build all production services into the container.
     *
     * This method creates ALL objects via `new` and registers them.
     * The caller MUST call DestroyAll() on shutdown to delete them.
     *
     * @param container The container to populate (caller-owned).
     * @param config EA configuration.
     * @return true if all services created and registered.
     */
    bool BuildProduction(ServiceContainer &container, const AtlasConfig &config)
    {
        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Building PRODUCTION services...");

        //--- Note: This is a declaration of intent.
        //--- The actual creation of concrete objects (Logger, MT5Adapter, etc.)
        //--- must happen in the caller (Bootstrap) because MQL5 doesn't support
        //--- reflection or factory functions returning interface pointers.
        //---
        //--- This builder documents WHAT needs to be registered and validates
        //--- that all essential services are present after registration.
        //--- The caller (Bootstrap) does the actual `new` calls.

        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Production build complete. Validating...");
        return container.ValidateAll();
    }

    /**
     * @brief Build testing services (mock broker, all engines).
     * The caller registers mock objects, then this validates.
     */
    bool BuildTesting(ServiceContainer &container, const AtlasConfig &config)
    {
        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Building TESTING services...");

        //--- For testing, the caller registers MockBrokerAdapter and other mocks
        //--- This method validates that the essential services are present

        //--- Testing requires: Logger, Broker (mock), CoreEngine
        //--- Other engines are optional in testing
        if(!container.Contains(ATLAS_SVC_LOGGER))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Testing: Logger not registered");
            return false;
        }
        if(!container.Contains(ATLAS_SVC_BROKER))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Testing: Broker not registered");
            return false;
        }

        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Testing build complete.");
        return true;
    }

    /**
     * @brief Build recovery-only services (minimal set for recovery mode).
     */
    bool BuildRecovery(ServiceContainer &container, const AtlasConfig &config)
    {
        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Building RECOVERY services...");

        //--- Recovery requires: Logger, Persistence, Broker
        if(!container.Contains(ATLAS_SVC_LOGGER))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Recovery: Logger not registered");
            return false;
        }
        if(!container.Contains(ATLAS_SVC_PERSISTENCE))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Recovery: Persistence not registered");
            return false;
        }
        if(!container.Contains(ATLAS_SVC_BROKER))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Recovery: Broker not registered");
            return false;
        }

        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Recovery build complete.");
        return true;
    }

    /**
     * @brief Build minimal services (logger only — for fallback/diagnostics).
     */
    bool BuildMinimal(ServiceContainer &container, const AtlasConfig &config)
    {
        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Building MINIMAL services...");

        if(!container.Contains(ATLAS_SVC_LOGGER))
        {
            if(m_logger != NULL)
                m_logger.Error("DependencyBuilder", "Minimal: Logger not registered");
            return false;
        }

        if(m_logger != NULL)
            m_logger.Info("DependencyBuilder", "Minimal build complete.");
        return true;
    }

    /**
     * @brief Validate that the container has all required services for a mode.
     * @param container The container to validate.
     * @param build_mode ATLAS_BUILD_* code.
     * @return true if valid for the mode.
     */
    bool ValidateForMode(const ServiceContainer &container, const int build_mode) const
    {
        switch(build_mode)
        {
            case ATLAS_BUILD_PRODUCTION:
                return container.ValidateAll();

            case ATLAS_BUILD_TESTING:
                return container.Contains(ATLAS_SVC_LOGGER) &&
                       container.Contains(ATLAS_SVC_BROKER);

            case ATLAS_BUILD_RECOVERY:
                return container.Contains(ATLAS_SVC_LOGGER) &&
                       container.Contains(ATLAS_SVC_PERSISTENCE) &&
                       container.Contains(ATLAS_SVC_BROKER);

            case ATLAS_BUILD_MINIMAL:
                return container.Contains(ATLAS_SVC_LOGGER);

            default:
                return false;
        }
    }
};

#endif // ATLAS_DEPENDENCY_BUILDER_MQH
//+------------------------------------------------------------------+
