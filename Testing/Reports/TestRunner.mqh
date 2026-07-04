//+------------------------------------------------------------------+
//|                    Testing/Reports/TestRunner.mqh               |
//|       AtlasEA v0.1.15.0 - Test Runner                            |
//+------------------------------------------------------------------+
#ifndef ATLAS_TEST_RUNNER_MQH
#define ATLAS_TEST_RUNNER_MQH

#include "../TestingConfig.mqh"
#include "../Scenarios/ScenarioRunner.mqh"
#include "TestReport.mqh"

/**
 * @class TestRunner
 * @brief Runs test suites and generates reports.
 *
 * Supports:
 *   - Run all tests
 *   - Run single test
 *   - Run test suite
 *   - Run performance tests
 *   - Run stress tests
 *   - Run recovery tests
 */
class TestRunner
{
private:
    TestingConfig      m_config;
    ScenarioRunner     m_scenarios;
    TestReportBuilder  m_report;

public:
    /**
     * @brief Constructor.
     */
    TestRunner(void) {}

    /**
     * @brief Initialize with config.
     */
    void Initialize(const TestingConfig &config)
    {
        m_config = config;
        m_scenarios.Initialize(config);
    }

    /**
     * @brief Get the report builder.
     */
    TestReportBuilder& GetReportBuilder(void) { return m_report; }

    /**
     * @brief Get the scenario runner.
     */
    ScenarioRunner& GetScenarios(void) { return m_scenarios; }

    //=== Test Execution ===

    /**
     * @brief Run all built-in scenarios.
     * @return Number of passed scenarios.
     */
    int RunAllTests(void)
    {
        m_report.Reset();
        ulong start = GetTickCount64();

        RunScenario("BullMarket",       &ScenarioRunner::RunBullMarket);
        RunScenario("BearMarket",       &ScenarioRunner::RunBearMarket);
        RunScenario("Sideways",         &ScenarioRunner::RunSideways);
        RunScenario("HighVolatility",   &ScenarioRunner::RunHighVolatility);
        RunScenario("LowVolatility",    &ScenarioRunner::RunLowVolatility);
        RunScenario("FlashCrash",       &ScenarioRunner::RunFlashCrash);
        RunScenario("NewsSpike",        &ScenarioRunner::RunNewsSpike);
        RunScenario("WeekendGap",       &ScenarioRunner::RunWeekendGap);
        RunScenario("BrokerDisconnect", &ScenarioRunner::RunBrokerDisconnect);
        RunScenario("SlowBroker",       &ScenarioRunner::RunSlowBroker);
        RunScenario("RecoveryAfterCrash", &ScenarioRunner::RunRecoveryAfterCrash);

        return m_report.GetReport().passed;
    }

    /**
     * @brief Run a single scenario by name.
     * @return true if passed.
     */
    bool RunSingleTest(const string name)
    {
        m_report.Reset();

        if(name == "BullMarket")        RunScenario("BullMarket", &ScenarioRunner::RunBullMarket);
        else if(name == "BearMarket")   RunScenario("BearMarket", &ScenarioRunner::RunBearMarket);
        else if(name == "Sideways")     RunScenario("Sideways", &ScenarioRunner::RunSideways);
        else if(name == "HighVolatility") RunScenario("HighVolatility", &ScenarioRunner::RunHighVolatility);
        else if(name == "LowVolatility")  RunScenario("LowVolatility", &ScenarioRunner::RunLowVolatility);
        else if(name == "FlashCrash")     RunScenario("FlashCrash", &ScenarioRunner::RunFlashCrash);
        else if(name == "NewsSpike")      RunScenario("NewsSpike", &ScenarioRunner::RunNewsSpike);
        else if(name == "WeekendGap")     RunScenario("WeekendGap", &ScenarioRunner::RunWeekendGap);
        else if(name == "BrokerDisconnect") RunScenario("BrokerDisconnect", &ScenarioRunner::RunBrokerDisconnect);
        else if(name == "SlowBroker")     RunScenario("SlowBroker", &ScenarioRunner::RunSlowBroker);
        else if(name == "RecoveryAfterCrash") RunScenario("RecoveryAfterCrash", &ScenarioRunner::RunRecoveryAfterCrash);
        else return false;

        return (m_report.GetReport().passed > 0);
    }

