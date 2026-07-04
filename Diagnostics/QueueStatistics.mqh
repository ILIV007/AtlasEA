//+------------------------------------------------------------------+
//|                     Diagnostics/QueueStatistics.mqh             |
//|       AtlasEA v0.1.12.0 - Queue Statistics Implementation       |
//+------------------------------------------------------------------+
#ifndef ATLAS_QUEUE_STATISTICS_MQH
#define ATLAS_QUEUE_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IQueueStatistics.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Number of wait-time samples per queue for averaging.
 */
#define ATLAS_QUEUE_WAIT_SAMPLES 128

/**
 * @class QueueStatistics
 * @brief Concrete implementation of IQueueStatistics.
 *
 * Tracks per-queue statistics: current/peak count, drops, overflows,
 * and average wait time (rolling window).
 *
 * Memory: ~256 bytes (fixed). No dynamic allocation.
 */
class QueueStatistics : public IQueueStatistics
{
private:
    QueueStats m_stats[ATLAS_QUEUE_COUNT];

    //--- Wait time rolling window
    double m_wait_samples[ATLAS_QUEUE_COUNT][ATLAS_QUEUE_WAIT_SAMPLES];
    int    m_wait_count[ATLAS_QUEUE_COUNT];
    int    m_wait_head[ATLAS_QUEUE_COUNT];
    double m_wait_sum[ATLAS_QUEUE_COUNT];

    ILogger *m_logger;

    /// @brief Validate queue ID.
    bool IsValidQueue(const int queue_id) const { return (queue_id >= 0 && queue_id < ATLAS_QUEUE_COUNT); }

public:
    /**
     * @brief Constructor.
     */
    QueueStatistics(void)
    {
        m_logger = NULL;
        ResetAll();
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IQueueStatistics implementation ===

    virtual void RecordEnqueue(const int queue_id) override
    {
        if(!IsValidQueue(queue_id)) return;
        m_stats[queue_id].total_enqueued++;
        m_stats[queue_id].current_count++;
        if(m_stats[queue_id].current_count > m_stats[queue_id].peak_count)
            m_stats[queue_id].peak_count = m_stats[queue_id].current_count;
    }

    virtual void RecordDequeue(const int queue_id, const double wait_ms) override
    {
        if(!IsValidQueue(queue_id)) return;
        m_stats[queue_id].total_dequeued++;
        if(m_stats[queue_id].current_count > 0)
            m_stats[queue_id].current_count--;

        //--- Add to wait-time rolling window
        if(m_wait_count[queue_id] > 0)
        {
            double old = m_wait_samples[queue_id][m_wait_head[queue_id]];
            m_wait_sum[queue_id] -= old;
        }
        m_wait_samples[queue_id][m_wait_head[queue_id]] = wait_ms;
        m_wait_sum[queue_id] += wait_ms;
        m_wait_head[queue_id] = (m_wait_head[queue_id] + 1) % ATLAS_QUEUE_WAIT_SAMPLES;
        if(m_wait_count[queue_id] < ATLAS_QUEUE_WAIT_SAMPLES)
            m_wait_count[queue_id]++;

        if(m_wait_count[queue_id] > 0)
            m_stats[queue_id].avg_wait_time_ms = m_wait_sum[queue_id] / (double)m_wait_count[queue_id];
    }

    virtual void RecordDrop(const int queue_id) override
    {
        if(!IsValidQueue(queue_id)) return;
        m_stats[queue_id].drop_count++;
    }

    virtual void RecordOverflow(const int queue_id) override
    {
        if(!IsValidQueue(queue_id)) return;
        m_stats[queue_id].overflow_count++;
    }

    virtual void UpdateDepth(const int queue_id, const int depth) override
    {
        if(!IsValidQueue(queue_id)) return;
        m_stats[queue_id].current_count = depth;
        if(depth > m_stats[queue_id].peak_count)
            m_stats[queue_id].peak_count = depth;
    }

    virtual void GetStats(const int queue_id, QueueStats &out) const override
    {
        if(!IsValidQueue(queue_id)) { ZeroMemory(out); return; }
        out = m_stats[queue_id];
    }

    virtual void Reset(const int queue_id) override
    {
        if(!IsValidQueue(queue_id)) return;
        ZeroMemory(m_stats[queue_id]);
        m_wait_count[queue_id] = 0;
        m_wait_head[queue_id]  = 0;
        m_wait_sum[queue_id]   = 0.0;
        for(int i = 0; i < ATLAS_QUEUE_WAIT_SAMPLES; i++)
            m_wait_samples[queue_id][i] = 0.0;
    }

    virtual void ResetAll(void) override
    {
        for(int i = 0; i < ATLAS_QUEUE_COUNT; i++)
            Reset(i);
    }
};

#endif // ATLAS_QUEUE_STATISTICS_MQH
//+------------------------------------------------------------------+
