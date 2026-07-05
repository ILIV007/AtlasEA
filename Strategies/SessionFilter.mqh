//+------------------------------------------------------------------+
//|                     Strategies/SessionFilter.mqh                 |
//|       AtlasEA v1.0 Step 3 - Reusable Session Filter              |
//+------------------------------------------------------------------+
#ifndef ATLAS_SESSION_FILTER_STRAT_MQH
#define ATLAS_SESSION_FILTER_STRAT_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Session bit flags (for session mask).
 */
#define ATLAS_SESS_MASK_OFF     0x01
#define ATLAS_SESS_MASK_TOKYO   0x02
#define ATLAS_SESS_MASK_LONDON  0x04
#define ATLAS_SESS_MASK_NY      0x08
#define ATLAS_SESS_MASK_OVERLAP 0x10
#define ATLAS_SESS_MASK_ALL     0x1F

/**
 * @struct SessionFilterConfig
 * @brief Configuration for the session filter.
 */
struct SessionFilterConfig
{
    int    session_mask;           ///< Bitmask of allowed sessions
    bool   block_weekend;          ///< Block Saturday/Sunday
    int    friday_close_hour;      ///< Friday close hour (server time)
    int    session_open_hour;      ///< Earliest hour to trade
    int    session_close_hour;     ///< Latest hour to trade

    SessionFilterConfig(void)
    {
        session_mask       = ATLAS_SESS_MASK_ALL;
        block_weekend      = true;
        friday_close_hour  = 20;
        session_open_hour  = 0;
        session_close_hour = 23;
    }
};

/**
 * @class SessionFilter
 * @brief Reusable session filter for strategies.
 *
 * Supports:
 *   - Tokyo (00:00-09:00 UTC)
 *   - London (08:00-17:00 UTC)
 *   - New York (13:00-22:00 UTC)
 *   - Overlap (13:00-17:00 UTC)
 *   - Weekend blocking
 *   - Friday early close
 *   - Configurable session mask
 *
 * Usage:
 *   SessionFilter sf;
 *   sf.SetConfig(config);
 *   if(sf.Passes(timestamp)) { ... proceed ... }
 *
 * Performance: O(1), no allocation, no recursion.
 */
class SessionFilter
{
private:
    SessionFilterConfig m_config;

public:
    /**
     * @brief Set the configuration.
     */
    void SetConfig(const SessionFilterConfig &config) { m_config = config; }

    /**
     * @brief Get the configuration.
     */
    const SessionFilterConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Check if the current time passes the session filter.
     * @param timestamp The timestamp to check (0 = use TimeCurrent()).
     * @return true if the time is within an allowed session.
     */
    bool Passes(const datetime timestamp = 0) const
    {
        datetime t = (timestamp > 0) ? timestamp : TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(t, dt);

        //--- Weekend check
        if(m_config.block_weekend)
        {
            if(dt.day_of_week == 6 || dt.day_of_week == 0)
                return false;
            //--- Friday close
            if(dt.day_of_week == 5 && dt.hour >= m_config.friday_close_hour)
                return false;
        }

        //--- Hour range check
        if(dt.hour < m_config.session_open_hour || dt.hour > m_config.session_close_hour)
            return false;

        //--- Session mask check
        int sess = DetectSession(dt.hour);
        int mask = 1 << sess;
        if((m_config.session_mask & mask) == 0)
            return false;

        return true;
    }

    /**
     * @brief Detect which session the given hour belongs to.
     * @param hour UTC hour (0-23).
     * @return Session code (0=OFF, 1=TOKYO, 2=LONDON, 3=NY, 4=OVERLAP).
     */
    int DetectSession(const int hour) const
    {
        //--- Overlap: London + NY (13:00-17:00)
        if(hour >= 13 && hour < 17) return 4; // OVERLAP
        //--- Tokyo: 00:00-09:00
        if(hour >= 0 && hour < 9) return 1;   // TOKYO
        //--- London: 08:00-17:00
        if(hour >= 8 && hour < 17) return 2;  // LONDON
        //--- New York: 13:00-22:00
        if(hour >= 13 && hour < 22) return 3; // NY
        return 0; // OFF
    }

    /**
     * @brief Get the current session name.
     */
    string GetCurrentSessionName(void) const
    {
        int sess = DetectSession(TimeToStruct_hour(TimeCurrent()));
        switch(sess)
        {
            case 0: return "OFF";
            case 1: return "TOKYO";
            case 2: return "LONDON";
            case 3: return "NEW_YORK";
            case 4: return "OVERLAP";
        }
        return "UNKNOWN";
    }

    /**
     * @brief Get the reason the filter rejected (for diagnostics).
     * @return Reason string, or "OK" if passes.
     */
    string RejectReason(const datetime timestamp = 0) const
    {
        datetime t = (timestamp > 0) ? timestamp : TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(t, dt);

        if(m_config.block_weekend)
        {
            if(dt.day_of_week == 6 || dt.day_of_week == 0)
                return "weekend";
            if(dt.day_of_week == 5 && dt.hour >= m_config.friday_close_hour)
                return "friday_close";
        }
        if(dt.hour < m_config.session_open_hour)
            return "before_session_open";
        if(dt.hour > m_config.session_close_hour)
            return "after_session_close";

        int sess = DetectSession(dt.hour);
        int mask = 1 << sess;
        if((m_config.session_mask & mask) == 0)
            return "session_not_allowed";

        return "OK";
    }

private:
    int TimeToStruct_hour(const datetime t) const
    {
        MqlDateTime dt;
        TimeToStruct(t, dt);
        return dt.hour;
    }
};

#endif // ATLAS_SESSION_FILTER_STRAT_MQH
//+------------------------------------------------------------------+
