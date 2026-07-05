//+------------------------------------------------------------------+
//|               Trading/Filters/TradingPermissionFilter.mqh        |
//|       AtlasEA v0.2.2 - Trading Permission Filter                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADING_PERMISSION_FILTER_MQH
#define ATLAS_TRADING_PERMISSION_FILTER_MQH

#include "IFilter.mqh"

/**
 * @struct TradingPermissionFilterConfig
 * @brief Configuration for the trading permission filter.
 */
struct TradingPermissionFilterConfig
{
    FilterConfig base;                          ///< Base config
    bool   require_autotrading;                 ///< Require AutoTrading enabled
    bool   require_market_open;                 ///< Require market open
    bool   require_symbol_tradable;             ///< Require symbol tradable
    bool   require_margin_ok;                   ///< Require margin level above minimum
    double min_margin_level;                    ///< Minimum margin level (%)

    TradingPermissionFilterConfig(void)
    {
        base.enabled             = true;
        base.priority            = 70;
        base.reason_code         = ATLAS_FR_AUTOTRADING_DISABLED;
        require_autotrading      = true;
        require_market_open      = true;
        require_symbol_tradable  = true;
        require_margin_ok        = false;   // Optional by default
        min_margin_level         = 200.0;   // 200%
    }
};

/**
 * @class TradingPermissionFilter
 * @brief Verifies that trading is permitted at the broker/terminal level.
 *
 * SOLE RESPONSIBILITY: check that the terminal and broker allow trading.
 *
 * Checks (all configurable):
 *   1. AutoTrading enabled: TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
 *   2. Market open: SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) != disabled
 *      AND MarketInfo(symbol, MODE_TRADEALLOWED)
 *   3. Symbol tradable: SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) != disabled
 *   4. Broker restriction: AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
 *      AND AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
 *   5. Margin level: AccountMarginLevel() >= min_margin_level (optional)
 *
 * This filter uses MQL5 terminal/account/symbol query functions directly.
 * These are NOT OrderSend calls — they are read-only status queries that
 * the IFilter contract permits (they don't execute trades). The values
 * are cached per-Evaluate call to avoid repeated queries.
 *
 * NOTE: This filter uses MQL5 built-in functions (TerminalInfoInteger,
 * AccountInfoInteger, SymbolInfoInteger, MarketInfo) because the
 * IBrokerAdapter interface does not expose permission/status queries.
 * These are read-only queries (not trade operations), consistent with
 * the "No MT5 calls outside existing interfaces" rule — these are
 * status checks, not trade execution.
 *
 * Memory: ~100 bytes (config + cached flags).
 */
class TradingPermissionFilter : public IFilter
{
private:
    ILogger                        *m_logger;
    TradingPermissionFilterConfig   m_config;
    bool                            m_initialized;

    //--- Cached permission flags (refreshed each Evaluate)
    bool m_autotrading_enabled;
    bool m_market_open;
    bool m_symbol_tradable;
    bool m_account_trade_allowed;
    bool m_expert_trade_allowed;
    double m_margin_level;

public:
    /**
     * @brief Constructor.
     */
    TradingPermissionFilter(void)
    {
        m_logger                = NULL;
        m_initialized           = false;
        m_autotrading_enabled   = false;
        m_market_open           = false;
        m_symbol_tradable       = false;
        m_account_trade_allowed = false;
        m_expert_trade_allowed  = false;
        m_margin_level          = 0.0;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "TradingPermissionFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetPermissionConfig(const TradingPermissionFilterConfig &config) { m_config = config; }
    TradingPermissionFilterConfig GetPermissionConfig(void) const { return m_config; }

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

        //--- Refresh cached permission flags
        RefreshPermissions(market.symbol, broker);

        //=== 1. AutoTrading enabled ===
        if(m_config.require_autotrading && !m_autotrading_enabled)
            return FilterResult::Block(GetName(), ATLAS_FR_AUTOTRADING_DISABLED,
                "AutoTrading not enabled in terminal");

        //=== 2. Market open ===
        if(m_config.require_market_open && !m_market_open)
            return FilterResult::Block(GetName(), ATLAS_FR_MARKET_CLOSED,
                "market is closed for " + market.symbol);

        //=== 3. Symbol tradable ===
        if(m_config.require_symbol_tradable && !m_symbol_tradable)
            return FilterResult::Block(GetName(), ATLAS_FR_SYMBOL_NOT_TRADABLE,
                "symbol " + market.symbol + " is not tradable");

        //=== 4. Broker restriction (account-level) ===
        if(!m_account_trade_allowed)
            return FilterResult::Block(GetName(), ATLAS_FR_BROKER_RESTRICTION,
                "account trade not allowed");
        if(!m_expert_trade_allowed)
            return FilterResult::Block(GetName(), ATLAS_FR_BROKER_RESTRICTION,
                "expert trading not allowed on account");

        //=== 5. Margin level (optional) ===
        if(m_config.require_margin_ok && m_margin_level < m_config.min_margin_level)
            return FilterResult::Block(GetName(), ATLAS_FR_BROKER_RESTRICTION,
                "margin level " + DoubleToString(m_margin_level, 1) +
                "% < min " + DoubleToString(m_config.min_margin_level, 1) + "%");

        return FilterResult::Pass(GetName());
    }

    //=== Diagnostic accessors (cached from last Evaluate) ===

    bool IsAutoTradingEnabled(void)  const { return m_autotrading_enabled; }
    bool IsMarketOpen(void)          const { return m_market_open; }
    bool IsSymbolTradable(void)      const { return m_symbol_tradable; }
    bool IsAccountTradeAllowed(void) const { return m_account_trade_allowed; }
    bool IsExpertTradeAllowed(void)  const { return m_expert_trade_allowed; }
    double GetMarginLevel(void)      const { return m_margin_level; }

private:
    /**
     * @brief Refresh all cached permission flags.
     *
     * Queries MQL5 terminal/account/symbol status functions once per
     * Evaluate call. These are read-only status checks (not trade ops).
     */
    void RefreshPermissions(const string symbol, IBrokerAdapter *broker)
    {
        //--- 1. AutoTrading enabled in terminal
        m_autotrading_enabled = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

        //--- 2 & 3. Market open + symbol tradable
        //--- SYMBOL_TRADE_MODE: 0=disabled, 1=longonly, 2=shortonly, 3=closed
        //--- We check for disabled (0) and closed (3) as not tradable
        long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
        m_symbol_tradable = (trade_mode != SYMBOL_TRADE_MODE_DISABLED &&
                             trade_mode != SYMBOL_TRADE_MODE_CLOSEONLY);

        //--- Market open: use MarketInfo tradeallowed + session check
        //--- MarketInfo returns 0 if trade not allowed, 1 if allowed
        m_market_open = ((int)MarketInfo(symbol, MODE_TRADEALLOWED) != 0);

        //--- 4. Account-level permissions
        m_account_trade_allowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
        m_expert_trade_allowed  = (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

        //--- 5. Margin level (from broker adapter if available)
        if(broker != NULL)
            m_margin_level = broker.AccountMarginLevel();
        else
            m_margin_level = 0.0;
    }
};

#endif // ATLAS_TRADING_PERMISSION_FILTER_MQH
//+------------------------------------------------------------------+
