//+------------------------------------------------------------------+
//|                    Plugins/PluginManager.mqh                    |
//|       AtlasEA v0.1.17.0 - Plugin Manager                         |
//+------------------------------------------------------------------+
#ifndef ATLAS_PLUGIN_MANAGER_MQH
#define ATLAS_PLUGIN_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategyPlugin.mqh"
#include "../Interfaces/ILogger.mqh"
#include "PluginRegistry.mqh"
#include "PluginValidator.mqh"
#include "PluginLoader.mqh"
#include "../StrategySDK/StrategyContext.mqh"
#include "../StrategySDK/StrategyResult.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"

/**
 * @struct PluginExecutionStats
 * @brief Per-plugin execution statistics.
 */
struct PluginExecutionStats
{
    int    plugin_id;
    ulong  evaluations;
    ulong  successes;
    ulong  abstentions;
    ulong  failures;
    double total_latency_ms;
    double peak_latency_ms;
};

/**
 * @class PluginManager
 * @brief Manages the entire plugin lifecycle and execution.
 *
 * Responsibilities:
 *   - Own the PluginRegistry
 *   - Own the PluginLoader
 *   - Execute enabled plugins
 *   - Collect results
 *   - Track statistics
 *   - Convert StrategyResult to StrategyVote (for VoteAggregator)
 *
 * The PluginManager is the bridge between the plugin architecture
 * and the existing StrategyEngine. It produces StrategyVote[] arrays
 * that the StrategyEngine returns to CoreEngine.
 */
class PluginManager
{
private:
    ILogger           *m_logger;
    PluginRegistry     m_registry;
    PluginLoader       m_loader;

    //--- Execution statistics
    PluginExecutionStats m_stats[ATLAS_PLUGIN_MAX];
    int                  m_stats_count;

    //--- Results buffer
    StrategyVote         m_votes[ATLAS_MAX_VOTES];
    int                  m_vote_count;

    /// @brief Find or create stats entry.
    PluginExecutionStats* GetStats(const int plugin_id)
    {
        for(int i = 0; i < m_stats_count; i++)
        {
            if(m_stats[i].plugin_id == plugin_id)
                return &m_stats[i];
        }

        if(m_stats_count >= ATLAS_PLUGIN_MAX)
            return &m_stats[0];

        m_stats[m_stats_count].plugin_id        = plugin_id;
        m_stats[m_stats_count].evaluations      = 0;
        m_stats[m_stats_count].successes        = 0;
        m_stats[m_stats_count].abstentions      = 0;
        m_stats[m_stats_count].failures         = 0;
        m_stats[m_stats_count].total_latency_ms = 0.0;
        m_stats[m_stats_count].peak_latency_ms  = 0.0;
        m_stats_count++;
        return &m_stats[m_stats_count - 1];
    }

    /// @brief Convert a StrategyResult to a StrategyVote.
    StrategyResult ConvertResult(const StrategyResult &result)
    {
        return result;  //--- Already the right type
    }

    /// @brief Convert a StrategyResult to a StrategyVote.
    void ResultToVote(const StrategyResult &result, const PluginMetadata &meta,
                      StrategyVote &out_vote)
    {
        out_vote.strategy_id      = meta.plugin_id;
        out_vote.strategy_version = meta.version;
        out_vote.direction        = result.direction;
        out_vote.confidence       = result.confidence * meta.weight;
        if(out_vote.confidence > 1.0) out_vote.confidence = 1.0;
        if(out_vote.confidence < 0.0) out_vote.confidence = 0.0;
        out_vote.suggested_volume = result.suggested_volume;
        out_vote.suggested_entry  = result.suggested_entry;
        out_vote.suggested_sl     = result.suggested_sl;
        out_vote.suggested_tp     = result.suggested_tp;
        out_vote.snapshot_id      = result.snapshot_id;
        out_vote.vote_time        = result.result_time;
    }

public:
    /**
     * @brief Constructor.
     */
    PluginManager(void)
    {
        m_logger      = NULL;
        m_stats_count = 0;
        m_vote_count  = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_registry.SetLogger(logger);
        m_loader.SetLogger(logger);
    }

    //=== Registry access ===

    PluginRegistry& GetRegistry(void) { return m_registry; }
    PluginLoader& GetLoader(void) { return m_loader; }

    /**
     * @brief Register a plugin directly.
     */
    bool RegisterPlugin(IStrategyPlugin *plugin)
    {
        return m_loader.LoadPlugin(m_registry, plugin);
    }

