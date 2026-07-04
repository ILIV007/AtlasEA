//+------------------------------------------------------------------+
//|              Engines/RiskEngine/RiskState.mqh                    |
//|       AtlasEA v0.1.11.0 - Risk Engine State Container            |
//+------------------------------------------------------------------+
#ifndef ATLAS_RISK_STATE_MQH
#define ATLAS_RISK_STATE_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/Events.mqh"

/**
 * @brief Risk state version code (incremented on structural changes).
 */
#define ATLAS_RISK_STATE_VERSION 1

/**
 * @brief Kill switch trigger reasons (machine-readable codes).
 */
#define ATLAS_KS_REASON_NONE                0
#define ATLAS_KS_REASON_DAILY_DD            1
#define ATLAS_KS_REASON_FLOATING_DD         2
#define ATLAS_KS_REASON_MARGIN_CRITICAL     3
#define ATLAS_KS_REASON_RECONCILIATION      4
#define ATLAS_KS_REASON_CORRUPTED_STATE     5
#define ATLAS_KS_REASON_MANUAL              6
#define ATLAS_KS_REASON_CONSECUTIVE_LOSSES  7

/**
 * @brief Cooldown type codes.
 */
#define ATLAS_COOLDOWN_NONE                0
#define ATLAS_COOLDOWN_PER_STRATEGY        1
#define ATLAS_COOLDOWN_GLOBAL              2
#define ATLAS_COOLDOWN_LOSS_STREAK         3
#define ATLAS_COOLDOWN_TIME_BASED          4

/**
 * @brief Position sizing method codes.
 */
#define ATLAS_SIZER_FIXED_LOT             0
#define ATLAS_SIZER_RISK_PERCENT          1
#define ATLAS_SIZER_FIXED_MONEY           2
#define ATLAS_SIZER_ATR_MULTIPLIER        3  ///< Placeholder
#define ATLAS_SIZER_KELLY                 4  ///< Placeholder

/**
 * @struct RiskState
 * @brief Complete risk engine state (mirrors context + extends with internal fields).
 *
 * This struct is the RiskEngine's internal state snapshot. It does NOT
 * replace IContextStore — it augments it with engine-specific fields
 * (per-strategy cooldowns, sizer config, rule config) that don't belong
 * on the global context.
 *
 * All mutable state that the RiskEngine owns lives here. The engine
 * reads from IContextStore (for shared state) and RiskState (for
 * engine-private state).
 *
 * Memory: fixed-size. No dynamic arrays. ~512 bytes.
 */
struct RiskState
{
    //--- Versioning ---
    int      version;                ///< RiskState format version
    datetime timestamp;              ///< Last update time

    //--- Daily PnL ---
    double   daily_pnl;              ///< Realized + unrealized PnL today
    double   daily_realized_pnl;     ///< Realized PnL only
    double   daily_floating_pnl;     ///< Floating PnL only

    //--- Drawdown ---
    double   daily_drawdown_pct;     ///< Daily drawdown from peak (%)
    double   floating_drawdown_pct;  ///< Floating drawdown from peak (%)
    double   peak_equity;            ///< Peak equity today
    double   current_equity;         ///< Current equity (from context)

    //--- Exposure ---
    double   current_exposure_pct;   ///< Current net exposure (% of equity)
    double   projected_exposure_pct; ///< Exposure if new trade is approved
    double   exposure_by_symbol;     ///< Exposure for current symbol
    double   exposure_by_direction;  ///< Net directional exposure

    //--- Trade counts ---
    int      trades_today;           ///< Total trades today
    int      trades_this_hour;       ///< Trades in current hour
    int      wins_today;             ///< Winning trades today
    int      losses_today;           ///< Losing trades today
    int      consecutive_losses;     ///< Current loss streak
    int      consecutive_wins;       ///< Current win streak

    //--- Kill switch ---
    bool     kill_switch_active;     ///< Is kill switch active?
    int      kill_switch_reason_code;///< Machine-readable reason
    string   kill_switch_reason_text;///< Human-readable reason
    datetime kill_switch_time;       ///< When activated

    //--- Cooldown ---
    int      cooldown_type;          ///< ATLAS_COOLDOWN_*
    datetime cooldown_until;         ///< When cooldown expires
    datetime last_trade_time;        ///< Last trade execution time
    int      cooldown_strategy_id;   ///< Strategy-specific cooldown target

    //--- Margin ---
    double   margin_level;           ///< Current margin level (%)
    double   free_margin;            ///< Free margin available
    double   used_margin;            ///< Margin in use

    //--- Per-strategy cooldowns (fixed array) ---
    int      strategy_cooldown_ids[ATLAS_MAX_STRATEGIES];     ///< Strategy IDs
    datetime strategy_cooldown_until[ATLAS_MAX_STRATEGIES];   ///< Cooldown expiry per strategy
    int      strategy_cooldown_count;                          ///< Number of active per-strategy cooldowns

