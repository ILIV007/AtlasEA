//+------------------------------------------------------------------+
//|                   Trading/Filters/CooldownFilter.mqh             |
//|       AtlasEA v0.2.2 - Cooldown Filter                           |
//+------------------------------------------------------------------+
#ifndef ATLAS_COOLDOWN_FILTER_MQH
#define ATLAS_COOLDOWN_FILTER_MQH

#include "IFilter.mqh"

/**
 * @brief Maximum strategies tracked for per-strategy cooldown.
 */
#define ATLAS_COOLDOWN_MAX_STRATEGIES 8

/**
 * @brief Maximum symbols tracked for per-symbol cooldown.
 */
#define ATLAS_COOLDOWN_MAX_SYMBOLS 8

/**
 * @struct CooldownEntry
 * @brief Tracks the last trade time for a specific strategy or symbol.
 */
struct CooldownEntry
{
    int      id;            ///< Strategy ID or symbol hash
    datetime last_trade;    ///< Last trade time for this entry
    bool     active;        ///< Is this slot in use?

    CooldownEntry(void)
    {
        id         = 0;
        last_trade = 0;
        active     = false;
    }
};

/**
 * @struct CooldownFilterConfig
 * @brief Configuration for the cooldown filter.
 */
struct CooldownFilterConfig
{
    FilterConfig base;                          ///< Base config
    int    global_cooldown_sec;                 ///< Global cooldown after any trade
    int    strategy_cooldown_sec;               ///< Per-strategy cooldown
    int    symbol_cooldown_sec;                 ///< Per-symbol cooldown
    bool   use_context_cooldown;                ///< Use IContextStore.GetCooldownUntil for global

    CooldownFilterConfig(void)
    {
        base.enabled             = true;
        base.priority            = 50;
        base.reason_code         = ATLAS_FR_COOLDOWN_GLOBAL;
        global_cooldown_sec      = 0;     // Disabled by default
        strategy_cooldown_sec    = 0;     // Disabled by default
        symbol_cooldown_sec      = 0;     // Disabled by default
        use_context_cooldown     = true;  // Use context's cooldown
    }
};

/**
 * @class CooldownFilter
 * @brief Prevents immediate re-entry after trades.
 *
 * SOLE RESPONSIBILITY: check that the system is not in a cooldown
 * period that would prevent a new entry.
 *
 * Three cooldown types (all configurable, all independent):
 *   1. GLOBAL: after any trade, block all new entries for N seconds.
 *      Uses IContextStore.GetCooldownUntil() (set by RiskEngine) AND
 *      IContextStore.GetLastTradeTime().
 *   2. STRATEGY: after a trade from strategy X, block new entries from
 *      strategy X for N seconds. Tracked in a fixed-size ring.
 *   3. SYMBOL: after a trade on symbol Y, block new entries on symbol Y
 *      for N seconds. Tracked in a fixed-size ring.
 *
 * When a trade is accepted, the lifecycle (or the filter engine) should
 * call RecordTrade() to update the cooldown timers.
 *
 * Memory: ~400 bytes (config + 2 rings of 8 entries each).
 */
class CooldownFilter : public IFilter
{
private:
    ILogger               *m_logger;
    CooldownFilterConfig   m_config;
    bool                   m_initialized;

    //--- Per-strategy cooldown tracking
    CooldownEntry m_strategy_entries[ATLAS_COOLDOWN_MAX_STRATEGIES];
    int           m_strategy_count;

