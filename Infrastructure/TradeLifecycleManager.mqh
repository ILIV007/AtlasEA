//+------------------------------------------------------------------+
//|             Infrastructure/TradeLifecycleManager.mqh            |
//|       AtlasEA v1.0 Step 2 - Trade Lifecycle Manager              |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADE_LIFECYCLE_MANAGER_MQH
#define ATLAS_TRADE_LIFECYCLE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ITradeLifecycleManager.mqh"

/**
 * @class TradeLifecycleManager
 * @brief The ONLY component responsible for modifying existing positions.
 *
 * Implements ITradeLifecycleManager. Manages the entire lifecycle of
 * open positions: SL/TP updates, break-even, trailing stop, partial
 * close, profit lock, time-based exit, emergency exit, session/weekend
 * close.
 *
 * RESPONSIBILITIES (12 features):
 *   1. Stop Loss updates          — ModifyPositionSLTP
 *   2. Take Profit updates         — ModifyPositionSLTP
 *   3. Break Even                  — Move SL to entry + offset when triggered
 *   4. Trailing Stop (5 modes)     — Classic, ATR, Step, Dynamic, Volatility
 *   5. ATR Trailing                — ATR-based trailing distance
 *   6. Time-based Exit             — Max duration, max bars, session timeout
 *   7. Profit Lock                 — Lock profit at configurable RR levels
 *   8. Partial Close               — Single/multiple, % or lot based
 *   9. Scale Out                   — Progressive partial closes
 *  10. Emergency Exit              — Kill switch, max DD, broker disconnect
 *  11. Session Close Exit          — Close at configured session end
 *  12. Weekend Close               — Close before weekend
 *
 * CONTRACT:
 *   - NEVER opens new positions (only modifies/closes existing).
 *   - ExecutionEngine opens; TradeLifecycleManager manages.
 *   - TradeManager owns positions; this receives read-only snapshots.
 *   - Never moves stop backwards (trailing only tightens).
 *
 * PERFORMANCE:
 *   - O(number_of_positions) per ManagePositions call.
 *   - No heap allocation (all stack, fixed-size).
 *   - No recursion, no STL, no templates.
 *   - Cached symbol properties (point, digits, spread).
 *   - No unnecessary broker requests (only sends when SL/TP changes).
 *
 * Memory: ~2 KB (config + stats + per-position tracking).
 */
class TradeLifecycleManager : public ITradeLifecycleManager
{
private:
    ILogger             *m_logger;
    AtlasConfig          m_config;
    TradeLifecycleStats  m_stats;
    bool                 m_initialized;

    //--- Cached symbol properties (refreshed per ManagePositions call)
    double m_point;
    int    m_digits;
    double m_bid;
    double m_ask;
    double m_spread;
    double m_atr;
    double m_tick_value;
    double m_tick_size;
    double m_contract_size;
    double m_vol_min;
    double m_vol_max;
    double m_vol_step;

    //--- Per-position tracking (fixed-size, indexed by position_id hash)
    struct PositionTrack
    {
        string position_id;             ///< Position ticket
        bool   breakeven_activated;     ///< Has BE been applied?
        double best_sl;                 ///< Best SL applied so far (trailing never moves backwards)
        int    partials_executed;       ///< Number of partial closes done
        bool   profit_lock_done[4];     ///< Which profit lock levels are done
        datetime last_manage_time;      ///< Last management time

        PositionTrack(void)
        {
            position_id        = "";
            breakeven_activated = false;
            best_sl            = 0.0;
            partials_executed  = 0;
            last_manage_time   = 0;
            for(int i = 0; i < 4; i++) profit_lock_done[i] = false;
        }
    };

    #define ATLAS_TLM_MAX_TRACKED 64
    PositionTrack m_tracks[ATLAS_TLM_MAX_TRACKED];
    int           m_track_count;

