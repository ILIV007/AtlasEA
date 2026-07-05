//+------------------------------------------------------------------+
//|                    Optimization/ParameterSpace.mqh               |
//|       AtlasEA v1.0 Step 6 - Parameter Space Definition            |
//+------------------------------------------------------------------+
#ifndef ATLAS_PARAMETER_SPACE_MQH
#define ATLAS_PARAMETER_SPACE_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IOptimizationManager.mqh"

/**
 * @class ParameterSpace
 * @brief Defines the space of optimizable parameters.
 *
 * SOLE RESPONSIBILITY: hold parameter definitions and provide
 * access to them. Does NOT validate or generate parameter sets.
 *
 * Each parameter has:
 *   - name (string identifier, maps to AtlasConfig field)
 *   - type (INT, DOUBLE, BOOL, ENUM)
 *   - min, max, default, step
 *   - enabled flag (whether to optimize this parameter)
 *
 * Memory: ~1 KB (32 ParameterDef × ~32 bytes each).
 */
class ParameterSpace
{
private:
    ParameterDef m_params[ATLAS_OPT_MAX_PARAMS];
    int          m_count;

public:
    ParameterSpace(void) { m_count = 0; }

    /**
     * @brief Add a parameter definition.
     * @return true if added, false if space full.
     */
    bool Add(const string name, const int type,
             const double min_val, const double max_val,
             const double default_val, const double step,
             const bool enabled = true)
    {
        if(m_count >= ATLAS_OPT_MAX_PARAMS) return false;
        //--- Check for duplicate name
        for(int i = 0; i < m_count; i++)
            if(m_params[i].name == name) return false;

        ParameterDef &p = m_params[m_count];
        p.name        = name;
        p.type        = type;
        p.min_val     = min_val;
        p.max_val     = max_val;
        p.default_val = default_val;
        p.step        = step;
        p.enabled     = enabled;
        p.enum_count  = 0;
        m_count++;
        return true;
    }

    /**
     * @brief Get a parameter definition by index.
     */
    const ParameterDef& Get(const int index) const
    {
        if(index < 0 || index >= m_count)
        {
            static ParameterDef empty;
            return empty;
        }
        return m_params[index];
    }

    /**
     * @brief Find a parameter by name.
     * @return Index, or -1 if not found.
     */
    int Find(const string name) const
    {
        for(int i = 0; i < m_count; i++)
            if(m_params[i].name == name) return i;
        return -1;
    }

    /**
     * @brief Get the number of parameters.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Get the number of ENABLED parameters.
     */
    int EnabledCount(void) const
    {
        int n = 0;
        for(int i = 0; i < m_count; i++)
            if(m_params[i].enabled) n++;
        return n;
    }

    /**
     * @brief Calculate the total number of grid combinations.
     * Only counts enabled parameters.
     * @return Total combinations, or -1 if infinite (step <= 0).
     */
    long GridSize(void) const
    {
        long total = 1;
        for(int i = 0; i < m_count; i++)
        {
            if(!m_params[i].enabled) continue;
            if(m_params[i].step <= 0.0) return -1;
            double range = m_params[i].max_val - m_params[i].min_val;
            long steps = (long)(range / m_params[i].step) + 1;
            total *= steps;
            if(total > 1000000) return -1; // Safety cap
        }
        return total;
    }

    /**
     * @brief Set whether a parameter is enabled for optimization.
     */
    bool SetEnabled(const string name, const bool enabled)
    {
        int idx = Find(name);
        if(idx < 0) return false;
        m_params[idx].enabled = enabled;
        return true;
    }

    /**
     * @brief Create the default parameter set (all defaults).
     */
    ParameterSet CreateDefaultSet(void) const
    {
        ParameterSet set;
        for(int i = 0; i < m_count; i++)
        {
            set.values[i].name  = m_params[i].name;
            set.values[i].value = m_params[i].default_val;
        }
        set.count = m_count;
        return set;
    }

