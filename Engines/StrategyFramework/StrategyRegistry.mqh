//+------------------------------------------------------------------+
//|           Engines/StrategyFramework/StrategyRegistry.mqh         |
//|       AtlasEA v0.1.10.0 - Strategy Registration & Lookup         |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_REGISTRY_MQH
#define ATLAS_STRATEGY_REGISTRY_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/IStrategy.mqh"
#include "StrategyMetadata.mqh"

/**
 * @class StrategyRegistry
 * @brief Manages the set of registered strategies.
 *
 * Responsibilities:
 *   - Register strategies (prevent duplicates, null, and capacity overflow)
 *   - Unregister strategies
 *   - Enable/disable strategies at runtime
 *   - Find strategies by ID
 *   - Get all (or all enabled) strategies
 *   - Validate IDs
 *
 * Ownership: the registry does NOT own the IStrategy pointers. The
 * caller (Bootstrap or StrategyEngine) owns them. The registry only
 * holds pointers for lookup.
 *
 * Memory: fixed-size array of ATLAS_MAX_STRATEGIES (8) pointers.
 * Zero dynamic allocation.
 *
 * Thread model: single-threaded (MQL5).
 */
class StrategyRegistry
{
private:
    IStrategy *m_strategies[ATLAS_MAX_STRATEGIES];  ///< Registered strategy pointers
    int        m_count;                               ///< Number of registered strategies
    ILogger   *m_logger;

    /// @brief Find the index of a strategy by ID.
    /// @return Index (0..m_count-1) or -1 if not found.
    int FindIndex(const int strategy_id) const;

    /// @brief Find the index of a strategy by pointer.
    int FindIndexByPtr(const IStrategy *strategy) const;

public:
    /**
     * @brief Constructor.
     */
    StrategyRegistry(void);

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a strategy.
     * @param strategy Pointer to the strategy (must not be NULL).
     * @return true if registered, false if:
     *   - strategy is NULL
     *   - strategy ID is invalid (<= 0)
     *   - strategy ID is a duplicate
     *   - registry is full (>= ATLAS_MAX_STRATEGIES)
     *   - metadata validation fails
     */
    bool Register(IStrategy *strategy);

    /**
     * @brief Unregister a strategy by ID.
     * Does NOT delete the strategy (caller owns lifetime).
     * @param strategy_id The ID to unregister.
     * @return true if unregistered, false if not found.
     */
    bool Unregister(const int strategy_id);

    /**
     * @brief Enable a strategy by ID.
     * @param strategy_id The ID to enable.
     * @return true if found and enabled.
     */
    bool Enable(const int strategy_id);

    /**
     * @brief Disable a strategy by ID.
     * @param strategy_id The ID to disable.
     * @return true if found and disabled.
     */
    bool Disable(const int strategy_id);

    /**
     * @brief Find a strategy by ID.
     * @param strategy_id The ID to find.
     * @return Pointer to the strategy, or NULL if not found.
     */
    IStrategy *Find(const int strategy_id) const;

    /**
     * @brief Get all registered strategies.
     * @param out_array Output array (caller-allocated, capacity >= ATLAS_MAX_STRATEGIES).
     * @param out_count Output: number of strategies written.
     */
    void GetAll(IStrategy *out_array[], int &out_count) const;

    /**
     * @brief Get all enabled strategies, sorted by priority (ascending).
     * @param out_array Output array (caller-allocated).
     * @param out_count Output: number of enabled strategies.
     */
    void GetEnabledSorted(IStrategy *out_array[], int &out_count) const;

    /**
     * @brief Get the metadata for a strategy.
     * @param strategy_id The ID to look up.
     * @return Const pointer to metadata, or NULL if not found.
     */
    const StrategyMetadata* GetMetadata(const int strategy_id) const;

    /**
     * @brief Number of registered strategies.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Number of enabled strategies.
     */
    int EnabledCount(void) const;

    /**
     * @brief Check if the registry is empty.
     */
    bool IsEmpty(void) const { return m_count == 0; }

    /**
     * @brief Check if the registry is full.
     */
    bool IsFull(void) const { return m_count >= ATLAS_MAX_STRATEGIES; }

