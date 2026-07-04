//+------------------------------------------------------------------+
//|                      Diagnostics/LatencyMonitor.mqh             |
//|       AtlasEA v0.1.14.0 - Latency Monitor (Expanded)            |
//+------------------------------------------------------------------+
#ifndef ATLAS_LATENCY_MONITOR_MQH
#define ATLAS_LATENCY_MONITOR_MQH

#include "../Config/Settings.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILatencyMonitor.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Number of samples kept per latency type.
 */

/**
 * @class LatencyMonitor
 * @brief Expanded concrete implementation of ILatencyMonitor.
 */
class LatencyMonitor : public ILatencyMonitor
{
private:
    double m_samples[ATLAS_LATENCY_COUNT][ATLAS_LATENCY_SAMPLES];
    int    m_sample_count[ATLAS_LATENCY_COUNT];
    int    m_sample_head[ATLAS_LATENCY_COUNT];
    double m_min[ATLAS_LATENCY_COUNT];
    double m_max[ATLAS_LATENCY_COUNT];
    double m_sum[ATLAS_LATENCY_COUNT];
    double m_last[ATLAS_LATENCY_COUNT];

    //--- NEW in v0.1.14.0 ---
    ulong  m_spike_count[ATLAS_LATENCY_COUNT];
    double m_spike_threshold[ATLAS_LATENCY_COUNT];

    ILogger *m_logger;

    bool IsValidType(const int type) const { return (type >= 0 && type < ATLAS_LATENCY_COUNT); }

    double Percentile(const int type, const double p) const
    {
        int n = m_sample_count[type];
        if(n == 0) return 0.0;

        double tmp[ATLAS_LATENCY_SAMPLES];
        for(int i = 0; i < n; i++)
            tmp[i] = m_samples[type][i];

        for(int i = 1; i < n; i++)
        {
            double key = tmp[i];
            int j = i - 1;
            while(j >= 0 && tmp[j] > key) { tmp[j+1] = tmp[j]; j--; }
            tmp[j+1] = key;
        }

        int idx = (int)(p * (double)(n - 1));
        if(idx < 0) idx = 0;
        if(idx >= n) idx = n - 1;
        return tmp[idx];
    }

