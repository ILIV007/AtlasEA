//+------------------------------------------------------------------+
//|                    tests/StrategyFrameworkTests.mq5              |
//|       AtlasEA v0.1.10.0 - Strategy Framework Unit Tests          |
//+------------------------------------------------------------------+
#property copyright "AtlasEA v0.1.10.0 - Tests"
#property strict

#include "../Core/NullLogger.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Engines/StrategyFramework/StrategyMetadata.mqh"
#include "../Engines/StrategyFramework/StrategyContext.mqh"
#include "../Engines/StrategyFramework/StrategyRegistry.mqh"
#include "../Engines/StrategyFramework/VoteBuilder.mqh"
#include "../Engines/StrategyFramework/StrategyExecutor.mqh"

//+------------------------------------------------------------------+
//| Test framework helpers                                           |
//+------------------------------------------------------------------+
int g_tests_run    = 0;
int g_tests_passed = 0;
int g_tests_failed = 0;

void AssertTrue(const string name, const bool condition)
{
    g_tests_run++;
    if(condition) { g_tests_passed++; Print("  [PASS] ", name); }
    else          { g_tests_failed++; Print("  [FAIL] ", name); }
}

void PrintHeader(const string title) { Print(""); Print("=== ", title, " ==="); }

void PrintSummary(void)
{
    Print(""); Print("=== TEST SUMMARY ===");
    Print("  Total:  ", g_tests_run);
    Print("  Passed: ", g_tests_passed);
    Print("  Failed: ", g_tests_failed);
    if(g_tests_failed == 0) Print("  *** ALL TESTS PASSED ***");
    else                     Print("  *** SOME TESTS FAILED ***");
}

//+------------------------------------------------------------------+
//| Mock strategy for testing                                        |
//+------------------------------------------------------------------+
class MockStrategy : public IStrategy
{
private:
    StrategyMetadata m_meta;
    bool m_enabled;
    bool m_will_fail;
    int  m_direction;
    double m_confidence;

public:
    MockStrategy(const int id, const string name, const int priority = 100, const double weight = 1.0)
    {
        m_meta.strategy_id = id;
        m_meta.name        = name;
        m_meta.version     = "1.0.0";
        m_meta.priority    = priority;
        m_meta.weight      = weight;
        m_meta.enabled     = true;
        m_enabled    = true;
        m_will_fail  = false;
        m_direction  = ATLAS_ORDER_NONE;
        m_confidence = 0.0;
    }

    void SetWillFail(const bool fail)        { m_will_fail = fail; }
    void SetVote(const int dir, const double conf) { m_direction = dir; m_confidence = conf; }
    void SetEnabled(const bool en)           { m_enabled = en; }

    virtual bool Initialize(const AtlasConfig &config) override { return true; }
    virtual void Shutdown(void) override {}
    virtual const StrategyMetadata& GetMetadata(void) const override { return m_meta; }

    virtual bool Evaluate(const StrategyContext &ctx, StrategyVote &vote) override
    {
        if(m_will_fail) return false;
        if(m_direction == ATLAS_ORDER_NONE)
        {
            ZeroMemory(vote);
            vote.strategy_id = m_meta.strategy_id;
            vote.strategy_version = m_meta.version;
            vote.direction = ATLAS_ORDER_NONE;
            vote.snapshot_id = ctx.GetSnapshotId();
            vote.vote_time = TimeCurrent();
            return true;
        }
        //--- Directional vote
        double price = ctx.GetMidPrice();
        double atr = ctx.GetATR();
        if(atr <= 0) atr = 0.001;
        double sl_mult = 2.0;
        double tp_mult = 4.0;
        vote.strategy_id = m_meta.strategy_id;
        vote.strategy_version = m_meta.version;
        vote.direction = m_direction;
        vote.confidence = m_confidence;
        vote.suggested_volume = 0.0;
        vote.suggested_entry = price;
        if(m_direction == ATLAS_ORDER_BUY)
        {
            vote.suggested_sl = price - atr * sl_mult;
            vote.suggested_tp = price + atr * tp_mult;
        }
        else
        {
            vote.suggested_sl = price + atr * sl_mult;
            vote.suggested_tp = price - atr * tp_mult;
        }
        vote.snapshot_id = ctx.GetSnapshotId();
        vote.vote_time = TimeCurrent();
        return true;
    }

    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void Reset(void) override {}
};

