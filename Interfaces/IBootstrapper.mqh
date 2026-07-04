//+------------------------------------------------------------------+
//|                    Interfaces/IBootstrapper.mqh                 |
//|       AtlasEA v0.1.21.0 - Bootstrapper Interface                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_IBOOTSTRAPPER_MQH
#define ATLAS_IBOOTSTRAPPER_MQH

#include "../Config/Settings.mqh"

//--- Forward
struct AtlasConfig;
class CoreEngine;
class IDependencyContainer;

/**
 * @brief Bootstrap result codes.
 */
#define ATLAS_BOOTSTRAP_SUCCESS   0
#define ATLAS_BOOTSTRAP_FAILED    1
#define ATLAS_BOOTSTRAP_PARTIAL   2

/**
 * @class IBootstrapper
 * @brief Interface for application bootstrapping.
 *
 * The Bootstrapper builds the entire application graph in the correct
 * order, injects all dependencies, validates the graph, and returns
 * a fully-initialized CoreEngine.
 *
 * CoreEngine must NEVER instantiate modules directly — everything
 * comes from the Bootstrapper via the DependencyContainer.
 */
class IBootstrapper
{
public:
    /// @brief Bootstrap the entire application.
    /// @param config EA configuration.
    /// @return Pointer to initialized CoreEngine, or NULL on failure.
    virtual CoreEngine *Bootstrap(const AtlasConfig &config) = 0;

    /// @brief Shutdown the application (deletes all owned instances).
    virtual void Shutdown(void) = 0;

    /// @brief Get the dependency container.
    virtual IDependencyContainer* GetContainer(void) = 0;

    /// @brief Get the last bootstrap result.
    virtual int GetLastResult(void) const = 0;

    /// @brief Get the failure reason (if bootstrap failed).
    virtual string GetFailureReason(void) const = 0;

    /// @brief Is the application running?
    virtual bool IsRunning(void) const = 0;

    virtual ~IBootstrapper(void) {}
};

#endif // ATLAS_IBOOTSTRAPPER_MQH
//+------------------------------------------------------------------+
