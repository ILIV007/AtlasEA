//+------------------------------------------------------------------+
//|             StrategySDK/StrategyParameters.mqh                 |
//|       AtlasEA v0.1.17.0 - Strategy Parameter Helper             |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_PARAMETERS_MQH
#define ATLAS_STRATEGY_PARAMETERS_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Maximum parameters per strategy.
 */
#define ATLAS_MAX_PARAMS 16

/**
 * @struct StrategyParam
 * @brief One strategy parameter (key-value pair).
 */
struct StrategyParam
{
    string key;
    string value;
    bool   is_set;
};

/**
 * @class StrategyParameters
 * @brief Container for strategy parameters.
 *
 * Fixed-size array of 16 key-value pairs. No dynamic allocation.
 * Strategies use this to read their configuration.
 */
class StrategyParameters
{
private:
    StrategyParam m_params[ATLAS_MAX_PARAMS];
    int           m_count;

public:
    /**
     * @brief Constructor.
     */
    StrategyParameters(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_MAX_PARAMS; i++)
            m_params[i].is_set = false;
    }

    /**
     * @brief Set a parameter.
     */
    void Set(const string key, const string value)
    {
        //--- Check if key already exists
        for(int i = 0; i < m_count; i++)
        {
            if(m_params[i].key == key)
            {
                m_params[i].value  = value;
                m_params[i].is_set = true;
                return;
            }
        }

        //--- Add new
        if(m_count < ATLAS_MAX_PARAMS)
        {
            m_params[m_count].key    = key;
            m_params[m_count].value  = value;
            m_params[m_count].is_set = true;
            m_count++;
        }
    }

    /**
     * @brief Set a parameter as double.
     */
    void SetDouble(const string key, const double value)
    {
        Set(key, DoubleToString(value, 8));
    }

    /**
     * @brief Set a parameter as int.
     */
    void SetInt(const string key, const int value)
    {
        Set(key, IntegerToString(value));
    }

    /**
     * @brief Set a parameter as bool.
     */
    void SetBool(const string key, const bool value)
    {
        Set(key, value ? "true" : "false");
    }

    /**
     * @brief Get a parameter as string.
     * @return The value, or default_val if not found.
     */
    string Get(const string key, const string default_val = "") const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_params[i].key == key && m_params[i].is_set)
                return m_params[i].value;
        }
        return default_val;
    }

    /**
     * @brief Get a parameter as double.
     */
    double GetDouble(const string key, const double default_val = 0.0) const
    {
        string val = Get(key, "");
        if(val == "") return default_val;
        return StringToDouble(val);
    }

    /**
     * @brief Get a parameter as int.
     */
    int GetInt(const string key, const int default_val = 0) const
    {
        string val = Get(key, "");
        if(val == "") return default_val;
        return (int)StringToInteger(val);
    }

    /**
     * @brief Get a parameter as bool.
     */
    bool GetBool(const string key, const bool default_val = false) const
    {
        string val = Get(key, "");
        if(val == "") return default_val;
        return (val == "true" || val == "1");
    }

    /**
     * @brief Check if a parameter is set.
     */
    bool Has(const string key) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_params[i].key == key && m_params[i].is_set)
                return true;
        }
        return false;
    }

    /**
     * @brief Number of parameters.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Clear all parameters.
     */
    void Clear(void)
    {
        m_count = 0;
        for(int i = 0; i < ATLAS_MAX_PARAMS; i++)
            m_params[i].is_set = false;
    }
};

#endif // ATLAS_STRATEGY_PARAMETERS_MQH
//+------------------------------------------------------------------+
