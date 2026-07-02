//+------------------------------------------------------------------+
//|                                      Core/ModuleRegistry.mqh
//|            AtlasEA v2.0 - Module Registration & Discovery         |
//+------------------------------------------------------------------+
#ifndef ATLAS_MODULE_REGISTRY_MQH
#define ATLAS_MODULE_REGISTRY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class ModuleRegistry
 * @brief Tracks which modules are registered and initialized.
 *
 * Provides module discovery for diagnostics and startup validation.
 * Each module is identified by its ATLAS_MODULE_* ID and has a name,
 * initialization status, and a version string.
 *
 * Memory: fixed-size arrays (no dynamic allocation).
 */
class ModuleRegistry
{
private:
    /// Maximum registered modules
    static const int MAX_MODULES = 16;

    int     m_ids[MAX_MODULES];       ///< Module IDs
    string  m_names[MAX_MODULES];     ///< Human-readable names
    string  m_versions[MAX_MODULES];  ///< Version strings
    bool    m_initialized[MAX_MODULES]; ///< Init status
    datetime m_init_time[MAX_MODULES]; ///< When initialized
    int     m_count;                  ///< Number of registered modules
    ILogger *m_logger;

    /// @brief Find the index of a module by ID. Returns -1 if not found.
    int FindIndex(const int module_id) const;

public:
    /**
     * @brief Constructor.
     */
    ModuleRegistry(void);

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a module.
     * @param module_id  ATLAS_MODULE_* constant.
     * @param name       Human-readable name.
     * @param version    Version string.
     * @return true if registered, false if table full or duplicate.
     */
    bool Register(const int module_id, const string name, const string version);

    /**
     * @brief Mark a module as initialized.
     * @param module_id ATLAS_MODULE_* constant.
     * @return true if marked, false if not registered.
     */
    bool MarkInitialized(const int module_id);

    /**
     * @brief Check if a module is registered.
     */
    bool IsRegistered(const int module_id) const;

    /**
     * @brief Check if a module is initialized.
     */
    bool IsInitialized(const int module_id) const;

    /**
     * @brief Get the name of a module.
     */
    string GetName(const int module_id) const;

    /**
     * @brief Get the version of a module.
     */
    string GetVersion(const int module_id) const;

    /**
     * @brief Get the initialization time of a module.
     */
    datetime GetInitTime(const int module_id) const;

    /// @brief Number of registered modules.
    int Count(void) const { return m_count; }

    /**
     * @brief Check if all registered modules are initialized.
     * @return true if every registered module has been marked initialized.
     */
    bool AllInitialized(void) const;

    /**
     * @brief Reset the registry (shutdown).
     */
    void Reset(void);

    /**
     * @brief Log the status of all registered modules.
     */
    void LogStatus(void) const;
};

//+------------------------------------------------------------------+
//| ModuleRegistry implementation                                     |
//+------------------------------------------------------------------+

ModuleRegistry::ModuleRegistry(void)
{
    m_logger = NULL;
    m_count  = 0;
    for(int i = 0; i < MAX_MODULES; i++)
    {
        m_ids[i]         = 0;
        m_initialized[i] = false;
        m_init_time[i]   = 0;
    }
}

//+------------------------------------------------------------------+
int ModuleRegistry::FindIndex(const int module_id) const
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_ids[i] == module_id)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
bool ModuleRegistry::Register(const int module_id, const string name, const string version)
{
    if(module_id <= 0)
    {
        if(m_logger != NULL)
            m_logger.Error("ModuleRegistry", "Register: invalid module_id");
        return false;
    }

    if(FindIndex(module_id) >= 0)
    {
        if(m_logger != NULL)
            m_logger.Warn("ModuleRegistry", "Register: module " + IntegerToString(module_id) + " already registered");
        return false;
    }

    if(m_count >= MAX_MODULES)
    {
        if(m_logger != NULL)
            m_logger.Error("ModuleRegistry", "Register: table full");
        return false;
    }

    m_ids[m_count]         = module_id;
    m_names[m_count]       = name;
    m_versions[m_count]    = version;
    m_initialized[m_count] = false;
    m_init_time[m_count]   = 0;
    m_count++;

    if(m_logger != NULL)
        m_logger.Info("ModuleRegistry", "Registered: " + name + " v" + version);
    return true;
}

//+------------------------------------------------------------------+
bool ModuleRegistry::MarkInitialized(const int module_id)
{
    int idx = FindIndex(module_id);
    if(idx < 0)
    {
        if(m_logger != NULL)
            m_logger.Error("ModuleRegistry", "MarkInitialized: module " + IntegerToString(module_id) + " not registered");
        return false;
    }

    m_initialized[idx] = true;
    m_init_time[idx]   = TimeCurrent();

    if(m_logger != NULL)
        m_logger.Info("ModuleRegistry", "Initialized: " + m_names[idx]);
    return true;
}

//+------------------------------------------------------------------+
bool ModuleRegistry::IsRegistered(const int module_id) const
{
    return (FindIndex(module_id) >= 0);
}

//+------------------------------------------------------------------+
bool ModuleRegistry::IsInitialized(const int module_id) const
{
    int idx = FindIndex(module_id);
    if(idx < 0) return false;
    return m_initialized[idx];
}

//+------------------------------------------------------------------+
string ModuleRegistry::GetName(const int module_id) const
{
    int idx = FindIndex(module_id);
    if(idx < 0) return "";
    return m_names[idx];
}

//+------------------------------------------------------------------+
string ModuleRegistry::GetVersion(const int module_id) const
{
    int idx = FindIndex(module_id);
    if(idx < 0) return "";
    return m_versions[idx];
}

//+------------------------------------------------------------------+
datetime ModuleRegistry::GetInitTime(const int module_id) const
{
    int idx = FindIndex(module_id);
    if(idx < 0) return 0;
    return m_init_time[idx];
}

//+------------------------------------------------------------------+
bool ModuleRegistry::AllInitialized(void) const
{
    for(int i = 0; i < m_count; i++)
    {
        if(!m_initialized[i])
            return false;
    }
    return (m_count > 0);
}

//+------------------------------------------------------------------+
void ModuleRegistry::Reset(void)
{
    m_count = 0;
    for(int i = 0; i < MAX_MODULES; i++)
    {
        m_ids[i]         = 0;
        m_names[i]       = "";
        m_versions[i]    = "";
        m_initialized[i] = false;
        m_init_time[i]   = 0;
    }
}

//+------------------------------------------------------------------+
void ModuleRegistry::LogStatus(void) const
{
    if(m_logger == NULL) return;

    for(int i = 0; i < m_count; i++)
    {
        string status = m_initialized[i] ? "INITIALIZED" : "PENDING";
        m_logger.Info("ModuleRegistry",
            m_names[i] + " v" + m_versions[i] + " [" + status + "]");
    }
}

#endif // ATLAS_MODULE_REGISTRY_MQH
//+------------------------------------------------------------------+