    /**
     * @brief Get a parameter value from a set by name.
     * @return Value, or default if not found.
     */
    double GetValue(const ParameterSet &set, const string name) const
    {
        for(int i = 0; i < set.count; i++)
            if(set.values[i].name == name) return set.values[i].value;
        //--- Return default
        int idx = Find(name);
        if(idx >= 0) return m_params[idx].default_val;
        return 0.0;
    }

    /**
     * @brief Apply a parameter set to an AtlasConfig.
     * Maps parameter names to AtlasConfig fields.
     */
    void ApplyToConfig(const ParameterSet &set, AtlasConfig &config) const
    {
        for(int i = 0; i < set.count; i++)
        {
            const string &name = set.values[i].name;
            double val = set.values[i].value;

            //--- Map parameter names to AtlasConfig fields
            if(name == "ma_fast_period")      config.ma_fast_period   = (int)val;
            else if(name == "ma_slow_period") config.ma_slow_period   = (int)val;
            else if(name == "atr_period")     config.atr_period       = (int)val;
            else if(name == "sl_atr_multiplier") config.sl_atr_multiplier = (int)val;
            else if(name == "tp_atr_multiplier") config.tp_atr_multiplier = (int)val;
            else if(name == "mm_risk_percent") config.mm_risk_percent  = val;
            else if(name == "mm_max_risk_percent") config.mm_max_risk_percent = val;
            else if(name == "mm_max_lot")     config.mm_max_lot       = val;
            else if(name == "mm_max_exposure_pct") config.mm_max_exposure_pct = val;
            else if(name == "mm_atr_multiplier") config.mm_atr_multiplier = val;
            else if(name == "tcm_trailing_distance") config.tcm_trailing_distance = val;
            else if(name == "tcm_atr_multiplier") config.tcm_atr_multiplier = val;
            else if(name == "tcm_breakeven_trigger") config.tcm_breakeven_trigger = val;
            else if(name == "tcm_breakeven_offset") config.tcm_breakeven_offset = val;
            else if(name == "max_spread_points") config.max_spread_points = val;
            //--- Additional parameters can be added here
        }
    }

    /**
     * @brief Initialize the parameter space with common AtlasEA parameters.
     */
    void InitializeDefaults(void)
    {
        m_count = 0;
        Add("ma_fast_period",      ATLAS_PARAM_INT,    5,   50,  20,  5);
        Add("ma_slow_period",      ATLAS_PARAM_INT,    20,  200, 50,  10);
        Add("atr_period",          ATLAS_PARAM_INT,    7,   28,  14,  1);
        Add("sl_atr_multiplier",   ATLAS_PARAM_INT,    1,   5,   2,   1);
        Add("tp_atr_multiplier",   ATLAS_PARAM_INT,    1,   8,   4,   1);
        Add("mm_risk_percent",     ATLAS_PARAM_DOUBLE, 0.1, 3.0, 1.0, 0.1);
        Add("mm_max_risk_percent", ATLAS_PARAM_DOUBLE, 1.0, 5.0, 3.0, 0.5);
        Add("mm_atr_multiplier",   ATLAS_PARAM_DOUBLE, 1.0, 4.0, 2.0, 0.5);
        Add("tcm_trailing_distance", ATLAS_PARAM_DOUBLE, 50, 500, 200, 50);
        Add("tcm_atr_multiplier",  ATLAS_PARAM_DOUBLE, 1.0, 4.0, 2.0, 0.5);
        Add("tcm_breakeven_trigger", ATLAS_PARAM_DOUBLE, 50, 400, 150, 25);
        Add("tcm_breakeven_offset",  ATLAS_PARAM_DOUBLE, 5,  100, 20,  5);
        Add("max_spread_points",   ATLAS_PARAM_DOUBLE, 10,  150, 50,  10);
    }
};

#endif // ATLAS_PARAMETER_SPACE_MQH
//+------------------------------------------------------------------+
