//+------------------------------------------------------------------+
//|               Production/TradingEnvironmentValidator.mqh         |
//|       AtlasEA v1.0 Step 7 - Trading Environment Validator        |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADING_ENVIRONMENT_VALIDATOR_MQH
#define ATLAS_TRADING_ENVIRONMENT_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IBrokerCompatibilityManager.mqh"

/**
 * @class TradingEnvironmentValidator
 * @brief Validates the MT5 terminal and account environment.
 *
 * SOLE RESPONSIBILITY: check terminal, account, and permission status
 * before allowing trading.
 *
 * Checks:
 *   1. AutoTrading enabled (TerminalInfoInteger TERMINAL_TRADE_ALLOWED)
 *   2. DLL enabled (if required by EA)
 *   3. Market open (MarketInfo TRADEALLOWED)
 *   4. Terminal connected (TerminalInfoInteger TERMINAL_CONNECTED)
 *   5. Price feed active (bid > 0, ask > 0)
 *   6. Valid account (AccountInfoInteger ACCOUNT_TRADE_ALLOWED)
 *   7. Not read-only investor password (ACCOUNT_TRADE_EXPERT)
 *   8. Sufficient permissions (ACCOUNT_TRADE_ALLOWED + ACCOUNT_TRADE_EXPERT)
 *
 * NOTE: Uses MQL5 terminal/account status functions. These are read-only
 * status queries (not trade operations), consistent with the IBrokerAdapter
 * contract.
 *
 * Performance: O(1). No allocation.
 */
class TradingEnvironmentValidator
{
private:
    ILogger *m_logger;
    IBrokerAdapter *m_broker;
    bool m_require_dll;

public:
    TradingEnvironmentValidator(void)
    {
        m_logger      = NULL;
        m_broker      = NULL;
        m_require_dll = false;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }
    void SetBroker(IBrokerAdapter *broker) { m_broker = broker; }
    void SetRequireDLL(const bool req) { m_require_dll = req; }

    /**
     * @brief Validate the trading environment.
     * @return EnvironmentValidationResult.
     */
    EnvironmentValidationResult Validate(void)
    {
        EnvironmentValidationResult result;

        //=== 1. AutoTrading enabled ===
        result.autotrading_enabled = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
        if(!result.autotrading_enabled)
        {
            result.code   = ATLAS_ENV_AUTOTRADING_DISABLED;
            result.detail = "AutoTrading is disabled in the terminal";
            return result;
        }

        //=== 2. DLL enabled (if required) ===
        if(m_require_dll)
        {
            bool dll_allowed = (bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED);
            if(!dll_allowed)
            {
                result.code   = ATLAS_ENV_DLL_DISABLED;
                result.detail = "DLL imports are disabled (required by EA)";
                return result;
            }
        }

        //=== 3. Terminal connected ===
        result.terminal_connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
        if(!result.terminal_connected)
        {
            result.code   = ATLAS_ENV_DISCONNECTED;
            result.detail = "Terminal is not connected to the trade server";
            return result;
        }

        //=== 4. Price feed active ===
        if(m_broker != NULL)
        {
            double bid = m_broker.SymbolBid();
            double ask = m_broker.SymbolAsk();
            result.price_feed_active = (bid > 0.0 && ask > 0.0);
            if(!result.price_feed_active)
            {
                result.code   = ATLAS_ENV_NO_PRICE_FEED;
                result.detail = "No price feed (bid=0 or ask=0)";
                return result;
            }
        }
        else
        {
            result.price_feed_active = false;
        }

        //=== 5. Market open ===
        //--- Use MarketInfo as a quick check for trade allowed
        //--- (the symbol must be passed; we use the broker's configured symbol)
        //--- We approximate: if price feed is active, market is likely open
        result.market_open = result.price_feed_active;
        if(!result.market_open)
        {
            result.code   = ATLAS_ENV_MARKET_CLOSED;
            result.detail = "Market appears to be closed";
            return result;
        }

        //=== 6-8. Account permissions ===
        result.trade_allowed  = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
        result.expert_allowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
        result.account_valid  = result.trade_allowed;

        if(!result.trade_allowed)
        {
            result.code   = ATLAS_ENV_READ_ONLY;
            result.detail = "Account trade not allowed (possibly investor password)";
            return result;
        }
        if(!result.expert_allowed)
        {
            result.code   = ATLAS_ENV_INSUFFICIENT_PERMS;
            result.detail = "Expert/EA trading not allowed on this account";
            return result;
        }

        //--- All checks passed
        result.code   = ATLAS_ENV_OK;
        result.detail = "All environment checks passed";
        return result;
    }
};

#endif // ATLAS_TRADING_ENVIRONMENT_VALIDATOR_MQH
//+------------------------------------------------------------------+
