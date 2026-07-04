//+------------------------------------------------------------------+
//|            Engines/RiskEngine/CooldownManager.mqh                |
//|       AtlasEA v0.1.11.0 - Cooldown Management                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_COOLDOWN_MANAGER_MQH
#define ATLAS_COOLDOWN_MANAGER_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"

/**
 * @class CooldownManager
 * @brief Manages all cooldown types.
 *
 * Cooldown types:
 *   - Per-strategy cooldown (individual strategy cooled down)
 *   - Global cooldown (all strategies cooled down)
 *   - Loss streak cooldown (triggered after N consecutive losses)
 *   - Time-based cooldown (fixed duration from a trigger event)
 *
 * Memory: operates on RiskState (no own data).
 */
class CooldownManager
{
private:
    ILogger *m_logger;

    /// @brief Loss streak threshold for cooldown.
    int      m_loss_streak_threshold;
    /// @brief Cooldown duration after loss streak (seconds).
    int      m_loss_streak_duration_sec;
    /// @brief Global cooldown duration (seconds).
    int      m_global_cooldown_duration_sec;

public:
    /**
     * @brief Constructor.
     */
    CooldownManager(void)
    {
        m_logger                     = NULL;
        m_loss_streak_threshold      = 3;
        m_loss_streak_duration_sec   = 1800;   ///< 30 minutes
        m_global_cooldown_duration_sec = 300;  ///< 5 minutes
    }

    /**
     * @brief Initialize.
     * @param logger Logger.
     * @param loss_streak_threshold Consecutive losses to trigger cooldown.
     * @param loss_streak_duration_sec Cooldown duration after loss streak.
     */
    void Initialize(ILogger *logger,
                    const int loss_streak_threshold = 3,
                    const int loss_streak_duration_sec = 1800)
    {
        m_logger                   = logger;
        m_loss_streak_threshold    = (loss_streak_threshold > 0) ? loss_streak_threshold : 3;
        m_loss_streak_duration_sec = (loss_streak_duration_sec > 0) ? loss_streak_duration_sec : 1800;
    }

    /**
     * @brief Check if a global cooldown is active.
     * @param state Risk state.
     * @return true if global cooldown is active.
     */
    bool IsGlobalCooldownActive(const RiskState &state) const
    {
        if(state.cooldown_type == ATLAS_COOLDOWN_NONE) return false;
        if(state.cooldown_type == ATLAS_COOLDOWN_PER_STRATEGY) return false;
        return (TimeCurrent() < state.cooldown_until);
    }

    /**
     * @brief Check if a specific strategy is in cooldown.
     * @param state Risk state.
     * @param strategy_id Strategy to check.
     * @return true if the strategy is in cooldown.
     */
    bool IsStrategyInCooldown(const RiskState &state, const int strategy_id) const
    {
        //--- Global cooldown blocks all strategies
        if(IsGlobalCooldownActive(state)) return true;
        //--- Per-strategy cooldown
        return state.IsStrategyInCooldown(strategy_id);
    }

    /**
     * @brief Apply a per-strategy cooldown.
     * @param state Risk state (mutated).
     * @param strategy_id Strategy to cool down.
     * @param duration_sec Cooldown duration.
     */
    void ApplyStrategyCooldown(RiskState &state, const int strategy_id, const int duration_sec)
    {
        datetime until = TimeCurrent() + (datetime)duration_sec;
        state.SetStrategyCooldown(strategy_id, until);
        if(m_logger != NULL)
            m_logger.Info("CooldownManager",
                "Strategy " + IntegerToString(strategy_id) + " cooldown for " +
                IntegerToString(duration_sec) + "s");
    }

    /**
     * @brief Apply a global cooldown.
     * @param state Risk state (mutated).
     * @param duration_sec Cooldown duration.
     */
    void ApplyGlobalCooldown(RiskState &state, const int duration_sec)
    {
        state.cooldown_type  = ATLAS_COOLDOWN_GLOBAL;
        state.cooldown_until = TimeCurrent() + (datetime)duration_sec;
        if(m_logger != NULL)
            m_logger.Info("CooldownManager",
                "Global cooldown for " + IntegerToString(duration_sec) + "s");
    }

    /**
     * @brief Check and apply loss streak cooldown.
     * Called after each trade result.
     * @param state Risk state (mutated).
     * @return true if a loss streak cooldown was applied.
     */
    bool CheckLossStreak(RiskState &state)
    {
        if(state.consecutive_losses >= m_loss_streak_threshold)
        {
            state.cooldown_type  = ATLAS_COOLDOWN_LOSS_STREAK;
            state.cooldown_until = TimeCurrent() + (datetime)m_loss_streak_duration_sec;
            if(m_logger != NULL)
                m_logger.Warn("CooldownManager",
                    "Loss streak cooldown triggered: " + IntegerToString(state.consecutive_losses) +
                    " losses → " + IntegerToString(m_loss_streak_duration_sec) + "s cooldown");
            return true;
        }
        return false;
    }

    /**
     * @brief Get remaining cooldown seconds (global).
     */
    long RemainingSeconds(const RiskState &state) const
    {
        if(!IsGlobalCooldownActive(state)) return 0;
        datetime now = TimeCurrent();
        if(state.cooldown_until <= now) return 0;
        return (long)(state.cooldown_until - now);
    }

    /**
     * @brief Clear all cooldowns.
     */
    void ClearAll(RiskState &state)
    {
        state.cooldown_type  = ATLAS_COOLDOWN_NONE;
        state.cooldown_until = 0;
        state.strategy_cooldown_count = 0;
        for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        {
            state.strategy_cooldown_ids[i]   = 0;
            state.strategy_cooldown_until[i] = 0;
        }
    }

    //=== Accessors ===
    int GetLossStreakThreshold(void)    const { return m_loss_streak_threshold; }
    int GetLossStreakDurationSec(void)  const { return m_loss_streak_duration_sec; }
    int GetGlobalCooldownDuration(void) const { return m_global_cooldown_duration_sec; }
};

#endif // ATLAS_COOLDOWN_MANAGER_MQH
//+------------------------------------------------------------------+
