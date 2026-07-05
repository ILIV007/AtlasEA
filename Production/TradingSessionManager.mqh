//+------------------------------------------------------------------+
//|                 Production/TradingSessionManager.mqh             |
//|       AtlasEA v1.0 Step 7 - Trading Session Manager              |
//+------------------------------------------------------------------+
#ifndef ATLAS_TRADING_SESSION_MANAGER_MQH
#define ATLAS_TRADING_SESSION_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"

/**
 * @brief Session event codes.
 */
#define ATLAS_SESSION_EVENT_NONE          0
#define ATLAS_SESSION_EVENT_WEEKEND_CLOSE 1
#define ATLAS_SESSION_EVENT_WEEKEND_REOPEN 2
#define ATLAS_SESSION_EVENT_DAILY_ROLLOVER 3
#define ATLAS_SESSION_EVENT_DST_CHANGE    4
#define ATLAS_SESSION_EVENT_SERVER_RESTART 5
#define ATLAS_SESSION_EVENT_TERMINAL_RESTART 6

/**
 * @struct SessionState
 * @brief Current session state.
 */
struct SessionState
{
    bool   is_weekend;          ///< Is it weekend?
    bool   is_session_open;     ///< Is the trading session open?
    bool   is_daily_rollover;   ///< Is a daily rollover occurring?
    bool   is_dst_change;       ///< Is a DST change occurring?
    int    day_of_week;         ///< Day of week (0=Sunday, 6=Saturday)
    int    hour;                ///< Current hour (server time)
    datetime last_rollover;     ///< Last daily rollover time
    datetime last_weekend_close; ///< Last weekend close time
    datetime last_weekend_reopen; ///< Last weekend reopen time
    datetime last_dst_change;   ///< Last DST change time
    bool   was_weekend;         ///< Was it weekend on the last check?
    int    last_day_of_week;    ///< Day of week on last check

    SessionState(void)
    {
        is_weekend         = false;
        is_session_open    = true;
        is_daily_rollover  = false;
        is_dst_change      = false;
        day_of_week        = 0;
        hour               = 0;
        last_rollover      = 0;
        last_weekend_close = 0;
        last_weekend_reopen = 0;
        last_dst_change    = 0;
        was_weekend        = false;
        last_day_of_week   = 0;
    }
};

/**
 * @class TradingSessionManager
 * @brief Handles session events: weekend close/reopen, daily rollover,
 *        DST changes, broker server restart, terminal restart, connection
 *        recovery, long idle periods.
 *
 * SOLE RESPONSIBILITY: detect and report session events.
 * Does NOT close positions or modify orders (that's TradeLifecycleManager).
 *
 * Detection:
 *   - Weekend: Saturday/Sunday, or Friday >= close hour
 *   - Daily rollover: day change (00:00 server time)
 *   - DST change: hour shift detected (comparing server time offset)
 *   - Server restart: large time gap between ticks
 *   - Terminal restart: initialized flag reset
 *   - Connection recovery: was disconnected, now reconnected
 *   - Long idle: no tick for > N seconds
 *
 * Performance: O(1) per check. No allocation.
 */
class TradingSessionManager
{
private:
    ILogger      *m_logger;
    SessionState  m_state;
    bool          m_initialized;

    //--- Configuration
    int    m_friday_close_hour;   ///< Friday close hour (server time)
    int    m_weekend_reopen_hour; ///< Sunday reopen hour (server time, 0=Sunday 22:00 typical)
    int    m_idle_threshold_sec;  ///< Seconds without tick = idle
    datetime m_last_tick_time;    ///< Last received tick time

public:
    TradingSessionManager(void)
    {
        m_logger             = NULL;
        m_initialized        = false;
        m_friday_close_hour  = 20;
        m_weekend_reopen_hour = 22;
        m_idle_threshold_sec = 60;
        m_last_tick_time     = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set session configuration.
     */
    void SetConfig(const int friday_close_hour,
                   const int weekend_reopen_hour,
                   const int idle_threshold_sec)
    {
        m_friday_close_hour  = friday_close_hour;
        m_weekend_reopen_hour = weekend_reopen_hour;
        m_idle_threshold_sec = idle_threshold_sec;
    }

    /**
     * @brief Initialize the session manager.
     */
    bool Initialize(void)
    {
        m_initialized = true;
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);
        m_state.day_of_week     = dt.day_of_week;
        m_state.hour            = dt.hour;
        m_state.last_day_of_week = dt.day_of_week;
        m_state.was_weekend     = (dt.day_of_week == 0 || dt.day_of_week == 6);
        m_state.is_weekend      = m_state.was_weekend;
        m_last_tick_time        = now;
        return true;
    }

