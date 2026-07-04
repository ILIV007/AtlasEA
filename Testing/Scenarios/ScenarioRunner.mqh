//+------------------------------------------------------------------+
//|                 Testing/Scenarios/ScenarioRunner.mqh            |
//|       AtlasEA v0.1.15.0 - Scenario Engine                        |
//+------------------------------------------------------------------+
#ifndef ATLAS_SCENARIO_RUNNER_MQH
#define ATLAS_SCENARIO_RUNNER_MQH

#include "../TestingConfig.mqh"
#include "../Mock/MockBrokerAdapter.mqh"
#include "../Mock/MockMarketDataSource.mqh"
#include "../Assertions/Assert.mqh"

/**
 * @brief Scenario result codes.
 */
#define ATLAS_SCENARIO_PASS     0
#define ATLAS_SCENARIO_FAIL     1
#define ATLAS_SCENARIO_SKIP     2
#define ATLAS_SCENARIO_ERROR    3

/**
 * @struct ScenarioResult
 * @brief Result of running a single scenario.
 */
struct ScenarioResult
{
    string name;
    int    code;           ///< ATLAS_SCENARIO_*
    ulong  ticks_generated;
    double duration_ms;
    ulong  assertions_passed;
    ulong  assertions_failed;
    string failure_reason;
};

/**
 * @brief Scenario function pointer type.
 * Runs a single test scenario.
 * Returns ScenarioResult.
 */
typedef ScenarioResult (*ScenarioFunc)(MockBrokerAdapter &broker,
                                        MockMarketDataSource &feed,
                                        const TestingConfig &config);

/**
 * @class ScenarioRunner
 * @brief Runs test scenarios against mock infrastructure.
 *
 * Scenarios:
 *   - Bull Market
 *   - Bear Market
 *   - Sideways
 *   - High Volatility
 *   - Low Volatility
 *   - Flash Crash
 *   - News Spike
 *   - Weekend Gap
 *   - Broker Disconnect
 *   - Slow Broker
 *   - Recovery After Crash
 */
class ScenarioRunner
{
private:
    TestingConfig         m_config;
    MockBrokerAdapter     m_broker;
    MockMarketDataSource  m_feed;
    ScenarioResult        m_last_result;

public:
    /**
     * @brief Constructor.
     */
    ScenarioRunner(void) {}

    /**
     * @brief Initialize with config.
     */
    void Initialize(const TestingConfig &config)
    {
        m_config = config;
        m_broker.Initialize(config);
        m_feed.Initialize(config, &m_broker);
        Assert.ResetCounters();
    }

    /**
     * @brief Get the mock broker (for direct manipulation in scenarios).
     */
    MockBrokerAdapter& GetBroker(void) { return m_broker; }

    /**
     * @brief Get the mock feed (for direct manipulation in scenarios).
     */
    MockMarketDataSource& GetFeed(void) { return m_feed; }

    /**
     * @brief Get the last scenario result.
     */
    const ScenarioResult& GetLastResult(void) const { return m_last_result; }

    //=== Built-in Scenarios ===