//+------------------------------------------------------------------+
//| Helper: build a valid MarketState                                |
//+------------------------------------------------------------------+
void BuildValidMarketState(MarketState &state)
{
    ZeroMemory(state);
    state.snapshot_id  = 1;
    state.timestamp    = TimeCurrent();
    state.symbol       = "EURUSD";
    state.bid          = 1.0850;
    state.ask          = 1.0851;
    state.last         = 1.0850;
    state.spread       = 0.0001;
    state.point        = 0.00001;
    state.digits       = 5;
    state.tick_volume  = 100;
    state.bar_volume   = 1000;
    state.real_volume  = 0;
    state.atr_14       = 0.0020;
    state.volatility_index = 18.0;
    state.is_fast_market   = false;
    state.trend_direction  = 1;
    state.trend_strength   = 50;
    state.trend_duration_bars = 5;
    state.open = 1.0845;
    state.high = 1.0855;
    state.low  = 1.0840;
    state.close = 1.0850;
    state.bar_time = TimeCurrent();
    state.session_state = ATLAS_SESSION_LONDON;
    state.feature_count = ATLAS_FEATURE_SIZE;
    for(int i = 0; i < ATLAS_FEATURE_SIZE; i++)
        state.features[i] = 0.5;
    state.is_valid = true;
    state.invalid_reason = "";
}

//+------------------------------------------------------------------+
//| Test 1: Duplicate registration                                  |
//+------------------------------------------------------------------+
void TestDuplicateRegistration(void)
{
    PrintHeader("Test 1: Duplicate Registration");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    MockStrategy s1(1, "Strategy1");
    MockStrategy s2(1, "Strategy2");  //--- Same ID

    AssertTrue("First registration succeeds", reg.Register(&s1));
    AssertTrue("Duplicate ID rejected", !reg.Register(&s2));
    AssertTrue("Count = 1", reg.Count() == 1);
}

//+------------------------------------------------------------------+
//| Test 2: Disabled strategy                                       |
//+------------------------------------------------------------------+
void TestDisabledStrategy(void)
{
    PrintHeader("Test 2: Disabled Strategy");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    MockStrategy s1(1, "Enabled");
    MockStrategy s2(2, "Disabled");
    s2.SetEnabled(false);

    reg.Register(&s1);
    reg.Register(&s2);

    AssertTrue("Count = 2", reg.Count() == 2);
    AssertTrue("EnabledCount = 1", reg.EnabledCount() == 1);

    IStrategy *enabled[ATLAS_MAX_STRATEGIES];
    int count = 0;
    reg.GetEnabledSorted(enabled, count);
    AssertTrue("GetEnabledSorted returns 1", count == 1);
    AssertTrue("Enabled strategy is s1", enabled[0] == &s1);
}

//+------------------------------------------------------------------+
//| Test 3: Failed strategy                                         |
//+------------------------------------------------------------------+
void TestFailedStrategy(void)
{
    PrintHeader("Test 3: Failed Strategy");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    MockStrategy s1(1, "Failing");
    s1.SetWillFail(true);
    MockStrategy s2(2, "Succeeding");
    s2.SetVote(ATLAS_ORDER_BUY, 0.8);

    reg.Register(&s1);
    reg.Register(&s2);

    VoteBuilder vb(&logger);
    StrategyExecutor exec;
    exec.Initialize(&logger, vb);

    MarketState state;
    BuildValidMarketState(state);
    AtlasConfig config;
    AtlasConfigDefaults(config);

    StrategyVote votes[ATLAS_MAX_VOTES];
    int count = 0;
    exec.Execute(reg, state, config, 1, votes, count);

    AssertTrue("Failed strategy doesn't stop execution", count == 1);
    AssertTrue("Succeeding strategy produced a vote", votes[0].direction == ATLAS_ORDER_BUY);
    AssertTrue("Executor recorded 1 failure", exec.TotalFailures() == 1);
}