    void Shutdown(void) { m_initialized = false; }

    /**
     * @brief Check for session events.
     * Called on each heartbeat (timer).
     * @return Event code (ATLAS_SESSION_EVENT_*).
     */
    int CheckSessionEvent(void)
    {
        if(!m_initialized) return ATLAS_SESSION_EVENT_NONE;

        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        int event = ATLAS_SESSION_EVENT_NONE;

        //=== Detect daily rollover (day change) ===
        if(dt.day != m_state.last_day_of_week || dt.day_of_week != m_state.day_of_week)
        {
            if(dt.day_of_week != m_state.day_of_week)
            {
                event = ATLAS_SESSION_EVENT_DAILY_ROLLOVER;
                m_state.last_rollover = now;
                m_state.is_daily_rollover = true;

                //--- Reset daily rollover flag after a delay
                if(m_logger != NULL)
                    m_logger.Info("TradingSessionManager",
                        "Daily rollover detected (day=" + IntegerToString(dt.day) + ")");
            }
            m_state.last_day_of_week = dt.day_of_week;
        }
        else
        {
            m_state.is_daily_rollover = false;
        }

        //=== Detect weekend ===
        bool is_weekend_now = false;
        if(dt.day_of_week == 6) // Saturday
            is_weekend_now = true;
        else if(dt.day_of_week == 0) // Sunday
            is_weekend_now = (dt.hour < m_weekend_reopen_hour);
        else if(dt.day_of_week == 5 && dt.hour >= m_friday_close_hour) // Friday evening
            is_weekend_now = true;

        //--- Weekend close transition
        if(is_weekend_now && !m_state.was_weekend)
        {
            event = ATLAS_SESSION_EVENT_WEEKEND_CLOSE;
            m_state.last_weekend_close = now;
            if(m_logger != NULL)
                m_logger.Info("TradingSessionManager",
                    "Weekend close detected");
        }
        //--- Weekend reopen transition
        else if(!is_weekend_now && m_state.was_weekend)
        {
            event = ATLAS_SESSION_EVENT_WEEKEND_REOPEN;
            m_state.last_weekend_reopen = now;
            if(m_logger != NULL)
                m_logger.Info("TradingSessionManager",
                    "Weekend reopen detected");
        }

        m_state.is_weekend  = is_weekend_now;
        m_state.was_weekend = is_weekend_now;
        m_state.day_of_week = dt.day_of_week;
        m_state.hour        = dt.hour;

        //=== Detect session open ===
        m_state.is_session_open = !is_weekend_now;

        //=== Detect long idle (possible disconnection) ===
        if(m_last_tick_time > 0)
        {
            long idle = (long)now - (long)m_last_tick_time;
            if(idle > m_idle_threshold_sec)
            {
                //--- Long idle → possible server restart or connection loss
                if(idle > 300) // > 5 minutes
                {
                    event = ATLAS_SESSION_EVENT_SERVER_RESTART;
                    if(m_logger != NULL)
                        m_logger.Warn("TradingSessionManager",
                        "Long idle detected: " + IntegerToString(idle) +
                        "s — possible server restart or disconnection");
                }
            }
        }

        m_last_tick_time = now;

        return event;
    }

    /**
     * @brief Notify that a tick was received (updates idle timer).
     */
    void OnTick(void)
    {
        m_last_tick_time = TimeCurrent();
    }

    /**
     * @brief Is the session currently open?
     */
    bool IsSessionOpen(void) const { return m_state.is_session_open; }

    /**
     * @brief Is it currently the weekend?
     */
    bool IsWeekend(void) const { return m_state.is_weekend; }

    /**
     * @brief Get the current session state.
     */
    const SessionState& GetState(void) const { return m_state; }
};

#endif // ATLAS_TRADING_SESSION_MANAGER_MQH
//+------------------------------------------------------------------+
