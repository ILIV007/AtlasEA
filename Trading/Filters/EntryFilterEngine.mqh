//+------------------------------------------------------------------+
//|                  Trading/Filters/EntryFilterEngine.mqh           |
//|       AtlasEA v0.2.2 - Entry Filter Engine (Chain Orchestrator)  |
//+------------------------------------------------------------------+
#ifndef ATLAS_ENTRY_FILTER_ENGINE_MQH
#define ATLAS_ENTRY_FILTER_ENGINE_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/IBrokerAdapter.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../TradeSignal.mqh"
#include "FilterResult.mqh"
#include "IFilter.mqh"
#include "SpreadFilter.mqh"
#include "SessionFilter.mqh"
#include "VolatilityFilter.mqh"
#include "MarketStateFilter.mqh"
#include "CooldownFilter.mqh"
#include "MaxTradesFilter.mqh"
#include "TradingPermissionFilter.mqh"

/**
 * @brief Maximum number of filters in the chain.
 */
#define ATLAS_MAX_FILTERS 8

/**
 * @struct FilterChainResult
 * @brief Aggregated result of running all filters in the chain.
 */
struct FilterChainResult
{
    bool   passed;              ///< True if all filters passed (or skipped)
    int    blocking_filter_idx; ///< Index of the filter that blocked (-1 if none)
    string blocking_filter_name; ///< Name of the blocking filter
    int    blocking_reason_code; ///< Reason code from the blocking filter
    string blocking_reason_text; ///< Reason text from the blocking filter
    int    total_evaluated;     ///< Total filters evaluated
    int    total_passed;        ///< Filters that returned PASS
    int    total_skipped;       ///< Filters that returned SKIP
    int    total_blocked;       ///< Filters that returned BLOCK (should be 0 or 1)

    FilterChainResult(void)
    {
        passed                = false;
        blocking_filter_idx   = -1;
        blocking_filter_name  = "";
        blocking_reason_code  = ATLAS_FR_OK;
        blocking_reason_text  = "";
        total_evaluated       = 0;
        total_passed          = 0;
        total_skipped         = 0;
        total_blocked         = 0;
    }
};

/**
 * @struct FilterEngineStats
 * @brief Statistics for the filter engine.
 */
struct FilterEngineStats
{
    int total_evaluations;     ///< Total EvaluateSignal() calls
    int total_passed;          ///< Signals that passed all filters
    int total_blocked;         ///< Signals blocked by any filter
    int block_counts[8];       ///< Per-filter block counts (indexed by filter slot)

    FilterEngineStats(void)
    {
        total_evaluations = 0;
        total_passed      = 0;
        total_blocked     = 0;
        for(int i = 0; i < 8; i++) block_counts[i] = 0;
    }
};

/**
 * @class EntryFilterEngine
 * @brief Runs a chain of entry filters in priority order.
 *
 * The EntryFilterEngine is the SINGLE ENTRY POINT for signal filtering.
 * It sits between the SignalPipeline and the TradeLifecycle:
 *
 *   SignalPipeline → EntryFilterEngine → TradeLifecycle
 *
 * The engine holds up to ATLAS_MAX_FILTERS (8) filters. Filters are
 * executed in priority order (lowest priority value = executed first).
 * When a filter returns BLOCK, the chain stops immediately and the
 * signal is rejected. SKIP (disabled filter) does not stop the chain.
 *
 * Default filter chain (in priority order):
 *   1. SpreadFilter           (priority 10)
 *   2. SessionFilter          (priority 20)
 *   3. VolatilityFilter       (priority 30)
 *   4. MarketStateFilter      (priority 40)
 *   5. CooldownFilter         (priority 50)
 *   6. MaxTradesFilter        (priority 60)
 *   7. TradingPermissionFilter (priority 70)
 *
 * Logging policy: only BLOCKED signals produce a log entry. PASSED
 * and SKIPPED filters are silent (no TRACE logging).
 *
 * Memory: ~4 KB (7 filter instances + chain array + stats).
 * No dynamic allocation. All filters are stack-allocated.
 */
class EntryFilterEngine
{
private:
    ILogger *m_logger;
    bool     m_initialized;

    //--- Filter chain (sorted by priority)
    IFilter *m_chain[ATLAS_MAX_FILTERS];
    int      m_chain_count;

