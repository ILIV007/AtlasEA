//+------------------------------------------------------------------+
//|                     Testing/Reports/TestReport.mqh              |
//|       AtlasEA v0.1.15.0 - Test Report                            |
//+------------------------------------------------------------------+
#ifndef ATLAS_TEST_REPORT_MQH
#define ATLAS_TEST_REPORT_MQH

#include "../TestingConfig.mqh"

/**
 * @struct TestReportEntry
 * @brief One entry in a test report.
 */
struct TestReportEntry
{
    string scenario_name;
    int    code;           ///< ATLAS_SCENARIO_*
    ulong  ticks;
    double duration_ms;
    ulong  assertions;
    string details;
};

/**
 * @struct TestReport
 * @brief Complete test report.
 */
struct TestReport
{
    ulong  total_scenarios;
    ulong  passed;
    ulong  failed;
    ulong  skipped;
    double total_duration_ms;
    ulong  total_ticks;
    ulong  total_assertions;
    ulong  peak_memory_mb;
    TestReportEntry entries[64];
    int    entry_count;
};

/**
 * @class TestReportBuilder
 * @brief Builds a TestReport from scenario results.
 */
class TestReportBuilder
{
private:
    TestReport m_report;

public:
    /**
     * @brief Constructor.
     */
    TestReportBuilder(void)
    {
        Reset();
    }

    /**
     * @brief Reset the report.
     */
    void Reset(void)
    {
        m_report.total_scenarios   = 0;
        m_report.passed            = 0;
        m_report.failed            = 0;
        m_report.skipped           = 0;
        m_report.total_duration_ms = 0.0;
        m_report.total_ticks       = 0;
        m_report.total_assertions  = 0;
        m_report.peak_memory_mb    = 0;
        m_report.entry_count       = 0;
    }

    /**
     * @brief Add a scenario result to the report.
     */
    void AddEntry(const string name, const int code,
                  const ulong ticks, const double duration_ms,
                  const ulong assertions, const string details = "")
    {
        if(m_report.entry_count >= 64) return;

        TestReportEntry &entry = m_report.entries[m_report.entry_count];
        entry.scenario_name = name;
        entry.code          = code;
        entry.ticks         = ticks;
        entry.duration_ms   = duration_ms;
        entry.assertions    = assertions;
        entry.details       = details;

        m_report.entry_count++;
        m_report.total_scenarios++;
        m_report.total_duration_ms += duration_ms;
        m_report.total_ticks       += ticks;
        m_report.total_assertions  += assertions;

        switch(code)
        {
            case ATLAS_SCENARIO_PASS: m_report.passed++;  break;
            case ATLAS_SCENARIO_FAIL: m_report.failed++;  break;
            case ATLAS_SCENARIO_SKIP: m_report.skipped++; break;
        }
    }

    /**
     * @brief Get the complete report.
     */
    const TestReport& GetReport(void) const { return m_report; }

    /**
     * @brief Get pass rate (0..1).
     */
    double PassRate(void) const
    {
        if(m_report.total_scenarios == 0) return 0.0;
        return (double)m_report.passed / (double)m_report.total_scenarios;
    }

    /**
     * @brief Get coverage estimate (0..1).
     */
    double CoverageEstimate(void) const
    {
        //--- Simple heuristic: coverage = pass_rate × (assertions / 100)
        double base = PassRate();
        double assertion_factor = MathMin(1.0, (double)m_report.total_assertions / 100.0);
        return base * assertion_factor;
    }

    /**
     * @brief Print the report to console.
     */
    void Print(void) const
    {
        Print("");
        Print("╔══════════════════════════════════════════════════╗");
        Print("║         AtlasEA Test Report                      ║");
        Print("╠══════════════════════════════════════════════════╣");
        Print("║  Scenarios:  ", m_report.total_scenarios);
        Print("║  Passed:     ", m_report.passed);
        Print("║  Failed:     ", m_report.failed);
        Print("║  Skipped:    ", m_report.skipped);
        Print("║  Pass Rate:  ", DoubleToString(PassRate() * 100.0, 1), "%");
        Print("║  Coverage:   ", DoubleToString(CoverageEstimate() * 100.0, 1), "%");
        Print("║  Duration:   ", DoubleToString(m_report.total_duration_ms, 1), "ms");
        Print("║  Ticks:      ", m_report.total_ticks);
        Print("║  Assertions: ", m_report.total_assertions);
        Print("║  Peak Mem:   ", m_report.peak_memory_mb, "MB");
        Print("╠══════════════════════════════════════════════════╣");

        for(int i = 0; i < m_report.entry_count; i++)
        {
            const TestReportEntry &e = m_report.entries[i];
            string status;
            switch(e.code)
            {
                case ATLAS_SCENARIO_PASS:  status = "PASS"; break;
                case ATLAS_SCENARIO_FAIL:  status = "FAIL"; break;
                case ATLAS_SCENARIO_SKIP:  status = "SKIP"; break;
                default:                   status = "ERR";  break;
            }
            Print("║  [", status, "] ", e.scenario_name,
                  " ticks=", e.ticks,
                  " ms=", DoubleToString(e.duration_ms, 1),
                  " asserts=", e.assertions);
        }

        Print("╚══════════════════════════════════════════════════╝");
    }
};

#endif // ATLAS_TEST_REPORT_MQH
//+------------------------------------------------------------------+
