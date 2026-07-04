//+------------------------------------------------------------------+
//|                 StrategySDK/StrategyResult.mqh                  |
//|       AtlasEA v0.1.17.0 - Strategy Result Helper                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_RESULT_MQH
#define ATLAS_STRATEGY_RESULT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"

/**
 * @class StrategyResultBuilder
 * @brief Helper for constructing valid StrategyResult objects.
 *
 * Provides static factory methods that produce pre-validated results.
 */
class StrategyResultBuilder
{
public:
    /**
     * @brief Build a BUY result.
     */
    static StrategyResult Buy(const int plugin_id, const long snapshot_id,
                               const double confidence,
                               const double entry, const double sl, const double tp,
                               const double volume = 0.0)
    {
        StrategyResult r;
        r.plugin_id        = plugin_id;
        r.direction        = ATLAS_ORDER_BUY;
        r.confidence       = Clamp(confidence, 0.0, 1.0);
        r.suggested_entry  = entry;
        r.suggested_sl     = sl;
        r.suggested_tp     = tp;
        r.suggested_volume = volume;
        r.snapshot_id      = snapshot_id;
        r.result_time      = TimeCurrent();
        r.valid            = true;
        return r;
    }

    /**
     * @brief Build a SELL result.
     */
    static StrategyResult Sell(const int plugin_id, const long snapshot_id,
                                const double confidence,
                                const double entry, const double sl, const double tp,
                                const double volume = 0.0)
    {
        StrategyResult r;
        r.plugin_id        = plugin_id;
        r.direction        = ATLAS_ORDER_SELL;
        r.confidence       = Clamp(confidence, 0.0, 1.0);
        r.suggested_entry  = entry;
        r.suggested_sl     = sl;
        r.suggested_tp     = tp;
        r.suggested_volume = volume;
        r.snapshot_id      = snapshot_id;
        r.result_time      = TimeCurrent();
        r.valid            = true;
        return r;
    }

    /**
     * @brief Build an abstention (no signal).
     */
    static StrategyResult Abstain(const int plugin_id, const long snapshot_id)
    {
        StrategyResult r;
        r.plugin_id   = plugin_id;
        r.direction   = ATLAS_ORDER_NONE;
        r.confidence  = 0.0;
        r.snapshot_id = snapshot_id;
        r.result_time = TimeCurrent();
        r.valid       = true;
        return r;
    }

    /**
     * @brief Build an error result (strategy failed).
     */
    static StrategyResult Error(const int plugin_id, const long snapshot_id)
    {
        StrategyResult r;
        r.plugin_id   = plugin_id;
        r.direction   = ATLAS_ORDER_NONE;
        r.confidence  = 0.0;
        r.snapshot_id = snapshot_id;
        r.result_time = TimeCurrent();
        r.valid       = false;
        return r;
    }

private:
    static double Clamp(const double v, const double lo, const double hi)
    {
        if(v < lo) return lo;
        if(v > hi) return hi;
        return v;
    }
};

#endif // ATLAS_STRATEGY_RESULT_MQH
//+------------------------------------------------------------------+