    //--- Owned filter instances (stack-allocated)
    SpreadFilter             m_spread_filter;
    SessionFilter            m_session_filter;
    VolatilityFilter         m_volatility_filter;
    MarketStateFilter        m_market_state_filter;
    CooldownFilter           m_cooldown_filter;
    MaxTradesFilter          m_max_trades_filter;
    TradingPermissionFilter  m_permission_filter;

    //--- Statistics
    FilterEngineStats m_stats;

public:
    /**
     * @brief Constructor.
     */
    EntryFilterEngine(void)
    {
        m_logger      = NULL;
        m_initialized = false;
        m_chain_count = 0;
        for(int i = 0; i < ATLAS_MAX_FILTERS; i++) m_chain[i] = NULL;
    }

    /**
     * @brief Set the logger (wires to all filters).
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_spread_filter.SetLogger(logger);
        m_session_filter.SetLogger(logger);
        m_volatility_filter.SetLogger(logger);
        m_market_state_filter.SetLogger(logger);
        m_cooldown_filter.SetLogger(logger);
        m_max_trades_filter.SetLogger(logger);
        m_permission_filter.SetLogger(logger);
    }

    /**
     * @brief Initialize the engine and build the default filter chain.
     *
     * The default chain includes all 7 built-in filters in priority order.
     * Each filter is initialized and added to the chain.
     *
     * @return true if all filters initialized successfully.
     */
    bool Initialize(void)
    {
        if(m_logger == NULL) return false;

        //--- Initialize all filters
        if(!m_spread_filter.Initialize())      return false;
        if(!m_session_filter.Initialize())     return false;
        if(!m_volatility_filter.Initialize())  return false;
        if(!m_market_state_filter.Initialize()) return false;
        if(!m_cooldown_filter.Initialize())    return false;
        if(!m_max_trades_filter.Initialize())  return false;
        if(!m_permission_filter.Initialize())  return false;

        //--- Build the chain in priority order
        m_chain_count = 0;
        m_chain[m_chain_count++] = &m_spread_filter;
        m_chain[m_chain_count++] = &m_session_filter;
        m_chain[m_chain_count++] = &m_volatility_filter;
        m_chain[m_chain_count++] = &m_market_state_filter;
        m_chain[m_chain_count++] = &m_cooldown_filter;
        m_chain[m_chain_count++] = &m_max_trades_filter;
        m_chain[m_chain_count++] = &m_permission_filter;

        //--- Sort by priority (insertion sort — chain is small)
        SortChainByPriority();

        m_initialized = true;
        m_logger.Info("EntryFilterEngine",
            "Initialized with " + IntegerToString(m_chain_count) + " filters");
        return true;
    }

    /**
     * @brief Shutdown the engine and all filters.
     */
    void Shutdown(void)
    {
        if(!m_initialized) return;

        for(int i = 0; i < m_chain_count; i++)
        {
            if(m_chain[i] != NULL)
                m_chain[i].Shutdown();
        }

        m_chain_count = 0;
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("EntryFilterEngine", "Shutdown complete");
    }

    /**
     * @brief Evaluate a signal through the entire filter chain.
     *
     * This is the MAIN ENTRY POINT. Runs every enabled filter in
     * priority order. Stops on the first BLOCK. Returns the
     * aggregated result.
     *
     * Logging: only BLOCKED signals produce a log entry (Warn level).
     * PASSED signals are silent.
     *
     * @param signal  The signal to evaluate.
     * @param market  Current market state.
     * @param broker  Broker adapter (may be NULL for some filters).
     * @param context Context store (may be NULL for some filters).
     * @return FilterChainResult.
     */
    FilterChainResult EvaluateSignal(const TradeSignal &signal,
                                      const MarketState &market,
                                      IBrokerAdapter *broker,
                                      IContextStore *context)
    {
        FilterChainResult result;
        m_stats.total_evaluations++;

        for(int i = 0; i < m_chain_count; i++)
        {
            if(m_chain[i] == NULL) continue;

            FilterResult fr = m_chain[i].Evaluate(signal, market, broker, context);
            result.total_evaluated++;

            if(fr.Blocked())
            {
                result.passed                = false;
                result.blocking_filter_idx   = i;
                result.blocking_filter_name  = fr.filter_name;
                result.blocking_reason_code  = fr.reason_code;
                result.blocking_reason_text  = fr.reason_text;
                result.total_blocked++;

                //--- Log only blocked signals (no TRACE logging)
                if(m_logger != NULL)
                    m_logger.Warn("EntryFilterEngine",
                        "BLOCKED " + signal.signal_id +
                        " [" + fr.filter_name + "] " +
                        FilterReasonName(fr.reason_code) +
                        ": " + fr.reason_text);

                if(i < 8) m_stats.block_counts[i]++;
                m_stats.total_blocked++;
                return result;
            }
            else if(fr.Skipped())
            {
                result.total_skipped++;
            }
            else // PASS
            {
                result.total_passed++;
            }
        }

        //--- All filters passed (or skipped)
        result.passed = true;
        m_stats.total_passed++;
        return result;
    }

