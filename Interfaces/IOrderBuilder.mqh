//+------------------------------------------------------------------+
//|                                      Interfaces/IOrderBuilder.mqh
//|                         AtlasEA v2.0 - Order Builder Interface     |
//+------------------------------------------------------------------+
#ifndef ATLAS_IORDER_BUILDER_MQH
#define ATLAS_IORDER_BUILDER_MQH

#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Order request builder interface.
 *
 * Implemented by ExecutionEngine. Consumed by CoreEngine (PhaseScheduler).
 * Transforms an approved RiskDecision + MarketState into a validated OrderRequest.
 *
 * Responsibilities:
 *   - Validate the RiskDecision (status, volume, direction, prices)
 *   - Enforce idempotency (decision_id dedup via IContextStore)
 *   - Normalize volume to broker step/min/max
 *   - Enforce SL/TP stops-level distance
 */
class IOrderBuilder
{
public:
    /**
     * @brief Build a validated OrderRequest from an approved RiskDecision.
     * @param decision  Approved risk decision (status must be ATLAS_DECISION_APPROVED).
     * @param state     Current market state (for current bid/ask).
     * @param req       Output: fully populated OrderRequest.
     * @return true if the request was built successfully, false on validation failure.
     */
    virtual bool BuildOrderRequest(const RiskDecision &decision,
                                   const MarketState &state,
                                   OrderRequest &req) = 0;

    /// @brief Initialize the order builder.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the order builder.
    virtual void Shutdown(void) = 0;

    virtual ~IOrderBuilder(void) {}
};

#endif // ATLAS_IORDER_BUILDER_MQH
//+------------------------------------------------------------------+
