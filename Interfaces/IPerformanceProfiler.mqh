//+------------------------------------------------------------------+
//|                         Interfaces/IPerformanceProfiler.mqh      |
//|       AtlasEA v0.1.12.0 - Performance Profiler Interface        |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPERFORMANCE_PROFILER_MQH
#define ATLAS_IPERFORMANCE_PROFILER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Phase identifiers for profiling.
 */
#define ATLAS_PHASE_MARKET      0
#define ATLAS_PHASE_STRATEGY    1
#define ATLAS_PHASE_RISK        2
#define ATLAS_PHASE_EXECUTION   3
#define ATLAS_PHASE_PERSISTENCE 4
#define ATLAS_PHASE_BROKER      5
#define ATLAS_PHASE_DISPATCH    6
#define ATLAS_PHASE_QUEUE       7
#define ATLAS_PHASE_COUNT       8

/**
 * @struct PhaseProfile
 * @brief Statistics for one profiled phase (expanded v0.1.14.0).
 */
struct PhaseProfile
{
    ulong count;             ///< Number of Start/Stop cycles
    ulong total_microseconds;///< Sum of all elapsed times
    ulong min_microseconds;  ///< Minimum single elapsed (best case)
    ulong max_microseconds;  ///< Maximum single elapsed (worst case)
    ulong last_microseconds; ///< Last elapsed time
    ulong start_tick;        ///< GetTickCount64() at Start (0 if not running)
    bool  running;           ///< Is this phase currently being timed?

    //--- NEW in v0.1.14.0 ---
    double variance;         ///< Variance of elapsed times
    double stddev;           ///< Standard deviation of elapsed times
    ulong  rolling_avg_us;   ///< Rolling average (last N samples)
    ulong  histogram[10];    ///< Execution histogram (10 buckets, fixed ranges)
};

/**
 * @class IPerformanceProfiler
 * @brief Interface for timing code execution phases (expanded v0.1.14.0).
 */
class IPerformanceProfiler
{
public:
    virtual void Start(const int phase) = 0;
    virtual void Stop(const int phase) = 0;
    virtual ulong ElapsedMicroseconds(const int phase) const = 0;
    virtual ulong Average(const int phase) const = 0;
    virtual ulong Min(const int phase) const = 0;
    virtual ulong Max(const int phase) const = 0;
    virtual ulong Count(const int phase) const = 0;
    virtual void Reset(const int phase) = 0;
    virtual void ResetAll(void) = 0;
    virtual void GetProfile(const int phase, PhaseProfile &out) const = 0;

    //--- NEW in v0.1.14.0 ---
    virtual double StdDev(const int phase) const = 0;
    virtual double Variance(const int phase) const = 0;
    virtual ulong  WorstCase(const int phase) const = 0;
    virtual ulong  BestCase(const int phase) const = 0;
    virtual ulong  RollingAverage(const int phase) const = 0;
    virtual void   GetHistogram(const int phase, ulong out_buckets[10]) const = 0;

    virtual ~IPerformanceProfiler(void) {}
};

#endif // ATLAS_IPERFORMANCE_PROFILER_MQH
//+------------------------------------------------------------------+
