//+------------------------------------------------------------------+
//|                                   Core/KillSwitchPropagator.mqh
//|             AtlasEA v2.0 - Kill Switch Propagation                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_KILL_SWITCH_PROPAGATOR_MQH
#define ATLAS_KILL_SWITCH_PROPAGATOR_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Interfaces/IEventBus.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class KillSwitchPropagator
 * @brief Broadcasts kill-switch activation and deactivation across the system.
 *
 * When the kill switch is triggered:
 *   1. Activates the kill switch on the context (non-bypassable flag).
 *   2. Emits EV_KILL_SWITCH_ACTIVATED as a PRIORITY event.
 *   3. All subsequent RiskEngine::EvaluateRisk calls return REJECTED.
 *
 * On new trading day:
 *   1. Deactivates the kill switch (operator must explicitly re-enable).
 *   2. Emits a normal event (system recovered).
 *
 * This class does NOT close positions — that is delegated to IBrokerAdapter.
 */
class KillSwitchPropagator
{
private:
    IEventBus    *m_event_bus;   ///< Event bus for broadcasting
    IContextStore *m_context;    ///< Context (owns kill-switch flag)
    ILogger       *m_logger;     ///< Logger

public:
    /**
     * @brief Constructor.
     */
    KillSwitchPropagator(void);

    /**
     * @brief Initialize the propagator.
     * @param bus     Event bus.
     * @param context Context store.
     * @param logger  Logger.
     */
    void Initialize(IEventBus *bus, IContextStore *context, ILogger *logger);

    /**
     * @brief Activate the kill switch and broadcast.
     * @param reason  Human-readable reason.
     * @param snapshot_id Current snapshot ID for correlation.
     */
    void Activate(const string reason, const long snapshot_id);

    /**
     * @brief Deactivate the kill switch (new trading day or manual reset).
     * @param snapshot_id Current snapshot ID.
     */
    void Deactivate(const long snapshot_id);

    /**
     * @brief Check if the kill switch is currently active.
     */
    bool IsActive(void) const;

    /**
     * @brief Get the reason for the current activation.
     */
    string GetReason(void) const;

    /**
     * @brief Build a kill-switch activation event.
     * @param snapshot_id Current snapshot ID.
     * @param reason      Activation reason.
     * @return A populated AtlasEvent of type EV_KILL_SWITCH_ACTIVATED.
     */
    AtlasEvent BuildActivationEvent(const long snapshot_id, const string reason) const;
};

//+------------------------------------------------------------------+
//| KillSwitchPropagator implementation                               |
//+------------------------------------------------------------------+

KillSwitchPropagator::KillSwitchPropagator(void)
{
    m_event_bus = NULL;
    m_context   = NULL;
    m_logger    = NULL;
}

//+------------------------------------------------------------------+
void KillSwitchPropagator::Initialize(IEventBus *bus, IContextStore *context, ILogger *logger)
{
    m_event_bus = bus;
    m_context   = context;
    m_logger    = logger;
}

//+------------------------------------------------------------------+
void KillSwitchPropagator::Activate(const string reason, const long snapshot_id)
{
    if(m_context == NULL) return;
    if(m_context.IsKillSwitchActive())
    {
        if(m_logger != NULL)
            m_logger.Debug("KillSwitchPropagator", "Already active: " + reason);
        return;
    }

    m_context.ActivateKillSwitch(reason);

    if(m_logger != NULL)
        m_logger.Fatal("KillSwitchPropagator", "*** KILL SWITCH ACTIVATED *** " + reason);

    if(m_event_bus != NULL)
    {
        AtlasEvent ev = BuildActivationEvent(snapshot_id, reason);
        m_event_bus.EmitPriorityEvent(ev);
    }
}

//+------------------------------------------------------------------+
void KillSwitchPropagator::Deactivate(const long snapshot_id)
{
    if(m_context == NULL) return;
    if(!m_context.IsKillSwitchActive()) return;

    string prev_reason = m_context.GetKillSwitchReason();
    m_context.DeactivateKillSwitch();

    if(m_logger != NULL)
        m_logger.Info("KillSwitchPropagator", "Kill switch deactivated (was: " + prev_reason + ")");

    if(m_event_bus != NULL)
    {
        AtlasEvent ev;
        ev.type          = EV_HEARTBEAT;
        ev.source_module = "KillSwitchPropagator";
        ev.timestamp     = TimeCurrent();
        ev.snapshot_id   = snapshot_id;
        ev.payload_size  = 0;
        m_event_bus.EmitEvent(ev);
    }
}

//+------------------------------------------------------------------+
bool KillSwitchPropagator::IsActive(void) const
{
    if(m_context == NULL) return false;
    return m_context.IsKillSwitchActive();
}

//+------------------------------------------------------------------+
string KillSwitchPropagator::GetReason(void) const
{
    if(m_context == NULL) return "";
    return m_context.GetKillSwitchReason();
}

//+------------------------------------------------------------------+
AtlasEvent KillSwitchPropagator::BuildActivationEvent(const long snapshot_id, const string reason) const
{
    AtlasEvent ev;
    ev.type          = EV_KILL_SWITCH_ACTIVATED;
    ev.source_module = "KillSwitchPropagator";
    ev.timestamp     = TimeCurrent();
    ev.snapshot_id   = snapshot_id;
    ev.payload_size  = 0;
    return ev;
}

#endif // ATLAS_KILL_SWITCH_PROPAGATOR_MQH
//+------------------------------------------------------------------+
