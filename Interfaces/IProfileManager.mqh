//+------------------------------------------------------------------+
//|                    Interfaces/IProfileManager.mqh                |
//|       AtlasEA v1.0 Step 4 - Profile Manager Interface            |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPROFILE_MANAGER_MQH
#define ATLAS_IPROFILE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "IMarketClassifier.mqh"

/**
 * @brief Profile codes.
 */
#define ATLAS_PROFILE_CONSERVATIVE   0   ///< Low risk, fewer trades
#define ATLAS_PROFILE_BALANCED       1   ///< Default balanced approach
#define ATLAS_PROFILE_AGGRESSIVE     2   ///< Higher risk, more trades
#define ATLAS_PROFILE_SCALPING       3   ///< Fast in/out, tight stops
#define ATLAS_PROFILE_SWING          4   ///< Longer holds, wider stops
#define ATLAS_PROFILE_NEWS_PROTECTION 5  ///< Protected mode during news
#define ATLAS_PROFILE_RECOVERY       6   ///< Recovery mode after losses

#define ATLAS_PROFILE_COUNT          7   ///< Total profile count

/**
 * @brief Profile switching mode codes.
 */
#define ATLAS_PROFILE_MODE_AUTO     0   ///< Automatic switching based on regime
#define ATLAS_PROFILE_MODE_MANUAL   1   ///< Manual override
#define ATLAS_PROFILE_MODE_LOCKED   2   ///< Locked (no switching)

/**
 * @brief Profile switch rejection reasons.
 */
#define ATLAS_PROFILE_SWITCH_OK              0
#define ATLAS_PROFILE_SWITCH_REJECT_LOCKED   1   ///< Profile is locked
#define ATLAS_PROFILE_SWITCH_REJECT_COOLDOWN 2   ///< Switch cooldown active
#define ATLAS_PROFILE_SWITCH_REJECT_ORDER    3   ///< Order execution in progress
#define ATLAS_PROFILE_SWITCH_REJECT_RECOVERY 4   ///< Recovery is active
#define ATLAS_PROFILE_SWITCH_REJECT_KILLSWITCH 5  ///< Kill switch active
#define ATLAS_PROFILE_SWITCH_REJECT_REPLAY   6   ///< Replay mode active
#define ATLAS_PROFILE_SWITCH_REJECT_SAME     7   ///< Same profile (no change)
#define ATLAS_PROFILE_SWITCH_REJECT_UNCONFIRMED 8 ///< Regime not confirmed

/**
 * @struct ProfileParams
 * @brief Trading parameters for a single profile.
 *
 * This struct defines ALL configurable parameters that a profile
 * controls. The StrategyEngine, MoneyManagementEngine, and
 * TradeLifecycleManager read these values when a profile is active.
 */
struct ProfileParams
{
    int    profile_code;            ///< ATLAS_PROFILE_*
    string profile_name;            ///< Human-readable name

    //--- Strategy configuration ---
    bool   strategy_enabled[8];     ///< Enable/disable per strategy (index = strategy_id - 1)
    int    strategy_priority[8];    ///< Priority per strategy
    double strategy_weight[8];      ///< Weight per strategy

    //--- Risk configuration ---
    double max_risk_percent;        ///< Max risk per trade
    double max_exposure_pct;        ///< Max total exposure
    double max_lot;                 ///< Max lot size
    double min_lot;                 ///< Min lot size
    int    max_trades_per_day;      ///< Max trades per day

    //--- Trade lifecycle configuration ---
    bool   trailing_enabled;        ///< Enable trailing stop
    int    trailing_mode;           ///< ATLAS_TRAIL_*
    double trailing_distance;       ///< Trailing distance (points)
    double atr_multiplier;          ///< ATR multiplier for trailing/SL
    bool   breakeven_enabled;       ///< Enable break-even
    double breakeven_trigger;       ///< BE trigger (points)
    double breakeven_offset;        ///< BE offset (points)
    int    max_trade_duration_sec;  ///< Max trade duration

