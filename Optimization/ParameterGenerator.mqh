//+------------------------------------------------------------------+
//|                   Optimization/ParameterGenerator.mqh            |
//|       AtlasEA v1.0 Step 6 - Parameter Set Generator              |
//+------------------------------------------------------------------+
#ifndef ATLAS_PARAMETER_GENERATOR_MQH
#define ATLAS_PARAMETER_GENERATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IOptimizationManager.mqh"
#include "ParameterSpace.mqh"

/**
 * @class ParameterGenerator
 * @brief Generates parameter sets for optimization.
 *
 * SOLE RESPONSIBILITY: generate parameter sets based on the search mode.
 * Does NOT validate or evaluate them.
 *
 * Search modes:
 *   - GRID: exhaustive enumeration of all combinations (step-based)
 *   - RANDOM: deterministic random sampling (LCG with configurable seed)
 *   - MANUAL: caller provides explicit parameter sets
 *
 * Determinism: RANDOM mode uses a configurable seed. Same seed → same
 * parameter sets, always.
 *
 * Performance: O(P) per set generated. No allocation.
 */
class ParameterGenerator
{
private:
    ILogger *m_logger;
    ulong    m_rng_state;

    /**
     * @brief Seed the RNG (LCG).
     */
    void SeedRNG(const ulong seed) { m_rng_state = seed; }

    /**
     * @brief Generate a deterministic random double [0, 1).
     */
    double Random(void)
    {
        m_rng_state = (m_rng_state * 1103515245 + 12345) & 0x7FFFFFFF;
        return (double)m_rng_state / (double)0x7FFFFFFF;
    }

    /**
     * @brief Generate a random value in [min, max] aligned to step.
     */
    double RandomInRange(const double min_val, const double max_val, const double step)
    {
        if(step <= 0.0) return min_val;
        double range = max_val - min_val;
        long steps = (long)(range / step) + 1;
        long rand_step = (long)(Random() * (double)steps);
        if(rand_step >= steps) rand_step = steps - 1;
        return min_val + (double)rand_step * step;
    }

public:
    ParameterGenerator(void) { m_logger = NULL; m_rng_state = 0; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Generate parameter sets using grid search.
     *
     * Enumerates all combinations of enabled parameters, stepping from
     * min to max by step. The caller provides an array to fill.
     *
     * @param space The parameter space.
     * @param sets Output array of parameter sets.
     * @param max_sets Maximum sets to generate.
     * @return Number of sets generated.
     */
    int GenerateGrid(const ParameterSpace &space, ParameterSet &sets[],
                     const int max_sets)
    {
        int count = 0;
        int enabled_indices[ATLAS_OPT_MAX_PARAMS];
        int enabled_count = 0;

        //--- Collect enabled parameter indices
        for(int i = 0; i < space.Count(); i++)
        {
            if(space.Get(i).enabled)
            {
                enabled_indices[enabled_count] = i;
                enabled_count++;
            }
        }

        if(enabled_count == 0) return 0;

        //--- Initialize current values to minimums
        double current[ATLAS_OPT_MAX_PARAMS];
        for(int i = 0; i < enabled_count; i++)
            current[i] = space.Get(enabled_indices[i]).min_val;

        //--- Enumerate all combinations
        while(count < max_sets)
        {
            //--- Build parameter set from current values
            ParameterSet set;
            set.set_index = count;

            //--- Fill enabled parameters
            for(int i = 0; i < enabled_count; i++)
            {
                set.values[i].name  = space.Get(enabled_indices[i]).name;
                set.values[i].value = current[i];
            }

            //--- Fill disabled parameters with defaults
            int idx = enabled_count;
            for(int i = 0; i < space.Count(); i++)
            {
                bool is_enabled = false;
                for(int j = 0; j < enabled_count; j++)
                    if(enabled_indices[j] == i) { is_enabled = true; break; }
                if(!is_enabled)
                {
                    set.values[idx].name  = space.Get(i).name;
                    set.values[idx].value = space.Get(i).default_val;
                    idx++;
                }
            }
            set.count = space.Count();
            sets[count] = set;
            count++;

            //--- Increment the rightmost parameter, carry on overflow
            int pos = enabled_count - 1;
            while(pos >= 0)
            {
                const ParameterDef &def = space.Get(enabled_indices[pos]);
                current[pos] += def.step;
                if(current[pos] <= def.max_val + 0.0001) break;

                //--- Overflow: reset and carry
                current[pos] = def.min_val;
                pos--;
            }
            if(pos < 0) break; // All combinations exhausted
        }

        if(m_logger != NULL)
            m_logger.Info("ParameterGenerator",
                "Grid search generated " + IntegerToString(count) + " sets");
        return count;
    }

    /**
     * @brief Generate parameter sets using random search.
     *
     * @param space The parameter space.
     * @param sets Output array of parameter sets.
     * @param max_sets Maximum sets to generate.
     * @param seed Deterministic random seed.
     * @return Number of sets generated.
     */
    int GenerateRandom(const ParameterSpace &space, ParameterSet &sets[],
                       const int max_sets, const ulong seed)
    {
        SeedRNG(seed);
        int count = 0;

        while(count < max_sets)
        {
            ParameterSet set;
            set.set_index = count;

            for(int i = 0; i < space.Count(); i++)
            {
                const ParameterDef &def = space.Get(i);
                set.values[i].name = def.name;

                if(def.enabled)
                    set.values[i].value = RandomInRange(def.min_val, def.max_val, def.step);
                else
                    set.values[i].value = def.default_val;
            }
            set.count = space.Count();
            sets[count] = set;
            count++;
        }

        if(m_logger != NULL)
            m_logger.Info("ParameterGenerator",
                "Random search generated " + IntegerToString(count) +
                " sets (seed=" + IntegerToString((long)seed) + ")");
        return count;
    }

    /**
     * @brief Generate a single manual parameter set from name-value pairs.
     *
     * @param space The parameter space (for defaults).
     * @param names Array of parameter names.
     * @param values Array of parameter values.
     * @param count Number of parameters.
     * @return A ParameterSet with specified values + defaults for unspecified.
     */
    ParameterSet GenerateManual(const ParameterSpace &space,
                                 const string &names[], const double &values[],
                                 const int count)
    {
        ParameterSet set = space.CreateDefaultSet();
        set.set_index = 0;

        for(int i = 0; i < count; i++)
        {
            for(int j = 0; j < set.count; j++)
            {
                if(set.values[j].name == names[i])
                {
                    set.values[j].value = values[i];
                    break;
                }
            }
        }

        return set;
    }
};

#endif // ATLAS_PARAMETER_GENERATOR_MQH
//+------------------------------------------------------------------+
