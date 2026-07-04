//+------------------------------------------------------------------+
//|                    Strategy/StrategyContext.mqh                  |
//|       AtlasEA v0.1.20.0 - Read-Only Strategy Context             |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_CONTEXT_V2_MQH
#define ATLAS_STRATEGY_CONTEXT_V2_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct AccountSnapshot
 * @brief Read-only account state for strategies.
 */
struct AccountSnapshot
{
    double balance;
    double equity;
    double free_margin;
    double leverage;

    AccountSnapshot(void)
    {
        balance     = 0.0;
        equity      = 0.0;
        free_margin = 0.0;
        leverage    = 100.0;
    }
};

/**
 * @struct SymbolInfo
 * @brief Read-only symbol information for strategies.
 */
struct SymbolInfo
{
    string symbol;
    double point;
    int    digits;
    double bid;
    double ask;
    double volume_min;
    double volume_max;
    double volume_step;
    long   stops_level;
    double contract_size;

    SymbolInfo(void)
    {
        symbol       = "";
        point        = 0.00001;
        digits       = 5;
        bid          = 0.0;
        ask          = 0.0;
        volume_min   = 0.01;
        volume_max   = 100.0;
        volume_step  = 0.01;
        stops_level  = 10;
        contract_size = 100000.0;
    }
};

/**
 * @struct SessionInfo
 * @brief Read-only session state for strategies.
 */
struct SessionInfo
{
    int    session_state;     ///< ATLAS_SESSION_*
    bool   market_open;
    bool   weekend;

    SessionInfo(void)
    {
        session_state = 0;
        market_open   = true;
        weekend       = false;
    }
};

/**
 * @struct ClockSnapshot
 * @brief Read-only time information for strategies.
 */
struct ClockSnapshot
{
    datetime current_time;
    datetime bar_time;
    int      day_of_week;
    int      hour;
    int      minute;

    ClockSnapshot(void)
    {
        current_time = 0;
        bar_time     = 0;
        day_of_week  = 0;
        hour         = 0;
        minute       = 0;
    }
};

/**
 * @class StrategyContext
 * @brief Read-only context passed to every strategy.
 *
 * Contains ONLY:
 *   - MarketState (immutable snapshot)
 *   - AccountSnapshot (read-only)
 *   - SymbolInfo (read-only)
 *   - SessionInfo (read-only)
 *   - ClockSnapshot (read-only)
 *   - ILogger (optional, for diagnostics — discouraged in hot path)
 *
 * Does NOT contain:
 *   - IBrokerAdapter (no broker access)
 *   - IContextStore (no context mutation)
 *   - IEventBus (no event emission)
 *   - PositionState (no position visibility)
 *   - RiskState (no risk visibility)
 *   - Other strategies
 *
 * This enforces complete isolation: a strategy can only read market
 * data and return a StrategyVote.
 */
class StrategyContext
{
private:
    const MarketState   *m_market;
    const AccountSnapshot *m_account;
    const SymbolInfo    *m_symbol;
    const SessionInfo   *m_session;
    const ClockSnapshot *m_clock;
    ILogger             *m_logger;
    long                 m_snapshot_id;

public:
    /**
     * @brief Default constructor — empty context.
     */
    StrategyContext(void)
    {
        m_market      = NULL;
        m_account     = NULL;
        m_symbol      = NULL;
        m_session     = NULL;
        m_clock       = NULL;
        m_logger      = NULL;
        m_snapshot_id = 0;
    }

    /**
     * @brief Full constructor.
     */
    StrategyContext(const MarketState *market,
                    const AccountSnapshot *account,
                    const SymbolInfo *symbol,
                    const SessionInfo *session,
                    const ClockSnapshot *clock,
                    ILogger *logger,
                    const long snapshot_id)
    {
        m_market      = market;
        m_account     = account;
        m_symbol      = symbol;
        m_session     = session;
        m_clock       = clock;
        m_logger      = logger;
        m_snapshot_id = snapshot_id;
    }

    //=== Read-only accessors ===
    const MarketState&     GetMarketState(void)  const { return *m_market; }
    const AccountSnapshot& GetAccount(void)      const { return *m_account; }
    const SymbolInfo&      GetSymbolInfo(void)   const { return *m_symbol; }
    const SessionInfo&     GetSession(void)      const { return *m_session; }
    const ClockSnapshot&   GetClock(void)        const { return *m_clock; }
    ILogger*               GetLogger(void)       const { return m_logger; }
    long                   GetSnapshotId(void)   const { return m_snapshot_id; }

    //=== Validity ===
    bool IsValid(void) const { return (m_market != NULL); }

    //=== Convenience accessors ===
    double GetMidPrice(void) const
    {
        if(m_market == NULL) return 0.0;
        return (m_market.bid + m_market.ask) / 2.0;
    }

    double GetATR(void) const
    {
        if(m_market == NULL) return 0.0;
        return m_market.atr_14;
    }

    double GetFeature(const int index) const
    {
        if(m_market == NULL) return 0.0;
        if(index < 0 || index >= ATLAS_FEATURE_SIZE) return 0.0;
        return m_market.features[index];
    }

    int GetTrendDirection(void) const
    {
        if(m_market == NULL) return 0;
        return m_market.trend_direction;
    }

    int GetTrendStrength(void) const
    {
        if(m_market == NULL) return 0;
        return m_market.trend_strength;
    }

    int GetSessionState(void) const
    {
        if(m_session == NULL) return 0;
        return m_session.session_state;
    }

    datetime GetCurrentTime(void) const
    {
        if(m_clock == NULL) return 0;
        return m_clock.current_time;
    }

    bool IsMarketOpen(void) const
    {
        if(m_session == NULL) return true;
        return m_session.market_open;
    }
};

#endif // ATLAS_STRATEGY_CONTEXT_V2_MQH
//+------------------------------------------------------------------+
