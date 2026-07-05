//+------------------------------------------------------------------+
//|                     Profiles/ProfileManager.mqh                  |
//|       AtlasEA v1.0 Step 4 - Profile Manager                       |
//+------------------------------------------------------------------+
#ifndef ATLAS_PROFILE_MANAGER_MQH
#define ATLAS_PROFILE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IMarketClassifier.mqh"
#include "../Interfaces/IProfileManager.mqh"
#include "MarketClassifier.mqh"
#include "ProfileSelector.mqh"

/**
 * @class ProfileManager
 * @brief Manages trading profiles and profile switching.
 *
 * Implements IProfileManager. The ONLY component that determines which
 * trading profile is active. All other modules (StrategyEngine,
 * MoneyManagementEngine, TradeLifecycleManager) read the active profile
 * via GetActiveProfile().
 *
 * PREDEFINED PROFILES (7):
 *   1. CONSERVATIVE    — low risk, fewer trades, tight limits
 *   2. BALANCED        — default, moderate risk
 *   3. AGGRESSIVE      — higher risk, more trades, wider limits
 *   4. SCALPING        — fast in/out, tight stops, low vol only
 *   5. SWING           — longer holds, wider stops, trend only
 *   6. NEWS_PROTECTION — protected mode during news events
 *   7. RECOVERY        — recovery mode after losses
 *
 * SWITCHING MODES:
 *   AUTO   — automatic switching based on market regime
 *   MANUAL — operator selects profile manually
 *   LOCKED — no switching (profile frozen)
 *
 * SAFETY (never switches while):
 *   - Order execution in progress
 *   - Recovery is active
 *   - Kill switch active
 *   - Replay mode active
 *
 * HYSTERESIS:
 *   - Regime must be stable for confirmation_bars evaluations
 *   - Cooldown between switches (cooldown_seconds)
 *
 * Performance: O(1), no allocation, no recursion.
 */
class ProfileManager : public IProfileManager
{
private:
    ILogger          *m_logger;
    AtlasConfig       m_config;
    ProfileStats      m_stats;
    bool              m_initialized;

    //--- Owned components ---
    MarketClassifier  m_classifier;
    ProfileSelector   m_selector;

    //--- Predefined profiles (fixed-size array, no heap allocation) ---
    ProfileParams m_profiles[ATLAS_PROFILE_COUNT];
    int           m_active_profile;

    //--- Switching state ---
    int  m_switching_mode;
    bool m_order_in_progress;
    bool m_recovery_active;
    bool m_kill_switch_active;
    bool m_replay_active;

