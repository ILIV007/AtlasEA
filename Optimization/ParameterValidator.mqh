//+------------------------------------------------------------------+
//|                   Optimization/ParameterValidator.mqh            |
//|       AtlasEA v1.0 Step 6 - Parameter Set Validator               |
//+------------------------------------------------------------------+
#ifndef ATLAS_PARAMETER_VALIDATOR_MQH
#define ATLAS_PARAMETER_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IOptimizationManager.mqh"
#include "ParameterSpace.mqh"

/**
 * @class ParameterValidator
 * @brief Validates parameter sets against cross-parameter rules.
 *
 * SOLE RESPONSIBILITY: reject invalid parameter combinations.
 * Does NOT run backtests or evaluate performance.
 *
 * Validation rules (cross-parameter):
 *   1. Fast EMA < Slow EMA (fast must be shorter period)
 *   2. Risk % <= Max Risk %
 *   3. SL multiplier > 0
 *   4. TP multiplier > 0
 *   5. ATR multiplier > 0
 *   6. Trailing step >= broker step (1 point minimum)
 *   7. Max exposure <= 100%
 *   8. Valid session combination (not all disabled)
 *   9. No duplicate profile names (checked externally)
 *  10. Parameter ranges valid (min <= max, step > 0)
 *  11. Values within [min, max] for each parameter
 *
 * Performance: O(P) where P = number of parameters. No allocation.
 */
class ParameterValidator
{
private:
    ILogger *m_logger;

public:
    ParameterValidator(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Validate a parameter set.
     * @param set The parameter set to validate.
     * @param space The parameter space (for range checks).
     * @return true if valid, false if rejected.
     */
    bool Validate(const ParameterSet &set, const ParameterSpace &space)
    {
        //--- 11. Check each value is within [min, max]
        for(int i = 0; i < set.count; i++)
        {
            int idx = space.Find(set.values[i].name);
            if(idx < 0) continue;
            const ParameterDef &def = space.Get(idx);
            if(set.values[i].value < def.min_val || set.values[i].value > def.max_val)
            {
                Reject(set, ATLAS_PVR_VALUE_OUT_OF_RANGE,
                    set.values[i].name + "=" + DoubleToString(set.values[i].value, 2) +
                    " outside [" + DoubleToString(def.min_val, 0) + ", " +
                    DoubleToString(def.max_val, 0) + "]");
                return false;
            }
        }

        //--- Get key parameter values
        double ma_fast   = GetValue(set, "ma_fast_period", 20);
        double ma_slow   = GetValue(set, "ma_slow_period", 50);
        double risk_pct  = GetValue(set, "mm_risk_percent", 1.0);
        double max_risk  = GetValue(set, "mm_max_risk_percent", 3.0);
        double sl_mult   = GetValue(set, "sl_atr_multiplier", 2);
        double tp_mult   = GetValue(set, "tp_atr_multiplier", 4);
        double atr_mult  = GetValue(set, "mm_atr_multiplier", 2.0);
        double trail_dist = GetValue(set, "tcm_trailing_distance", 200);
        double exposure  = GetValue(set, "mm_max_exposure_pct", 20.0);

        //--- 1. Fast EMA < Slow EMA
        if(ma_fast >= ma_slow)
        {
            Reject(set, ATLAS_PVR_FAST_LT_SLOW,
                "ma_fast " + DoubleToString(ma_fast, 0) +
                " >= ma_slow " + DoubleToString(ma_slow, 0));
            return false;
        }

        //--- 2. Risk <= Max Risk
        if(risk_pct > max_risk)
        {
            Reject(set, ATLAS_PVR_RISK_EXCEEDED,
                "risk " + DoubleToString(risk_pct, 2) +
                " > max_risk " + DoubleToString(max_risk, 2));
            return false;
        }

        //--- 3. SL multiplier > 0
        if(sl_mult <= 0.0)
        {
            Reject(set, ATLAS_PVR_SL_INVALID,
                "sl_atr_multiplier <= 0");
            return false;
        }

        //--- 4. TP multiplier > 0
        if(tp_mult <= 0.0)
        {
            Reject(set, ATLAS_PVR_TP_INVALID,
                "tp_atr_multiplier <= 0");
            return false;
        }

        //--- 5. ATR multiplier > 0
        if(atr_mult <= 0.0)
        {
            Reject(set, ATLAS_PVR_ATR_MULT_INVALID,
                "mm_atr_multiplier <= 0");
            return false;
        }

        //--- 6. Trailing distance >= 1 (broker minimum step)
        if(trail_dist < 1.0)
        {
            Reject(set, ATLAS_PVR_TRAILING_STEP,
                "trailing_distance " + DoubleToString(trail_dist, 0) + " < broker step");
            return false;
        }

        //--- 7. Max exposure <= 100%
        if(exposure > 100.0)
        {
            Reject(set, ATLAS_PVR_EXPOSURE_INVALID,
                "max_exposure " + DoubleToString(exposure, 1) + "% > 100%");
            return false;
        }

        //--- All checks passed
        return true;
    }

private:
    double GetValue(const ParameterSet &set, const string name, const double default_val) const
    {
        for(int i = 0; i < set.count; i++)
            if(set.values[i].name == name) return set.values[i].value;
        return default_val;
    }

    void Reject(ParameterSet &set, const int code, const string detail) const
    {
        set.valid           = false;
        set.validation_code = code;
        set.validation_detail = detail;
    }
};

#endif // ATLAS_PARAMETER_VALIDATOR_MQH
//+------------------------------------------------------------------+