    //--- Session & spread filters ---
    int    session_mask;            ///< Allowed sessions bitmask
    double spread_limit_points;     ///< Max spread (points)
    double volatility_min;          ///< Min volatility index
    double volatility_max;          ///< Max volatility index

    //--- Cooldown ---
    int    cooldown_sec;            ///< Cooldown between signals

    /**
     * @brief Default constructor — produces a balanced profile.
     */
    ProfileParams(void)
    {
        profile_code = ATLAS_PROFILE_BALANCED;
        profile_name = "Balanced";

        for(int i = 0; i < 8; i++)
        {
            strategy_enabled[i]  = true;
            strategy_priority[i] = (i + 1) * 10;
            strategy_weight[i]   = 1.0;
        }

        max_risk_percent   = 1.0;
        max_exposure_pct   = 15.0;
        max_lot            = 5.0;
        min_lot            = 0.01;
        max_trades_per_day = 10;

        trailing_enabled   = true;
        trailing_mode      = 2;  // ATR
        trailing_distance  = 200;
        atr_multiplier     = 2.0;
        breakeven_enabled  = true;
        breakeven_trigger  = 150;
        breakeven_offset   = 20;
        max_trade_duration_sec = 86400;

        session_mask       = 0xFF;  // All sessions
        spread_limit_points = 50.0;
        volatility_min     = 0.5;
        volatility_max     = 10.0;

        cooldown_sec       = 300;
    }
};

/**
 * @struct ProfileStats
 * @brief Statistics for the profile manager.
 */
struct ProfileStats
{
    int    current_profile;          ///< Current active profile code
    string current_profile_name;     ///< Current profile name
    int    previous_profile;         ///< Previous profile code
    string previous_profile_name;    ///< Previous profile name
    int    switch_count;             ///< Total profile switches
    int    rejected_switches;        ///< Switch attempts rejected
    datetime current_profile_start;  ///< When current profile started
    datetime last_switch_time;       ///< Last switch time
    double sum_profile_duration_sec; ///< Sum of durations (for average)
    int    profile_durations_count;  ///< Number of completed durations
    int    reject_counts[9];         ///< Per-reason rejection counts
    string last_switch_reason;       ///< Reason for last switch
    string last_reject_reason;       ///< Reason for last rejection

    ProfileStats(void)
    {
        current_profile         = ATLAS_PROFILE_BALANCED;
        current_profile_name    = "Balanced";
        previous_profile        = ATLAS_PROFILE_BALANCED;
        previous_profile_name   = "Balanced";
        switch_count            = 0;
        rejected_switches       = 0;
        current_profile_start   = 0;
        last_switch_time        = 0;
        sum_profile_duration_sec = 0.0;
        profile_durations_count = 0;
        for(int i = 0; i < 9; i++) reject_counts[i] = 0;
        last_switch_reason      = "";
        last_reject_reason      = "";
    }

    double AverageProfileDuration(void) const
    {
        return (profile_durations_count > 0)
            ? sum_profile_duration_sec / (double)profile_durations_count
            : 0.0;
    }
};

/**
 * @class IProfileManager
 * @brief The ONLY interface through which any module may query the
 *        active trading profile.
 *
 * Implemented by ProfileManager (Profiles/). Consumed by:
 *   - StrategyEngine (reads strategy enable/priority/weight)
 *   - MoneyManagementEngine (reads risk/exposure/lot limits)
 *   - TradeLifecycleManager (reads trailing/BE/duration params)
 *   - CoreEngine (coordinates switching)
 *
 * Contract:
 *   - Never switches profile while: order in progress, recovery active,
 *     kill switch active, or replay mode active.
 *   - Implements hysteresis to prevent rapid oscillation.
 *   - Automatic switching requires regime confirmation period.
 *   - Manual mode allows operator override.
 *   - Locked mode prevents all switching.
 */
class IProfileManager
{
public:
    /**
     * @brief Get the current active profile parameters.
     * @return Const reference to the active ProfileParams.
     */
    virtual const ProfileParams& GetActiveProfile(void) const = 0;