    /**
     * @brief Record that a trade was accepted (updates cooldown tracking).
     *
     * Called by the lifecycle or pipeline after a signal passes all
     * filters and the trade is accepted.
     *
     * @param strategy_id The strategy that generated the signal.
     * @param symbol The symbol traded.
     */
    void RecordAcceptedTrade(const int strategy_id, const string symbol)
    {
        int sym_hash = 0;
        for(int i = 0; i < StringLen(symbol); i++)
            sym_hash = ((sym_hash << 5) + sym_hash) + (int)StringGetCharacter(symbol, i);
        m_cooldown_filter.RecordTrade(strategy_id, sym_hash);
    }

    /**
     * @brief Clear all cooldown tracking (e.g., on new trading day).
     */
    void ClearCooldowns(void)
    {
        m_cooldown_filter.ClearCooldowns();
    }

    //=== Filter accessors (for configuration) ===

    SpreadFilter&             GetSpreadFilter(void)         { return m_spread_filter; }
    SessionFilter&            GetSessionFilter(void)        { return m_session_filter; }
    VolatilityFilter&         GetVolatilityFilter(void)     { return m_volatility_filter; }
    MarketStateFilter&        GetMarketStateFilter(void)    { return m_market_state_filter; }
    CooldownFilter&           GetCooldownFilter(void)       { return m_cooldown_filter; }
    MaxTradesFilter&          GetMaxTradesFilter(void)      { return m_max_trades_filter; }
    TradingPermissionFilter&  GetPermissionFilter(void)    { return m_permission_filter; }

    /**
     * @brief Get the number of filters in the chain.
     */
    int GetChainCount(void) const { return m_chain_count; }

    /**
     * @brief Get a filter from the chain by index.
     */
    IFilter* GetFilterAt(const int index)
    {
        if(index < 0 || index >= m_chain_count) return NULL;
        return m_chain[index];
    }

    /**
     * @brief Get the engine statistics.
     */
    const FilterEngineStats& GetStats(void) const { return m_stats; }

    /**
     * @brief Reset statistics.
     */
    void ResetStats(void)
    {
        m_stats = FilterEngineStats();
    }

    /**
     * @brief Log the engine statistics.
     */
    void LogStats(void) const
    {
        if(m_logger == NULL) return;
        m_logger.Info("EntryFilterEngine",
            "Evaluations=" + IntegerToString(m_stats.total_evaluations) +
            " Passed=" + IntegerToString(m_stats.total_passed) +
            " Blocked=" + IntegerToString(m_stats.total_blocked));

        for(int i = 0; i < m_chain_count; i++)
        {
            if(m_chain[i] == NULL) continue;
            int blocks = (i < 8) ? m_stats.block_counts[i] : 0;
            m_logger.Info("EntryFilterEngine",
                "  [" + IntegerToString(i) + "] " + m_chain[i].GetName() +
                " blocks=" + IntegerToString(blocks));
        }
    }

    /**
     * @brief Check if the engine is initialized.
     */
    bool IsInitialized(void) const { return m_initialized; }

private:
    /**
     * @brief Sort the filter chain by priority (ascending — lowest priority first).
     * Uses insertion sort (chain is small, <8 elements).
     */
    void SortChainByPriority(void)
    {
        for(int i = 1; i < m_chain_count; i++)
        {
            IFilter *key = m_chain[i];
            int key_prio = key.GetConfig().priority;
            int j = i - 1;
            while(j >= 0 && m_chain[j].GetConfig().priority > key_prio)
            {
                m_chain[j + 1] = m_chain[j];
                j--;
            }
            m_chain[j + 1] = key;
        }
    }
};

#endif // ATLAS_ENTRY_FILTER_ENGINE_MQH
//+------------------------------------------------------------------+