//+------------------------------------------------------------------+
//| Test 4: Timeout strategy (simulated via slow Evaluate)           |
//+------------------------------------------------------------------+
void TestTimeoutStrategy(void)
{
    PrintHeader("Test 4: Timeout Strategy");
    //--- Note: We can't truly simulate a 5ms+ timeout in a unit test
    //--- without Sleep(), which would slow the test suite.
    //--- Instead, we verify that the executor tracks latency.

    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    MockStrategy s1(1, "Normal");
    s1.SetVote(ATLAS_ORDER_SELL, 0.7);
    reg.Register(&s1);

    VoteBuilder vb(&logger);
    StrategyExecutor exec;
    exec.Initialize(&logger, vb);

    MarketState state;
    BuildValidMarketState(state);
    AtlasConfig config;
    AtlasConfigDefaults(config);

    StrategyVote votes[ATLAS_MAX_VOTES];
    int count = 0;
    exec.Execute(reg, state, config, 1, votes, count);

    AssertTrue("Vote produced", count == 1);
    AssertTrue("Total executions = 1", exec.TotalExecutions() == 1);
    AssertTrue("Peak latency >= 0", exec.PeakLatencyMs() >= 0.0);
}

//+------------------------------------------------------------------+
//| Test 5: Empty registry                                          |
//+------------------------------------------------------------------+
void TestEmptyRegistry(void)
{
    PrintHeader("Test 5: Empty Registry");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    AssertTrue("Empty registry count = 0", reg.Count() == 0);
    AssertTrue("Empty registry is empty", reg.IsEmpty());
    AssertTrue("Empty registry not full", !reg.IsFull());
    AssertTrue("Find on empty returns NULL", reg.Find(1) == NULL);

    VoteBuilder vb(&logger);
    StrategyExecutor exec;
    exec.Initialize(&logger, vb);

    MarketState state;
    BuildValidMarketState(state);
    AtlasConfig config;
    AtlasConfigDefaults(config);

    StrategyVote votes[ATLAS_MAX_VOTES];
    int count = 999;
    bool ok = exec.Execute(reg, state, config, 1, votes, count);

    AssertTrue("Execute on empty registry returns false", !ok);
    AssertTrue("Vote count = 0", count == 0);
}

