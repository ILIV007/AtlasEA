//+------------------------------------------------------------------+
//|                     Strategy/StrategyHealth.mqh                  |
//|       AtlasEA v0.1.20.0 - Strategy Health Tracker                |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_HEALTH_V2_MQH
#define ATLAS_STRATEGY_HEALTH_V2_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IStrategy.mqh"

/**
 * @brief Health reason codes.
 */
#define ATLAS_HEALTH_REASON_OK               0
#define ATLAS_HEALTH_REASON_TIMEOUT          1
#define ATLAS_HEALTH_REASON_EXCEPTION        2
#define ATLAS_HEALTH_REASON_INVALID_VOTES    3
#define ATLAS_HEALTH_REASON_DISABLED         4
#define ATLAS_HEALTH_REASON_MANUAL_BLOCK     5
#define ATLAS_HEALTH_REASON_COOLDOWN         6

/**
 * @struct StrategyHealthState
 * @brief Tracks health state for a single strategy.
 */
struct StrategyHealthState
{
    int      status;             ///< ATLAS_STRAT_HEALTH_*
    int      reason_code;        ///< ATLAS_HEALTH_REASON_*
    string   reason_text;        ///< Human-readable reason
    int      consecutive_failures;
    int      consecutive_timeouts;
    int      invalid_vote_count;
    datetime last_failure_time;
    datetime last_recovery_time;
    bool     manually_blocked;

    /**
     * @brief Default constructor — GREEN.
     */
    StrategyHealthState(void)
    {
        status               = ATLAS_STRAT_HEALTH_GREEN;
        reason_code          = ATLAS_HEALTH_REASON_OK;
        reason_text          = "";
        consecutive_failures = 0;
        consecutive_timeouts = 0;
        invalid_vote_count   = 0;
        last_failure_time    = 0;
        last_recovery_time   = 0;
        manually_blocked     = false;
    }

    /**
     * @brief Reset to GREEN.
     */
    void Reset(void)
    {
        status               = ATLAS_STRAT_HEALTH_GREEN;
        reason_code          = ATLAS_HEALTH_REASON_OK;
        reason_text          = "";
        consecutive_failures = 0;
        consecutive_timeouts = 0;
        invalid_vote_count   = 0;
        manually_blocked     = false;
    }

    /**
     * @brief Check if the strategy is healthy enough to execute.
     */
    bool CanExecute(void) const
    {
        if(manually_blocked) return false;
        if(status == ATLAS_STRAT_HEALTH_RED) return false;
        return true;
    }
};

/**
 * @class StrategyHealth
 * @brief Manages health state for strategies.
 *
 * Thresholds:
 *   - 3 consecutive failures → YELLOW
 *   - 5 consecutive failures → RED
 *   - 2 consecutive timeouts → YELLOW
 *   - 10 invalid votes in a row → YELLOW
 */
class StrategyHealth
{
private:
    static const int FAIL_THRESHOLD_YELLOW = 3;
    static const int FAIL_THRESHOLD_RED    = 5;
    static const int TIMEOUT_THRESHOLD     = 2;
    static const int INVALID_VOTE_THRESHOLD = 10;

public:
    /**
     * @brief Record a successful execution.
     */
    static void RecordSuccess(StrategyHealthState &state)
    {
        if(state.status != ATLAS_STRAT_HEALTH_GREEN)
        {
            state.status             = ATLAS_STRAT_HEALTH_GREEN;
            state.reason_code        = ATLAS_HEALTH_REASON_OK;
            state.reason_text        = "";
            state.last_recovery_time = TimeCurrent();
        }
        state.consecutive_failures = 0;
        state.consecutive_timeouts = 0;
        state.invalid_vote_count   = 0;
    }

    /**
     * @brief Record a failure (exception or invalid return).
     */
    static void RecordFailure(StrategyHealthState &state, const string reason)
    {
        state.consecutive_failures++;
        state.last_failure_time = TimeCurrent();

        if(state.consecutive_failures >= FAIL_THRESHOLD_RED)
        {
            state.status      = ATLAS_STRAT_HEALTH_RED;
            state.reason_code = ATLAS_HEALTH_REASON_EXCEPTION;
            state.reason_text = "Consecutive failures: " + IntegerToString(state.consecutive_failures) + " — " + reason;
        }
        else if(state.consecutive_failures >= FAIL_THRESHOLD_YELLOW)
        {
            state.status      = ATLAS_STRAT_HEALTH_YELLOW;
            state.reason_code = ATLAS_HEALTH_REASON_EXCEPTION;
            state.reason_text = "Failures: " + IntegerToString(state.consecutive_failures) + " — " + reason;
        }
    }

    /**
     * @brief Record a timeout.
     */
    static void RecordTimeout(StrategyHealthState &state)
    {
        state.consecutive_timeouts++;
        state.last_failure_time = TimeCurrent();

        if(state.consecutive_timeouts >= TIMEOUT_THRESHOLD)
        {
            state.status      = ATLAS_STRAT_HEALTH_YELLOW;
            state.reason_code = ATLAS_HEALTH_REASON_TIMEOUT;
            state.reason_text = "Timeouts: " + IntegerToString(state.consecutive_timeouts);
        }
    }

    /**
     * @brief Record an invalid vote.
     */
    static void RecordInvalidVote(StrategyHealthState &state)
    {
        state.invalid_vote_count++;
        if(state.invalid_vote_count >= INVALID_VOTE_THRESHOLD)
        {
            state.status      = ATLAS_STRAT_HEALTH_YELLOW;
            state.reason_code = ATLAS_HEALTH_REASON_INVALID_VOTES;
            state.reason_text = "Invalid votes: " + IntegerToString(state.invalid_vote_count);
        }
    }

    /**
     * @brief Manually block a strategy.
     */
    static void Block(StrategyHealthState &state, const string reason)
    {
        state.manually_blocked = true;
        state.status           = ATLAS_STRAT_HEALTH_RED;
        state.reason_code      = ATLAS_HEALTH_REASON_MANUAL_BLOCK;
        state.reason_text      = "Manual block: " + reason;
    }

    /**
     * @brief Unblock a strategy.
     */
    static void Unblock(StrategyHealthState &state)
    {
        state.manually_blocked = false;
        state.status           = ATLAS_STRAT_HEALTH_GREEN;
        state.reason_code      = ATLAS_HEALTH_REASON_OK;
        state.reason_text      = "";
    }
};

#endif // ATLAS_STRATEGY_HEALTH_V2_MQH
//+------------------------------------------------------------------+