    /**
     * @brief Execute all enabled plugins and collect votes.
     * @param ctx The strategy context.
     * @param out_votes Output: array of votes (caller checks count).
     * @param out_count Output: number of votes produced.
     * @return true if at least one plugin executed.
     */
    bool ExecuteAll(const StrategyContext &ctx,
                     StrategyVote out_votes[],
                     int &out_count)
    {
        out_count = 0;

        //--- Get enabled plugins sorted by priority
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int plugin_count = 0;
        m_registry.GetEnabledSorted(plugins, plugin_count);

        if(plugin_count == 0) return false;

        //--- Execute each plugin
        for(int i = 0; i < plugin_count && out_count < ATLAS_MAX_VOTES; i++)
        {
            IStrategyPlugin *plugin = plugins[i];
            if(plugin == NULL) continue;

            const PluginMetadata &meta = plugin.GetMetadata();

            //--- Check symbol support
            if(!meta.SupportsSymbol(ctx.GetConfig().symbol))
                continue;

            //--- Check if plugin has EVALUATE capability
            if((meta.capabilities & ATLAS_CAP_EVALUATE) == 0)
                continue;

            //--- Time the execution
            ulong start = GetTickCount64();

            StrategyResult result;
            result = plugin.Evaluate(ctx);

            double elapsed = (double)(GetTickCount64() - start);

            //--- Update stats
            PluginExecutionStats *stats = GetStats(meta.plugin_id);
            if(stats != NULL)
            {
                stats.evaluations++;
                stats.total_latency_ms += elapsed;
                if(elapsed > stats.peak_latency_ms)
                    stats.peak_latency_ms = elapsed;

                if(!result.valid)
                    stats.failures++;
                else if(result.direction == ATLAS_ORDER_NONE)
                    stats.abstentions++;
                else
                    stats.successes++;
            }

            //--- Skip invalid or abstention results
            if(!result.valid) continue;
            if(result.direction == ATLAS_ORDER_NONE) continue;

            //--- Convert to vote and add to output
            ResultToVote(result, meta, out_votes[out_count]);
            out_count++;
        }

        return (out_count > 0);
    }

    /**
     * @brief Call OnMarket() on all enabled plugins with that capability.
     */
    void NotifyOnMarket(const StrategyContext &ctx)
    {
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int count = 0;
        m_registry.FindByCapability(ATLAS_CAP_ON_MARKET, plugins, count);

        for(int i = 0; i < count; i++)
        {
            if(plugins[i] == NULL) continue;
            if(!plugins[i].GetMetadata().enabled) continue;
            plugins[i].OnMarket(ctx);
        }
    }

    /**
     * @brief Call OnBar() on all enabled plugins with that capability.
     */
    void NotifyOnBar(const StrategyContext &ctx)
    {
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int count = 0;
        m_registry.FindByCapability(ATLAS_CAP_ON_BAR, plugins, count);

        for(int i = 0; i < count; i++)
        {
            if(plugins[i] == NULL) continue;
            if(!plugins[i].GetMetadata().enabled) continue;
            plugins[i].OnBar(ctx);
        }
    }

    /**
     * @brief Call OnTimer() on all enabled plugins with that capability.
     */
    void NotifyOnTimer(const StrategyContext &ctx)
    {
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int count = 0;
        m_registry.FindByCapability(ATLAS_CAP_ON_TIMER, plugins, count);

        for(int i = 0; i < count; i++)
        {
            if(plugins[i] == NULL) continue;
            if(!plugins[i].GetMetadata().enabled) continue;
            plugins[i].OnTimer(ctx);
        }
    }

    /**
     * @brief Reset all plugins.
     */
    void ResetAll(void)
    {
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int count = 0;
        m_registry.GetEnabledSorted(plugins, count);

        for(int i = 0; i < count; i++)
        {
            if(plugins[i] != NULL)
                plugins[i].Reset();
        }
    }

    /**
     * @brief Shutdown all plugins.
     */
    void ShutdownAll(void)
    {
        IStrategyPlugin *plugins[ATLAS_PLUGIN_MAX];
        int count = 0;
        m_registry.GetEnabledSorted(plugins, count);

        for(int i = 0; i < count; i++)
        {
            if(plugins[i] != NULL)
                plugins[i].Shutdown();
        }

        m_registry.Clear();
    }

    /**
     * @brief Log execution statistics.
     */
    void LogStats(void) const
    {
        if(m_logger == NULL) return;

        for(int i = 0; i < m_stats_count; i++)
        {
            if(m_stats[i].plugin_id == 0) continue;
            double avg = 0.0;
            if(m_stats[i].evaluations > 0)
                avg = m_stats[i].total_latency_ms / (double)m_stats[i].evaluations;

            m_logger.Info("PluginManager",
                "id=" + IntegerToString(m_stats[i].plugin_id) +
                " evals=" + IntegerToString((long)m_stats[i].evaluations) +
                " ok=" + IntegerToString((long)m_stats[i].successes) +
                " abst=" + IntegerToString((long)m_stats[i].abstentions) +
                " fail=" + IntegerToString((long)m_stats[i].failures) +
                " avg_ms=" + DoubleToString(avg, 3) +
                " peak_ms=" + DoubleToString(m_stats[i].peak_latency_ms, 3));
        }
    }

    //=== Accessors ===
    int PluginCount(void) const { return m_registry.Count(); }
    int EnabledCount(void) const { return m_registry.EnabledCount(); }
};

#endif // ATLAS_PLUGIN_MANAGER_MQH
//+------------------------------------------------------------------+