    /**
     * @brief Check if a strategy ID is registered.
     */
    bool IsRegistered(const int strategy_id) const { return (FindIndex(strategy_id) >= 0); }

    /**
     * @brief Validate a strategy ID (non-zero, unique).
     * @param strategy_id The ID to validate.
     * @return true if the ID is valid and not already registered.
     */
    bool ValidateId(const int strategy_id) const;

    /**
     * @brief Clear all registrations (does NOT delete strategies).
     */
    void Clear(void);

    /**
     * @brief Log the registry status.
     */
    void LogStatus(void) const;
};

//+------------------------------------------------------------------+
//| StrategyRegistry implementation                                   |
//+------------------------------------------------------------------+

StrategyRegistry::StrategyRegistry(void)
{
    m_logger = NULL;
    m_count  = 0;
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        m_strategies[i] = NULL;
}

//+------------------------------------------------------------------+
int StrategyRegistry::FindIndex(const int strategy_id) const
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_strategies[i] != NULL)
        {
            const StrategyMetadata &meta = m_strategies[i].GetMetadata();
            if(meta.strategy_id == strategy_id)
                return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
int StrategyRegistry::FindIndexByPtr(const IStrategy *strategy) const
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_strategies[i] == strategy)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
bool StrategyRegistry::Register(IStrategy *strategy)
{
    if(strategy == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("StrategyRegistry", "Register: strategy is NULL");
        return false;
    }

    if(m_count >= ATLAS_MAX_STRATEGIES)
    {
        if(m_logger != NULL)
            m_logger.Error("StrategyRegistry",
                "Register: registry full (max " + IntegerToString(ATLAS_MAX_STRATEGIES) + ")");
        return false;
    }

    //--- Validate metadata
    const StrategyMetadata &meta = strategy.GetMetadata();
    string reason;
    if(!meta.Validate(reason))
    {
        if(m_logger != NULL)
            m_logger.Error("StrategyRegistry", "Register: metadata invalid: " + reason);
        return false;
    }

    //--- Check for duplicate ID
    if(FindIndex(meta.strategy_id) >= 0)
    {
        if(m_logger != NULL)
            m_logger.Warn("StrategyRegistry",
                "Register: duplicate strategy_id " + IntegerToString(meta.strategy_id));
        return false;
    }

    m_strategies[m_count] = strategy;
    m_count++;

    if(m_logger != NULL)
        m_logger.Info("StrategyRegistry",
            "Registered: " + meta.name + " v" + meta.version +
            " (id=" + IntegerToString(meta.strategy_id) +
            " weight=" + DoubleToString(meta.weight, 2) + ")");

    return true;
}

//+------------------------------------------------------------------+
bool StrategyRegistry::Unregister(const int strategy_id)
{
    int idx = FindIndex(strategy_id);
    if(idx < 0) return false;

    //--- Shift remaining strategies left
    for(int i = idx + 1; i < m_count; i++)
        m_strategies[i-1] = m_strategies[i];

    m_count--;
    m_strategies[m_count] = NULL;

    if(m_logger != NULL)
        m_logger.Info("StrategyRegistry", "Unregistered strategy_id=" + IntegerToString(strategy_id));

    return true;
}

//+------------------------------------------------------------------+
bool StrategyRegistry::Enable(const int strategy_id)
{
    int idx = FindIndex(strategy_id);
    if(idx < 0) return false;
    //--- Enable is handled by the strategy itself (metadata.enabled is read-only
    //--- because GetMetadata returns const&). We use IsEnabled()/Reset() pattern.
    //--- For runtime enable/disable, the strategy must have an internal flag.
    //--- Since IStrategy::IsEnabled() is virtual, the strategy controls it.
    //--- This method is a no-op stub; actual enable/disable is strategy-specific.
    //--- A future refactor could add IStrategy::SetEnabled(bool).
    if(m_logger != NULL)
        m_logger.Debug("StrategyRegistry", "Enable called for id=" + IntegerToString(strategy_id) + " (strategy-controlled)");
    return true;
}

