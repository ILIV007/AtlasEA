//+------------------------------------------------------------------+
//|                   Trading/Filters/MaxTradesFilter.mqh            |
//|       AtlasEA v0.2.2 - Maximum Trades Filter                     |
//+------------------------------------------------------------------+
#ifndef ATLAS_MAX_TRADES_FILTER_MQH
#define ATLAS_MAX_TRADES_FILTER_MQH

#include "IFilter.mqh"

/**
 * @struct MaxTradesFilterConfig
 * @brief Configuration for the max trades filter.
 */
struct MaxTradesFilterConfig
{
    FilterConfig base;                          ///< Base config
    int    max_total_positions;                 ///< Max simultaneous positions (0 = unlimited)
    int    max_symbol_positions;                ///< Max positions per symbol (0 = unlimited)
    int    max_strategy_positions;              ///< Max positions per strategy (0 = unlimited)

    MaxTradesFilterConfig(void)
    {
        base.enabled              = true;
        base.priority             = 60;
        base.reason_code          = ATLAS_FR_MAX_TOTAL_POSITIONS;
        max_total_positions       = 5;     // 5 concurrent positions max
        max_symbol_positions      = 1;     // 1 position per symbol
        max_strategy_positions    = 2;     // 2 positions per strategy
    }
};

/**
 * @class MaxTradesFilter
 * @brief Rejects signals when maximum position limits are reached.
 *
 * SOLE RESPONSIBILITY: count current open positions and reject if any
 * limit is exceeded.
 *
 * Three limits (all configurable, all independent):
 *   1. MAX_TOTAL: maximum simultaneous positions across all symbols/strategies.
 *   2. MAX_SYMBOL: maximum positions for the signal's symbol.
 *   3. MAX_STRATEGY: maximum positions for the signal's strategy.
 *
 * Position counting:
 *   - Total positions: uses IBrokerAdapter.CountPositionsForMagic()
 *     (cached — no repeated calls within the same Evaluate).
 *   - Symbol/strategy positions: iterates IContextStore.GetPosition(i)
 *     and counts matching symbol/strategy. Since PositionState doesn't
 *     carry strategy_id, the symbol count uses the position's symbol
 *     field. Strategy count is estimated by matching the order comment
 *     prefix (if available) — this is a best-effort check.
 *
 * Memory: ~100 bytes (config + cached counts).
 */
class MaxTradesFilter : public IFilter
{
private:
    ILogger                *m_logger;
    MaxTradesFilterConfig   m_config;
    bool                    m_initialized;

    //--- Cached counts (refreshed each Evaluate call)
    int m_cached_total_count;
    int m_cached_symbol_count;
    int m_cached_strategy_count;

public:
    /**
     * @brief Constructor.
     */
    MaxTradesFilter(void)
    {
        m_logger                = NULL;
        m_initialized           = false;
        m_cached_total_count    = 0;
        m_cached_symbol_count   = 0;
        m_cached_strategy_count = 0;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "MaxTradesFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetMaxTradesConfig(const MaxTradesFilterConfig &config) { m_config = config; }
    MaxTradesFilterConfig GetMaxTradesConfig(void) const { return m_config; }

    virtual void SetLogger(ILogger *logger) override { m_logger = logger; }

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized = false;
    }

    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) override
    {
        if(!m_config.base.enabled)
            return FilterResult::Skip(GetName(), ATLAS_FR_FILTER_DISABLED, "disabled");

        if(broker == NULL || context == NULL)
            return FilterResult::Skip(GetName(), ATLAS_FR_NO_CONTEXT, "broker or context is NULL");

        //=== Count total positions ===
        m_cached_total_count = broker.CountPositionsForMagic();

        //=== Count symbol positions ===
        m_cached_symbol_count = 0;
        int pos_count = context.GetPositionCount();
        for(int i = 0; i < pos_count; i++)
        {
            PositionState pos;
            context.GetPosition(i, pos);
            if(pos.symbol == market.symbol)
                m_cached_symbol_count++;
        }

        //=== Count strategy positions ===
        //--- PositionState doesn't carry strategy_id, so we estimate by
        //--- counting positions with a comment matching the strategy ID.
        //--- This is a best-effort check. If comments don't contain the
        //--- strategy ID, this count will be 0 (no limit enforced).
        m_cached_strategy_count = CountStrategyPositions(context, signal.strategy_id);

        //=== Check max total ===
        if(m_config.max_total_positions > 0 &&
           m_cached_total_count >= m_config.max_total_positions)
            return FilterResult::Block(GetName(), ATLAS_FR_MAX_TOTAL_POSITIONS,
                "total " + IntegerToString(m_cached_total_count) +
                " >= max " + IntegerToString(m_config.max_total_positions));

        //=== Check max symbol ===
        if(m_config.max_symbol_positions > 0 &&
           m_cached_symbol_count >= m_config.max_symbol_positions)
            return FilterResult::Block(GetName(), ATLAS_FR_MAX_SYMBOL_POSITIONS,
                "symbol " + IntegerToString(m_cached_symbol_count) +
                " >= max " + IntegerToString(m_config.max_symbol_positions));

        //=== Check max strategy ===
        if(m_config.max_strategy_positions > 0 &&
           m_cached_strategy_count >= m_config.max_strategy_positions)
            return FilterResult::Block(GetName(), ATLAS_FR_MAX_STRATEGY_POSITIONS,
                "strategy " + IntegerToString(m_cached_strategy_count) +
                " >= max " + IntegerToString(m_config.max_strategy_positions));

        return FilterResult::Pass(GetName());
    }

    //=== Diagnostic accessors ===

    int GetCachedTotalCount(void)    const { return m_cached_total_count; }
    int GetCachedSymbolCount(void)   const { return m_cached_symbol_count; }
    int GetCachedStrategyCount(void) const { return m_cached_strategy_count; }

private:
    /**
     * @brief Count positions associated with a strategy.
     *
     * Since PositionState doesn't carry strategy_id, this is a
     * best-effort count based on position_id prefix or comment.
     * If no matching positions are found, returns 0 (limit not enforced).
     */
    int CountStrategyPositions(IContextStore *context, const int strategy_id) const
    {
        if(context == NULL) return 0;
        string prefix = "S" + IntegerToString(strategy_id) + "_";
        int count = 0;
        int pos_count = context.GetPositionCount();
        for(int i = 0; i < pos_count; i++)
        {
            PositionState pos;
            context.GetPosition(i, pos);
            //--- Check if the position_id starts with the strategy prefix
            if(StringLen(pos.position_id) >= StringLen(prefix) &&
               StringSubstr(pos.position_id, 0, StringLen(prefix)) == prefix)
                count++;
        }
        return count;
    }
};

#endif // ATLAS_MAX_TRADES_FILTER_MQH
//+------------------------------------------------------------------+