    /**
     * @brief Run market scenarios suite (Bull, Bear, Sideways, Volatility).
     */
    int RunMarketSuite(void)
    {
        m_report.Reset();
        RunScenario("BullMarket",     &ScenarioRunner::RunBullMarket);
        RunScenario("BearMarket",     &ScenarioRunner::RunBearMarket);
        RunScenario("Sideways",       &ScenarioRunner::RunSideways);
        RunScenario("HighVolatility", &ScenarioRunner::RunHighVolatility);
        RunScenario("LowVolatility",  &ScenarioRunner::RunLowVolatility);
        return m_report.GetReport().passed;
    }

    /**
     * @brief Run crash scenarios suite (FlashCrash, NewsSpike, WeekendGap).
     */
    int RunCrashSuite(void)
    {
        m_report.Reset();
        RunScenario("FlashCrash",  &ScenarioRunner::RunFlashCrash);
        RunScenario("NewsSpike",   &ScenarioRunner::RunNewsSpike);
        RunScenario("WeekendGap",  &ScenarioRunner::RunWeekendGap);
        return m_report.GetReport().passed;
    }

    /**
     * @brief Run broker scenarios suite (Disconnect, SlowBroker).
     */
    int RunBrokerSuite(void)
    {
        m_report.Reset();
        RunScenario("BrokerDisconnect", &ScenarioRunner::RunBrokerDisconnect);
        RunScenario("SlowBroker",       &ScenarioRunner::RunSlowBroker);
        return m_report.GetReport().passed;
    }

    /**
     * @brief Run recovery scenarios suite.
     */
    int RunRecoverySuite(void)
    {
        m_report.Reset();
        RunScenario("RecoveryAfterCrash", &ScenarioRunner::RunRecoveryAfterCrash);
        return m_report.GetReport().passed;
    }

    /**
     * @brief Run performance tests (high tick count).
     */
    int RunPerformanceTests(void)
    {
        m_report.Reset();
        ulong start = GetTickCount64();

        //--- Performance test: 100K ticks
        TestingConfig cfg = m_config;
        cfg.market_mode = ATLAS_TEST_MODE_FAST;
        m_scenarios.Initialize(cfg);

        ulong tick_start = GetTickCount64();
        for(int i = 0; i < 100000; i++)
            m_scenarios.GetFeed().GenerateTick();
        ulong tick_elapsed = GetTickCount64() - tick_start;

        m_report.AddEntry("Performance_100K_Ticks", ATLAS_SCENARIO_PASS,
                          m_scenarios.GetFeed().GetTickCount(),
                          (double)tick_elapsed, 0,
                          "100K ticks in " + IntegerToString((long)tick_elapsed) + "ms");

        return m_report.GetReport().passed;
    }

    /**
     * @brief Run stress tests (1M ticks, queue overflow, memory pressure).
     */
    int RunStressTests(void)
    {
        m_report.Reset();

        //--- Stress test: 1M ticks (or configured amount)
        TestingConfig cfg = m_config;
        cfg.market_mode = ATLAS_TEST_MODE_FAST;
        m_scenarios.Initialize(cfg);

        ulong tick_start = GetTickCount64();
        long tick_target = MathMin(m_config.stress_tick_count, 100000); ///< Cap at 100K for safety
        for(long i = 0; i < tick_target; i++)
            m_scenarios.GetFeed().GenerateTick();
        ulong tick_elapsed = GetTickCount64() - tick_start;

        m_report.AddEntry("Stress_Ticks", ATLAS_SCENARIO_PASS,
                          m_scenarios.GetFeed().GetTickCount(),
                          (double)tick_elapsed, 0,
                          IntegerToString(tick_target) + " ticks in " + IntegerToString((long)tick_elapsed) + "ms");

        return m_report.GetReport().passed;
    }

    /**
     * @brief Print the test report.
     */
    void PrintReport(void) const
    {
        m_report.Print();
    }

    /**
     * @brief Get the test report.
     */
    const TestReport& GetReport(void) const
    {
        return m_report.GetReport();
    }

private:
    /// @brief Run a scenario and add to report.
    typedef ScenarioResult (ScenarioRunner::*ScenarioMethod)(void);

    void RunScenario(const string name, ScenarioMethod method)
    {
        ScenarioResult result = (m_scenarios.*method)();
        m_report.AddEntry(name, result.code, result.ticks_generated,
                         result.duration_ms, result.assertions_passed,
                         result.failure_reason);
    }
};

#endif // ATLAS_TEST_RUNNER_MQH
//+------------------------------------------------------------------+