    /**
     * @brief Default constructor — initializes to safe defaults.
     */
    RiskState(void)
    {
        version                = ATLAS_RISK_STATE_VERSION;
        timestamp              = 0;
        daily_pnl              = 0.0;
        daily_realized_pnl     = 0.0;
        daily_floating_pnl     = 0.0;
        daily_drawdown_pct     = 0.0;
        floating_drawdown_pct  = 0.0;
        peak_equity            = 0.0;
        current_equity         = 0.0;
        current_exposure_pct   = 0.0;
        projected_exposure_pct = 0.0;
        exposure_by_symbol     = 0.0;
        exposure_by_direction  = 0.0;
        trades_today           = 0;
        trades_this_hour       = 0;
        wins_today             = 0;
        losses_today           = 0;
        consecutive_losses     = 0;
        consecutive_wins       = 0;
        kill_switch_active     = false;
        kill_switch_reason_code = ATLAS_KS_REASON_NONE;
        kill_switch_reason_text = "";
        kill_switch_time       = 0;
        cooldown_type          = ATLAS_COOLDOWN_NONE;
        cooldown_until         = 0;
        last_trade_time        = 0;
        cooldown_strategy_id   = 0;
        margin_level           = 0.0;
        free_margin            = 0.0;
        used_margin            = 0.0;
        strategy_cooldown_count = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        {
            strategy_cooldown_ids[i]   = 0;
            strategy_cooldown_until[i] = 0;
        }
    }

    /**
     * @brief Reset daily fields (called on new trading day).
     */
    void ResetDaily(void)
    {
        daily_pnl              = 0.0;
        daily_realized_pnl     = 0.0;
        daily_floating_pnl     = 0.0;
        daily_drawdown_pct     = 0.0;
        floating_drawdown_pct  = 0.0;
        trades_today           = 0;
        trades_this_hour       = 0;
        wins_today             = 0;
        losses_today           = 0;
        consecutive_losses     = 0;
        consecutive_wins       = 0;
        cooldown_type          = ATLAS_COOLDOWN_NONE;
        cooldown_until         = 0;
        timestamp              = TimeCurrent();
    }

    /**
     * @brief Reset everything (cold start).
     */
    void ResetAll(void)
    {
        ResetDaily();
        kill_switch_active      = false;
        kill_switch_reason_code = ATLAS_KS_REASON_NONE;
        kill_switch_reason_text = "";
        kill_switch_time        = 0;
        peak_equity             = 0.0;
        current_equity          = 0.0;
        current_exposure_pct    = 0.0;
        projected_exposure_pct  = 0.0;
        margin_level            = 0.0;
        free_margin             = 0.0;
        used_margin             = 0.0;
        strategy_cooldown_count = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        {
            strategy_cooldown_ids[i]   = 0;
            strategy_cooldown_until[i] = 0;
        }
    }

    /**
     * @brief Check if a per-strategy cooldown is active.
     * @param strategy_id The strategy to check.
     * @return true if the strategy is in cooldown.
     */
    bool IsStrategyInCooldown(const int strategy_id) const
    {
        datetime now = TimeCurrent();
        for(int i = 0; i < strategy_cooldown_count; i++)
        {
            if(strategy_cooldown_ids[i] == strategy_id)
                return (now < strategy_cooldown_until[i]);
        }
        return false;
    }

    /**
     * @brief Set a per-strategy cooldown.
     * @param strategy_id The strategy to cool down.
     * @param until When the cooldown expires.
     */
    void SetStrategyCooldown(const int strategy_id, const datetime until)
    {
        //--- Check if already exists
        for(int i = 0; i < strategy_cooldown_count; i++)
        {
            if(strategy_cooldown_ids[i] == strategy_id)
            {
                strategy_cooldown_until[i] = until;
                return;
            }
        }

        //--- Add new entry
        if(strategy_cooldown_count < ATLAS_MAX_STRATEGIES)
        {
            strategy_cooldown_ids[strategy_cooldown_count]   = strategy_id;
            strategy_cooldown_until[strategy_cooldown_count] = until;
            strategy_cooldown_count++;
        }
    }

    /**
     * @brief Clear a per-strategy cooldown.
     */
    void ClearStrategyCooldown(const int strategy_id)
    {
        for(int i = 0; i < strategy_cooldown_count; i++)
        {
            if(strategy_cooldown_ids[i] == strategy_id)
            {
                //--- Shift remaining left
                for(int j = i + 1; j < strategy_cooldown_count; j++)
                {
                    strategy_cooldown_ids[j-1]   = strategy_cooldown_ids[j];
                    strategy_cooldown_until[j-1] = strategy_cooldown_until[j];
                }
                strategy_cooldown_count--;
                strategy_cooldown_ids[strategy_cooldown_count]   = 0;
                strategy_cooldown_until[strategy_cooldown_count] = 0;
                return;
            }
        }
    }
};

#endif // ATLAS_RISK_STATE_MQH
//+------------------------------------------------------------------+