    /// @brief Compute average of the worst N% of samples.
    double WorstPercentileAvg(const int type, const double pct) const
    {
        int n = m_sample_count[type];
        if(n == 0) return 0.0;

        double tmp[ATLAS_LATENCY_SAMPLES];
        for(int i = 0; i < n; i++)
            tmp[i] = m_samples[type][i];

        //--- Sort descending (worst first)
        for(int i = 1; i < n; i++)
        {
            double key = tmp[i];
            int j = i - 1;
            while(j >= 0 && tmp[j] < key) { tmp[j+1] = tmp[j]; j--; }
            tmp[j+1] = key;
        }

        int worst_count = (int)((double)n * pct);
        if(worst_count < 1) worst_count = 1;

        double sum = 0.0;
        for(int i = 0; i < worst_count; i++)
            sum += tmp[i];
        return sum / (double)worst_count;
    }

public:
    LatencyMonitor(void)
    {
        m_logger = NULL;
        ResetAll();
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    virtual void Record(const int type, const double milliseconds) override
    {
        if(!IsValidType(type)) return;
        if(milliseconds < 0.0) return;

        int idx = m_sample_head[type];
        m_samples[type][idx] = milliseconds;
        m_sample_head[type] = (m_sample_head[type] + 1) % ATLAS_LATENCY_SAMPLES;
        if(m_sample_count[type] < ATLAS_LATENCY_SAMPLES)
            m_sample_count[type]++;

        if(m_min[type] <= 0.0 || milliseconds < m_min[type])
            m_min[type] = milliseconds;
        if(milliseconds > m_max[type])
            m_max[type] = milliseconds;
        m_sum[type] += milliseconds;
        m_last[type] = milliseconds;

        //--- Spike detection
        if(m_spike_threshold[type] > 0.0 && milliseconds > m_spike_threshold[type])
            m_spike_count[type]++;
    }

    virtual void GetStats(const int type, LatencyStats &out) const override
    {
        if(!IsValidType(type)) { ZeroMemory(out); return; }

        out.count   = (ulong)m_sample_count[type];
        out.last_ms = m_last[type];
        out.min_ms  = (m_min[type] > 0.0) ? m_min[type] : 0.0;
        out.max_ms  = m_max[type];

        if(m_sample_count[type] > 0)
            out.avg_ms = m_sum[type] / (double)m_sample_count[type];
        else
            out.avg_ms = 0.0;

        out.p50_ms = Percentile(type, 0.50);
        out.p95_ms = Percentile(type, 0.95);
        out.p99_ms = Percentile(type, 0.99);

        //--- NEW
        out.worst_1pct_ms     = WorstPercentileAvg(type, 0.01);
        out.worst_5pct_ms     = WorstPercentileAvg(type, 0.05);
        out.spike_count       = m_spike_count[type];
        out.spike_threshold   = m_spike_threshold[type];
        out.rolling_p50_ms    = Percentile(type, 0.50);  ///< Same as p50 for now
        out.rolling_p95_ms    = Percentile(type, 0.95);  ///< Same as p95 for now
    }

    virtual double GetAverage(const int type) const override
    {
        if(!IsValidType(type)) return 0.0;
        if(m_sample_count[type] == 0) return 0.0;
        return m_sum[type] / (double)m_sample_count[type];
    }

    virtual double GetPeak(const int type) const override
    {
        if(!IsValidType(type)) return 0.0;
        return m_max[type];
    }

    virtual void Reset(const int type) override
    {
        if(!IsValidType(type)) return;
        m_sample_count[type] = 0;
        m_sample_head[type]  = 0;
        m_min[type] = 0.0;
        m_max[type] = 0.0;
        m_sum[type] = 0.0;
        m_last[type] = 0.0;
        m_spike_count[type] = 0;
        m_spike_threshold[type] = 0.0;
        for(int i = 0; i < ATLAS_LATENCY_SAMPLES; i++)
            m_samples[type][i] = 0.0;
    }

    virtual void ResetAll(void) override
    {
        for(int i = 0; i < ATLAS_LATENCY_COUNT; i++)
            Reset(i);
    }

    //--- NEW in v0.1.14.0 ---

    virtual void SetSpikeThreshold(const int type, const double threshold_ms) override
    {
        if(!IsValidType(type)) return;
        m_spike_threshold[type] = threshold_ms;
    }

    virtual ulong GetSpikeCount(const int type) const override
    {
        if(!IsValidType(type)) return 0;
        return m_spike_count[type];
    }

    virtual double GetWorst1Percent(const int type) const override
    {
        if(!IsValidType(type)) return 0.0;
        return WorstPercentileAvg(type, 0.01);
    }

    virtual double GetWorst5Percent(const int type) const override
    {
        if(!IsValidType(type)) return 0.0;
        return WorstPercentileAvg(type, 0.05);
    }

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate structural invariants of the latency monitor.
     *
     * Walks every latency-type slot and verifies that:
     *   - m_sample_count[i] is in [0, ATLAS_LATENCY_SAMPLES]
     *   - m_sum[i] is non-negative (Record() rejects negative inputs,
     *     so a negative sum indicates corruption)
     *   - m_spike_count[i] is non-negative (ulong — cast to long)
     *   - m_min[i] / m_max[i] are non-negative
     *
     * @return ValidationResult::Ok() if all invariants hold,
     *         ValidationResult::Fail(code, reason, field) otherwise.
     */
    ValidationResult Validate(void) const
    {
        for(int i = 0; i < ATLAS_LATENCY_COUNT; i++)
        {
            if(m_sample_count[i] < 0 ||
               m_sample_count[i] > ATLAS_LATENCY_SAMPLES)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_sample_count[" + IntegerToString(i) + "] out of range",
                    "m_sample_count");

            if(m_sum[i] < 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_sum[" + IntegerToString(i) + "] is negative",
                    "m_sum");

            if((long)m_spike_count[i] < 0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_spike_count[" + IntegerToString(i) + "] is negative",
                    "m_spike_count");

            if(m_min[i] < 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_min[" + IntegerToString(i) + "] is negative",
                    "m_min");

            if(m_max[i] < 0.0)
                return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                    "m_max[" + IntegerToString(i) + "] is negative",
                    "m_max");
        }
        return ValidationResult::Ok();
    }
};

#endif // ATLAS_LATENCY_MONITOR_MQH
//+------------------------------------------------------------------+
