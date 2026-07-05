//+------------------------------------------------------------------+
//|                    Trading/Filters/SessionFilter.mqh             |
//|       AtlasEA v0.2.2 - Trading Session Filter                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_SESSION_FILTER_MQH
#define ATLAS_SESSION_FILTER_MQH

#include "IFilter.mqh"

/**
 * @brief Maximum number of custom sessions.
 */
#define ATLAS_MAX_CUSTOM_SESSIONS 8

/**
 * @struct SessionWindow
 * @brief A trading session time window (in server time hours/minutes).
 */
struct SessionWindow
{
    int  start_hour;     ///< Start hour (0-23)
    int  start_minute;   ///< Start minute (0-59)
    int  end_hour;       ///< End hour (0-23)
    int  end_minute;     ///< End minute (0-59)
    bool enabled;        ///< Is this session enabled?
    string name;         ///< Session name (e.g., "Tokyo")

    SessionWindow(void)
    {
        start_hour   = 0;
        start_minute = 0;
        end_hour     = 0;
        end_minute   = 0;
        enabled      = true;
        name         = "";
    }
};

/**
 * @struct SessionFilterConfig
 * @brief Configuration for the session filter.
 */
struct SessionFilterConfig
{
    FilterConfig base;                   ///< Base config
    bool   allow_tokyo;                  ///< Allow Tokyo session
    bool   allow_london;                 ///< Allow London session
    bool   allow_new_york;               ///< Allow New York session
    bool   allow_overlap;                ///< Allow London/NY overlap
    bool   block_weekend;                ///< Block all trading on weekends
    SessionWindow custom[ATLAS_MAX_CUSTOM_SESSIONS]; ///< Custom sessions
    int    custom_count;                 ///< Number of custom sessions

    SessionFilterConfig(void)
    {
        base.enabled      = true;
        base.priority     = 20;
        base.reason_code  = ATLAS_FR_SESSION_CLOSED;
        allow_tokyo       = true;
        allow_london      = true;
        allow_new_york    = true;
        allow_overlap     = true;
        block_weekend     = true;
        custom_count      = 0;
    }
};

/**
 * @class SessionFilter
 * @brief Allows trading only during configured sessions.
 *
 * SOLE RESPONSIBILITY: check that the current time falls within an
 * allowed trading session.
 *
 * Built-in sessions (server time):
 *   - Tokyo:    00:00 - 09:00 UTC
 *   - London:   08:00 - 17:00 UTC
 *   - New York: 13:00 - 22:00 UTC
 *   - Overlap:  13:00 - 17:00 UTC (London + NY)
 *
 * Custom sessions: up to ATLAS_MAX_CUSTOM_SESSIONS custom windows
 * can be added via AddCustomSession().
 *
 * Weekend blocking: if block_weekend is true, all signals on Saturday
 * and Sunday are rejected (BLOCK).
 *
 * The filter uses the signal's timestamp (or TimeCurrent() if the
 * timestamp is zero) to determine the current session.
 *
 * Memory: ~400 bytes (config with 8 custom sessions).
 */
class SessionFilter : public IFilter
{
private:
    ILogger             *m_logger;
    SessionFilterConfig  m_config;
    bool                 m_initialized;

    //--- Built-in session windows (UTC hours)
    SessionWindow m_tokyo;
    SessionWindow m_london;
    SessionWindow m_new_york;
    SessionWindow m_overlap;

public:
    /**
     * @brief Constructor.
     */
    SessionFilter(void)
    {
        m_logger      = NULL;
        m_initialized = false;

        //--- Built-in sessions (UTC)
        m_tokyo.name         = "Tokyo";
        m_tokyo.start_hour   = 0;  m_tokyo.start_minute = 0;
        m_tokyo.end_hour     = 9;  m_tokyo.end_minute   = 0;
        m_tokyo.enabled      = true;

        m_london.name        = "London";
        m_london.start_hour  = 8;  m_london.start_minute = 0;
        m_london.end_hour    = 17; m_london.end_minute   = 0;
        m_london.enabled     = true;

        m_new_york.name      = "NewYork";
        m_new_york.start_hour = 13; m_new_york.start_minute = 0;
        m_new_york.end_hour   = 22; m_new_york.end_minute   = 0;
        m_new_york.enabled    = true;

        m_overlap.name       = "Overlap";
        m_overlap.start_hour = 13; m_overlap.start_minute = 0;
        m_overlap.end_hour   = 17; m_overlap.end_minute   = 0;
        m_overlap.enabled    = true;
    }

    //=== IFilter implementation ===

