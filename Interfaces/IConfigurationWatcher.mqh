//+------------------------------------------------------------------+
//|                Interfaces/IConfigurationWatcher.mqh             |
//|       AtlasEA v0.1.22.0 - Configuration Watcher Interface       |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONFIGURATION_WATCHER_MQH
#define ATLAS_ICONFIGURATION_WATCHER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Watcher callback type.
 */
typedef void (*ConfigChangeCallback)(void *user_data);

/**
 * @class IConfigurationWatcher
 * @brief Interface for watching configuration changes.
 *
 * Detects configuration file changes and triggers safe reload.
 * Prevents reload during critical execution (tick processing).
 */
class IConfigurationWatcher
{
public:
    /// @brief Check if configuration has changed (called on timer).
    virtual bool CheckForChanges(void) = 0;

    /// @brief Register a callback for change notifications.
    virtual void RegisterCallback(ConfigChangeCallback callback, void *user_data) = 0;

    /// @brief Enter critical section (prevents reload).
    virtual void EnterCriticalSection(void) = 0;

    /// @brief Leave critical section (allows reload).
    virtual void LeaveCriticalSection(void) = 0;

    /// @brief Is reload pending?
    virtual bool IsReloadPending(void) const = 0;

    /// @brief Is in critical section?
    virtual bool IsInCriticalSection(void) const = 0;

    virtual ~IConfigurationWatcher(void) {}
};

#endif // ATLAS_ICONFIGURATION_WATCHER_MQH
//+------------------------------------------------------------------+
