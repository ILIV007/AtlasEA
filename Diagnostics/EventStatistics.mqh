//+------------------------------------------------------------------+
//|                    Diagnostics/EventStatistics.mqh              |
//|       AtlasEA v0.1.14.0 - Event Statistics (Expanded)           |
//+------------------------------------------------------------------+
#ifndef ATLAS_EVENT_STATISTICS_MQH
#define ATLAS_EVENT_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IEventStatistics.mqh"
#include "../Interfaces/ILogger.mqh"

#define ATLAS_DEPTH_SAMPLES 128
#define ATLAS_EPS_WINDOW    10   ///< Seconds for EPS rolling window

/**
 * @class EventStatistics
 * @brief Expanded concrete implementation of IEventStatistics.
 */
class EventStatistics : public IEventStatistics
{
private:
    ulong  m_events_generated;
    ulong  m_events_processed;
    ulong  m_events_dropped;
    ulong  m_priority_events;
    ulong  m_rejected_events;
    ulong  m_duplicate_events;
    ulong  m_per_type_count[13];
    ulong  m_max_queue_depth;

    //--- Queue depth averaging
    int    m_depth_samples[ATLAS_DEPTH_SAMPLES];
    int    m_depth_count;
    int    m_depth_head;
    long   m_depth_sum;

    //--- NEW in v0.1.14.0 ---
    ulong  m_total_event_size;
    ulong  m_largest_event;
    ulong  m_dropped_by_reason[8];

    //--- EPS tracking
    ulong  m_eps_window_count[ATLAS_EPS_WINDOW];
    int    m_eps_head;
    datetime m_last_eps_update;
    double m_events_per_second;
    double m_peak_events_per_second;

    ILogger *m_logger;

public:
    EventStatistics(void)
    {
        m_logger = NULL;
        Reset();
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    virtual void RecordGenerated(const int event_type) override
    {
        m_events_generated++;
        if(event_type >= 0 && event_type < 13)
            m_per_type_count[event_type]++;
    }

    virtual void RecordProcessed(const int event_type) override
    {
        m_events_processed++;
    }

    virtual void RecordDropped(void) override { m_events_dropped++; }
    virtual void RecordPriority(void) override { m_priority_events++; }
    virtual void RecordRejected(void) override { m_rejected_events++; }
    virtual void RecordDuplicate(void) override { m_duplicate_events++; }

    virtual void RecordQueueDepth(const int depth) override
    {
        if(m_depth_count > 0)
        {
            int old = m_depth_samples[m_depth_head];
            m_depth_sum -= old;
        }
        m_depth_samples[m_depth_head] = depth;
        m_depth_sum += depth;
        m_depth_head = (m_depth_head + 1) % ATLAS_DEPTH_SAMPLES;
        if(m_depth_count < ATLAS_DEPTH_SAMPLES)
            m_depth_count++;

        if((ulong)depth > m_max_queue_depth)
            m_max_queue_depth = (ulong)depth;
    }

    virtual void GetStats(EventStats &out) const override
    {
        out.events_generated  = m_events_generated;
        out.events_processed  = m_events_processed;
        out.events_dropped    = m_events_dropped;
        out.priority_events   = m_priority_events;
        out.rejected_events   = m_rejected_events;
        out.duplicate_events  = m_duplicate_events;
        out.max_queue_depth   = m_max_queue_depth;

        if(m_depth_count > 0)
            out.avg_queue_depth = (double)m_depth_sum / (double)m_depth_count;
        else
            out.avg_queue_depth = 0.0;

        for(int i = 0; i < 13; i++)
            out.per_type_count[i] = m_per_type_count[i];

        //--- NEW
        out.avg_event_size = (m_events_generated > 0) ?
            (double)m_total_event_size / (double)m_events_generated : 0.0;
        out.largest_event = m_largest_event;
        for(int i = 0; i < 8; i++)
            out.dropped_by_reason[i] = m_dropped_by_reason[i];

        out.duplicate_ratio = (m_events_generated > 0) ?
            (double)m_duplicate_events / (double)m_events_generated : 0.0;
        out.priority_ratio = (m_events_generated > 0) ?
            (double)m_priority_events / (double)m_events_generated : 0.0;

        out.events_per_second = m_events_per_second;
        out.peak_events_per_second = m_peak_events_per_second;
    }

    virtual void Reset(void) override
    {
        m_events_generated  = 0;
        m_events_processed  = 0;
        m_events_dropped    = 0;
        m_priority_events   = 0;
        m_rejected_events   = 0;
        m_duplicate_events  = 0;
        m_max_queue_depth   = 0;
        for(int i = 0; i < 13; i++)
            m_per_type_count[i] = 0;
        m_depth_count = 0;
        m_depth_head  = 0;
        m_depth_sum   = 0;
        for(int i = 0; i < ATLAS_DEPTH_SAMPLES; i++)
            m_depth_samples[i] = 0;

        //--- NEW
        m_total_event_size = 0;
        m_largest_event    = 0;
        for(int i = 0; i < 8; i++)
            m_dropped_by_reason[i] = 0;
        m_eps_head = 0;
        m_last_eps_update = 0;
        m_events_per_second = 0.0;
        m_peak_events_per_second = 0.0;
        for(int i = 0; i < ATLAS_EPS_WINDOW; i++)
            m_eps_window_count[i] = 0;
    }

    //--- NEW in v0.1.14.0 ---

    virtual void RecordEventSize(const ulong bytes) override
    {
        m_total_event_size += bytes;
        if(bytes > m_largest_event)
            m_largest_event = bytes;
    }

    virtual void RecordDroppedByReason(const int reason_code) override
    {
        if(reason_code >= 0 && reason_code < 8)
            m_dropped_by_reason[reason_code]++;
    }

    virtual void UpdateEventsPerSecond(void) override
    {
        datetime now = TimeCurrent();
        if(m_last_eps_update == 0)
        {
            m_last_eps_update = now;
            return;
        }

        long elapsed = (long)(now - m_last_eps_update);
        if(elapsed <= 0) return;

        //--- Shift window and add current count
        ulong current_count = m_events_generated;
        ulong window_total = 0;
        for(int i = 0; i < ATLAS_EPS_WINDOW; i++)
            window_total += m_eps_window_count[i];

        m_events_per_second = (double)window_total / (double)(ATLAS_EPS_WINDOW);
        if(m_events_per_second > m_peak_events_per_second)
            m_peak_events_per_second = m_events_per_second;

        m_last_eps_update = now;
    }
};

#endif // ATLAS_EVENT_STATISTICS_MQH
//+------------------------------------------------------------------+
