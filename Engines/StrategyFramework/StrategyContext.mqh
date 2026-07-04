//+------------------------------------------------------------------+
//|           Engines/StrategyFramework/StrategyContext.mqh          |
//|       AtlasEA v0.1.10.0 - Read-Only Strategy Context             |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_CONTEXT_MQH
#define ATLAS_STRATEGY_CONTEXT_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @class StrategyContext
 * @brief Read-only context passed to every strategy during Evaluate().
 *
 * Contains ONLY:
 *   - MarketState (immutable snapshot)
 *   - AtlasConfig (EA configuration)
 *   - ILogger (for optional strategy logging — discouraged in hot path)
 *   - Snapshot ID (correlation)
 *
 * Does NOT contain:
 *   - PositionState (strategies must not know about open positions)
 *   - RiskState (strategies must not know about risk metrics)
 *   - Broker access (no IBrokerAdapter)
 *   - Account info (no equity, balance, margin)
 *   - Event bus (strategies cannot emit events)
 *
 * This enforces isolation: a strategy can only read market data and config.
 * It cannot influence the system outside of returning a StrategyVote.
 */
class StrategyContext
{
private:
    const MarketState *m_state;       ///< Pointer to immutable market state
    const AtlasConfig *m_config;      ///< Pointer to EA configuration
    ILogger           *m_logger;      ///< Logger (may be NULL)
    long               m_snapshot_id; ///< Current snapshot ID

public:
    /**
     * @brief Default constructor — creates an empty context.
     */
    StrategyContext(void)
    {
        m_state       = NULL;
        m_config      = NULL;
        m_logger      = NULL;
        m_snapshot_id = 0;
    }

    /**
     * @brief Construct a context from its components.
     * @param state       Pointer to the market state (must outlive the context).
     * @param config      Pointer to the config (must outlive the context).
     * @param logger      Logger pointer (may be NULL).
     * @param snapshot_id Current snapshot ID.
     */
    StrategyContext(const MarketState *state, const AtlasConfig *config,
                    ILogger *logger, const long snapshot_id)
    {
        m_state       = state;
        m_config      = config;
        m_logger      = logger;
        m_snapshot_id = snapshot_id;
    }

    //=== Read-only accessors ===

    /**
     * @brief Get the market state.
     * @return Const reference to the MarketState.
     *
     * Caller must check IsValid() first. If the context was constructed
     * with a NULL state pointer, calling GetMarketState() is undefined.
     */
    const MarketState& GetMarketState(void) const { return *m_state; }

    /**
     * @brief Get the EA configuration.
     * @return Const reference to the AtlasConfig.
     */
    const AtlasConfig& GetConfig(void) const { return *m_config; }

    /**
     * @brief Get the logger.
     * @return Logger pointer (may be NULL — always check).
     */
    ILogger *GetLogger(void) const { return m_logger; }

    /**
     * @brief Get the current snapshot ID.
     */
    long GetSnapshotId(void) const { return m_snapshot_id; }

    //=== Validity ===

    /**
     * @brief Check if the context is valid (state + config non-NULL).
     * @return true if both state and config pointers are set.
     */
    bool IsValid(void) const
    {
        return (m_state != NULL && m_config != NULL);
    }

    /**
     * @brief Check if the market state is valid.
     * @return true if state is non-NULL and state.is_valid is true.
     */
    bool IsMarketValid(void) const
    {
        if(m_state == NULL) return false;
        return m_state.is_valid;
    }

    //=== Convenience accessors for common market state fields ===

    /**
     * @brief Get the mid price (bid + ask) / 2.
     * @return Mid price, or 0.0 if state is NULL.
     */
    double GetMidPrice(void) const
    {
        if(m_state == NULL) return 0.0;
        return (m_state.bid + m_state.ask) / 2.0;
    }

    /**
     * @brief Get the current ATR(14).
     */
    double GetATR(void) const
    {
        if(m_state == NULL) return 0.0;
        return m_state.atr_14;
    }

    /**
     * @brief Get a feature by index.
     * @param index Feature index (0..ATLAS_FEATURE_SIZE-1).
     * @return Feature value, or 0.0 if out of range.
     */
    double GetFeature(const int index) const
    {
        if(m_state == NULL) return 0.0;
        if(index < 0 || index >= ATLAS_FEATURE_SIZE) return 0.0;
        return m_state.features[index];
    }

    /**
     * @brief Get the current session state.
     */
    int GetSession(void) const
    {
        if(m_state == NULL) return 0;
        return m_state.session_state;
    }

    /**
     * @brief Get the trend direction (-1, 0, 1).
     */
    int GetTrendDirection(void) const
    {
        if(m_state == NULL) return 0;
        return m_state.trend_direction;
    }

    /**
     * @brief Get the trend strength (0..100).
     */
    int GetTrendStrength(void) const
    {
        if(m_state == NULL) return 0;
        return m_state.trend_strength;
    }
};

#endif // ATLAS_STRATEGY_CONTEXT_MQH
//+------------------------------------------------------------------+