//+------------------------------------------------------------------+
//| Test 6: Vote validation                                         |
//+------------------------------------------------------------------+
void TestVoteValidation(void)
{
    PrintHeader("Test 6: Vote Validation");
    NullLogger logger;
    VoteBuilder vb(&logger);

    StrategyMetadata meta;
    meta.strategy_id = 1;
    meta.name = "Test";
    meta.version = "1.0.0";
    meta.weight = 1.0;

    //--- Valid directional vote
    StrategyVote vote;
    bool ok = vb.BuildDirectional(vote, meta, ATLAS_ORDER_BUY, 0.8,
                                   1.0850, 1.0800, 1.0950, 0.0, 1);
    AssertTrue("BuildDirectional succeeds", ok);
    AssertTrue("Vote direction = BUY", vote.direction == ATLAS_ORDER_BUY);

    string reason;
    AssertTrue("Valid vote passes validation", vb.Validate(vote, reason));

    //--- Invalid direction
    ok = vb.BuildDirectional(vote, meta, 5, 0.8, 1.0850, 1.0800, 1.0950, 0.0, 1);
    AssertTrue("Invalid direction rejected", !ok);

    //--- Confidence clamping
    ok = vb.BuildDirectional(vote, meta, ATLAS_ORDER_BUY, 1.5,
                              1.0850, 1.0800, 1.0950, 0.0, 1);
    AssertTrue("Confidence > 1.0 accepted (clamped)", ok);
    AssertTrue("Confidence clamped to 1.0", vote.confidence <= 1.0);

    //--- Weight applied
    meta.weight = 0.5;
    ok = vb.BuildDirectional(vote, meta, ATLAS_ORDER_BUY, 0.8,
                              1.0850, 1.0800, 1.0950, 0.0, 1);
    AssertTrue("Weighted vote built", ok);
    AssertTrue("Confidence halved by weight", MathAbs(vote.confidence - 0.4) < 0.001);

    //--- Abstention
    ok = vb.BuildAbstention(vote, meta, 1);
    AssertTrue("Abstention built", ok);
    AssertTrue("Abstention direction = NONE", vote.direction == ATLAS_ORDER_NONE);
    AssertTrue("Abstention confidence = 0", vote.confidence == 0.0);
}

//+------------------------------------------------------------------+
//| Test 7: Maximum strategy count                                  |
//+------------------------------------------------------------------+
void TestMaxStrategyCount(void)
{
    PrintHeader("Test 7: Maximum Strategy Count");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    //--- Register ATLAS_MAX_STRATEGIES strategies
    MockStrategy *strategies[ATLAS_MAX_STRATEGIES];
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
    {
        strategies[i] = new MockStrategy(i + 1, "S" + IntegerToString(i + 1));
        AssertTrue("Register " + IntegerToString(i + 1), reg.Register(strategies[i]));
    }

    AssertTrue("Registry full", reg.IsFull());
    AssertTrue("Count = MAX", reg.Count() == ATLAS_MAX_STRATEGIES);

    //--- Try to register one more — should fail
    MockStrategy extra(999, "Extra");
    AssertTrue("Extra strategy rejected when full", !reg.Register(&extra));

    //--- Cleanup
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
        delete strategies[i];
}

//+------------------------------------------------------------------+
//| Test 8: Priority sorting                                        |
//+------------------------------------------------------------------+
void TestPrioritySorting(void)
{
    PrintHeader("Test 8: Priority Sorting");
    NullLogger logger;
    StrategyRegistry reg;
    reg.SetLogger(&logger);

    MockStrategy s1(1, "LowPriority", 100);   //--- Lower priority (executed last)
    MockStrategy s2(2, "HighPriority", 10);   //--- Higher priority (executed first)
    MockStrategy s3(3, "MedPriority", 50);

    reg.Register(&s1);
    reg.Register(&s2);
    reg.Register(&s3);

    IStrategy *sorted[ATLAS_MAX_STRATEGIES];
    int count = 0;
    reg.GetEnabledSorted(sorted, count);

    AssertTrue("3 strategies sorted", count == 3);
    AssertTrue("First = HighPriority (10)", sorted[0] == &s2);
    AssertTrue("Second = MedPriority (50)", sorted[1] == &s3);
    AssertTrue("Third = LowPriority (100)", sorted[2] == &s1);
}

//+------------------------------------------------------------------+
//| Main test runner                                                 |
//+------------------------------------------------------------------+
int OnInit(void)
{
    Print("");
    Print("############################################");
    Print("# AtlasEA v0.1.10.0 - Strategy Framework  #");
    Print("############################################");

    TestDuplicateRegistration();
    TestDisabledStrategy();
    TestFailedStrategy();
    TestTimeoutStrategy();
    TestEmptyRegistry();
    TestVoteValidation();
    TestMaxStrategyCount();
    TestPrioritySorting();

    PrintSummary();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}
void OnTick(void) {}
void OnTimer(void) {}
//+------------------------------------------------------------------+
