//+------------------------------------------------------------------+
//|                  Strategy/StrategyRegistry.mqh                  |
//|       AtlasEA v0.1.20.0 - Strategy Registration & Lookup        |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_REGISTRY_V2_MQH
#define ATLAS_STRATEGY_REGISTRY_V2_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class StrategyRegistry
 * @brief Manages registered strategy instances.
 *
 * Responsibilities:
 *   - Register/unregister strategies
 *   - Enable/disable at runtime
 *   - Find by ID or name
 *   - Priority-sorted retrieval
 *   - Duplicate detection
 *
 * Fixed-size array of ATLAS_MAX_STRATEGIES (8). No dynamic allocation.
 */
class StrategyRegistry
{
private:
    IStrategy *m_strategies[ATLAS_MAX_STRATEGIES];
    int        m_count;
    ILogger   *m_logger;

    int FindIndexById(const int id) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] != NULL && m_strategies[i].GetId() == id)
                return i;
        }
        return -1;
    }

    int FindIndexByName(const string name) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] != NULL && m_strategies[i].Name() == name)
                return i;
        }
        return -1;
    }

    int FindIndexByPtr(const IStrategy *strategy) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] == strategy)
                return i;
        }
        return -1;
    }

public:
    /**
     * @brief Constructor.
     */
    StrategyRegistry(void)
    {
        m_logger = NULL;
        m_count  = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
            m_strategies[i] = NULL;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a strategy.
     * @param strategy Pointer to the strategy (caller owns lifetime).
     * @param id Unique strategy ID (> 0, assigned by caller).
     * @return true if registered, false on duplicate/full/NULL.
     */
    bool Register(IStrategy *strategy, const int id)
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
                    "Register: full (max " + IntegerToString(ATLAS_MAX_STRATEGIES) + ")");
            return false;
        }

        if(id <= 0)
        {
            if(m_logger != NULL)
                m_logger.Error("StrategyRegistry", "Register: ID must be > 0");
            return false;
        }

        if(FindIndexById(id) >= 0)
        {
            if(m_logger != NULL)
                m_logger.Warn("StrategyRegistry",
                    "Register: duplicate ID " + IntegerToString(id));
            return false;
        }

        //--- Set the ID on the strategy (BaseStrategy has SetId)
        //--- We cast to BaseStrategy* to access SetId. This is safe because
        //--- all strategies must inherit BaseStrategy.
        //--- For strategies that don't inherit BaseStrategy, they must
        //--- handle ID internally.
        strategy.SetId(id);

        m_strategies[m_count] = strategy;
        m_count++;

        if(m_logger != NULL)
            m_logger.Info("StrategyRegistry",
                "Registered: " + strategy.Name() + " v" + strategy.Version() +
                " (id=" + IntegerToString(id) +
                " prio=" + IntegerToString(strategy.Priority()) +
                " weight=" + DoubleToString(strategy.Weight(), 2) + ")");

        return true;
    }

    /**
     * @brief Unregister a strategy by ID.
     * Does NOT delete the strategy (caller owns lifetime).
     */
    bool Unregister(const int id)
    {
        int idx = FindIndexById(id);
        if(idx < 0) return false;

        for(int i = idx + 1; i < m_count; i++)
            m_strategies[i-1] = m_strategies[i];

        m_count--;
        m_strategies[m_count] = NULL;

        if(m_logger != NULL)
            m_logger.Info("StrategyRegistry", "Unregistered ID=" + IntegerToString(id));
        return true;
    }

    /**
     * @brief Find a strategy by ID.
     */
    IStrategy *FindById(const int id) const
    {
        int idx = FindIndexById(id);
        if(idx < 0) return NULL;
        return m_strategies[idx];
    }

    /**
     * @brief Find a strategy by name.
     */
    IStrategy *FindByName(const string name) const
    {
        int idx = FindIndexByName(name);
        if(idx < 0) return NULL;
        return m_strategies[idx];
    }

    /**
     * @brief Enable a strategy by ID.
     */
    bool Enable(const int id)
    {
        IStrategy *s = FindById(id);
        if(s == NULL) return false;
        s.SetEnabled(true);
        return true;
    }

    /**
     * @brief Disable a strategy by ID.
     */
    bool Disable(const int id)
    {
        IStrategy *s = FindById(id);
        if(s == NULL) return false;
        s.SetEnabled(false);
        return true;
    }

    /**
     * @brief Get all enabled strategies, sorted by priority (ascending).
     * @param out_array Caller-allocated array (capacity >= ATLAS_MAX_STRATEGIES).
     * @param out_count Output: number of enabled strategies.
     */
    void GetEnabledSorted(IStrategy *out_array[], int &out_count) const
    {
        //--- Collect enabled
        IStrategy *enabled[ATLAS_MAX_STRATEGIES];
        int enabled_count = 0;

        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] != NULL && m_strategies[i].Enabled())
            {
                enabled[enabled_count] = m_strategies[i];
                enabled_count++;
            }
        }

        //--- Insertion sort by priority (ascending = highest priority first)
        for(int i = 1; i < enabled_count; i++)
        {
            IStrategy *key = enabled[i];
            int key_prio = key.Priority();
            int j = i - 1;
            while(j >= 0 && enabled[j].Priority() > key_prio)
            {
                enabled[j+1] = enabled[j];
                j--;
            }
            enabled[j+1] = key;
        }

        out_count = enabled_count;
        for(int i = 0; i < enabled_count; i++)
            out_array[i] = enabled[i];
    }

    /**
     * @brief Get all registered strategies (unsorted).
     */
    void GetAll(IStrategy *out_array[], int &out_count) const
    {
        out_count = m_count;
        for(int i = 0; i < m_count; i++)
            out_array[i] = m_strategies[i];
    }

    int Count(void) const { return m_count; }

    int EnabledCount(void) const
    {
        int c = 0;
        for(int i = 0; i < m_count; i++)
            if(m_strategies[i] != NULL && m_strategies[i].Enabled()) c++;
        return c;
    }

    bool IsRegistered(const int id) const { return (FindIndexById(id) >= 0); }

    void Clear(void)
    {
        for(int i = 0; i < m_count; i++)
            m_strategies[i] = NULL;
        m_count = 0;
    }
};

#endif // ATLAS_STRATEGY_REGISTRY_V2_MQH
//+------------------------------------------------------------------+
