//+------------------------------------------------------------------+
//|                  StrategySDK/StrategyBase.mqh                   |
//|       AtlasEA v0.1.17.0 - Strategy Base Class                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_BASE_MQH
#define ATLAS_STRATEGY_BASE_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"
#include "StrategyContext.mqh"
#include "StrategyResult.mqh"
#include "StrategyCapabilities.mqh"
#include "StrategyParameters.mqh"
#include "StrategyLifecycle.mqh"

/**
 * @class StrategyBase
 * @brief Base class for all strategy plugins.
 *
 * Provides default implementations for all IStrategyPlugin methods.
 * Subclasses override only what they need.
 *
 * Usage:
 *   class MyStrategy : public StrategyBase
 *   {
 *   public:
 *       MyStrategy(void)
 *       {
 *           m_metadata.plugin_id  = 100;
 *           m_metadata.name       = "MyStrategy";
 *           m_metadata.version    = "1.0.0";
 *           m_metadata.author     = "Me";
 *           m_metadata.category   = ATLAS_PLUGIN_CAT_STRATEGY;
 *           m_metadata.capabilities = ATLAS_CAP_EVALUATE;
 *       }
 *
 *       virtual StrategyResult Evaluate(const StrategyContext &ctx) override
 *       {
 *           //--- Strategy logic here
 *           return StrategyResultBuilder::Abstain(m_metadata.plugin_id, ctx.GetSnapshotId());
 *       }
 *   };
 *
 * This base class:
 *   - Stores the metadata (subclasses configure in constructor)
 *   - Stores the lifecycle state
 *   - Stores parameters
 *   - Provides no-op defaults for OnMarket/OnBar/OnTimer
 *   - Provides default Evaluate() that returns abstention
 */
class StrategyBase : public IStrategyPlugin
{
protected:
    PluginMetadata      m_metadata;
    StrategyLifecycle   m_lifecycle;
    StrategyParameters  m_params;

public:
    /**
     * @brief Constructor.
     */
    StrategyBase(void)
    {
        //--- Subclasses configure m_metadata in their constructor
    }

    virtual ~StrategyBase(void) {}

    //=== IStrategyPlugin implementation (defaults) ===

    virtual bool Initialize(void) override
    {
        m_lifecycle.ToInitialized();
        m_lifecycle.ToActive();
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_lifecycle.ToShutdown();
    }

    virtual void Reset(void) override
    {
        //--- Subclasses can override to reset internal state
    }

    virtual void OnMarket(const StrategyContext &ctx) override
    {
        //--- Default: no-op. Override if CAP_ON_MARKET is set.
    }

    virtual void OnBar(const StrategyContext &ctx) override
    {
        //--- Default: no-op. Override if CAP_ON_BAR is set.
    }

    virtual void OnTimer(const StrategyContext &ctx) override
    {
        //--- Default: no-op. Override if CAP_ON_TIMER is set.
    }

    virtual StrategyResult Evaluate(const StrategyContext &ctx) override
    {
        //--- Default: abstain. Subclasses MUST override if CAP_EVALUATE.
        return StrategyResultBuilder::Abstain(m_metadata.plugin_id, ctx.GetSnapshotId());
    }

    //=== Metadata ===

    virtual const PluginMetadata& GetMetadata(void) const override
    {
        return m_metadata;
    }

    virtual string Name(void) const override { return m_metadata.name; }
    virtual string Version(void) const override { return m_metadata.version; }
    virtual string Author(void) const override { return m_metadata.author; }
    virtual string Description(void) const override { return m_metadata.description; }
    virtual int    Capabilities(void) const override { return m_metadata.capabilities; }

    //=== Parameter access ===

    /**
     * @brief Get the strategy parameters.
     */
    StrategyParameters& GetParameters(void) { return m_params; }

    /**
     * @brief Get the lifecycle state.
     */
    const StrategyLifecycle& GetLifecycle(void) const { return m_lifecycle; }

protected:
    /**
     * @brief Set a capability flag.
     */
    void SetCapability(const int cap_flag)
    {
        m_metadata.capabilities |= cap_flag;
    }
};

#endif // ATLAS_STRATEGY_BASE_MQH
//+------------------------------------------------------------------+