    /**
     * @brief Run Bull Market scenario (trending up).
     */
    ScenarioResult RunBullMarket(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "BullMarket";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode    = ATLAS_TEST_MODE_TREND;
        cfg.trend_strength = 0.8;  ///< Strong uptrend
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        //--- Generate 1000 ticks
        for(int i = 0; i < 1000; i++)
        {
            m_feed.GenerateTick();
        }

        double final_price = m_feed.GetPrice();
        Assert.IsTrue("Bull market: price increased", final_price > cfg.initial_price);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Bear Market scenario (trending down).
     */
    ScenarioResult RunBearMarket(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "BearMarket";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode    = ATLAS_TEST_MODE_TREND;
        cfg.trend_strength = 0.2;  ///< Strong downtrend
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        for(int i = 0; i < 1000; i++)
            m_feed.GenerateTick();

        double final_price = m_feed.GetPrice();
        Assert.IsTrue("Bear market: price decreased", final_price < cfg.initial_price);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Sideways scenario (ranging).
     */
    ScenarioResult RunSideways(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "Sideways";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode = ATLAS_TEST_MODE_RANGE;
        cfg.range_low   = cfg.initial_price - 0.005;
        cfg.range_high  = cfg.initial_price + 0.005;
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        for(int i = 0; i < 1000; i++)
            m_feed.GenerateTick();

        double final_price = m_feed.GetPrice();
        Assert.IsTrue("Sideways: price within range",
                       final_price >= cfg.range_low - 0.01 && final_price <= cfg.range_high + 0.01);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run High Volatility scenario.
     */
    ScenarioResult RunHighVolatility(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "HighVolatility";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode  = ATLAS_TEST_MODE_RANDOM;
        cfg.volatility   = 1.0;  ///< Maximum volatility
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        double prices[100];
        for(int i = 0; i < 100; i++)
        {
            m_feed.GenerateTick();
            prices[i] = m_feed.GetPrice();
        }

        //--- Check that price moved significantly
        double max_price = prices[0], min_price = prices[0];
        for(int i = 1; i < 100; i++)
        {
            if(prices[i] > max_price) max_price = prices[i];
            if(prices[i] < min_price) min_price = prices[i];
        }
        double range = max_price - min_price;
        Assert.IsGreater("High volatility: significant range", range, 0.0005);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Low Volatility scenario.
     */
    ScenarioResult RunLowVolatility(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "LowVolatility";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode  = ATLAS_TEST_MODE_RANDOM;
        cfg.volatility   = 0.05;  ///< Very low volatility
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        double prices[100];
        for(int i = 0; i < 100; i++)
        {
            m_feed.GenerateTick();
            prices[i] = m_feed.GetPrice();
        }

        double max_price = prices[0], min_price = prices[0];
        for(int i = 1; i < 100; i++)
        {
            if(prices[i] > max_price) max_price = prices[i];
            if(prices[i] < min_price) min_price = prices[i];
        }
        double range = max_price - min_price;
        Assert.IsLess("Low volatility: small range", range, 0.001);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Flash Crash scenario.
     */
    ScenarioResult RunFlashCrash(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "FlashCrash";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode = ATLAS_TEST_MODE_FLASH;
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        double initial = m_feed.GetPrice();

        //--- Generate 700 ticks (crash at 500, recovery at 600)
        for(int i = 0; i < 700; i++)
            m_feed.GenerateTick();

        double final_price = m_feed.GetPrice();

        //--- Verify a crash occurred
        Assert.IsTrue("Flash crash: price changed significantly",
                       MathAbs(final_price - initial) > 0.001);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run News Spike scenario (sudden volatility increase).
     */
    ScenarioResult RunNewsSpike(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "NewsSpike";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        m_feed.Initialize(m_config, &m_broker);
        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        //--- Normal market for 100 ticks
        for(int i = 0; i < 100; i++)
            m_feed.GenerateTick();

        //--- News spike: force a jump
        m_feed.ForceJump(0.005);  ///< +0.5% jump

        //--- Continue for 100 more ticks
        for(int i = 0; i < 100; i++)
            m_feed.GenerateTick();

        Assert.IsTrue("News spike: completed", m_feed.GetTickCount() == 201);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Weekend Gap scenario.
     */
    ScenarioResult RunWeekendGap(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "WeekendGap";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.market_mode = ATLAS_TEST_MODE_GAP;
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        for(int i = 0; i < 300; i++)
            m_feed.GenerateTick();

        Assert.IsTrue("Weekend gap: completed", m_feed.GetTickCount() == 300);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Broker Disconnect scenario.
     */
    ScenarioResult RunBrokerDisconnect(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "BrokerDisconnect";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        m_feed.Initialize(m_config, &m_broker);
        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        //--- Normal operation
        m_feed.GenerateTick();
        Assert.IsTrue("Broker connected initially", m_broker.AccountEquity() > 0);

        //--- Disconnect
        m_broker.SetConnected(false);
        m_feed.GenerateTick();

        //--- Reconnect
        m_broker.SetConnected(true);
        m_feed.GenerateTick();
        Assert.IsTrue("Broker reconnected", m_broker.AccountEquity() > 0);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Slow Broker scenario (high latency).
     */
    ScenarioResult RunSlowBroker(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "SlowBroker";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        TestingConfig cfg = m_config;
        cfg.broker_delay_ms = 10;  ///< 10ms per order
        m_broker.Initialize(cfg);
        m_feed.Initialize(cfg, &m_broker);

        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        //--- Generate ticks
        for(int i = 0; i < 50; i++)
            m_feed.GenerateTick();

        Assert.IsTrue("Slow broker: completed", m_feed.GetTickCount() == 50);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run Recovery After Crash scenario.
     */
    ScenarioResult RunRecoveryAfterCrash(void)
    {
        ulong start = GetTickCount64();
        m_last_result.name = "RecoveryAfterCrash";
        m_last_result.code = ATLAS_SCENARIO_PASS;

        m_feed.Initialize(m_config, &m_broker);
        ulong pass_before = Assert.GetPassCount();
        ulong fail_before = Assert.GetFailCount();

        //--- Generate some ticks
        for(int i = 0; i < 100; i++)
            m_feed.GenerateTick();

        double price_before = m_feed.GetPrice();

        //--- Simulate crash: reset broker but keep price
        TestingConfig cfg = m_config;
        cfg.initial_price = price_before;
        m_broker.Initialize(cfg);
        m_feed.Initialize(cfg, &m_broker);

        //--- Continue after "recovery"
        for(int i = 0; i < 100; i++)
            m_feed.GenerateTick();

        Assert.IsTrue("Recovery: continued after crash", m_feed.GetTickCount() >= 100);

        m_last_result.ticks_generated    = m_feed.GetTickCount();
        m_last_result.duration_ms        = (double)(GetTickCount64() - start);
        m_last_result.assertions_passed  = Assert.GetPassCount() - pass_before;
        m_last_result.assertions_failed  = Assert.GetFailCount() - fail_before;

        if(m_last_result.assertions_failed > 0)
            m_last_result.code = ATLAS_SCENARIO_FAIL;

        return m_last_result;
    }

    /**
     * @brief Run all built-in scenarios.
     * @return Number of passed scenarios.
     */
    int RunAll(void)
    {
        int passed = 0;

        if(RunBullMarket().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunBearMarket().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunSideways().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunHighVolatility().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunLowVolatility().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunFlashCrash().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunNewsSpike().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunWeekendGap().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunBrokerDisconnect().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunSlowBroker().code == ATLAS_SCENARIO_PASS) passed++;
        if(RunRecoveryAfterCrash().code == ATLAS_SCENARIO_PASS) passed++;

        return passed;
    }
};

#endif // ATLAS_SCENARIO_RUNNER_MQH
//+------------------------------------------------------------------+
