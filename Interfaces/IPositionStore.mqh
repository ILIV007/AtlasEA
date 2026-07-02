//+------------------------------------------------------------------+
//|                                    Interfaces/IPositionStore.mqh
//|                       AtlasEA v2.0 - Position Store Interface      |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPOSITION_STORE_MQH
#define ATLAS_IPOSITION_STORE_MQH

#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Position store interface.
 *
 * Implemented by TradeManager. Consumed by CoreEngine.
 * Maintains an internal mirror of broker positions and computes floating PnL.
 *
 * TradeManager never queries MT5 directly — it receives PositionSnapshotEvent
 * from IBrokerAdapter::QueryBrokerPositions().
 */
class IPositionStore
{
public:
    /// @brief Replace the internal position mirror with broker truth.
    virtual void ReconcilePositions(const PositionSnapshotEvent &snap) = 0;

    /// @brief Recompute floating PnL for all mirrored positions using current market state.
    virtual void UpdatePricesOnHeartbeat(const MarketState &state) = 0;

    /// @brief Process a fill event (update internal counters).
    virtual void ProcessFill(const ExecutionEvent &event) = 0;

    /// @brief Get all open positions (caller-allocated array).
    virtual void GetOpenPositions(PositionState &pos[], int &count) const = 0;

    /// @brief Initialize the position store.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the position store.
    virtual void Shutdown(void) = 0;

    virtual ~IPositionStore(void) {}
};

#endif // ATLAS_IPOSITION_STORE_MQH
//+------------------------------------------------------------------+