    /**
     * @brief Initialize all 7 predefined profiles with their parameters.
     */
    void InitializeProfiles(void)
    {
        //=== 1. CONSERVATIVE ===
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].profile_code = ATLAS_PROFILE_CONSERVATIVE;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].profile_name = "Conservative";
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].max_risk_percent   = 0.5;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].max_exposure_pct   = 8.0;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].max_lot            = 2.0;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].max_trades_per_day = 5;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].trailing_distance  = 150;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].atr_multiplier     = 1.5;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].breakeven_trigger  = 100;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].breakeven_offset   = 10;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].max_trade_duration_sec = 43200; // 12h
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].session_mask       = 0x1C; // London+NY+Overlap
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].spread_limit_points = 30.0;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].volatility_min     = 1.0;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].volatility_max     = 8.0;
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].cooldown_sec       = 600;
        //--- Disable breakout and momentum (too risky for conservative)
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].strategy_enabled[2] = true;  // EMA trend
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].strategy_enabled[3] = true;  // Pullback
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].strategy_enabled[4] = false; // Breakout off
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].strategy_enabled[5] = false; // Momentum off
        m_profiles[ATLAS_PROFILE_CONSERVATIVE].strategy_enabled[6] = false; // Range off

        //=== 2. BALANCED ===
        m_profiles[ATLAS_PROFILE_BALANCED].profile_code = ATLAS_PROFILE_BALANCED;
        m_profiles[ATLAS_PROFILE_BALANCED].profile_name = "Balanced";
        m_profiles[ATLAS_PROFILE_BALANCED].max_risk_percent   = 1.0;
        m_profiles[ATLAS_PROFILE_BALANCED].max_exposure_pct   = 15.0;
        m_profiles[ATLAS_PROFILE_BALANCED].max_lot            = 5.0;
        m_profiles[ATLAS_PROFILE_BALANCED].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_BALANCED].max_trades_per_day = 10;
        m_profiles[ATLAS_PROFILE_BALANCED].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_BALANCED].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_BALANCED].trailing_distance  = 200;
        m_profiles[ATLAS_PROFILE_BALANCED].atr_multiplier     = 2.0;
        m_profiles[ATLAS_PROFILE_BALANCED].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_BALANCED].breakeven_trigger  = 150;
        m_profiles[ATLAS_PROFILE_BALANCED].breakeven_offset   = 20;
        m_profiles[ATLAS_PROFILE_BALANCED].max_trade_duration_sec = 86400; // 24h
        m_profiles[ATLAS_PROFILE_BALANCED].session_mask       = 0xFF; // All
        m_profiles[ATLAS_PROFILE_BALANCED].spread_limit_points = 50.0;
        m_profiles[ATLAS_PROFILE_BALANCED].volatility_min     = 0.5;
        m_profiles[ATLAS_PROFILE_BALANCED].volatility_max     = 10.0;
        m_profiles[ATLAS_PROFILE_BALANCED].cooldown_sec       = 300;
        //--- All strategies enabled (default from ProfileParams constructor)

        //=== 3. AGGRESSIVE ===
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].profile_code = ATLAS_PROFILE_AGGRESSIVE;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].profile_name = "Aggressive";
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].max_risk_percent   = 2.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].max_exposure_pct   = 25.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].max_lot            = 10.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].max_trades_per_day = 20;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].trailing_distance  = 300;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].atr_multiplier     = 2.5;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].breakeven_trigger  = 200;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].breakeven_offset   = 30;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].max_trade_duration_sec = 172800; // 48h
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].session_mask       = 0xFF;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].spread_limit_points = 80.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].volatility_min     = 0.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].volatility_max     = 15.0;
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].cooldown_sec       = 120;
        //--- All strategies enabled with higher weights for breakout/momentum
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].strategy_weight[4] = 1.5; // Breakout
        m_profiles[ATLAS_PROFILE_AGGRESSIVE].strategy_weight[5] = 1.5; // Momentum

        //=== 4. SCALPING ===
        m_profiles[ATLAS_PROFILE_SCALPING].profile_code = ATLAS_PROFILE_SCALPING;
        m_profiles[ATLAS_PROFILE_SCALPING].profile_name = "Scalping";
        m_profiles[ATLAS_PROFILE_SCALPING].max_risk_percent   = 0.5;
        m_profiles[ATLAS_PROFILE_SCALPING].max_exposure_pct   = 10.0;
        m_profiles[ATLAS_PROFILE_SCALPING].max_lot            = 3.0;
        m_profiles[ATLAS_PROFILE_SCALPING].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_SCALPING].max_trades_per_day = 30;
        m_profiles[ATLAS_PROFILE_SCALPING].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_SCALPING].trailing_mode      = 1;  // Classic
        m_profiles[ATLAS_PROFILE_SCALPING].trailing_distance  = 50;
        m_profiles[ATLAS_PROFILE_SCALPING].atr_multiplier     = 1.0;
        m_profiles[ATLAS_PROFILE_SCALPING].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_SCALPING].breakeven_trigger  = 50;
        m_profiles[ATLAS_PROFILE_SCALPING].breakeven_offset   = 5;
        m_profiles[ATLAS_PROFILE_SCALPING].max_trade_duration_sec = 1800; // 30 min
        m_profiles[ATLAS_PROFILE_SCALPING].session_mask       = 0x1C; // London+NY+Overlap
        m_profiles[ATLAS_PROFILE_SCALPING].spread_limit_points = 20.0;
        m_profiles[ATLAS_PROFILE_SCALPING].volatility_min     = 0.0;
        m_profiles[ATLAS_PROFILE_SCALPING].volatility_max     = 5.0;
        m_profiles[ATLAS_PROFILE_SCALPING].cooldown_sec       = 60;
        //--- Only momentum and range for scalping
        for(int i = 0; i < 8; i++)
            m_profiles[ATLAS_PROFILE_SCALPING].strategy_enabled[i] = false;
        m_profiles[ATLAS_PROFILE_SCALPING].strategy_enabled[5] = true; // Momentum
        m_profiles[ATLAS_PROFILE_SCALPING].strategy_enabled[6] = true; // Range

        //=== 5. SWING ===
        m_profiles[ATLAS_PROFILE_SWING].profile_code = ATLAS_PROFILE_SWING;
        m_profiles[ATLAS_PROFILE_SWING].profile_name = "Swing";
        m_profiles[ATLAS_PROFILE_SWING].max_risk_percent   = 1.5;
        m_profiles[ATLAS_PROFILE_SWING].max_exposure_pct   = 20.0;
        m_profiles[ATLAS_PROFILE_SWING].max_lot            = 8.0;
        m_profiles[ATLAS_PROFILE_SWING].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_SWING].max_trades_per_day = 5;
        m_profiles[ATLAS_PROFILE_SWING].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_SWING].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_SWING].trailing_distance  = 400;
        m_profiles[ATLAS_PROFILE_SWING].atr_multiplier     = 3.0;
        m_profiles[ATLAS_PROFILE_SWING].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_SWING].breakeven_trigger  = 300;
        m_profiles[ATLAS_PROFILE_SWING].breakeven_offset   = 50;
        m_profiles[ATLAS_PROFILE_SWING].max_trade_duration_sec = 259200; // 3 days
        m_profiles[ATLAS_PROFILE_SWING].session_mask       = 0xFF;
        m_profiles[ATLAS_PROFILE_SWING].spread_limit_points = 100.0;
        m_profiles[ATLAS_PROFILE_SWING].volatility_min     = 1.0;
        m_profiles[ATLAS_PROFILE_SWING].volatility_max     = 12.0;
        m_profiles[ATLAS_PROFILE_SWING].cooldown_sec       = 1800; // 30 min
        //--- Only EMA trend and pullback for swing
        for(int i = 0; i < 8; i++)
            m_profiles[ATLAS_PROFILE_SWING].strategy_enabled[i] = false;
        m_profiles[ATLAS_PROFILE_SWING].strategy_enabled[2] = true; // EMA trend
        m_profiles[ATLAS_PROFILE_SWING].strategy_enabled[3] = true; // Pullback

        //=== 6. NEWS_PROTECTION ===
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].profile_code = ATLAS_PROFILE_NEWS_PROTECTION;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].profile_name = "NewsProtection";
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].max_risk_percent   = 0.0; // No new trades
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].max_exposure_pct   = 0.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].max_lot            = 0.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].max_trades_per_day = 0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].trailing_distance  = 100;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].atr_multiplier     = 1.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].breakeven_trigger  = 50;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].breakeven_offset   = 0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].max_trade_duration_sec = 3600; // 1h
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].session_mask       = 0xFF;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].spread_limit_points = 200.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].volatility_min     = 0.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].volatility_max     = 100.0;
        m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].cooldown_sec       = 0;
        //--- All strategies disabled (no new trades during news)
        for(int i = 0; i < 8; i++)
            m_profiles[ATLAS_PROFILE_NEWS_PROTECTION].strategy_enabled[i] = false;

        //=== 7. RECOVERY ===
        m_profiles[ATLAS_PROFILE_RECOVERY].profile_code = ATLAS_PROFILE_RECOVERY;
        m_profiles[ATLAS_PROFILE_RECOVERY].profile_name = "Recovery";
        m_profiles[ATLAS_PROFILE_RECOVERY].max_risk_percent   = 0.3;
        m_profiles[ATLAS_PROFILE_RECOVERY].max_exposure_pct   = 5.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].max_lot            = 1.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].min_lot            = 0.01;
        m_profiles[ATLAS_PROFILE_RECOVERY].max_trades_per_day = 3;
        m_profiles[ATLAS_PROFILE_RECOVERY].trailing_enabled   = true;
        m_profiles[ATLAS_PROFILE_RECOVERY].trailing_mode      = 2;  // ATR
        m_profiles[ATLAS_PROFILE_RECOVERY].trailing_distance  = 100;
        m_profiles[ATLAS_PROFILE_RECOVERY].atr_multiplier     = 1.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].breakeven_enabled  = true;
        m_profiles[ATLAS_PROFILE_RECOVERY].breakeven_trigger  = 50;
        m_profiles[ATLAS_PROFILE_RECOVERY].breakeven_offset   = 5;
        m_profiles[ATLAS_PROFILE_RECOVERY].max_trade_duration_sec = 14400; // 4h
        m_profiles[ATLAS_PROFILE_RECOVERY].session_mask       = 0x1C; // London+NY+Overlap
        m_profiles[ATLAS_PROFILE_RECOVERY].spread_limit_points = 25.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].volatility_min     = 1.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].volatility_max     = 6.0;
        m_profiles[ATLAS_PROFILE_RECOVERY].cooldown_sec       = 600;
        //--- Only EMA trend (safest strategy) for recovery
        for(int i = 0; i < 8; i++)
            m_profiles[ATLAS_PROFILE_RECOVERY].strategy_enabled[i] = false;
        m_profiles[ATLAS_PROFILE_RECOVERY].strategy_enabled[2] = true; // EMA trend only
    }

    /**
     * @brief Check if a profile switch is allowed (safety checks).
     */
    int CheckSwitchAllowed(void) const
    {
        if(m_switching_mode == ATLAS_PROFILE_MODE_LOCKED)
            return ATLAS_PROFILE_SWITCH_REJECT_LOCKED;
        if(m_order_in_progress)
            return ATLAS_PROFILE_SWITCH_REJECT_ORDER;
        if(m_recovery_active)
            return ATLAS_PROFILE_SWITCH_REJECT_RECOVERY;
        if(m_kill_switch_active)
            return ATLAS_PROFILE_SWITCH_REJECT_KILLSWITCH;
        if(m_replay_active)
            return ATLAS_PROFILE_SWITCH_REJECT_REPLAY;
        return ATLAS_PROFILE_SWITCH_OK;
    }

    /**
     * @brief Record a rejected switch.
     */
    void RecordRejection(const int reason, const string detail)
    {
        m_stats.rejected_switches++;
        if(reason >= 0 && reason < 9)
            m_stats.reject_counts[reason]++;
        m_stats.last_reject_reason = detail;
    }

