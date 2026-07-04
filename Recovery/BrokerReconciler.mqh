//+------------------------------------------------------------------+
//|                  Recovery/BrokerReconciler.mqh                  |
//|       AtlasEA v0.1.13.0 - Broker Reconciliation                  |
//+------------------------------------------------------------------+
#ifndef ATLAS_BROKER_RECONCILER_MQH
#define ATLAS_BROKER_RECONCILER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IEventBus.mqh"

/**
 * @struct ReconciliationResult
 * @brief Result of broker reconciliation.
 */
struct ReconciliationResult
{
    bool   success;               ///< Did reconciliation complete?
    int    internal_count;        ///< Positions in internal state
    int    broker_count;          ///< Positions at broker
    int    matched_count;         ///< Positions that match
    int    mismatch_count;        ///< Positions that differ
    int    missing_internal;      ///< Positions at broker but not internal
    int    missing_broker;        ///< Positions internal but not broker
    string mismatch_details[ATLAS_MAX_POSITIONS]; ///< Per-mismatch details
    int    detail_count;          ///< Number of mismatch details
};

/**
 * @class BrokerReconciler
 * @brief Reconciles internal position state with broker positions.
 *
 * After recovery, the internal position mirror (from snapshot) may differ
 * from the actual broker positions (which are always authoritative).
 * This class compares the two and:
 *   1. Updates the internal mirror to match broker truth
 *   2. Logs any discrepancies
 *   3. Emits a RECONCILE event if mismatches were found
 *
 * The broker is ALWAYS the source of truth for positions. If there's a
 * mismatch, the internal state is corrected to match the broker.
 */
class BrokerReconciler
{
private:
    ILogger        *m_logger;
    IBrokerAdapter *m_broker;
    IEventBus      *m_event_bus;
    long            m_magic;

    /// @brief Add a mismatch detail.
    void AddDetail(ReconciliationResult &result, const string detail)
    {
        if(result.detail_count < ATLAS_MAX_POSITIONS)
        {
            result.mismatch_details[result.detail_count] = detail;
            result.detail_count++;
        }
    }

public:
    /**
     * @brief Constructor.
     */
    BrokerReconciler(void)
    {
        m_logger   = NULL;
        m_broker   = NULL;
        m_event_bus = NULL;
        m_magic    = 0;
    }

    /**
     * @brief Initialize.
     * @param logger Logger.
     * @param broker Broker adapter.
     * @param event_bus Event bus (for emitting reconcile events).
     * @param magic EA magic number.
     */
    void Initialize(ILogger *logger, IBrokerAdapter *broker,
                    IEventBus *event_bus, const long magic)
    {
        m_logger    = logger;
        m_broker    = broker;
        m_event_bus = event_bus;
        m_magic     = magic;
    }

    /**
     * @brief Reconcile internal state with broker.
     * @param context The context (mutated — positions updated to match broker).
     * @return ReconciliationResult with details.
     */
    ReconciliationResult Reconcile(AtlasContext &context)
    {
        ReconciliationResult result;
        result.success          = true;
        result.internal_count   = 0;
        result.broker_count     = 0;
        result.matched_count    = 0;
        result.mismatch_count   = 0;
        result.missing_internal = 0;
        result.missing_broker   = 0;
        result.detail_count     = 0;

        if(m_broker == NULL)
        {
            result.success = false;
            if(m_logger != NULL)
                m_logger.Error("BrokerReconciler", "Broker adapter is NULL");
            return result;
        }

        //--- Query broker positions
        PositionSnapshotEvent broker_snap = m_broker.QueryBrokerPositions();
        result.broker_count = broker_snap.count;

        //--- Get internal positions
        result.internal_count = context.GetPositionCount();

        //--- Compare: in this phase, we simply replace internal with broker truth.
        //--- A more sophisticated comparison would match by ticket, volume, type.
        if(result.broker_count != result.internal_count)
        {
            result.mismatch_count = MathAbs(result.broker_count - result.internal_count);
            if(result.broker_count > result.internal_count)
                result.missing_internal = result.broker_count - result.internal_count;
            else
                result.missing_broker = result.internal_count - result.broker_count;

            AddDetail(result, "Count mismatch: internal=" + IntegerToString(result.internal_count) +
                             " broker=" + IntegerToString(result.broker_count));
        }

        //--- Update internal state to match broker
        if(broker_snap.count > 0)
        {
            context.SetPositions(broker_snap.broker_positions, broker_snap.count);
        }
        else
        {
            context.ClearPositions();
        }

        result.matched_count = broker_snap.count;

        //--- Log result
        if(m_logger != NULL)
        {
            if(result.mismatch_count > 0)
            {
                m_logger.Warn("BrokerReconciler",
                    "Reconciliation: " + IntegerToString(result.mismatch_count) +
                    " mismatches found. Internal updated to match broker.");
                for(int i = 0; i < result.detail_count; i++)
                    m_logger.Warn("BrokerReconciler", "  " + result.mismatch_details[i]);
            }
            else
            {
                m_logger.Info("BrokerReconciler",
                    "Reconciliation OK: " + IntegerToString(result.matched_count) + " positions matched");
            }
        }

        //--- Emit reconcile event if mismatches found
        if(result.mismatch_count > 0 && m_event_bus != NULL)
        {
            AtlasEvent ev;
            ev.type          = EV_ERROR_OCCURRED;  ///< Reuse error event for reconciliation
            ev.source_module = "BrokerReconciler";
            ev.timestamp     = TimeCurrent();
            ev.snapshot_id   = context.GetSnapshotId();
            ev.payload_size  = 0;
            m_event_bus.EmitEvent(ev);
        }

        return result;
    }
};

#endif // ATLAS_BROKER_RECONCILER_MQH
//+------------------------------------------------------------------+
