//+------------------------------------------------------------------+
//|                         Engines/MarketEngine/SessionDetector.mqh  |
//|          AtlasEA v0.1.1.0 - Trading Session Detection            |
//+------------------------------------------------------------------+
#ifndef ATLAS_SESSION_DETECTOR_MQH
#define ATLAS_SESSION_DETECTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @class SessionDetector
 * @brief Classifies the current time into a trading session.
 *
 * Sessions detected:
 *   - ATLAS_SESSION_OFF     : Outside all sessions / weekend / holiday
 *   - ATLAS_SESSION_ASIAN   : Tokyo (00:00-07:00 UTC)
 *   - ATLAS_SESSION_LONDON  : London (07:00-13:00 UTC)
 *   - ATLAS_SESSION_OVERLAP : London + NY overlap (13:00-17:00 UTC)
 *   - ATLAS_SESSION_NY      : New York (17:00-21:00 UTC)
 *
 * Weekend detection: Saturday and Sunday (server time).
 * Holiday detection: Simplified — checks for known fixed-date holidays
 *   (Jan 1, Dec 25, Dec 26, Jan 1). A full holiday calendar would
 *   require external data; this covers the major fixed-date closures.
 *
 * All checks are O(1). No allocation. No external dependencies.
 *
 * Note: Session hours are in UTC. The EA uses TimeCurrent() which
 * returns broker server time. The offset between server time and UTC
 * is configurable via m_server_utc_offset_hours.
 */
class SessionDetector
{
private:
    ILogger *m_logger;
    int      m_server_utc_offset_hours;  ///< Server time - UTC (in hours)

    /// @brief Check if the given date is a weekend (Saturday or Sunday).
    bool IsWeekend(const MqlDateTime &dt) const;

    /// @brief Check if the given date is a known holiday.
    bool IsHoliday(const MqlDateTime &dt) const;

public:
    /**
     * @brief Constructor.
     */
    SessionDetector(void);

    /**
     * @brief Initialize the session detector.
     * @param logger             Logger.
     * @param server_utc_offset  Broker server time minus UTC (hours).
     */
    void Initialize(ILogger *logger, const int server_utc_offset);

    /**
     * @brief Detect the current trading session.
     * @param server_time Current broker server time.
     * @return Session code (ATLAS_SESSION_*).
     */
    int DetectSession(const datetime server_time) const;

    /**
     * @brief Check if the market is currently open (not weekend/holiday/off).
     * @param server_time Current broker server time.
     * @return true if a trading session is active.
     */
    bool IsMarketOpen(const datetime server_time) const;

    /**
     * @brief Get a human-readable name for a session code.
     */
    string SessionName(const int session_code) const;
};

//+------------------------------------------------------------------+
//| SessionDetector implementation                                    |
//+------------------------------------------------------------------+

SessionDetector::SessionDetector(void)
{
    m_logger                  = NULL;
    m_server_utc_offset_hours = 0;
}

//+------------------------------------------------------------------+
void SessionDetector::Initialize(ILogger *logger, const int server_utc_offset)
{
    m_logger                  = logger;
    m_server_utc_offset_hours = server_utc_offset;
}

//+------------------------------------------------------------------+
bool SessionDetector::IsWeekend(const MqlDateTime &dt) const
{
    //--- day_of_week: 0=Sunday, 6=Saturday
    return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

//+------------------------------------------------------------------+
bool SessionDetector::IsHoliday(const MqlDateTime &dt) const
{
    //--- Major fixed-date holidays (FX market closures)
    //--- New Year's Day (Jan 1)
    if(dt.mon == 1 && dt.day == 1) return true;
    //--- Christmas Day (Dec 25)
    if(dt.mon == 12 && dt.day == 25) return true;
    //--- Boxing Day (Dec 26)
    if(dt.mon == 12 && dt.day == 26) return true;

    return false;
}

//+------------------------------------------------------------------+
int SessionDetector::DetectSession(const datetime server_time) const
{
    MqlDateTime dt;
    TimeToStruct(server_time, dt);

    //--- Weekend check
    if(IsWeekend(dt))
        return ATLAS_SESSION_OFF;

    //--- Holiday check
    if(IsHoliday(dt))
        return ATLAS_SESSION_OFF;

    //--- Convert server time to UTC
    int utc_hour = dt.hour - m_server_utc_offset_hours;
    //--- Normalize to 0-23 range
    while(utc_hour < 0)  utc_hour += 24;
    while(utc_hour >= 24) utc_hour -= 24;

    //--- Session classification (UTC hours):
    //--- Asian:   00:00 - 07:00 UTC (Tokyo)
    //--- London:  07:00 - 13:00 UTC
    //--- Overlap: 13:00 - 17:00 UTC (London + NY)
    //--- NY:      17:00 - 21:00 UTC
    //--- Off:     21:00 - 24:00 UTC

    if(utc_hour >= 0  && utc_hour < 7)  return ATLAS_SESSION_ASIAN;
    if(utc_hour >= 7  && utc_hour < 13) return ATLAS_SESSION_LONDON;
    if(utc_hour >= 13 && utc_hour < 17) return ATLAS_SESSION_OVERLAP;
    if(utc_hour >= 17 && utc_hour < 21) return ATLAS_SESSION_NY;

    return ATLAS_SESSION_OFF;
}

//+------------------------------------------------------------------+
bool SessionDetector::IsMarketOpen(const datetime server_time) const
{
    int session = DetectSession(server_time);
    return (session != ATLAS_SESSION_OFF);
}

//+------------------------------------------------------------------+
string SessionDetector::SessionName(const int session_code) const
{
    switch(session_code)
    {
        case ATLAS_SESSION_OFF:     return "OFF";
        case ATLAS_SESSION_ASIAN:   return "ASIAN";
        case ATLAS_SESSION_LONDON:  return "LONDON";
        case ATLAS_SESSION_NY:      return "NY";
        case ATLAS_SESSION_OVERLAP: return "OVERLAP";
    }
    return "UNKNOWN";
}

#endif // ATLAS_SESSION_DETECTOR_MQH
//+------------------------------------------------------------------+