    /**
     * @brief Find or create a tracking entry for a position.
     */
    PositionTrack* GetTrack(const string position_id)
    {
        //--- Find existing
        for(int i = 0; i < m_track_count; i++)
            if(m_tracks[i].position_id == position_id)
                return &m_tracks[i];

        //--- Create new (if space)
        if(m_track_count >= ATLAS_TLM_MAX_TRACKED) return NULL;
        m_tracks[m_track_count].position_id = position_id;
        m_tracks[m_track_count].breakeven_activated = false;
        m_tracks[m_track_count].best_sl = 0.0;
        m_tracks[m_track_count].partials_executed = 0;
        m_tracks[m_track_count].last_manage_time = 0;
        for(int i = 0; i < 4; i++) m_tracks[m_track_count].profit_lock_done[i] = false;
        m_track_count++;
        return &m_tracks[m_track_count - 1];
    }

    /**
     * @brief Remove a tracking entry (when position is closed).
     */
    void RemoveTrack(const string position_id)
    {
        for(int i = 0; i < m_track_count; i++)
        {
            if(m_tracks[i].position_id == position_id)
            {
                //--- Shift left
                for(int j = i + 1; j < m_track_count; j++)
                    m_tracks[j - 1] = m_tracks[j];
                m_track_count--;
                return;
            }
        }
    }

    /**
     * @brief Refresh cached symbol/market properties.
     */
    void RefreshCache(const MarketState &market, IBrokerAdapter *broker)
    {
        m_point        = market.point;
        m_digits       = market.digits;
        m_bid          = market.bid;
        m_ask          = market.ask;
        m_spread       = market.spread;
        m_atr          = market.atr_14;
        m_tick_value   = (broker != NULL) ? broker.SymbolTickValue() : 0.0;
        m_tick_size    = (broker != NULL) ? broker.SymbolTickSize() : 0.0;
        m_contract_size = (broker != NULL) ? broker.SymbolContractSize() : 100000.0;
        m_vol_min      = (broker != NULL) ? broker.SymbolVolumeMin() : 0.01;
        m_vol_max      = (broker != NULL) ? broker.SymbolVolumeMax() : 100.0;
        m_vol_step     = (broker != NULL) ? broker.SymbolVolumeStep() : 0.01;
    }

    /**
     * @brief Compute the current R:R ratio for a position.
     *
     * RR = current_profit / initial_risk
     * initial_risk = |entry - SL_initial|
     * current_profit = |current_price - entry| (in direction of trade)
     */
    double ComputeRR(const PositionState &pos) const
    {
        if(pos.current_sl <= 0.0 || pos.open_price <= 0.0) return 0.0;
        double risk = MathAbs(pos.open_price - pos.current_sl);
        if(risk <= 0.0) return 0.0;
        double profit = 0.0;
        if(pos.type == POSITION_TYPE_BUY)
            profit = m_bid - pos.open_price;
        else
            profit = pos.open_price - m_ask;
        return profit / risk;
    }

    /**
     * @brief Compute profit in points.
     */
    double ComputeProfitPoints(const PositionState &pos) const
    {
        if(m_point <= 0.0) return 0.0;
        double profit = 0.0;
        if(pos.type == POSITION_TYPE_BUY)
            profit = m_bid - pos.open_price;
        else
            profit = pos.open_price - m_ask;
        return profit / m_point;
    }

    /**
     * @brief Normalize a price to symbol digits.
     */
    double NormalizePrice(const double price) const
    {
        return NormalizeDouble(price, m_digits);
    }

    /**
     * @brief Normalize a volume to broker step.
     */
    double NormalizeVolume(const double vol) const
    {
        double step = (m_vol_step > 0.0) ? m_vol_step : 0.01;
        double v = MathRound(vol / step) * step;
        if(v < m_vol_min) v = m_vol_min;
        if(v > m_vol_max) v = m_vol_max;
        return NormalizeDouble(v, 2);
    }