    virtual string GetName(void) const override { return "SessionFilter"; }

    virtual FilterConfig GetConfig(void) const override { return m_config.base; }

    virtual void SetConfig(const FilterConfig &config) override
    {
        m_config.base = config;
    }

    void SetSessionConfig(const SessionFilterConfig &config) { m_config = config; }
    SessionFilterConfig GetSessionConfig(void) const { return m_config; }

    virtual void SetLogger(ILogger *logger) override { m_logger = logger; }

    virtual bool Initialize(void) override
    {
        m_initialized = true;
        return true;
    }

    virtual void Shutdown(void) override
    {
        m_initialized = false;
    }

    /**
     * @brief Add a custom session window.
     */
    bool AddCustomSession(const string name,
                           const int start_hour, const int start_minute,
                           const int end_hour, const int end_minute)
    {
        if(m_config.custom_count >= ATLAS_MAX_CUSTOM_SESSIONS) return false;
        SessionWindow &s = m_config.custom[m_config.custom_count];
        s.name         = name;
        s.start_hour   = start_hour;
        s.start_minute = start_minute;
        s.end_hour     = end_hour;
        s.end_minute   = end_minute;
        s.enabled      = true;
        m_config.custom_count++;
        return true;
    }

    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) override
    {
        if(!m_config.base.enabled)
            return FilterResult::Skip(GetName(), ATLAS_FR_FILTER_DISABLED, "disabled");

        //--- Get the evaluation time (use signal timestamp, or TimeCurrent)
        datetime eval_time = (signal.timestamp > 0) ? signal.timestamp : TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(eval_time, dt);

        //--- Weekend check
        if(m_config.block_weekend)
        {
            //--- Saturday = 6, Sunday = 0
            if(dt.day_of_week == 0 || dt.day_of_week == 6)
                return FilterResult::Block(GetName(), ATLAS_FR_SESSION_WEEKEND,
                    "weekend (day=" + IntegerToString(dt.day_of_week) + ")");
        }

        //--- Check built-in sessions
        if(m_config.allow_overlap && IsInSession(dt, m_overlap))
            return FilterResult::Pass(GetName());
        if(m_config.allow_tokyo && IsInSession(dt, m_tokyo))
            return FilterResult::Pass(GetName());
        if(m_config.allow_london && IsInSession(dt, m_london))
            return FilterResult::Pass(GetName());
        if(m_config.allow_new_york && IsInSession(dt, m_new_york))
            return FilterResult::Pass(GetName());

        //--- Check custom sessions
        for(int i = 0; i < m_config.custom_count; i++)
        {
            if(m_config.custom[i].enabled && IsInSession(dt, m_config.custom[i]))
                return FilterResult::Pass(GetName());
        }

        //--- Not in any allowed session
        return FilterResult::Block(GetName(), ATLAS_FR_SESSION_CLOSED,
            "outside all allowed sessions at " +
            IntegerToString(dt.hour) + ":" + IntegerToString(dt.min));
    }

    /**
     * @brief Get the name of the current active session (for diagnostics).
     */
    string GetCurrentSession(void) const
    {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        if(m_config.allow_overlap && IsInSession(dt, m_overlap)) return "Overlap";
        if(m_config.allow_tokyo && IsInSession(dt, m_tokyo))     return "Tokyo";
        if(m_config.allow_london && IsInSession(dt, m_london))   return "London";
        if(m_config.allow_new_york && IsInSession(dt, m_new_york)) return "NewYork";

        for(int i = 0; i < m_config.custom_count; i++)
            if(m_config.custom[i].enabled && IsInSession(dt, m_config.custom[i]))
                return m_config.custom[i].name;

        return "None";
    }

private:
    /**
     * @brief Check if a datetime falls within a session window.
     * Handles overnight sessions (end_hour < start_hour).
     */
    bool IsInSession(const MqlDateTime &dt, const SessionWindow &sess) const
    {
        if(!sess.enabled) return false;

        int current_min = dt.hour * 60 + dt.min;
        int start_min   = sess.start_hour * 60 + sess.start_minute;
        int end_min     = sess.end_hour * 60 + sess.end_minute;

        if(end_min > start_min)
        {
            //--- Same-day session
            return current_min >= start_min && current_min < end_min;
        }
        else if(end_min < start_min)
        {
            //--- Overnight session (wraps past midnight)
            return current_min >= start_min || current_min < end_min;
        }
        //--- start == end → 24h session (always open)
        return true;
    }
};

#endif // ATLAS_SESSION_FILTER_MQH
//+------------------------------------------------------------------+
