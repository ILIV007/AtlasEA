//+------------------------------------------------------------------+
//|                  Config/ConfigurationWatcher.mqh                |
//|       AtlasEA v0.1.22.0 - Configuration Change Watcher          |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_WATCHER_MQH
#define ATLAS_CONFIGURATION_WATCHER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IConfigurationWatcher.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Maximum callbacks.
 */
#define ATLAS_CONFIG_WATCHER_MAX_CALLBACKS 8

/**
 * @class ConfigurationWatcher
 * @brief Concrete implementation of IConfigurationWatcher.
 *
 * Watches for configuration file changes and triggers safe reload.
 * Uses a critical section to prevent reload during tick processing.
 *
 * The watcher checks file modification time on every timer tick.
 * If the file has changed and we're not in a critical section,
 * reload is triggered and callbacks are notified.
 *
 * Critical section:
 *   - EnterCriticalSection() is called before OnTick()
 *   - LeaveCriticalSection() is called after OnTick() completes
 *   - If reload is pending, it executes after LeaveCriticalSection()
 */
class ConfigurationWatcher : public IConfigurationWatcher
{
private:
    ILogger *m_logger;
    string   m_config_filename;
    datetime m_last_file_time;
    bool     m_reload_pending;
    int      m_critical_section_depth;

    ConfigChangeCallback m_callbacks[ATLAS_CONFIG_WATCHER_MAX_CALLBACKS];
    void    *m_callback_data[ATLAS_CONFIG_WATCHER_MAX_CALLBACKS];
    int      m_callback_count;

public:
    /**
     * @brief Constructor.
     */
    ConfigurationWatcher(void)
    {
        m_logger               = NULL;
        m_config_filename      = "";
        m_last_file_time       = 0;
        m_reload_pending       = false;
        m_critical_section_depth = 0;
        m_callback_count       = 0;
    }

    /**
     * @brief Set the logger and config filename.
     */
    void SetDependencies(ILogger *logger, const string filename)
    {
        m_logger          = logger;
        m_config_filename = filename;
        m_last_file_time  = GetFileTime(filename);
    }

    //=== IConfigurationWatcher implementation ===

    virtual bool CheckForChanges(void) override
    {
        if(m_config_filename == "") return false;

        datetime current_time = GetFileTime(m_config_filename);
        if(current_time == 0) return false;  //--- File not found

        if(current_time > m_last_file_time)
        {
            m_last_file_time = current_time;

            if(m_critical_section_depth > 0)
            {
                //--- In critical section — defer reload
                m_reload_pending = true;
                if(m_logger != NULL)
                    m_logger.Info("ConfigurationWatcher",
                        "Change detected — reload deferred (critical section)");
                return false;
            }

            //--- Safe to reload
            TriggerReload();
            return true;
        }

        return false;
    }

    virtual void RegisterCallback(ConfigChangeCallback callback, void *user_data) override
    {
        if(m_callback_count >= ATLAS_CONFIG_WATCHER_MAX_CALLBACKS) return;
        m_callbacks[m_callback_count]     = callback;
        m_callback_data[m_callback_count] = user_data;
        m_callback_count++;
    }

    virtual void EnterCriticalSection(void) override
    {
        m_critical_section_depth++;
    }

    virtual void LeaveCriticalSection(void) override
    {
        if(m_critical_section_depth > 0)
            m_critical_section_depth--;

        //--- If reload was pending and we're now out of critical section
        if(m_reload_pending && m_critical_section_depth == 0)
        {
            m_reload_pending = false;
            TriggerReload();
        }
    }

    virtual bool IsReloadPending(void) const override { return m_reload_pending; }
    virtual bool IsInCriticalSection(void) const override { return m_critical_section_depth > 0; }

private:
    /// @brief Trigger all registered callbacks.
    void TriggerReload(void)
    {
        if(m_logger != NULL)
            m_logger.Info("ConfigurationWatcher", "Triggering reload callbacks");

        for(int i = 0; i < m_callback_count; i++)
        {
            if(m_callbacks[i] != NULL)
                m_callbacks[i](m_callback_data[i]);
        }
    }

    /// @brief Get file modification time (0 if not found).
    datetime GetFileTime(const string filename) const
    {
        if(filename == "") return 0;
        if(!FileIsExist(filename)) return 0;

        //--- MQL5 doesn't expose file modification time directly
        //--- Use a sentinel: open the file and read the first line
        //--- In production, this would use a hash or timestamp embedded in the file
        datetime result = 0;
        int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle != INVALID_HANDLE)
        {
            if(!FileIsEnding(handle))
            {
                string first_line = FileReadString(handle);
                //--- Parse timestamp from first line if present
                //--- For now, use current time as a proxy
                result = TimeCurrent();
            }
            FileClose(handle);
        }
        return result;
    }
};

#endif // ATLAS_CONFIGURATION_WATCHER_MQH
//+------------------------------------------------------------------+
