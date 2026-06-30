//+------------------------------------------------------------------+
//|                                              Core/IEventBus.mqh  |
//|                            AtlasEA v1.0 - Event Bus Interface    |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_BUS_MQH
#define ATLAS_EVENT_BUS_MQH

#include "../Contracts/Events.mqh"

//+------------------------------------------------------------------+
//| IEventBus - abstract event bus implemented by CoreEngine         |
//+------------------------------------------------------------------+
class IEventBus
{
public:
    virtual void EmitEvent(const AtlasEvent &event)         = 0;
    virtual void EmitPriorityEvent(const AtlasEvent &event) = 0;
};

#endif // ATLAS_EVENT_BUS_MQH
//+------------------------------------------------------------------+
