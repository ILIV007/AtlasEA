//+------------------------------------------------------------------+
//|                                       Interfaces/IStateStore.mqh
//|                        AtlasEA v2.0 - State Store Interface        |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISTATE_STORE_MQH
#define ATLAS_ISTATE_STORE_MQH

#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"

/**
 * @brief State persistence interface.
 *
 * Implemented by PersistenceManager. Consumed by CoreEngine.
 * Writes context snapshots and event logs, and recovers state on startup.
 *
 * PersistenceManager owns all file I/O — no other module touches the filesystem.
 * Uses BinarySerializer internally (introduced in a later phase).
 */
class IStateStore
{
public:
    /**
     * @brief Write a context snapshot to persistent storage.
     * @param ctx The context to serialize.
     * @param id  Snapshot ID for filename / correlation.
     * @return true on success, false on I/O failure.
     */
    virtual bool WriteSnapshot(const AtlasContext &ctx, const long id) = 0;

    /// @brief Append an event to the rolling event log (buffered).
    virtual bool AppendEvent(const AtlasEvent &ev) = 0;

    /// @brief Flush the event log buffer to disk.
    virtual bool FlushEventBuffer(void) = 0;

    /**
     * @brief Recover context state from persistent storage.
     * @param ctx The context to populate from the latest snapshot.
     * @return true if a snapshot was found and loaded, false otherwise.
     */
    virtual bool RecoverState(AtlasContext &ctx) = 0;

    /// @brief Initialize the state store.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the state store (flushes buffers).
    virtual void Shutdown(void) = 0;

    virtual ~IStateStore(void) {}
};

#endif // ATLAS_ISTATE_STORE_MQH
//+------------------------------------------------------------------+
