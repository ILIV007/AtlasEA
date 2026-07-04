//+------------------------------------------------------------------+
//|                   Interfaces/IReplayEngine.mqh                  |
//|       AtlasEA v0.1.23.0 - Event Replay Engine Interface         |
//+------------------------------------------------------------------+
#ifndef ATLAS_IREPLAY_ENGINE_MQH
#define ATLAS_IREPLAY_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"

/**
 * @brief Replay speed codes.
 */
#define ATLAS_REPLAY_1X        0   ///< Real-time (1x speed)
#define ATLAS_REPLAY_10X       1   ///< 10x speed
#define ATLAS_REPLAY_100X      2   ///< 100x speed
#define ATLAS_REPLAY_MAX       3   ///< Maximum (no delay)
#define ATLAS_REPLAY_STEP      4   ///< Step-by-step (manual advance)

/**
 * @brief Replay state codes.
 */
#define ATLAS_REPLAY_STATE_IDLE       0
#define ATLAS_REPLAY_STATE_LOADING    1
#define ATLAS_REPLAY_STATE_READY      2
#define ATLAS_REPLAY_STATE_RUNNING    3
#define ATLAS_REPLAY_STATE_PAUSED     4
#define ATLAS_REPLAY_STATE_STOPPED    5
#define ATLAS_REPLAY_STATE_COMPLETED  6
#define ATLAS_REPLAY_STATE_FAILED     7

/**
 * @struct ReplayResult
 * @brief Result of a replay operation.
 */
struct ReplayResult
{
    bool   success;
    long   events_replayed;
    long   events_skipped;
    double duration_ms;
    double avg_speed;
    string failure_reason;
};

/**
 * @brief Replay event callback type.
 * Called for each event during replay.
 */
typedef void (*ReplayEventCallback)(const AtlasEvent &event, void *user_data);

/**
 * @class IReplayEngine
 * @brief Interface for deterministic event replay.
 *
 * The replay engine loads persisted events and replays them in exact
 * order, generating the same EventBus events as Live mode.
 *
 * CoreEngine does not know whether events come from Live or Replay.
 *
 * Supports:
 *   - Replay by timestamp range
 *   - Replay by sequence range
 *   - Replay from a specific snapshot
 *   - Pause / Resume / Stop
 *   - JumpTo (seek to arbitrary position)
 *   - Speed control (1x, 10x, 100x, MAX, STEP)
 */
class IReplayEngine
{
public:
    /// @brief Load events from an event store for replay.
    virtual bool LoadEvents(const long from_sequence, const long to_sequence) = 0;

    /// @brief Start replay from current position.
    virtual bool Play(const int speed) = 0;

    /// @brief Pause replay.
    virtual bool Pause(void) = 0;

    /// @brief Resume paused replay.
    virtual bool Resume(void) = 0;

    /// @brief Stop replay and reset cursor.
    virtual bool Stop(void) = 0;

    /// @brief Jump to a specific sequence number.
    virtual bool JumpTo(const long sequence) = 0;

    /// @brief Step forward one event (for STEP mode).
    virtual bool StepForward(void) = 0;

    /// @brief Get the current replay state.
    virtual int GetState(void) const = 0;

    /// @brief Get the current sequence position.
    virtual long GetCurrentSequence(void) const = 0;

    /// @brief Get total loaded events.
    virtual long GetLoadedCount(void) const = 0;

    /// @brief Get the last replay result.
    virtual const ReplayResult& GetLastResult(void) const = 0;

    /// @brief Set the event callback.
    virtual void SetCallback(ReplayEventCallback callback, void *user_data) = 0;

    /// @brief Set the replay speed.
    virtual void SetSpeed(const int speed) = 0;

    virtual ~IReplayEngine(void) {}
};

#endif // ATLAS_IREPLAY_ENGINE_MQH
//+------------------------------------------------------------------+
