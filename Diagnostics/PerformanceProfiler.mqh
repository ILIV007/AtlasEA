//+------------------------------------------------------------------+
//|                    Diagnostics/PerformanceProfiler.mqh          |
//|       AtlasEA v0.1.14.0 - Performance Profiler (Expanded)       |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERFORMANCE_PROFILER_MQH
#define ATLAS_PERFORMANCE_PROFILER_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/IPerformanceProfiler.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Number of samples for rolling average.
 */
#define ATLAS_PROFILER_SAMPLES 64

/**
 * @brief Histogram bucket boundaries (microseconds).
 * 0: 0-100us, 1: 100-500us, 2: 500us-1ms, 3: 1-2ms, 4: 2-5ms,
 * 5: 5-10ms, 6: 10-25ms, 7: 25-50ms, 8: 50-100ms, 9: 100ms+
 */
static const ulong HISTOGRAM_BOUNDS[10] = {
    100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000, 0xFFFFFFFF
};

/**
 * @class PerformanceProfiler
 * @brief Expanded concrete implementation of IPerformanceProfiler.
 *
 * Tracks per-phase: count, total, min, max, variance, stddev,
 * rolling average, and a 10-bucket execution histogram.
 */
class PerformanceProfiler : public IPerformanceProfiler
{
private:
    PhaseProfile m_profiles[ATLAS_PHASE_COUNT];
    ILogger     *m_logger;

    //--- Rolling sample window for variance/stddev/rolling_avg
    double m_samples[ATLAS_PHASE_COUNT][ATLAS_PROFILER_SAMPLES];
    int    m_sample_count[ATLAS_PHASE_COUNT];
    int    m_sample_head[ATLAS_PHASE_COUNT];
    double m_sample_sum[ATLAS_PHASE_COUNT];
    double m_sample_sq_sum[ATLAS_PHASE_COUNT];  ///< Sum of squares (for variance)

    bool IsValidPhase(const int phase) const { return (phase >= 0 && phase < ATLAS_PHASE_COUNT); }

    /// @brief Update histogram with a new sample.
    void UpdateHistogram(const int phase, const ulong elapsed_us)
    {
        for(int b = 0; b < 10; b++)
        {
            if(elapsed_us <= HISTOGRAM_BOUNDS[b])
            {
                m_profiles[phase].histogram[b]++;
                return;
            }
        }
    }

