//+------------------------------------------------------------------+
//|                                            Interfaces/IEventBus.mqh
//|                            AtlasEA v2.0 - Event Bus Interface     |
//+------------------------------------------------------------------+
#ifndef ATLAS_IEVENT_BUS_MQH
#define ATLAS_IEVENT_BUS_MQH

#include "../Contracts/Events.mqh"

/**
 * @brief Abstract event bus interface.
 *
 * Implemented by CoreEngine. Consumed by any module that needs to
 * emit events onto the central queue (MT5Adapter, TradeManager, etc.).
 *
 * Thread model: MQL5 single-threaded — no synchronization needed.
 * Allocation: implementations must NOT allocate on the hot path.
 */
class IEventBus
{
public:
    /**
     * @brief Emit a normal-priority event onto the queue.
     * @param event Const reference to the event envelope. Copied into the ring buffer.
     */
    virtual void EmitEvent(const AtlasEvent &event) = 0;

    /**
     * @brief Emit a high-priority event (processed before normal events).
     * @param event Const reference to the event envelope.
     */
    virtual void EmitPriorityEvent(const AtlasEvent &event) = 0;

    virtual ~IEventBus(void) {}
};

#endif // ATLAS_IEVENT_BUS_MQH
//+------------------------------------------------------------------+
