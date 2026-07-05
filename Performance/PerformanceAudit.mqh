//+------------------------------------------------------------------+
//|                     Performance/PerformanceAudit.mqh              |
//|       AtlasEA v1.0 Step 8 - Performance Audit                      |
//+------------------------------------------------------------------+
#ifndef ATLAS_PERFORMANCE_AUDIT_MQH
#define ATLAS_PERFORMANCE_AUDIT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "RuntimeStatistics.mqh"

/**
 * @brief Hot path component codes.
 */
#define ATLAS_HP_CORE_ENGINE      0
#define ATLAS_HP_MARKET_ENGINE     1
#define ATLAS_HP_STRATEGY_ENGINE   2
#define ATLAS_HP_RISK_ENGINE       3
#define ATLAS_HP_EXECUTION_ENGINE  4
#define ATLAS_HP_PERSISTENCE       5
#define ATLAS_HP_REPLAY            6
#define ATLAS_HP_VALIDATION        7
#define ATLAS_HP_OPTIMIZATION      8
#define ATLAS_HP_COUNT             9

/**
 * @struct HotPathEntry
 * @brief Performance entry for a single hot path component.
 */
struct HotPathEntry
{
    int    component;        ///< ATLAS_HP_*
    string name;             ///< Component name
    double avg_time_ms;      ///< Average time per call
    double peak_time_ms;     ///< Peak time
    ulong  call_count;       ///< Total calls
    bool   over_budget;      ///< Exceeds time budget?

    //--- Optimization recommendations ---
    bool   has_repeated_calcs;    ///< Repeated calculations detected
    bool   has_unnecessary_work;  ///< Unnecessary work detected
    bool   has_missing_cache;     ///< Missing cache
    bool   has_excessive_branching; ///< Excessive branching

    HotPathEntry(void)
    {
        component           = 0;
        name                = "";
        avg_time_ms         = 0.0;
        peak_time_ms        = 0.0;
        call_count          = 0;
        over_budget         = false;
        has_repeated_calcs  = false;
        has_unnecessary_work = false;
        has_missing_cache   = false;
        has_excessive_branching = false;
    }
};

/**
 * @struct PerformanceAuditResult
 * @brief Result of a performance audit.
 */
struct PerformanceAuditResult
{
    HotPathEntry entries[ATLAS_HP_COUNT];
    int    entry_count;

    //--- Summary ---
    int    over_budget_count;     ///< Components exceeding budget
    int    total_recommendations;  ///< Total optimization recommendations
    double total_avg_time_ms;     ///< Sum of all avg times

    //--- Targets ---
    double target_avg_tick_ms;    ///< Target average tick
    double target_peak_tick_ms;   ///< Target peak tick

    //--- Measured ---
    double measured_avg_tick_ms;  ///< Measured average tick
    double measured_peak_tick_ms; ///< Measured peak tick
    double measured_p95_tick_ms;  ///< Measured p95 tick

    //--- Assessment ---
    bool   meets_targets;         ///< Does the system meet performance targets?
    string assessment;            ///< Human-readable assessment

    PerformanceAuditResult(void)
    {
        entry_count           = 0;
        over_budget_count     = 0;
        total_recommendations = 0;
        total_avg_time_ms     = 0.0;
        target_avg_tick_ms    = 5.0;
        target_peak_tick_ms   = 20.0;
        measured_avg_tick_ms  = 0.0;
        measured_peak_tick_ms = 0.0;
        measured_p95_tick_ms  = 0.0;
        meets_targets         = false;
        assessment            = "";
    }
};

