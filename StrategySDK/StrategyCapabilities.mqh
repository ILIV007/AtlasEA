//+------------------------------------------------------------------+
//|             StrategySDK/StrategyCapabilities.mqh               |
//|       AtlasEA v0.1.17.0 - Strategy Capability Helper             |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_CAPABILITIES_MQH
#define ATLAS_STRATEGY_CAPABILITIES_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IPluginMetadata.mqh"

/**
 * @class StrategyCapabilities
 * @brief Helper for building capability bitmasks.
 *
 * Usage:
 *   StrategyCapabilities caps;
 *   caps.SetOnMarket().SetOnBar().SetEvaluate();
 *   int mask = caps.GetMask();
 */
class StrategyCapabilities
{
private:
    int m_mask;

public:
    /**
     * @brief Constructor — starts with no capabilities.
     */
    StrategyCapabilities(void) { m_mask = 0; }

    //=== Fluent setters ===

    StrategyCapabilities& SetOnMarket(void)       { m_mask |= ATLAS_CAP_ON_MARKET;       return *this; }
    StrategyCapabilities& SetOnBar(void)          { m_mask |= ATLAS_CAP_ON_BAR;          return *this; }
    StrategyCapabilities& SetOnTimer(void)        { m_mask |= ATLAS_CAP_ON_TIMER;        return *this; }
    StrategyCapabilities& SetEvaluate(void)       { m_mask |= ATLAS_CAP_EVALUATE;        return *this; }
    StrategyCapabilities& SetMultiSymbol(void)    { m_mask |= ATLAS_CAP_MULTI_SYMBOL;    return *this; }
    StrategyCapabilities& SetMultiTimeframe(void) { m_mask |= ATLAS_CAP_MULTI_TIMEFRAME; return *this; }
    StrategyCapabilities& SetHedgeAware(void)     { m_mask |= ATLAS_CAP_HEDGE_AWARE;     return *this; }
    StrategyCapabilities& SetNewsAware(void)      { m_mask |= ATLAS_CAP_NEWS_AWARE;      return *this; }
    StrategyCapabilities& SetStateful(void)       { m_mask |= ATLAS_CAP_STATEFUL;        return *this; }

    //=== Queries ===

    bool HasOnMarket(void) const       { return (m_mask & ATLAS_CAP_ON_MARKET) != 0; }
    bool HasOnBar(void) const          { return (m_mask & ATLAS_CAP_ON_BAR) != 0; }
    bool HasOnTimer(void) const        { return (m_mask & ATLAS_CAP_ON_TIMER) != 0; }
    bool HasEvaluate(void) const       { return (m_mask & ATLAS_CAP_EVALUATE) != 0; }
    bool HasMultiSymbol(void) const    { return (m_mask & ATLAS_CAP_MULTI_SYMBOL) != 0; }
    bool HasMultiTimeframe(void) const { return (m_mask & ATLAS_CAP_MULTI_TIMEFRAME) != 0; }
    bool HasHedgeAware(void) const     { return (m_mask & ATLAS_CAP_HEDGE_AWARE) != 0; }
    bool HasNewsAware(void) const      { return (m_mask & ATLAS_CAP_NEWS_AWARE) != 0; }
    bool HasStateful(void) const       { return (m_mask & ATLAS_CAP_STATEFUL) != 0; }

    /// @brief Get the bitmask.
    int GetMask(void) const { return m_mask; }

    /// @brief Reset to no capabilities.
    void Reset(void) { m_mask = 0; }
};

#endif // ATLAS_STRATEGY_CAPABILITIES_MQH
//+------------------------------------------------------------------+
