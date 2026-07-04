//+------------------------------------------------------------------+
//|                    Interfaces/IStrategyPlugin.mqh               |
//|       AtlasEA v0.1.17.0 - Strategy Plugin Interface              |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISTRATEGY_PLUGIN_MQH
#define ATLAS_ISTRATEGY_PLUGIN_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "IPluginMetadata.mqh"

//--- Forward declarations
class StrategyContext;

/**
 * @struct StrategyResult
 * @brief Result returned by a plugin's Evaluate() method.
 */
struct StrategyResult
{
    int      plugin_id;        ///< Which plugin produced this result
    int      direction;        ///< ATLAS_ORDER_BUY / SELL / NONE
    double   confidence;       ///< [0.0, 1.0]
    double   suggested_entry;  ///< Suggested entry price
    double   suggested_sl;     ///< Suggested stop-loss
    double   suggested_tp;     ///< Suggested take-profit
    double   suggested_volume; ///< Suggested volume (0 = use default)
    long     snapshot_id;      ///< MarketState snapshot this result is for
    datetime result_time;      ///< When the result was produced
    bool     valid;            ///< Is this result valid?

    /**
     * @brief Default constructor — creates an abstention.
     */
    StrategyResult(void)
    {
        plugin_id        = 0;
        direction        = ATLAS_ORDER_NONE;
        confidence       = 0.0;
        suggested_entry  = 0.0;
        suggested_sl     = 0.0;
        suggested_tp     = 0.0;
        suggested_volume = 0.0;
        snapshot_id      = 0;
        result_time      = 0;
        valid            = true;
    }

    /**
     * @brief Create an abstention result.
     */
    static StrategyResult Abstention(const int plugin_id, const long snapshot_id)
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
};

/**
 * @class IStrategyPlugin
 * @brief Interface that every strategy plugin must implement.
 *
 * Lifecycle:
 *   1. Constructed (by factory or manually)
 *   2. Initialize() — called once at startup
 *   3. OnMarket() — called on every tick (if CAP_ON_MARKET)
 *   4. OnBar() — called on bar close (if CAP_ON_BAR)
 *   5. OnTimer() — called on timer (if CAP_ON_TIMER)
 *   6. Evaluate() — called to produce a vote (if CAP_EVALUATE)
 *   7. Reset() — called on daily reset
 *   8. Shutdown() — called at EA shutdown
 *
 * Restrictions:
 *   - No broker API calls
 *   - No file access
 *   - No direct logging (use StrategyContext if needed)
 *   - No access to CoreEngine
 *   - No access to other plugins
 *   - No static mutable state
 */
class IStrategyPlugin
{
public:
    //=== Lifecycle ===
    virtual bool Initialize(void) = 0;
    virtual void Shutdown(void) = 0;
    virtual void Reset(void) = 0;

    //=== Callbacks ===
    virtual void OnMarket(const StrategyContext &ctx) = 0;
    virtual void OnBar(const StrategyContext &ctx) = 0;
    virtual void OnTimer(const StrategyContext &ctx) = 0;
    virtual StrategyResult Evaluate(const StrategyContext &ctx) = 0;

    //=== Metadata ===
    virtual const PluginMetadata& GetMetadata(void) const = 0;
    virtual string Name(void) const = 0;
    virtual string Version(void) const = 0;
    virtual string Author(void) const = 0;
    virtual string Description(void) const = 0;
    virtual int    Capabilities(void) const = 0;

    virtual ~IStrategyPlugin(void) {}
};

#endif // ATLAS_ISTRATEGY_PLUGIN_MQH
//+------------------------------------------------------------------+