    //--- Per-symbol cooldown tracking (hash-based, since we can't store strings in a simple ring)
    CooldownEntry m_symbol_entries[ATLAS_COOLDOWN_MAX_SYMBOLS];
    int           m_symbol_count;

public:
    /**
     * @brief Constructor.
     */
    CooldownFilter(void)
    {
        m_logger          = NULL;
        m_initialized     = false;
        m_strategy_count  = 0;
        m_symbol_count    = 0;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "CooldownFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetCooldownConfig(const CooldownFilterConfig &config) { m_config = config; }
    CooldownFilterConfig GetCooldownConfig(void) const { return m_config; }

    virtual void SetLogger(ILogger *logger) override { m_logger = logger; }

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized = false;
        m_strategy_count = 0;
        m_symbol_count   = 0;
    }

    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) override
    {
        if(!m_config.base.enabled)
            return FilterResult::Skip(GetName(), ATLAS_FR_FILTER_DISABLED, "disabled");

        datetime now = TimeCurrent();

        //=== 1. Global cooldown ===
        if(m_config.global_cooldown_sec > 0 && context != NULL)
        {
            //--- Check context's cooldown_until (set by RiskEngine on losses)
            if(m_config.use_context_cooldown)
            {
                datetime cooldown_until = context.GetCooldownUntil();
                if(cooldown_until > now)
                    return FilterResult::Block(GetName(), ATLAS_FR_COOLDOWN_GLOBAL,
                        "global cooldown active (context) until " +
                        IntegerToString((long)cooldown_until));
            }

            //--- Check last trade time
            datetime last_trade = context.GetLastTradeTime();
            if(last_trade > 0)
            {
                long elapsed = (long)now - (long)last_trade;
                if(elapsed < m_config.global_cooldown_sec)
                    return FilterResult::Block(GetName(), ATLAS_FR_COOLDOWN_GLOBAL,
                        "global cooldown: " + IntegerToString(elapsed) + "s < " +
                        IntegerToString(m_config.global_cooldown_sec) + "s");
            }
        }

        //=== 2. Strategy cooldown ===
        if(m_config.strategy_cooldown_sec > 0)
        {
            datetime strat_last = GetStrategyLastTrade(signal.strategy_id);
            if(strat_last > 0)
            {
                long elapsed = (long)now - (long)strat_last;
                if(elapsed < m_config.strategy_cooldown_sec)
                    return FilterResult::Block(GetName(), ATLAS_FR_COOLDOWN_STRATEGY,
                        "strategy " + IntegerToString(signal.strategy_id) +
                        " cooldown: " + IntegerToString(elapsed) + "s < " +
                        IntegerToString(m_config.strategy_cooldown_sec) + "s");
            }
        }

        //=== 3. Symbol cooldown ===
        if(m_config.symbol_cooldown_sec > 0)
        {
            int sym_hash = HashString(market.symbol);
            datetime sym_last = GetSymbolLastTrade(sym_hash);
            if(sym_last > 0)
            {
                long elapsed = (long)now - (long)sym_last;
                if(elapsed < m_config.symbol_cooldown_sec)
                    return FilterResult::Block(GetName(), ATLAS_FR_COOLDOWN_SYMBOL,
                        "symbol cooldown: " + IntegerToString(elapsed) + "s < " +
                        IntegerToString(m_config.symbol_cooldown_sec) + "s");
            }
        }

        return FilterResult::Pass(GetName());
    }

    /**
     * @brief Record that a trade was accepted (update cooldown timers).
     *
     * Called by the filter engine or lifecycle after a signal passes
     * all filters and is accepted.
     *
     * @param strategy_id The strategy that generated the signal.
     * @param symbol_hash The hash of the symbol traded.
     */
    void RecordTrade(const int strategy_id, const int symbol_hash)
    {
        datetime now = TimeCurrent();
        RecordStrategyTrade(strategy_id, now);
        RecordSymbolTrade(symbol_hash, now);
    }

    /**
     * @brief Clear all cooldown tracking (e.g., on new trading day).
     */
    void ClearCooldowns(void)
    {
        m_strategy_count = 0;
        m_symbol_count   = 0;
        for(int i = 0; i < ATLAS_COOLDOWN_MAX_STRATEGIES; i++)
            m_strategy_entries[i].active = false;
        for(int i = 0; i < ATLAS_COOLDOWN_MAX_SYMBOLS; i++)
            m_symbol_entries[i].active = false;
    }

private:
    /**
     * @brief Get the last trade time for a strategy.
     */
    datetime GetStrategyLastTrade(const int strategy_id) const
    {
        for(int i = 0; i < m_strategy_count; i++)
            if(m_strategy_entries[i].active && m_strategy_entries[i].id == strategy_id)
                return m_strategy_entries[i].last_trade;
        return 0;
    }

    /**
     * @brief Get the last trade time for a symbol (by hash).
     */
    datetime GetSymbolLastTrade(const int symbol_hash) const
    {
        for(int i = 0; i < m_symbol_count; i++)
            if(m_symbol_entries[i].active && m_symbol_entries[i].id == symbol_hash)
                return m_symbol_entries[i].last_trade;
        return 0;
    }

    /**
     * @brief Record a strategy trade.
     */
    void RecordStrategyTrade(const int strategy_id, const datetime time)
    {
        //--- Find existing
        for(int i = 0; i < m_strategy_count; i++)
        {
            if(m_strategy_entries[i].active && m_strategy_entries[i].id == strategy_id)
            {
                m_strategy_entries[i].last_trade = time;
                return;
            }
        }
        //--- Add new
        if(m_strategy_count < ATLAS_COOLDOWN_MAX_STRATEGIES)
        {
            m_strategy_entries[m_strategy_count].id         = strategy_id;
            m_strategy_entries[m_strategy_count].last_trade = time;
            m_strategy_entries[m_strategy_count].active     = true;
            m_strategy_count++;
        }
    }

    /**
     * @brief Record a symbol trade.
     */
    void RecordSymbolTrade(const int symbol_hash, const datetime time)
    {
        //--- Find existing
        for(int i = 0; i < m_symbol_count; i++)
        {
            if(m_symbol_entries[i].active && m_symbol_entries[i].id == symbol_hash)
            {
                m_symbol_entries[i].last_trade = time;
                return;
            }
        }
        //--- Add new
        if(m_symbol_count < ATLAS_COOLDOWN_MAX_SYMBOLS)
        {
            m_symbol_entries[m_symbol_count].id         = symbol_hash;
            m_symbol_entries[m_symbol_count].last_trade = time;
            m_symbol_entries[m_symbol_count].active     = true;
            m_symbol_count++;
        }
    }

    /**
     * @brief Simple string hash (deterministic, no allocation).
     */
    static int HashString(const string s)
    {
        int hash = 5381;
        for(int i = 0; i < StringLen(s); i++)
            hash = ((hash << 5) + hash) + (int)StringGetCharacter(s, i);
        return hash;
    }
};

#endif // ATLAS_COOLDOWN_FILTER_MQH
//+------------------------------------------------------------------+
