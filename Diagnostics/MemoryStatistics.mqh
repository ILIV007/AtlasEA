//+------------------------------------------------------------------+
//|                     Diagnostics/MemoryStatistics.mqh            |
//|       AtlasEA v0.1.14.0 - Memory Statistics (Expanded)           |
//+------------------------------------------------------------------+
#ifndef ATLAS_MEMORY_STATISTICS_MQH
#define ATLAS_MEMORY_STATISTICS_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IMemoryStatistics.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class MemoryStatistics
 * @brief Expanded concrete implementation of IMemoryStatistics.
 *
 * Tracks 10 memory metrics:
 *   1. Array usage
 *   2. RingBuffer usage
 *   3. AtlasContext size
 *   4. Contract sizes
 *   5. Event Queue size
 *   6. Priority Queue size
 *   7. Snapshot size
 *   8. Static memory estimate
 *   9. Runtime memory estimate
 *  10. Peak usage + growth rate
 *
 * Memory: ~192 bytes (fixed). No dynamic allocation.
 */
class MemoryStatistics : public IMemoryStatistics
{
private:
    ulong   m_array_usage_bytes;
    ulong   m_ringbuffer_usage_bytes;
    ulong   m_context_size_bytes;
    ulong   m_contract_size_bytes;
    ulong   m_event_queue_slots;
    ulong   m_event_queue_size_bytes;
    ulong   m_priority_queue_size_bytes;
    ulong   m_snapshot_size_bytes;
    ulong   m_static_memory;
    ulong   m_peak_memory_mb;
    ulong   m_current_memory_mb;
    ulong   m_baseline_memory_mb;
    ulong   m_peak_usage_bytes;
    double  m_memory_growth_rate;
    datetime m_last_growth_check;
    ulong   m_last_growth_memory;
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     */
    MemoryStatistics(void)
    {
        m_logger                    = NULL;
        m_array_usage_bytes         = 0;
        m_ringbuffer_usage_bytes    = 0;
        m_context_size_bytes        = 0;
        m_contract_size_bytes       = 0;
        m_event_queue_slots         = 0;
        m_event_queue_size_bytes    = 0;
        m_priority_queue_size_bytes = 0;
        m_snapshot_size_bytes       = 0;
        m_static_memory             = 0;
        m_peak_memory_mb            = 0;
        m_current_memory_mb         = 0;
        m_baseline_memory_mb        = 0;
        m_peak_usage_bytes          = 0;
        m_memory_growth_rate        = 0.0;
        m_last_growth_check         = 0;
        m_last_growth_memory        = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IMemoryStatistics implementation ===

    virtual void RecordArrayUsage(const ulong bytes) override { m_array_usage_bytes = bytes; }
    virtual void RecordRingBufferUsage(const ulong bytes) override { m_ringbuffer_usage_bytes = bytes; }
    virtual void RecordContextSize(const ulong bytes) override { m_context_size_bytes = bytes; }
    virtual void RecordContractSize(const ulong bytes) override { m_contract_size_bytes = bytes; }
    virtual void RecordEventQueueUsage(const ulong slots) override { m_event_queue_slots = slots; }
    virtual void RecordSnapshotSize(const ulong bytes) override { m_snapshot_size_bytes = bytes; }

    virtual void UpdateMqlMemory(void) override
    {
        m_current_memory_mb = (ulong)MQLInfoInteger(MQL_MEMORY_USED);
        if(m_current_memory_mb > m_peak_memory_mb)
            m_peak_memory_mb = m_current_memory_mb;

        ulong runtime = m_current_memory_mb * 1024 * 1024;
        if(runtime > m_peak_usage_bytes)
            m_peak_usage_bytes = runtime;
    }

    virtual MemorySnapshot GetSnapshot(void) const override
    {
        MemorySnapshot snap;
        snap.array_usage_bytes         = m_array_usage_bytes;
        snap.ringbuffer_usage_bytes    = m_ringbuffer_usage_bytes;
        snap.context_size_bytes        = m_context_size_bytes;
        snap.contract_size_bytes       = m_contract_size_bytes;
        snap.event_queue_usage         = m_event_queue_slots;
        snap.snapshot_size_bytes       = m_snapshot_size_bytes;
        snap.peak_memory_mb            = m_peak_memory_mb;
        snap.current_memory_mb         = m_current_memory_mb;
        snap.event_queue_size_bytes    = m_event_queue_size_bytes;
        snap.priority_queue_size_bytes = m_priority_queue_size_bytes;
        snap.estimated_static_memory   = m_static_memory;
        snap.estimated_runtime_memory  = m_current_memory_mb * 1024 * 1024;
        snap.memory_growth_rate        = m_memory_growth_rate;
        snap.peak_usage_bytes          = m_peak_usage_bytes;

        if(m_baseline_memory_mb > 0)
            snap.memory_growth_pct = ((double)(m_current_memory_mb - m_baseline_memory_mb) /
                                      (double)m_baseline_memory_mb) * 100.0;
        else
            snap.memory_growth_pct = 0.0;

        return snap;
    }

    virtual void SetBaseline(void) override
    {
        UpdateMqlMemory();
        m_baseline_memory_mb = m_current_memory_mb;
        m_last_growth_check  = TimeCurrent();
        m_last_growth_memory = m_current_memory_mb;
    }

    virtual void Reset(void) override
    {
        m_array_usage_bytes         = 0;
        m_ringbuffer_usage_bytes    = 0;
        m_context_size_bytes        = 0;
        m_contract_size_bytes       = 0;
        m_event_queue_slots         = 0;
        m_event_queue_size_bytes    = 0;
        m_priority_queue_size_bytes = 0;
        m_snapshot_size_bytes       = 0;
        m_static_memory             = 0;
        m_peak_memory_mb            = 0;
        m_current_memory_mb         = 0;
        m_baseline_memory_mb        = 0;
        m_peak_usage_bytes          = 0;
        m_memory_growth_rate        = 0.0;
        m_last_growth_check         = 0;
        m_last_growth_memory        = 0;
    }

    //--- NEW in v0.1.14.0 ---

    virtual void RecordEventQueueSize(const ulong bytes) override
    {
        m_event_queue_size_bytes = bytes;
    }

    virtual void RecordPriorityQueueSize(const ulong bytes) override
    {
        m_priority_queue_size_bytes = bytes;
    }

    virtual void RecordStaticMemory(const ulong bytes) override
    {
        m_static_memory = bytes;
    }

    virtual void UpdateGrowthRate(void) override
    {
        datetime now = TimeCurrent();
        if(m_last_growth_check == 0)
        {
            m_last_growth_check  = now;
            m_last_growth_memory = m_current_memory_mb;
            return;
        }

        long elapsed_sec = (long)(now - m_last_growth_check);
        if(elapsed_sec <= 0) return;

        long mem_delta = (long)(m_current_memory_mb - m_last_growth_memory);
        m_memory_growth_rate = (double)mem_delta / (double)elapsed_sec;

        m_last_growth_check  = now;
        m_last_growth_memory = m_current_memory_mb;
    }
};

#endif // ATLAS_MEMORY_STATISTICS_MQH
//+------------------------------------------------------------------+