public:
    /**
     * @brief Constructor.
     */
    ProfileManager(void)
    {
        m_logger             = NULL;
        m_initialized        = false;
        m_active_profile     = ATLAS_PROFILE_BALANCED;
        m_switching_mode     = ATLAS_PROFILE_MODE_AUTO;
        m_order_in_progress  = false;
        m_recovery_active    = false;
        m_kill_switch_active = false;
        m_replay_active      = false;
        InitializeProfiles();
    }

    /**
     * @brief Set the logger (wires to sub-components).
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_classifier.SetLogger(logger);
        m_selector.SetLogger(logger);
    }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const AtlasConfig &config)
    {
        m_config = config;

        //--- Configure the selector from config
        ProfileSelectorConfig sc;
        sc.confirmation_bars      = config.profile_confirmation_bars;
        sc.cooldown_seconds       = config.profile_cooldown_minutes * 60;
        sc.enable_news_protection = config.enable_news_protection_profile;
        m_selector.SetConfig(sc);

        //--- Set initial profile
        m_active_profile = config.profile_default;
        m_stats.current_profile      = m_active_profile;
        m_stats.current_profile_name = ProfileName(m_active_profile);
        m_stats.current_profile_start = TimeCurrent();

        //--- Set switching mode
        if(!config.auto_profile_switch)
            m_switching_mode = ATLAS_PROFILE_MODE_MANUAL;
    }

    //=== IProfileManager implementation ===

    virtual const ProfileParams& GetActiveProfile(void) const override
    {
        return m_profiles[m_active_profile];
    }

    virtual int GetActiveProfileCode(void) const override
    {
        return m_active_profile;
    }

    virtual string GetActiveProfileName(void) const override
    {
        return ProfileName(m_active_profile);
    }

    virtual int GetSwitchingMode(void) const override
    {
        return m_switching_mode;
    }

    virtual void SetSwitchingMode(const int mode) override
    {
        if(mode < ATLAS_PROFILE_MODE_AUTO || mode > ATLAS_PROFILE_MODE_LOCKED)
            return;
        m_switching_mode = mode;
        if(m_logger != NULL)
            m_logger.Info("ProfileManager",
                "Switching mode set to " +
                IntegerToString(mode));
    }

    virtual bool SelectProfile(const int profile_code) override
    {
        if(m_switching_mode != ATLAS_PROFILE_MODE_MANUAL)
        {
            if(m_logger != NULL)
                m_logger.Warn("ProfileManager",
                    "Manual select rejected: not in MANUAL mode");
            return false;
        }
        if(profile_code < 0 || profile_code >= ATLAS_PROFILE_COUNT)
            return false;

        return DoSwitch(profile_code, "Manual selection");
    }

    virtual bool EvaluateSwitch(const MarketClassification &classification,
                                 bool order_in_progress,
                                 bool recovery_active,
                                 bool kill_switch_active,
                                 bool replay_active) override
    {
        if(!m_initialized) return false;

        //--- Update safety flags
        m_order_in_progress  = order_in_progress;
        m_recovery_active    = recovery_active;
        m_kill_switch_active = kill_switch_active;
        m_replay_active      = replay_active;

        //--- Only AUTO mode evaluates switches
        if(m_switching_mode != ATLAS_PROFILE_MODE_AUTO)
            return false;

        //--- Check safety
        int allowed = CheckSwitchAllowed();
        if(allowed != ATLAS_PROFILE_SWITCH_OK)
        {
            RecordRejection(allowed, ProfileSwitchRejectName(allowed));
            return false;
        }

        //--- Ask the selector for a recommendation
        int target = m_selector.Evaluate(classification, m_active_profile);
        if(target < 0)
            return false; // No switch recommended

        //--- Execute the switch
        string reason = "Auto: regime=" + MarketRegimeName(classification.regime) +
                        " → profile=" + ProfileName(target);
        return DoSwitch(target, reason);
    }

    virtual const ProfileStats& GetStats(void) const override
    {
        return m_stats;
    }

    virtual void ResetStats(void) override
    {
        m_stats = ProfileStats();
        m_stats.current_profile      = m_active_profile;
        m_stats.current_profile_name = ProfileName(m_active_profile);
        m_stats.current_profile_start = TimeCurrent();
        m_selector.Reset();
    }

    virtual void LogStatus(void) const override
    {
        if(m_logger == NULL) return;
        m_logger.Info("ProfileManager",
            "Active=" + ProfileName(m_active_profile) +
            " Mode=" + IntegerToString(m_switching_mode) +
            " Switches=" + IntegerToString(m_stats.switch_count) +
            " Rejected=" + IntegerToString(m_stats.rejected_switches) +
            " AvgDur=" + DoubleToString(m_stats.AverageProfileDuration(), 0) + "s" +
            " ConfirmedRegime=" + MarketRegimeName(m_selector.GetConfirmedRegime()) +
            " Pending=" + MarketRegimeName(m_selector.GetPendingRegime()) +
            "(" + IntegerToString(m_selector.GetPendingCount()) + ")");
    }

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_stats.current_profile_start = TimeCurrent();
        m_logger.Info("ProfileManager",
            "Initialized. Default=" + ProfileName(m_active_profile) +
            " Mode=" + IntegerToString(m_switching_mode));
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        LogStatus();
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("ProfileManager", "Shutdown complete");
    }

    //=== Extended API ===

    /**
     * @brief Get the market classifier (for CoreEngine to call Classify).
     */
    MarketClassifier& GetClassifier(void) { return m_classifier; }

    /**
     * @brief Set the news time flag (for CoreEngine to notify).
     */
    void SetNewsTime(const bool active)
    {
        m_classifier.SetNewsTime(active);
    }

    /**
     * @brief Get a specific profile's parameters (for configuration).
     */
    ProfileParams& GetProfile(const int code)
    {
        if(code < 0 || code >= ATLAS_PROFILE_COUNT)
            return m_profiles[ATLAS_PROFILE_BALANCED];
        return m_profiles[code];
    }