    /**
     * @brief Get the current profile code.
     */
    virtual int GetActiveProfileCode(void) const = 0;

    /**
     * @brief Get the current profile name.
     */
    virtual string GetActiveProfileName(void) const = 0;

    /**
     * @brief Get the current switching mode.
     */
    virtual int GetSwitchingMode(void) const = 0;

    /**
     * @brief Set the switching mode (AUTO / MANUAL / LOCKED).
     */
    virtual void SetSwitchingMode(const int mode) = 0;

    /**
     * @brief Manually select a profile (only in MANUAL mode).
     * @param profile_code ATLAS_PROFILE_* code.
     * @return true if accepted.
     */
    virtual bool SelectProfile(const int profile_code) = 0;

    /**
     * @brief Evaluate whether a profile switch should occur.
     *
     * Called by CoreEngine on each heartbeat. In AUTO mode, checks the
     * current market regime (via MarketClassifier) and switches if the
     * regime has been stable for the confirmation period AND no safety
     * blocks are active.
     *
     * @param classification Current market classification.
     * @param order_in_progress Is an order currently being executed?
     * @param recovery_active Is recovery currently active?
     * @param kill_switch_active Is the kill switch active?
     * @param replay_active Is replay mode active?
     * @return true if a switch occurred.
     */
    virtual bool EvaluateSwitch(const MarketClassification &classification,
                                 bool order_in_progress,
                                 bool recovery_active,
                                 bool kill_switch_active,
                                 bool replay_active) = 0;

    /**
     * @brief Get statistics.
     */
    virtual const ProfileStats& GetStats(void) const = 0;

    /**
     * @brief Reset statistics.
     */
    virtual void ResetStats(void) = 0;

    /**
     * @brief Log current status.
     */
    virtual void LogStatus(void) const = 0;

    /**
     * @brief Initialize the manager.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the manager.
     */
    virtual void Shutdown(void) = 0;

    virtual ~IProfileManager(void) {}
};

/**
 * @brief Get the name of a profile code.
 */
string ProfileName(const int profile_code)
{
    switch(profile_code)
    {
        case ATLAS_PROFILE_CONSERVATIVE:    return "Conservative";
        case ATLAS_PROFILE_BALANCED:        return "Balanced";
        case ATLAS_PROFILE_AGGRESSIVE:      return "Aggressive";
        case ATLAS_PROFILE_SCALPING:        return "Scalping";
        case ATLAS_PROFILE_SWING:           return "Swing";
        case ATLAS_PROFILE_NEWS_PROTECTION: return "NewsProtection";
        case ATLAS_PROFILE_RECOVERY:        return "Recovery";
    }
    return "Unknown";
}

/**
 * @brief Get the name of a switch rejection reason.
 */
string ProfileSwitchRejectName(const int reason)
{
    switch(reason)
    {
        case ATLAS_PROFILE_SWITCH_OK:              return "OK";
        case ATLAS_PROFILE_SWITCH_REJECT_LOCKED:   return "LOCKED";
        case ATLAS_PROFILE_SWITCH_REJECT_COOLDOWN: return "COOLDOWN";
        case ATLAS_PROFILE_SWITCH_REJECT_ORDER:    return "ORDER_IN_PROGRESS";
        case ATLAS_PROFILE_SWITCH_REJECT_RECOVERY: return "RECOVERY_ACTIVE";
        case ATLAS_PROFILE_SWITCH_REJECT_KILLSWITCH: return "KILLSWITCH_ACTIVE";
        case ATLAS_PROFILE_SWITCH_REJECT_REPLAY:   return "REPLAY_ACTIVE";
        case ATLAS_PROFILE_SWITCH_REJECT_SAME:     return "SAME_PROFILE";
        case ATLAS_PROFILE_SWITCH_REJECT_UNCONFIRMED: return "UNCONFIRMED";
    }
    return "UNKNOWN";
}

#endif // ATLAS_IPROFILE_MANAGER_MQH
//+------------------------------------------------------------------+
