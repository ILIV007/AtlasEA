//+------------------------------------------------------------------+
//|                                      Interfaces/IStrategySet.mqh
//|                         AtlasEA v2.0 - Strategy Set Interface      |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISTRATEGY_SET_MQH
#define ATLAS_ISTRATEGY_SET_MQH

#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Strategy evaluation interface.
 *
 * Implemented by StrategyEngine. Consumed by CoreEngine (PhaseScheduler).
 * Evaluates all registered strategies against a MarketState and produces votes.
 */
class IStrategySet
{
public:
    /**
     * @brief Evaluate all active strategies against the given market state.
     * @param state  Validated market state (caller must check is_valid).
     * @param votes  Output array (caller-allocated, capacity ATLAS_MAX_VOTES).
     * @return Number of non-empty votes written to the array (0..ATLAS_MAX_VOTES).
     */
    virtual int EvaluateStrategies(const MarketState &state, StrategyVote &votes[]) = 0;

    /// @brief Initialize the strategy set.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the strategy set.
    virtual void Shutdown(void) = 0;

    virtual ~IStrategySet(void) {}
};

#endif // ATLAS_ISTRATEGY_SET_MQH
//+------------------------------------------------------------------+
