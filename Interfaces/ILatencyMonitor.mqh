//+------------------------------------------------------------------+
//|                          Interfaces/ILatencyMonitor.mqh         |
//|       AtlasEA v0.1.12.0 - Latency Monitor Interface             |
//+------------------------------------------------------------------+
#ifndef ATLAS_ILATENCY_MONITOR_MQH
#define ATLAS_ILATENCY_MONITOR_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Latency type identifiers.
 */
#define ATLAS_LATENCY_TICK        0   ///< OnTick total
#define ATLAS_LATENCY_PIPELINE    1   ///< Full pipeline (Market→Execution)
#define ATLAS_LATENCY_ORDER       2   ///< OrderSend total
#define ATLAS_LATENCY_BROKER      3   ///< Broker round-trip
#define ATLAS_LATENCY_TRADE_FILL  4   ///< Trade execution to fill
#define ATLAS_LATENCY_PERSISTENCE 5   ///< Snapshot write
#define ATLAS_LATENCY_RECOVERY    6   ///< Startup recovery
#define ATLAS_LATENCY_COUNT       7

/**
 * @struct LatencyStats
 * @brief Rolling statistics for one latency type (expanded v0.1.14.0).
 */
struct LatencyStats
{
    ulong  count;           ///< Number of samples
    double avg_ms;          ///< Average (ms)
    double min_ms;          ///< Minimum (ms)
    double max_ms;          ///< Maximum (ms)
    double p50_ms;          ///< 50th percentile (ms)
    double p95_ms;          ///< 95th percentile (ms)
    double p99_ms;          ///< 99th percentile (ms)
    double last_ms;         ///< Last sample (ms)

    //--- NEW in v0.1.14.0 ---
    double worst_1pct_ms;   ///< Worst 1% average (ms)
    double worst_5pct_ms;   ///< Worst 5% average (ms)
    ulong  spike_count;     ///< Number of spikes (exceeded threshold)
    double spike_threshold; ///< Spike threshold (ms)
    double rolling_p50_ms;  ///< Rolling p50 (last N samples)
    double rolling_p95_ms;  ///< Rolling p95 (last N samples)
};

/**
 * @class ILatencyMonitor
 * @brief Interface for monitoring latency (expanded v0.1.14.0).
 */
class ILatencyMonitor
{
public:
    virtual void Record(const int type, const double milliseconds) = 0;
    virtual void GetStats(const int type, LatencyStats &out) const = 0;
    virtual double GetAverage(const int type) const = 0;
    virtual double GetPeak(const int type) const = 0;
    virtual void Reset(const int type) = 0;
    virtual void ResetAll(void) = 0;

    //--- NEW in v0.1.14.0 ---
    virtual void SetSpikeThreshold(const int type, const double threshold_ms) = 0;
    virtual ulong GetSpikeCount(const int type) const = 0;
    virtual double GetWorst1Percent(const int type) const = 0;
    virtual double GetWorst5Percent(const int type) const = 0;

    virtual ~ILatencyMonitor(void) {}
};

#endif // ATLAS_ILATENCY_MONITOR_MQH
//+------------------------------------------------------------------+
