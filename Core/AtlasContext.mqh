//+------------------------------------------------------------------+
//|                                            Core/AtlasContext.mqh |
//|                  AtlasEA v1.0 - Shared Mutable Context State     |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONTEXT_MQH
#define ATLAS_CONTEXT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

//+------------------------------------------------------------------+
//| AtlasContext - the single mutable shared state of the EA.        |
//| All writes go through ContextGuardian (single-writer rule).      |
//+------------------------------------------------------------------+
class AtlasContext
{
public:
    //--- Identity / time
    long     current_snapshot_id;
    datetime current_tick_time;
    datetime trading_day_start;

    //--- Daily risk stats
    double   daily_start_equity;
    double   daily_peak_equity;
    double   daily_drawdown_pct;
    double   daily_realized_pnl;
    int      daily_trade_count;
    int      daily_loss_count;

    //--- Exposure
    double   current_exposure_pct;
    double   total_floating_pnl;

    //--- Kill switch (non-bypassable once triggered)
    bool     kill_switch_active;
    string   kill_switch_reason;
    datetime kill_switch_time;

    //--- Risk state
    int      consecutive_losses;
    datetime last_trade_time;
    datetime cooldown_until;

    //--- Position mirror
    PositionState positions[ATLAS_MAX_POSITIONS];
    int           position_count;

    //--- Telemetry
    ulong    total_ticks_processed;
    ulong    total_events_emitted;
    ulong    total_orders_sent;
    ulong    total_orders_filled;

    //--- ContextGuardian ownership
    int      current_writer_module;
    int      current_writer_contract;

    //--- Idempotency ring (decision_id dedup)
    string   processed_decisions[32];
    int      processed_count;

    AtlasContext() { Reset(); }

    //+--------------------------------------------------------------+
    void Reset(void)
    {
        current_snapshot_id       = 0;
        current_tick_time         = 0;
        trading_day_start         = 0;

        daily_start_equity        = 0;
        daily_peak_equity         = 0;
        daily_drawdown_pct        = 0;
        daily_realized_pnl        = 0;
        daily_trade_count         = 0;
        daily_loss_count          = 0;

        current_exposure_pct      = 0;
        total_floating_pnl        = 0;

        kill_switch_active        = false;
        kill_switch_reason        = "";
        kill_switch_time          = 0;

        consecutive_losses        = 0;
        last_trade_time           = 0;
        cooldown_until            = 0;

        position_count            = 0;

        total_ticks_processed     = 0;
        total_events_emitted      = 0;
        total_orders_sent         = 0;
        total_orders_filled       = 0;

        current_writer_module     = 0;
        current_writer_contract   = 0;

        processed_count           = 0;
    }

    //+--------------------------------------------------------------+
    bool IsDecisionProcessed(const string decision_id) const
    {
        for(int i = 0; i < processed_count; i++)
            if(processed_decisions[i] == decision_id)
                return true;
        return false;
    }

    //+--------------------------------------------------------------+
    void MarkDecisionProcessed(const string decision_id)
    {
        if(IsDecisionProcessed(decision_id))
            return;
        if(processed_count >= 32)
        {
            for(int i = 1; i < 32; i++)
                processed_decisions[i-1] = processed_decisions[i];
            processed_count = 31;
        }
        processed_decisions[processed_count] = decision_id;
        processed_count++;
    }
};

#endif // ATLAS_CONTEXT_MQH
//+------------------------------------------------------------------+