    /**
     * @brief Check if a new SL is better (tighter) than the current SL.
     * Never move stop backwards.
     */
    bool IsBetterSL(const PositionState &pos, const double new_sl) const
    {
        if(new_sl <= 0.0) return false;
        if(pos.type == POSITION_TYPE_BUY)
            return new_sl > pos.current_sl;  // BUY: higher SL is better
        else
            return new_sl < pos.current_sl;  // SELL: lower SL is better
    }

public:
    /**
     * @brief Constructor.
     */
    TradeLifecycleManager(void)
    {
        m_logger      = NULL;
        m_initialized = false;
        m_track_count = 0;
        m_point = 0.0; m_digits = 5; m_bid = 0.0; m_ask = 0.0;
        m_spread = 0.0; m_atr = 0.0; m_tick_value = 0.0; m_tick_size = 0.0;
        m_contract_size = 100000.0; m_vol_min = 0.01; m_vol_max = 100.0; m_vol_step = 0.01;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const AtlasConfig &config) { m_config = config; }

    //=== ITradeLifecycleManager implementation ===

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("TradeLifecycleManager",
            "Initialized. Trailing=" + (m_config.tcm_enable_trailing ? "ON" : "OFF") +
            " BE=" + (m_config.tcm_enable_breakeven ? "ON" : "OFF") +
            " Partial=" + (m_config.tcm_enable_partial_close ? "ON" : "OFF") +
            " ProfitLock=" + (m_config.tcm_enable_profit_lock ? "ON" : "OFF") +
            " TimeExit=" + (m_config.tcm_enable_time_exit ? "ON" : "OFF") +
            " Weekend=" + (m_config.tcm_enable_weekend_exit ? "ON" : "OFF") +
            " Emergency=" + (m_config.tcm_enable_emergency_exit ? "ON" : "OFF"));
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        LogStats();
        m_track_count = 0;
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("TradeLifecycleManager", "Shutdown complete");
    }

    /**
     * @brief Evaluate all open positions and execute management actions.
     *
     * Called on each heartbeat. Iterates all positions, evaluates each
     * against the 12 management features, and executes actions via the
     * broker adapter.
     *
     * @param snapshot  Read-only broker position snapshot.
     * @param market    Current market state.
     * @param context   Context store (for kill switch, drawdown).
     * @param broker    Broker adapter (for executing actions).
     * @return Number of actions executed.
     */
    virtual int ManagePositions(const PositionSnapshotEvent &snapshot,
                                 const MarketState &market,
                                 IContextStore *context,
                                 IBrokerAdapter *broker) override
    {
        if(!m_initialized || broker == NULL) return 0;

        //--- Refresh cached properties (once per call)
        RefreshCache(market, broker);

        int actions = 0;

        for(int i = 0; i < snapshot.count; i++)
        {
            const PositionState &pos = snapshot.broker_positions[i];
            if(StringLen(pos.position_id) == 0) continue;

            PositionTrack *track = GetTrack(pos.position_id);
            if(track == NULL) continue;

            track.last_manage_time = TimeCurrent();

            //=== 1. EMERGENCY EXIT (highest priority) ===
            if(m_config.tcm_enable_emergency_exit)
            {
                int emer = CheckEmergencyExit(pos, market, context);
                if(emer != ATLAS_TLM_EXIT_NONE)
                {
                    if(broker.ClosePosition(pos.position_id))
                    {
                        m_stats.emergency_closes++;
                        m_stats.full_closes++;
                        RecordExit(emer, pos, track);
                        actions++;
                    }
                    continue;
                }
            }

            //=== 2. TIME-BASED EXIT ===
            if(m_config.tcm_enable_time_exit)
            {
                int tex = CheckTimeExit(pos, market);
                if(tex != ATLAS_TLM_EXIT_NONE)
                {
                    if(broker.ClosePosition(pos.position_id))
                    {
                        m_stats.full_closes++;
                        RecordExit(tex, pos, track);
                        actions++;
                    }
                    continue;
                }
            }

            //=== 3. WEEKEND / SESSION CLOSE ===
            if(m_config.tcm_enable_weekend_exit)
            {
                int wex = CheckWeekendExit(pos, market);
                if(wex != ATLAS_TLM_EXIT_NONE)
                {
                    if(broker.ClosePosition(pos.position_id))
                    {
                        m_stats.full_closes++;
                        RecordExit(wex, pos, track);
                        actions++;
                    }
                    continue;
                }
            }

            //=== 4. PARTIAL CLOSE (scale out) ===
            if(m_config.tcm_enable_partial_close)
            {
                double partial_vol = CheckPartialClose(pos, track);
                if(partial_vol > 0.0)
                {
                    partial_vol = NormalizeVolume(partial_vol);
                    if(partial_vol > 0.0 && partial_vol < pos.volume)
                    {
                        if(broker.ClosePartialPosition(pos.position_id, partial_vol))
                        {
                            m_stats.partial_closes++;
                            track.partials_executed++;
                            actions++;
                            if(m_logger != NULL)
                                m_logger.Debug("TradeLifecycleManager",
                                    "Partial close " + pos.position_id +
                                    " vol=" + DoubleToString(partial_vol, 2) +
                                    " level=" + IntegerToString(track.partials_executed));
                        }
                    }
                }
            }

            //=== 5. PROFIT LOCK (move SL to lock profit) ===
            if(m_config.tcm_enable_profit_lock)
            {
                double lock_sl = CheckProfitLock(pos, track);
                if(lock_sl > 0.0 && IsBetterSL(pos, lock_sl))
                {
                    if(broker.ModifyPositionSLTP(pos.position_id, lock_sl, pos.current_tp))
                    {
                        m_stats.profit_locks++;
                        m_stats.sl_modifications++;
                        track.best_sl = lock_sl;
                        actions++;
                    }
                }
            }

            //=== 6. BREAK EVEN ===
            if(m_config.tcm_enable_breakeven && !track.breakeven_activated)
            {
                double be_sl = CheckBreakEven(pos, market);
                if(be_sl > 0.0 && IsBetterSL(pos, be_sl))
                {
                    if(broker.ModifyPositionSLTP(pos.position_id, be_sl, pos.current_tp))
                    {
                        m_stats.breakeven_activations++;
                        m_stats.sl_modifications++;
                        track.breakeven_activated = true;
                        track.best_sl = be_sl;
                        actions++;
                        if(m_logger != NULL)
                            m_logger.Debug("TradeLifecycleManager",
                                "Break-even activated " + pos.position_id +
                                " SL=" + DoubleToString(be_sl, m_digits));
                    }
                }
            }

            //=== 7. TRAILING STOP ===
            if(m_config.tcm_enable_trailing)
            {
                double trail_sl = CheckTrailing(pos, market, track);
                if(trail_sl > 0.0 && IsBetterSL(pos, trail_sl))
                {
                    if(broker.ModifyPositionSLTP(pos.position_id, trail_sl, pos.current_tp))
                    {
                        m_stats.trailing_updates++;
                        m_stats.sl_modifications++;
                        track.best_sl = trail_sl;
                        actions++;
                    }
                }
            }
        }

        return actions;
    }

    virtual int EmergencyCloseAll(IBrokerAdapter *broker,
                                   const string reason) override
    {
        if(broker == NULL) return 0;
        if(m_logger != NULL)
            m_logger.Fatal("TradeLifecycleManager",
                "EMERGENCY CLOSE ALL: " + reason);
        int closed = broker.CloseAllPositionsForMagic("AtlasEA: " + reason);
        m_stats.emergency_closes += closed;
        m_stats.full_closes += closed;
        return closed;
    }

    virtual TradeLifecycleStats GetStats(void) const override
    {
        return m_stats;
    }

    virtual void ResetDaily(void) override
    {
        //--- Reset daily-countable stats (keep cumulative for session)
        m_stats.trailing_updates = 0;
        m_stats.breakeven_activations = 0;
        m_stats.partial_closes = 0;
        m_stats.profit_locks = 0;
        m_stats.full_closes = 0;
        m_stats.emergency_closes = 0;
        m_stats.sl_modifications = 0;
        m_stats.tp_modifications = 0;
        m_stats.sum_holding_time_sec = 0.0;
        m_stats.max_holding_time_sec = 0.0;
        m_stats.closed_count = 0;
        m_stats.sum_rr = 0.0;
        for(int i = 0; i < 12; i++) m_stats.exit_counts[i] = 0;
    }

    virtual void ResetAll(void) override
    {
        m_stats = TradeLifecycleStats();
        m_track_count = 0;
    }

    virtual void LogStats(void) const override
    {
        if(m_logger == NULL) return;
        m_logger.Info("TradeLifecycleManager",
            "TrailingUpdates=" + IntegerToString((long)m_stats.trailing_updates) +
            " BEActivations=" + IntegerToString((long)m_stats.breakeven_activations) +
            " PartialCloses=" + IntegerToString((long)m_stats.partial_closes) +
            " ProfitLocks=" + IntegerToString((long)m_stats.profit_locks) +
            " FullCloses=" + IntegerToString((long)m_stats.full_closes) +
            " EmergencyCloses=" + IntegerToString((long)m_stats.emergency_closes) +
            " SLMods=" + IntegerToString((long)m_stats.sl_modifications) +
            " AvgHold=" + DoubleToString(m_stats.AverageHoldingTime(), 0) + "s" +
            " MaxHold=" + DoubleToString(m_stats.max_holding_time_sec, 0) + "s" +
            " AvgRR=" + DoubleToString(m_stats.AverageRR(), 2));

        string dist = "ExitDist: ";
        for(int i = 0; i < 12; i++)
            if(m_stats.exit_counts[i] > 0)
                dist += TradeLifecycleExitName(i) + "=" + IntegerToString(m_stats.exit_counts[i]) + " ";
        m_logger.Info("TradeLifecycleManager", dist);
    }

