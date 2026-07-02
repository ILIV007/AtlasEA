//+------------------------------------------------------------------+
//|                                   Interfaces/IMarketDataSource.mqh
//|                       AtlasEA v2.0 - Market Data Source Interface  |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMARKET_DATA_SOURCE_MQH
#define ATLAS_IMARKET_DATA_SOURCE_MQH

#include "../Contracts/MarketState.mqh"

/**
 * @brief Market data processing interface.
 *
 * Implemented by MarketEngine. Consumed by CoreEngine (PhaseScheduler).
 * Transforms a RawTick into an immutable MarketState with indicators + features.
 */
class IMarketDataSource
{
public:
    /**
     * @brief Process a raw tick and produce a MarketState snapshot.
     * @param tick        Validated raw tick from the broker adapter.
     * @param snapshot_id Monotonic snapshot ID assigned by SnapshotManager.
     * @return Fully populated MarketState (check is_valid before use).
     */
    virtual MarketState ProcessTick(const RawTick &tick, const long snapshot_id) = 0;

    /// @brief Initialize the market data source with config.
    virtual bool Initialize(void) = 0;

    /// @brief Release all indicator handles and resources.
    virtual void Shutdown(void) = 0;

    virtual ~IMarketDataSource(void) {}
};

#endif // ATLAS_IMARKET_DATA_SOURCE_MQH
//+------------------------------------------------------------------+
