//+------------------------------------------------------------------+
//|                     Profiles/ProfileSelector.mqh                 |
//|       AtlasEA v1.0 Step 4 - Profile Selector (Regime → Profile)  |
//+------------------------------------------------------------------+
#ifndef ATLAS_PROFILE_SELECTOR_MQH
#define ATLAS_PROFILE_SELECTOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IMarketClassifier.mqh"
#include "../Interfaces/IProfileManager.mqh"

/**
 * @struct ProfileSelectorConfig
 * @brief Configuration for the profile selector.
 */
struct ProfileSelectorConfig
{
    int confirmation_bars;       ///< Bars of stable regime before switching
    int cooldown_seconds;        ///< Min seconds between switches (hysteresis)
    bool enable_news_protection; ///< Auto-switch to NewsProtection profile

    ProfileSelectorConfig(void)
    {
        confirmation_bars       = 3;    // 3 bars of stable regime
        cooldown_seconds        = 300;  // 5 minutes between switches
        enable_news_protection  = true;
    }
};

/**
 * @class ProfileSelector
 * @brief Maps market regime to trading profile with confirmation and hysteresis.
 *
 * SOLE RESPONSIBILITY: determine WHICH profile should be active based
 * on the current market regime, with confirmation period and cooldown
 * to prevent rapid oscillation.
 *
 * Default regime → profile mapping:
 *   TRENDING        → BALANCED (or SWING if configured)
 *   RANGING         → CONSERVATIVE (or SCALPING if configured)
 *   HIGH_VOLATILITY → CONSERVATIVE
 *   LOW_VOLATILITY  → SCALPING
 *   BREAKOUT        → AGGRESSIVE
 *   NEWS_PROTECTION → NEWS_PROTECTION
 *   UNKNOWN         → CONSERVATIVE (safest)
 *
 * Confirmation: the regime must remain stable for `confirmation_bars`
 * evaluations before a switch is recommended. This prevents oscillation.
 *
 * Cooldown: after a switch, no new switch for `cooldown_seconds`.
 *
 * Memory: ~200 bytes (config + tracking state).
 */
class ProfileSelector
{
private:
    ILogger              *m_logger;
    ProfileSelectorConfig m_config;

    //--- Regime confirmation tracking ---
    int    m_pending_regime;          ///< Regime waiting for confirmation
    int    m_pending_confidence;      ///< Confidence of pending regime
    int    m_pending_count;           ///< Consecutive evaluations with same regime
    int    m_confirmed_regime;        ///< Last confirmed regime
    datetime m_last_switch_time;      ///< Last switch time (for cooldown)

    /**
     * @brief Map a regime to a profile code.
     */
    int RegimeToProfile(const int regime) const
    {
        switch(regime)
        {
            case ATLAS_REGIME_TRENDING:        return ATLAS_PROFILE_BALANCED;
            case ATLAS_REGIME_RANGING:         return ATLAS_PROFILE_CONSERVATIVE;
            case ATLAS_REGIME_HIGH_VOLATILITY: return ATLAS_PROFILE_CONSERVATIVE;
            case ATLAS_REGIME_LOW_VOLATILITY:  return ATLAS_PROFILE_SCALPING;
            case ATLAS_REGIME_BREAKOUT:        return ATLAS_PROFILE_AGGRESSIVE;
            case ATLAS_REGIME_NEWS_PROTECTION: return ATLAS_PROFILE_NEWS_PROTECTION;
            case ATLAS_REGIME_UNKNOWN:         return ATLAS_PROFILE_CONSERVATIVE;
        }
        return ATLAS_PROFILE_CONSERVATIVE;
    }

public:
    /**
     * @brief Constructor.
     */
    ProfileSelector(void)
    {
        m_logger              = NULL;
        m_pending_regime      = ATLAS_REGIME_UNKNOWN;
        m_pending_confidence  = 0;
        m_pending_count       = 0;
        m_confirmed_regime    = ATLAS_REGIME_UNKNOWN;
        m_last_switch_time    = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the configuration.
     */
    void SetConfig(const ProfileSelectorConfig &config) { m_config = config; }

    /**
     * @brief Get the configuration.
     */
    const ProfileSelectorConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Evaluate the classification and determine if a switch is recommended.
     *
     * @param classification Current market classification.
     * @param current_profile Current active profile code.
     * @return Profile code to switch to, or -1 if no switch recommended.
     */
    int Evaluate(const MarketClassification &classification, const int current_profile)
    {
        int new_regime = classification.regime;

        //--- News protection: immediate switch (no confirmation needed)
        if(m_config.enable_news_protection &&
           new_regime == ATLAS_REGIME_NEWS_PROTECTION)
        {
            m_confirmed_regime = new_regime;
            m_pending_count    = 0;
            int target = ATLAS_PROFILE_NEWS_PROTECTION;
            if(target != current_profile)
                return target;
            return -1; // Already on news protection
        }

        //--- Track regime confirmation
        if(new_regime == m_pending_regime)
        {
            m_pending_count++;
        }
        else
        {
            m_pending_regime     = new_regime;
            m_pending_confidence = classification.confidence;
            m_pending_count      = 1;
        }

        //--- Check confirmation period
        if(m_pending_count < m_config.confirmation_bars)
            return -1; // Not confirmed yet

        //--- Regime is confirmed — check if profile should change
        m_confirmed_regime = new_regime;
        int target_profile = RegimeToProfile(new_regime);

        if(target_profile == current_profile)
            return -1; // Same profile, no switch needed

        //--- Check cooldown (hysteresis)
        if(m_config.cooldown_seconds > 0 && m_last_switch_time > 0)
        {
            long elapsed = (long)TimeCurrent() - (long)m_last_switch_time;
            if(elapsed < m_config.cooldown_seconds)
                return -1; // Cooldown active
        }

        return target_profile;
    }

    /**
     * @brief Notify that a switch has occurred (updates cooldown).
     */
    void NotifySwitched(void)
    {
        m_last_switch_time = TimeCurrent();
        m_pending_count    = 0;
    }

    /**
     * @brief Get the confirmed regime.
     */
    int GetConfirmedRegime(void) const { return m_confirmed_regime; }

    /**
     * @brief Get the pending regime (waiting for confirmation).
     */
    int GetPendingRegime(void) const { return m_pending_regime; }

    /**
     * @brief Get the pending count (how many bars the pending regime has been stable).
     */
    int GetPendingCount(void) const { return m_pending_count; }

    /**
     * @brief Reset the selector (e.g., on new trading day).
     */
    void Reset(void)
    {
        m_pending_regime     = ATLAS_REGIME_UNKNOWN;
        m_pending_confidence = 0;
        m_pending_count      = 0;
        m_confirmed_regime   = ATLAS_REGIME_UNKNOWN;
        m_last_switch_time   = 0;
    }
};

#endif // ATLAS_PROFILE_SELECTOR_MQH
//+------------------------------------------------------------------+