/**
 * @class PerformanceAudit
 * @brief Audits hot path performance and provides optimization recommendations.
 *
 * SOLE RESPONSIBILITY: analyze performance data and recommend optimizations.
 * Does NOT modify any code or system behavior.
 *
 * Audit areas:
 *   1. CoreEngine: OnTick, OnTimer, OnTrade
 *   2. MarketEngine: ProcessTick
 *   3. StrategyEngine: EvaluateStrategies
 *   4. RiskEngine: EvaluateRisk
 *   5. ExecutionEngine: BuildOrderRequest, SendOrder
 *   6. PersistenceManager: WriteSnapshot, FlushEventBuffer
 *   7. ReplayEngine: replay tick (if active)
 *   8. Validation: backtest, walk-forward, Monte Carlo
 *   9. Optimization: parameter evaluation
 *
 * Recommendations:
 *   - Repeated calculations → cache results
 *   - Unnecessary work → skip when not needed
 *   - Missing cache → add caching layer
 *   - Excessive branching → simplify logic
 *
 * Performance: O(H) where H = hot path components. No allocation.
 */
class PerformanceAudit
{
private:
    ILogger *m_logger;
    HotPathEntry m_entries[ATLAS_HP_COUNT];
    bool    m_initialized;

public:
    PerformanceAudit(void)
    {
        m_logger      = NULL;
        m_initialized = false;

        //--- Initialize entries
        m_entries[ATLAS_HP_CORE_ENGINE].name     = "CoreEngine";
        m_entries[ATLAS_HP_MARKET_ENGINE].name   = "MarketEngine";
        m_entries[ATLAS_HP_STRATEGY_ENGINE].name = "StrategyEngine";
        m_entries[ATLAS_HP_RISK_ENGINE].name     = "RiskEngine";
        m_entries[ATLAS_HP_EXECUTION_ENGINE].name = "ExecutionEngine";
        m_entries[ATLAS_HP_PERSISTENCE].name     = "PersistenceManager";
        m_entries[ATLAS_HP_REPLAY].name          = "ReplayEngine";
        m_entries[ATLAS_HP_VALIDATION].name      = "Validation";
        m_entries[ATLAS_HP_OPTIMIZATION].name    = "Optimization";
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Record timing for a hot path component.
     */
    void RecordTiming(const int component, const double time_ms)
    {
        if(component < 0 || component >= ATLAS_HP_COUNT) return;
        HotPathEntry &e = m_entries[component];
        e.call_count++;
        //--- Running average
        e.avg_time_ms = ((e.avg_time_ms * (double)(e.call_count - 1)) + time_ms) /
                        (double)e.call_count;
        if(time_ms > e.peak_time_ms) e.peak_time_ms = time_ms;
    }

    /**
     * @brief Mark a component as having repeated calculations.
     */
    void FlagRepeatedCalcs(const int component, const bool flag)
    {
        if(component >= 0 && component < ATLAS_HP_COUNT)
            m_entries[component].has_repeated_calcs = flag;
    }

    /**
     * @brief Mark a component as having unnecessary work.
     */
    void FlagUnnecessaryWork(const int component, const bool flag)
    {
        if(component >= 0 && component < ATLAS_HP_COUNT)
            m_entries[component].has_unnecessary_work = flag;
    }

    /**
     * @brief Mark a component as missing a cache.
     */
    void FlagMissingCache(const int component, const bool flag)
    {
        if(component >= 0 && component < ATLAS_HP_COUNT)
            m_entries[component].has_missing_cache = flag;
    }

    /**
     * @brief Run the performance audit.
     * @param runtime_stats Runtime statistics to include.
     * @return PerformanceAuditResult with findings + recommendations.
     */
    PerformanceAuditResult Audit(const RuntimeStats &runtime_stats)
    {
        PerformanceAuditResult result;
        result.entry_count = ATLAS_HP_COUNT;
        result.target_avg_tick_ms  = 5.0;
        result.target_peak_tick_ms = 20.0;

        //--- Copy entries
        for(int i = 0; i < ATLAS_HP_COUNT; i++)
        {
            result.entries[i] = m_entries[i];

            //--- Check budget (each component gets a fraction of the 5ms tick budget)
            double budget = 0.0;
            switch(i)
            {
                case ATLAS_HP_CORE_ENGINE:      budget = 0.5; break;
                case ATLAS_HP_MARKET_ENGINE:     budget = 1.5; break;
                case ATLAS_HP_STRATEGY_ENGINE:   budget = 1.0; break;
                case ATLAS_HP_RISK_ENGINE:       budget = 0.5; break;
                case ATLAS_HP_EXECUTION_ENGINE:  budget = 0.5; break;
                case ATLAS_HP_PERSISTENCE:       budget = 0.5; break;
                case ATLAS_HP_REPLAY:            budget = 2.0; break;
                case ATLAS_HP_VALIDATION:        budget = 50.0; break; // Offline
                case ATLAS_HP_OPTIMIZATION:      budget = 100.0; break; // Offline
            }

            if(m_entries[i].avg_time_ms > budget && m_entries[i].call_count > 0)
            {
                result.entries[i].over_budget = true;
                result.over_budget_count++;
            }

            //--- Count recommendations
            if(m_entries[i].has_repeated_calcs)     result.total_recommendations++;
            if(m_entries[i].has_unnecessary_work)   result.total_recommendations++;
            if(m_entries[i].has_missing_cache)      result.total_recommendations++;
            if(m_entries[i].has_excessive_branching) result.total_recommendations++;

            result.total_avg_time_ms += m_entries[i].avg_time_ms;
        }

        //--- Measured performance
        result.measured_avg_tick_ms  = runtime_stats.avg_tick_ms;
        result.measured_peak_tick_ms = runtime_stats.peak_tick_ms;
        result.measured_p95_tick_ms  = runtime_stats.p95_tick_ms;

        //--- Assessment
        result.meets_targets =
            (result.measured_avg_tick_ms <= result.target_avg_tick_ms) &&
            (result.measured_peak_tick_ms <= result.target_peak_tick_ms);

        if(result.meets_targets && result.over_budget_count == 0)
            result.assessment = "System meets all performance targets. No action required.";
        else if(result.meets_targets)
            result.assessment = "System meets tick targets but " +
                IntegerToString(result.over_budget_count) +
                " component(s) are over budget. Monitor for degradation.";
        else
            result.assessment = "System EXCEEDS performance targets. " +
                IntegerToString(result.total_recommendations) +
                " optimization(s) recommended. Avg tick " +
                DoubleToString(result.measured_avg_tick_ms, 2) + "ms > " +
                DoubleToString(result.target_avg_tick_ms, 1) + "ms target.";

        return result;
    }

    /**
     * @brief Log the audit results.
     */
    void LogAudit(const PerformanceAuditResult &result) const
    {
        if(m_logger == NULL) return;

        m_logger.Info("PerformanceAudit",
            "Targets: avg<" + DoubleToString(result.target_avg_tick_ms, 1) + "ms" +
            " peak<" + DoubleToString(result.target_peak_tick_ms, 1) + "ms");
        m_logger.Info("PerformanceAudit",
            "Measured: avg=" + DoubleToString(result.measured_avg_tick_ms, 2) + "ms" +
            " peak=" + DoubleToString(result.measured_peak_tick_ms, 2) + "ms" +
            " p95=" + DoubleToString(result.measured_p95_tick_ms, 2) + "ms" +
            " meets=" + (result.meets_targets ? "YES" : "NO"));
        m_logger.Info("PerformanceAudit",
            "OverBudget: " + IntegerToString(result.over_budget_count) +
            " Recommendations: " + IntegerToString(result.total_recommendations));

        for(int i = 0; i < result.entry_count; i++)
        {
            const HotPathEntry &e = result.entries[i];
            string flags = "";
            if(e.over_budget)            flags += " [OVER_BUDGET]";
            if(e.has_repeated_calcs)     flags += " [REPEATED_CALCS]";
            if(e.has_unnecessary_work)   flags += " [UNNECESSARY_WORK]";
            if(e.has_missing_cache)      flags += " [MISSING_CACHE]";

            m_logger.Info("PerformanceAudit",
                "  " + e.name +
                " avg=" + DoubleToString(e.avg_time_ms, 3) + "ms" +
                " peak=" + DoubleToString(e.peak_time_ms, 3) + "ms" +
                " calls=" + IntegerToString((long)e.call_count) +
                flags);
        }

        m_logger.Info("PerformanceAudit", "Assessment: " + result.assessment);
    }
};

#endif // ATLAS_PERFORMANCE_AUDIT_MQH
//+------------------------------------------------------------------+
