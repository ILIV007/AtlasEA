//+------------------------------------------------------------------+
//|                        Interfaces/IMemoryStatistics.mqh         |
//|       AtlasEA v0.1.12.0 - Memory Statistics Interface           |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMEMORY_STATISTICS_MQH
#define ATLAS_IMEMORY_STATISTICS_MQH

#include "../Config/Settings.mqh"

/**
 * @struct MemorySnapshot
 * @brief Point-in-time memory usage snapshot (expanded v0.1.14.0).
 */
struct MemorySnapshot
{
    ulong  array_usage_bytes;        ///< Estimated array memory in use
    ulong  ringbuffer_usage_bytes;   ///< Ring buffer memory in use
    ulong  context_size_bytes;       ///< AtlasContext instance size
    ulong  contract_size_bytes;      ///< Contract struct sizes
    ulong  event_queue_usage;        ///< Event queue used slots
    ulong  snapshot_size_bytes;      ///< Last snapshot size
    ulong  peak_memory_mb;           ///< Peak MQL5 memory (MB)
    ulong  current_memory_mb;        ///< Current MQL5 memory (MB)
    double memory_growth_pct;        ///< Growth since baseline (%)

    //--- NEW in v0.1.14.0 ---
    ulong  event_queue_size_bytes;   ///< Event queue total size (bytes)
    ulong  priority_queue_size_bytes;///< Priority queue total size (bytes)
    ulong  estimated_static_memory;  ///< Estimated static memory (compile-time)
    ulong  estimated_runtime_memory; ///< Estimated runtime memory (current)
    double memory_growth_rate;       ///< Growth rate (MB/sec)
    ulong  peak_usage_bytes;         ///< Peak total usage (bytes)
};

/**
 * @class IMemoryStatistics
 * @brief Interface for monitoring memory usage (expanded v0.1.14.0).
 */
class IMemoryStatistics
{
public:
    virtual void RecordArrayUsage(const ulong bytes) = 0;
    virtual void RecordRingBufferUsage(const ulong bytes) = 0;
    virtual void RecordContextSize(const ulong bytes) = 0;
    virtual void RecordContractSize(const ulong bytes) = 0;
    virtual void RecordEventQueueUsage(const ulong slots) = 0;
    virtual void RecordSnapshotSize(const ulong bytes) = 0;
    virtual void UpdateMqlMemory(void) = 0;
    virtual MemorySnapshot GetSnapshot(void) const = 0;
    virtual void SetBaseline(void) = 0;
    virtual void Reset(void) = 0;

    //--- NEW in v0.1.14.0 ---
    virtual void RecordEventQueueSize(const ulong bytes) = 0;
    virtual void RecordPriorityQueueSize(const ulong bytes) = 0;
    virtual void RecordStaticMemory(const ulong bytes) = 0;
    virtual void UpdateGrowthRate(void) = 0;

    virtual ~IMemoryStatistics(void) {}
};

#endif // ATLAS_IMEMORY_STATISTICS_MQH
//+------------------------------------------------------------------+