    /// @brief Add a sample to the rolling window + update variance/stddev.
    void AddSample(const int phase, const ulong elapsed_us)
    {
        double val = (double)elapsed_us;

        //--- Remove old value if window is full
        if(m_sample_count[phase] >= ATLAS_PROFILER_SAMPLES)
        {
            double old = m_samples[phase][m_sample_head[phase]];
            m_sample_sum[phase]     -= old;
            m_sample_sq_sum[phase]  -= (old * old);
        }

        //--- Add new value
        m_samples[phase][m_sample_head[phase]] = val;
        m_sample_sum[phase]    += val;
        m_sample_sq_sum[phase] += (val * val);
        m_sample_head[phase] = (m_sample_head[phase] + 1) % ATLAS_PROFILER_SAMPLES;
        if(m_sample_count[phase] < ATLAS_PROFILER_SAMPLES)
            m_sample_count[phase]++;

        //--- Compute rolling average
        m_profiles[phase].rolling_avg_us = (ulong)(m_sample_sum[phase] / (double)m_sample_count[phase]);

        //--- Compute variance and stddev
        double n = (double)m_sample_count[phase];
        double mean = m_sample_sum[phase] / n;
        double variance = (m_sample_sq_sum[phase] / n) - (mean * mean);
        if(variance < 0.0) variance = 0.0;  ///< Floating-point safety
        m_profiles[phase].variance = variance;
        m_profiles[phase].stddev   = MathSqrt(variance);
    }

public:
    PerformanceProfiler(void)
    {
        m_logger = NULL;
        ResetAll();
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    //=== IPerformanceProfiler implementation ===

    virtual void Start(const int phase) override
    {
        if(!IsValidPhase(phase)) return;
        m_profiles[phase].start_tick = GetTickCount64();
        m_profiles[phase].running    = true;
    }

    virtual void Stop(const int phase) override
    {
        if(!IsValidPhase(phase)) return;
        if(!m_profiles[phase].running) return;

        ulong elapsed_ms = GetTickCount64() - m_profiles[phase].start_tick;
        ulong elapsed_us = elapsed_ms * 1000;

        m_profiles[phase].last_microseconds = elapsed_us;
        m_profiles[phase].total_microseconds += elapsed_us;
        m_profiles[phase].count++;

        if(m_profiles[phase].min_microseconds == 0 || elapsed_us < m_profiles[phase].min_microseconds)
            m_profiles[phase].min_microseconds = elapsed_us;
        if(elapsed_us > m_profiles[phase].max_microseconds)
            m_profiles[phase].max_microseconds = elapsed_us;

        m_profiles[phase].running    = false;
        m_profiles[phase].start_tick = 0;

        //--- NEW: update rolling stats + histogram
        AddSample(phase, elapsed_us);
        UpdateHistogram(phase, elapsed_us);
    }

    virtual ulong ElapsedMicroseconds(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        return m_profiles[phase].last_microseconds;
    }

    virtual ulong Average(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        if(m_profiles[phase].count == 0) return 0;
        return m_profiles[phase].total_microseconds / m_profiles[phase].count;
    }

    virtual ulong Min(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        return m_profiles[phase].min_microseconds;
    }

    virtual ulong Max(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        return m_profiles[phase].max_microseconds;
    }

    virtual ulong Count(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        return m_profiles[phase].count;
    }

    virtual void Reset(const int phase) override
    {
        if(!IsValidPhase(phase)) return;
        m_profiles[phase].count = 0;
        m_profiles[phase].total_microseconds = 0;
        m_profiles[phase].min_microseconds = 0;
        m_profiles[phase].max_microseconds = 0;
        m_profiles[phase].last_microseconds = 0;
        m_profiles[phase].start_tick = 0;
        m_profiles[phase].running = false;
        m_profiles[phase].variance = 0.0;
        m_profiles[phase].stddev = 0.0;
        m_profiles[phase].rolling_avg_us = 0;
        for(int i = 0; i < 10; i++)
            m_profiles[phase].histogram[i] = 0;

        m_sample_count[phase] = 0;
        m_sample_head[phase]  = 0;
        m_sample_sum[phase]   = 0.0;
        m_sample_sq_sum[phase] = 0.0;
        for(int i = 0; i < ATLAS_PROFILER_SAMPLES; i++)
            m_samples[phase][i] = 0.0;
    }

    virtual void ResetAll(void) override
    {
        for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
            Reset(i);
    }

    virtual void GetProfile(const int phase, PhaseProfile &out) const override
    {
        if(!IsValidPhase(phase)) { ZeroMemory(out); return; }
        out = m_profiles[phase];
    }

    //--- NEW in v0.1.14.0 ---

    virtual double StdDev(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0.0;
        return m_profiles[phase].stddev;
    }

    virtual double Variance(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0.0;
        return m_profiles[phase].variance;
    }

    virtual ulong WorstCase(const int phase) const override
    {
        return Max(phase);  ///< Worst case = max
    }

    virtual ulong BestCase(const int phase) const override
    {
        return Min(phase);  ///< Best case = min
    }

    virtual ulong RollingAverage(const int phase) const override
    {
        if(!IsValidPhase(phase)) return 0;
        return m_profiles[phase].rolling_avg_us;
    }

    virtual void GetHistogram(const int phase, ulong out_buckets[10]) const override
    {
        if(!IsValidPhase(phase)) { for(int i=0;i<10;i++) out_buckets[i]=0; return; }
        for(int i = 0; i < 10; i++)
            out_buckets[i] = m_profiles[phase].histogram[i];
    }

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate structural invariants of the performance profiler.
     *
     * Walks every phase slot and verifies that:
     *   - m_profiles[i].count, min_microseconds, max_microseconds,
     *     total_microseconds are non-negative (all ulong — cast to long)
     *   - m_sample_count[i] is in [0, ATLAS_PROFILER_SAMPLES]
     *   - m_sample_sum[i] / m_sample_sq_sum[i] are non-negative
     *
     * @return ValidationResult::Ok() if all invariants hold,
     *         ValidationResult::Fail(code, reason, field) otherwise.
     */
    ValidationResult Validate(void) const
    {
        for(int i = 0; i < ATLAS_PHASE_COUNT; i++)
        {
            if((long)m_profiles[i].count < 0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_profiles[" + IntegerToString(i) + "].count is negative",
                    "count");

            if((long)m_profiles[i].min_microseconds < 0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_profiles[" + IntegerToString(i) + "].min_microseconds is negative",
                    "min_microseconds");

            if((long)m_profiles[i].max_microseconds < 0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_profiles[" + IntegerToString(i) + "].max_microseconds is negative",
                    "max_microseconds");

            if((long)m_profiles[i].total_microseconds < 0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_profiles[" + IntegerToString(i) + "].total_microseconds is negative",
                    "total_microseconds");

            if(m_sample_count[i] < 0 ||
               m_sample_count[i] > ATLAS_PROFILER_SAMPLES)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_sample_count[" + IntegerToString(i) + "] out of range",
                    "m_sample_count");

            if(m_sample_sum[i] < 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_sample_sum[" + IntegerToString(i) + "] is negative",
                    "m_sample_sum");

            if(m_sample_sq_sum[i] < 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_sample_sq_sum[" + IntegerToString(i) + "] is negative",
                    "m_sample_sq_sum");
        }
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_PERFORMANCE_PROFILER_MQH
//+------------------------------------------------------------------+