private:
    /**
     * @brief Execute a profile switch.
     */
    bool DoSwitch(const int target, const string reason)
    {
        if(target < 0 || target >= ATLAS_PROFILE_COUNT)
            return false;
        if(target == m_active_profile)
        {
            RecordRejection(ATLAS_PROFILE_SWITCH_REJECT_SAME, "Same profile");
            return false;
        }

        //--- Record duration of the previous profile
        if(m_stats.current_profile_start > 0)
        {
            double duration = (double)((long)TimeCurrent() - (long)m_stats.current_profile_start);
            m_stats.sum_profile_duration_sec += duration;
            m_stats.profile_durations_count++;
        }

        //--- Update stats
        m_stats.previous_profile      = m_active_profile;
        m_stats.previous_profile_name = ProfileName(m_active_profile);
        m_stats.switch_count++;
        m_stats.last_switch_time      = TimeCurrent();
        m_stats.last_switch_reason    = reason;

        //--- Switch
        m_active_profile = target;
        m_stats.current_profile       = target;
        m_stats.current_profile_name  = ProfileName(target);
        m_stats.current_profile_start = TimeCurrent();

        //--- Notify selector
        m_selector.NotifySwitched();

        if(m_logger != NULL)
            m_logger.Info("ProfileManager",
                "Profile switched: " + m_stats.previous_profile_name +
                " → " + m_stats.current_profile_name +
                " (" + reason + ")");

        return true;
    }
};

#endif // ATLAS_PROFILE_MANAGER_MQH
//+------------------------------------------------------------------+