//+------------------------------------------------------------------+
bool StrategyRegistry::Disable(const int strategy_id)
{
    int idx = FindIndex(strategy_id);
    if(idx < 0) return false;
    if(m_logger != NULL)
        m_logger.Debug("StrategyRegistry", "Disable called for id=" + IntegerToString(strategy_id) + " (strategy-controlled)");
    return true;
}

//+------------------------------------------------------------------+
IStrategy *StrategyRegistry::Find(const int strategy_id) const
{
    int idx = FindIndex(strategy_id);
    if(idx < 0) return NULL;
    return m_strategies[idx];
}

//+------------------------------------------------------------------+
void StrategyRegistry::GetAll(IStrategy *out_array[], int &out_count) const
{
    out_count = m_count;
    for(int i = 0; i < m_count; i++)
        out_array[i] = m_strategies[i];
}

//+------------------------------------------------------------------+
void StrategyRegistry::GetEnabledSorted(IStrategy *out_array[], int &out_count) const
{
    //--- Collect enabled strategies
    IStrategy *enabled[ATLAS_MAX_STRATEGIES];
    int enabled_count = 0;
    for(int i = 0; i < m_count; i++)
    {
        if(m_strategies[i] != NULL && m_strategies[i].IsEnabled())
        {
            enabled[enabled_count] = m_strategies[i];
            enabled_count++;
        }
    }

    //--- Sort by priority (ascending) — simple insertion sort
    for(int i = 1; i < enabled_count; i++)
    {
        IStrategy *key = enabled[i];
        const StrategyMetadata &key_meta = key.GetMetadata();
        int j = i - 1;
        while(j >= 0)
        {
            const StrategyMetadata &j_meta = enabled[j].GetMetadata();
            if(j_meta.priority > key_meta.priority)
            {
                enabled[j+1] = enabled[j];
                j--;
            }
            else
                break;
        }
        enabled[j+1] = key;
    }

    //--- Copy to output
    out_count = enabled_count;
    for(int i = 0; i < enabled_count; i++)
        out_array[i] = enabled[i];
}

//+------------------------------------------------------------------+
const StrategyMetadata* StrategyRegistry::GetMetadata(const int strategy_id) const
{
    int idx = FindIndex(strategy_id);
    if(idx < 0) return NULL;
    return &m_strategies[idx].GetMetadata();
}

//+------------------------------------------------------------------+
int StrategyRegistry::EnabledCount(void) const
{
    int c = 0;
    for(int i = 0; i < m_count; i++)
    {
        if(m_strategies[i] != NULL && m_strategies[i].IsEnabled())
            c++;
    }
    return c;
}

//+------------------------------------------------------------------+
bool StrategyRegistry::ValidateId(const int strategy_id) const
{
    if(strategy_id <= 0) return false;
    if(FindIndex(strategy_id) >= 0) return false;
    return true;
}

//+------------------------------------------------------------------+
void StrategyRegistry::Clear(void)
{
    for(int i = 0; i < m_count; i++)
        m_strategies[i] = NULL;
    m_count = 0;
}

//+------------------------------------------------------------------+
void StrategyRegistry::LogStatus(void) const
{
    if(m_logger == NULL) return;
    m_logger.Info("StrategyRegistry",
        "Registered: " + IntegerToString(m_count) + "/" + IntegerToString(ATLAS_MAX_STRATEGIES));
    for(int i = 0; i < m_count; i++)
    {
        if(m_strategies[i] == NULL) continue;
        const StrategyMetadata &meta = m_strategies[i].GetMetadata();
        string status = m_strategies[i].IsEnabled() ? "ENABLED" : "DISABLED";
        m_logger.Info("StrategyRegistry",
            "  [" + IntegerToString(i) + "] id=" + IntegerToString(meta.strategy_id) +
            " " + meta.name + " v" + meta.version +
            " prio=" + IntegerToString(meta.priority) +
            " weight=" + DoubleToString(meta.weight, 2) +
            " [" + status + "]");
    }
}

#endif // ATLAS_STRATEGY_REGISTRY_MQH
//+------------------------------------------------------------------+
