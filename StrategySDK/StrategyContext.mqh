//+------------------------------------------------------------------+
//|                  StrategySDK/StrategyContext.mqh                |
//|       AtlasEA v0.1.17.0 - Read-Only Strategy Context             |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_CONTEXT_SDK_MQH
#define ATLAS_STRATEGY_CONTEXT_SDK_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct RiskContext
 * @brief Read-only risk context for strategies.
 * Strategies can read risk state but cannot modify it.
 */
struct RiskContext
{
    double daily_drawdown_pct;
    double floating_drawdown_pct;
    double current_exposure_pct;
    int    consecutive_losses;
    bool   kill_switch_active;
    int    daily_trade_count;

    RiskContext(void)
    {
        daily_drawdown_pct  = 0.0;
        floating_drawdown_pct = 0.0;
        current_exposure_pct = 0.0;
        consecutive_losses  = 0;
        kill_switch_active  = false;
        daily_trade_count   = 0;
    }
};

/**
 * @struct PositionContext
 * @brief Read-only position context for strategies.
 * Strategies can see open positions but cannot modify them.
 */
struct PositionContext
{
    int    open_count;
    double total_volume;
    double total_floating_pnl;
    double net_direction;  ///< +1 = long, -1 = short, 0 = flat

    PositionContext(void)
    {
        open_count         = 0;
        total_volume       = 0.0;
        total_floating_pnl = 0.0;
        net_direction      = 0.0;
    }
};

/**
 * @struct AccountContext
 * @brief Read-only account context for strategies.
 */
struct AccountContext
{
    double balance;
    double equity;
    double free_margin;
    double leverage;

    AccountContext(void)
    {
        balance     = 0.0;
        equity      = 0.0;
        free_margin = 0.0;
        leverage    = 100.0;
    }
};

/**
 * @class StrategyContext
 * @brief Read-only context passed to every strategy plugin.
 *
 * Contains:
 *   - MarketState (immutable snapshot)
 *   - AtlasConfig (EA configuration)
 *   - RiskContext (read-only risk state)
 *   - PositionContext (read-only position summary)
 *   - AccountContext (read-only account summary)
 *   - ILogger (for optional strategy logging)
 *   - Snapshot ID
 *
 * Does NOT contain:
 *   - IBrokerAdapter (no broker access)
 *   - IEventBus (no event emission)
 *   - IContextStore (no context mutation)
 *   - Other plugins
 *
 * This enforces isolation: a strategy can only read data and return
 * a StrategyResult. It cannot influence the system outside of that.
 */
class StrategyContext
{
private:
    const MarketState   *m_market;
    const AtlasConfig   *m_config;
    RiskContext          m_risk;
    PositionContext      m_positions;
    AccountContext       m_account;
    ILogger             *m_logger;
    long                 m_snapshot_id;

public:
    /**
     * @brief Default constructor — creates an empty context.
     */
    StrategyContext(void)
    {
        m_market       = NULL;
        m_config       = NULL;
        m_logger       = NULL;
        m_snapshot_id  = 0;
    }

    /**
     * @brief Construct a full context.
     */
    StrategyContext(const MarketState *market,
                    const AtlasConfig *config,
                    const RiskContext &risk,
                    const PositionContext &positions,
                    const AccountContext &account,
                    ILogger *logger,
                    const long snapshot_id)
    {
        m_market      = market;
        m_config      = config;
        m_risk        = risk;
        m_positions   = positions;
        m_account     = account;
        m_logger      = logger;
        m_snapshot_id = snapshot_id;
    }

    //=== Read-only accessors ===

    /// @brief Get the market state.
    const MarketState& GetMarketState(void) const { return *m_market; }

    /// @brief Get the EA configuration.
    const AtlasConfig& GetConfig(void) const { return *m_config; }

    /// @brief Get the risk context.
    const RiskContext& GetRiskContext(void) const { return m_risk; }

    /// @brief Get the position context.
    const PositionContext& GetPositionContext(void) const { return m_positions; }

    /// @brief Get the account context.
    const AccountContext& GetAccountContext(void) const { return m_account; }

    /// @brief Get the logger (may be NULL — always check).
    ILogger *GetLogger(void) const { return m_logger; }

    /// @brief Get the current snapshot ID.
    long GetSnapshotId(void) const { return m_snapshot_id; }

    //=== Validity ===

    /// @brief Check if the context is valid.
    bool IsValid(void) const
    {
        return (m_market != NULL && m_config != NULL);
    }

    /// @brief Check if the market state is valid.
    bool IsMarketValid(void) const
    {
        if(m_market == NULL) return false;
        return m_market.is_valid;
    }

    //=== Convenience accessors ===

    /// @brief Get mid price.
    double GetMidPrice(void) const
    {
        if(m_market == NULL) return 0.0;
        return (m_market.bid + m_market.ask) / 2.0;
    }

    /// @brief Get ATR.
    double GetATR(void) const
    {
        if(m_market == NULL) return 0.0;
        return m_market.atr_14;
    }

    /// @brief Get a feature by index.
    double GetFeature(const int index) const
    {
        if(m_market == NULL) return 0.0;
        if(index < 0 || index >= ATLAS_FEATURE_SIZE) return 0.0;
        return m_market.features[index];
    }

    /// @brief Get trend direction.
    int GetTrendDirection(void) const
    {
        if(m_market == NULL) return 0;
        return m_market.trend_direction;
    }

    /// @brief Get session state.
    int GetSession(void) const
    {
        if(m_market == NULL) return 0;
        return m_market.session_state;
    }

    /// @brief Check if kill switch is active.
    bool IsKillSwitchActive(void) const { return m_risk.kill_switch_active; }
};

#endif // ATLAS_STRATEGY_CONTEXT_SDK_MQH
//+------------------------------------------------------------------+