private:
    //=== Management feature checks (all O(1)) ===

    /**
     * @brief Check for emergency exit conditions.
     * @return Exit reason code, or ATLAS_TLM_EXIT_NONE if no emergency.
     */
    int CheckEmergencyExit(const PositionState &pos,
                            const MarketState &market,
                            IContextStore *context) const
    {
        if(context != NULL)
        {
            if(context.IsKillSwitchActive())
                return ATLAS_TLM_EXIT_EMERGENCY;
            if(context.GetDailyDrawdownPct() >= m_config.mm_max_drawdown_pct)
                return ATLAS_TLM_EXIT_EMERGENCY;
        }
        //--- Symbol invalid (bid/ask zero)
        if(m_bid <= 0.0 || m_ask <= 0.0)
            return ATLAS_TLM_EXIT_EMERGENCY;
        return ATLAS_TLM_EXIT_NONE;
    }

    /**
     * @brief Check for time-based exit.
     */
    int CheckTimeExit(const PositionState &pos, const MarketState &market) const
    {
        //--- Maximum trade duration
        if(m_config.tcm_max_trade_duration_sec > 0 && pos.open_time > 0)
        {
            long elapsed = (long)TimeCurrent() - (long)pos.open_time;
            if(elapsed >= m_config.tcm_max_trade_duration_sec)
                return ATLAS_TLM_EXIT_TIME_EXIT;
        }
        //--- Session close hour
        if(m_config.tcm_session_close_hour >= 0 && m_config.tcm_session_close_hour <= 23)
        {
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            if(dt.hour == m_config.tcm_session_close_hour)
                return ATLAS_TLM_EXIT_SESSION_CLOSE;
        }
        return ATLAS_TLM_EXIT_NONE;
    }

    /**
     * @brief Check for weekend / Friday close.
     */
    int CheckWeekendExit(const PositionState &pos, const MarketState &market) const
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        //--- Friday close
        if(dt.day_of_week == 5 && m_config.tcm_friday_close_hour >= 0)
        {
            if(dt.hour >= m_config.tcm_friday_close_hour)
                return ATLAS_TLM_EXIT_WEEKEND_CLOSE;
        }
        //--- Saturday or Sunday
        if(dt.day_of_week == 6 || dt.day_of_week == 0)
            return ATLAS_TLM_EXIT_WEEKEND_CLOSE;
        return ATLAS_TLM_EXIT_NONE;
    }

    /**
     * @brief Check for partial close trigger.
     * @return Volume to close, or 0.0 if no partial close.
     */
    double CheckPartialClose(const PositionState &pos, PositionTrack *track)
    {
        if(m_config.tcm_partial_count <= 0) return 0.0;
        double rr = ComputeRR(pos);

        for(int i = 0; i < m_config.tcm_partial_count && i < ATLAS_TLM_MAX_PARTIAL_LEVELS; i++)
        {
            //--- Skip if already executed (track by partials_executed count)
            if(i < track.partials_executed) continue;
            if(m_config.tcm_partial_levels[i] <= 0.0) continue;

            //--- Trigger by RR or by percentage
            bool trigger = false;
            if(m_config.tcm_partial_levels[i] > 0.0)
                trigger = (rr >= m_config.tcm_partial_levels[i]);

            if(trigger)
            {
                double fraction = m_config.tcm_partial_fractions[i];
                if(fraction <= 0.0 || fraction > 1.0) fraction = 0.5;
                return pos.volume * fraction;
            }
        }
        return 0.0;
    }

    /**
     * @brief Check for profit lock — move SL to lock profit at RR level.
     * @return New SL, or 0.0 if no lock.
     */
    double CheckProfitLock(const PositionState &pos, PositionTrack *track)
    {
        if(m_config.tcm_profit_lock_count <= 0) return 0.0;
        double rr = ComputeRR(pos);

        for(int i = 0; i < m_config.tcm_profit_lock_count && i < ATLAS_TLM_MAX_PROFIT_LOCK_LEVELS; i++)
        {
            if(track.profit_lock_done[i]) continue;
            if(m_config.tcm_profit_lock_levels[i] <= 0.0) continue;

            if(rr >= m_config.tcm_profit_lock_levels[i])
            {
                track.profit_lock_done[i] = true;
                double lock_frac = m_config.tcm_profit_lock_lock[i];
                //--- Lock fraction: 0 = breakeven, 1 = full profit
                double risk = MathAbs(pos.open_price - pos.current_sl);
                double profit = 0.0;
                if(pos.type == POSITION_TYPE_BUY)
                    profit = m_bid - pos.open_price;
                else
                    profit = pos.open_price - m_ask;

                double lock_profit = profit * lock_frac;
                double new_sl = 0.0;
                if(pos.type == POSITION_TYPE_BUY)
                    new_sl = pos.open_price + lock_profit;
                else
                    new_sl = pos.open_price - lock_profit;

                return NormalizePrice(new_sl);
            }
        }
        return 0.0;
    }

    /**
     * @brief Check for break-even trigger.
     * @return New SL (at breakeven + offset), or 0.0 if not triggered.
     */
    double CheckBreakEven(const PositionState &pos, const MarketState &market) const
    {
        double profit_points = ComputeProfitPoints(pos);
        if(profit_points < m_config.tcm_breakeven_trigger) return 0.0;
        if(profit_points < m_config.tcm_breakeven_min_profit) return 0.0;

        //--- Compute BE SL = entry + offset (in direction of trade)
        double offset = m_config.tcm_breakeven_offset * m_point;
        double spread_comp = m_config.tcm_breakeven_spread_comp ? (m_spread / 2.0) : 0.0;

        double be_sl = 0.0;
        if(pos.type == POSITION_TYPE_BUY)
            be_sl = pos.open_price + offset - spread_comp;
        else
            be_sl = pos.open_price - offset + spread_comp;

        return NormalizePrice(be_sl);
    }

    /**
     * @brief Check for trailing stop update.
     * @return New SL, or 0.0 if no update needed.
     *
     * Supports 5 trailing modes:
     *   CLASSIC: fixed distance (points)
     *   ATR: distance = ATR × multiplier
     *   STEP: move in fixed increments
     *   DYNAMIC: distance scales with profit
     *   VOLATILITY: distance scales with volatility index
     *
     * NEVER moves stop backwards.
     */
    double CheckTrailing(const PositionState &pos, const MarketState &market,
                          PositionTrack *track)
    {
        if(m_config.tcm_trailing_mode == ATLAS_TRAIL_OFF) return 0.0;

        //--- Don't trail until minimum RR is reached
        double rr = ComputeRR(pos);
        if(rr < m_config.tcm_trailing_start_rr) return 0.0;

        double trail_distance = 0.0;  // In price units

        switch(m_config.tcm_trailing_mode)
        {
            case ATLAS_TRAIL_CLASSIC:
                trail_distance = m_config.tcm_trailing_distance * m_point;
                break;

            case ATLAS_TRAIL_ATR:
                if(m_atr <= 0.0) return 0.0;
                trail_distance = m_atr * m_config.tcm_atr_multiplier;
                break;

            case ATLAS_TRAIL_STEP:
            {
                //--- Step trailing: move SL by fixed increment when price moves favorably
                double step = m_config.tcm_trailing_step * m_point;
                if(step <= 0.0) return 0.0;
                if(pos.type == POSITION_TYPE_BUY)
                {
                    double ideal_sl = m_bid - trail_distance;
                    double current_step = MathFloor((ideal_sl - pos.current_sl) / step) * step;
                    if(current_step <= 0.0) return 0.0;
                    trail_distance = m_config.tcm_trailing_distance * m_point;
                }
                else
                {
                    double ideal_sl = m_ask + trail_distance;
                    double current_step = MathFloor((pos.current_sl - ideal_sl) / step) * step;
                    if(current_step <= 0.0) return 0.0;
                    trail_distance = m_config.tcm_trailing_distance * m_point;
                }
                break;
            }

            case ATLAS_TRAIL_DYNAMIC:
            {
                //--- Dynamic: distance scales with profit (tighter as profit grows)
                double base_dist = m_config.tcm_trailing_distance * m_point;
                double profit_pts = ComputeProfitPoints(pos);
                double scale = 1.0;
                if(profit_pts > 0.0)
                    scale = MathMax(0.3, 1.0 - (profit_pts / 1000.0));
                trail_distance = base_dist * scale;
                break;
            }

            case ATLAS_TRAIL_VOLATILITY:
            {
                //--- Volatility-adjusted: distance scales with volatility index
                double base_dist = m_config.tcm_trailing_distance * m_point;
                double vol_scale = 1.0;
                if(market.volatility_index > 0.0)
                    vol_scale = MathMin(3.0, MathMax(0.5, market.volatility_index / 5.0));
                trail_distance = base_dist * vol_scale;
                break;
            }

            default:
                return 0.0;
        }

        if(trail_distance <= 0.0) return 0.0;

        //--- Compute new SL based on direction
        double new_sl = 0.0;
        if(pos.type == POSITION_TYPE_BUY)
            new_sl = m_bid - trail_distance;
        else
            new_sl = m_ask + trail_distance;

        return NormalizePrice(new_sl);
    }

    /**
     * @brief Record an exit in the statistics.
     */
    void RecordExit(const int reason, const PositionState &pos, PositionTrack *track)
    {
        if(reason >= 0 && reason < 12)
            m_stats.exit_counts[reason]++;

        m_stats.closed_count++;

        //--- Holding time
        if(pos.open_time > 0)
        {
            double hold = (double)((long)TimeCurrent() - (long)pos.open_time);
            m_stats.sum_holding_time_sec += hold;
            if(hold > m_stats.max_holding_time_sec)
                m_stats.max_holding_time_sec = hold;
        }

        //--- RR at exit
        double rr = ComputeRR(pos);
        m_stats.sum_rr += rr;

        //--- Remove tracking
        RemoveTrack(pos.position_id);

        if(m_logger != NULL)
            m_logger.Info("TradeLifecycleManager",
                "Position " + pos.position_id + " closed: " +
                TradeLifecycleExitName(reason) +
                " hold=" + IntegerToString((long)((TimeCurrent() - pos.open_time))) + "s" +
                " RR=" + DoubleToString(rr, 2));
    }
};

#endif // ATLAS_TRADE_LIFECYCLE_MANAGER_MQH
//+------------------------------------------------------------------+
