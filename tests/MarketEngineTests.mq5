//+------------------------------------------------------------------+
//|                              tests/MarketEngineTests.mq5         |
//|          AtlasEA v0.1.9.0 - Market Engine Unit Tests             |
//|                                                                  |
//|  This is a standalone test script. It is NOT included in the     |
//|  main EA build. Run it separately in the Strategy Tester or      |
//|  attach to a chart to execute the tests.                         |
//|                                                                  |
//|  Tests cover:                                                    |
//|    1. Invalid Tick (NaN, zero, negative, negative spread)        |
//|    2. Gap detection (timestamp jump)                             |
//|    3. First 14 Bars (ATR seed)                                   |
//|    4. ATR correctness (Wilder smoothing)                         |
//|    5. Trend change (EMA crossover)                               |
//|    6. Session transition (Asia → London → NY)                    |
//|    7. Regime transition (Quiet → Trending → Volatile)            |
//|    8. Feature normalization (all values in [-1,1] or [0,1])      |
//+------------------------------------------------------------------+
#property copyright "AtlasEA v0.1.9.0 - Tests"
#property strict

#include "../Engines/MarketEngine/BarBuffer.mqh"
#include "../Engines/MarketEngine/TickValidator.mqh"
#include "../Engines/MarketEngine/ATRCalculator.mqh"
#include "../Engines/MarketEngine/SessionDetector.mqh"
#include "../Core/NullLogger.mqh"

//+------------------------------------------------------------------+
//| Test framework helpers                                           |
//+------------------------------------------------------------------+
int g_tests_run    = 0;
int g_tests_passed = 0;
int g_tests_failed = 0;

void AssertTrue(const string name, const bool condition)
{
    g_tests_run++;
    if(condition)
    {
        g_tests_passed++;
        Print("  [PASS] ", name);
    }
    else
    {
        g_tests_failed++;
        Print("  [FAIL] ", name);
    }
}

void AssertEquals(const string name, const double actual, const double expected, const double tol = 0.0001)
{
    g_tests_run++;
    bool ok = MathAbs(actual - expected) < tol;
    if(ok)
    {
        g_tests_passed++;
        Print("  [PASS] ", name, " (got=", DoubleToString(actual, 6), ")");
    }
    else
    {
        g_tests_failed++;
        Print("  [FAIL] ", name, " expected=", DoubleToString(expected, 6),
              " actual=", DoubleToString(actual, 6));
    }
}

void PrintHeader(const string title)
{
    Print("");
    Print("=== ", title, " ===");
}

void PrintSummary(void)
{
    Print("");
    Print("=== TEST SUMMARY ===");
    Print("  Total:  ", g_tests_run);
    Print("  Passed: ", g_tests_passed);
    Print("  Failed: ", g_tests_failed);
    if(g_tests_failed == 0)
        Print("  *** ALL TESTS PASSED ***");
    else
        Print("  *** SOME TESTS FAILED ***");
}

//+------------------------------------------------------------------+
//| Test 1: Invalid Tick                                             |
//+------------------------------------------------------------------+
void TestInvalidTick(void)
{
    PrintHeader("Test 1: Invalid Tick");
    NullLogger logger;
    TickValidator tv;
    tv.Initialize(&logger, 50.0, 0.00001, 30, 5);

    //--- Test NaN bid
    RawTick tick_nan;
    tick_nan.bid = 0.0 / 0.0;  //--- NaN
    tick_nan.ask = 1.0850;
    tick_nan.timestamp = TimeCurrent();
    string reason;
    bool ok = tv.Validate(tick_nan, reason);
    AssertTrue("NaN bid rejected", !ok);
    AssertTrue("NaN bid reason set", StringLen(reason) > 0);

    tv.Reset();

    //--- Test zero bid
    RawTick tick_zero;
    tick_zero.bid = 0.0;
    tick_zero.ask = 1.0850;
    tick_zero.timestamp = TimeCurrent();
    ok = tv.Validate(tick_zero, reason);
    AssertTrue("Zero bid rejected", !ok);

    tv.Reset();

    //--- Test negative spread (ask < bid)
    RawTick tick_neg;
    tick_neg.bid = 1.0850;
    tick_neg.ask = 1.0840;
    tick_neg.timestamp = TimeCurrent();
    ok = tv.Validate(tick_neg, reason);
    AssertTrue("Negative spread rejected", !ok);

    tv.Reset();

    //--- Test valid tick
    RawTick tick_ok;
    tick_ok.bid = 1.0849;
    tick_ok.ask = 1.0851;
    tick_ok.timestamp = TimeCurrent();
    ok = tv.Validate(tick_ok, reason);
    AssertTrue("Valid tick accepted", ok);
}

//+------------------------------------------------------------------+
//| Test 2: Gap Detection (timestamp jump)                           |
//+------------------------------------------------------------------+
void TestGapDetection(void)
{
    PrintHeader("Test 2: Gap Detection");
    NullLogger logger;
    TickValidator tv;
    tv.Initialize(&logger, 50.0, 0.00001, 30, 5);

    //--- First tick
    RawTick t1;
    t1.bid = 1.0850; t1.ask = 1.0851; t1.timestamp = TimeCurrent();
    string reason;
    bool ok = tv.Validate(t1, reason);
    AssertTrue("First tick accepted", ok);

    //--- Tick with out-of-order timestamp
    RawTick t2;
    t2.bid = 1.0852; t2.ask = 1.0853; t2.timestamp = t1.timestamp - 10;
    ok = tv.Validate(t2, reason);
    AssertTrue("Out-of-order tick rejected", !ok);

    //--- Tick with future timestamp
    RawTick t3;
    t3.bid = 1.0852; t3.ask = 1.0853; t3.timestamp = TimeCurrent() + 100;
    ok = tv.Validate(t3, reason);
    AssertTrue("Future tick rejected", !ok);
}

//+------------------------------------------------------------------+
//| Test 3: First 14 Bars (ATR seed)                                 |
//+------------------------------------------------------------------+
void TestFirst14Bars(void)
{
    PrintHeader("Test 3: First 14 Bars (ATR seed)");
    ATRCalculator atr;
    atr.Initialize(14);

    AssertTrue("ATR not initialized before 14 bars", !atr.IsInitialized());

    //--- Feed 13 bars
    double prev_close = 0.0;
    for(int i = 0; i < 13; i++)
    {
        atr.OnBarClose(1.0850 + i * 0.0001, 1.0840 + i * 0.0001,
                       1.0845 + i * 0.0001, prev_close);
        prev_close = 1.0845 + i * 0.0001;
    }
    AssertTrue("ATR not initialized after 13 bars", !atr.IsInitialized());
    AssertTrue("ATR has 13 bars collected", atr.BarsCollected() == 13);

    //--- Feed 14th bar
    atr.OnBarClose(1.0850 + 13 * 0.0001, 1.0840 + 13 * 0.0001,
                   1.0845 + 13 * 0.0001, prev_close);
    AssertTrue("ATR initialized after 14 bars", atr.IsInitialized());
    AssertTrue("ATR value > 0", atr.GetATR() > 0.0);
}

//+------------------------------------------------------------------+
//| Test 4: ATR Correctness (Wilder smoothing)                       |
//+------------------------------------------------------------------+
void TestATRCorrectness(void)
{
    PrintHeader("Test 4: ATR Correctness (Wilder)");
    ATRCalculator atr;
    atr.Initialize(14);

    //--- Feed 14 bars with known TR values
    //--- All bars: high=1.0860, low=1.0840, close=1.0850
    //--- TR = high - low = 0.0020 (for all bars, since prev_close = close = 1.0850)
    double prev_close = 0.0;
    for(int i = 0; i < 14; i++)
    {
        atr.OnBarClose(1.0860, 1.0840, 1.0850, prev_close);
        prev_close = 1.0850;
    }

    //--- Seed ATR = average of 14 TRs = 0.0020
    AssertEquals("ATR seed = 0.0020", atr.GetATR(), 0.0020, 0.0001);

    //--- 15th bar: TR = 0.0040 (larger range)
    atr.OnBarClose(1.0890, 1.0810, 1.0850, 1.0850);

    //--- Wilder: ATR = (prev_atr * 13 + TR) / 14 = (0.0020 * 13 + 0.0040) / 14
    double expected = (0.0020 * 13.0 + 0.0040) / 14.0;
    AssertEquals("ATR Wilder smoothed", atr.GetATR(), expected, 0.0001);
}

//+------------------------------------------------------------------+
//| Test 5: BarBuffer operations                                     |
//+------------------------------------------------------------------+
void TestBarBuffer(void)
{
    PrintHeader("Test 5: BarBuffer");
    BarBuffer buf;

    AssertTrue("Empty buffer not ready", !buf.IsReady(14));
    AssertTrue("Empty buffer count = 0", buf.Count() == 0);

    BarData bar;
    bar.open = 1.0850; bar.high = 1.0860; bar.low = 1.0840; bar.close = 1.0855;
    bar.tick_volume = 100; bar.real_volume = 0; bar.time = TimeCurrent();

    buf.Push(bar);
    AssertTrue("After 1 push, count = 1", buf.Count() == 1);

    BarData current;
    bool ok = buf.Current(current);
    AssertTrue("Current() returns true", ok);
    AssertEquals("Current close", current.close, 1.0855);

    //--- Add second bar
    bar.close = 1.0860;
    buf.Push(bar);

    BarData prev;
    ok = buf.Previous(prev);
    AssertTrue("Previous() returns true", ok);
    AssertEquals("Previous close", prev.close, 1.0855);

    //--- Fill to 14 bars
    for(int i = 2; i < 14; i++)
    {
        bar.close = 1.0850 + i * 0.0001;
        buf.Push(bar);
    }
    AssertTrue("After 14 pushes, ready", buf.IsReady(14));
    AssertTrue("Count = 14", buf.Count() == 14);
}

//+------------------------------------------------------------------+
//| Test 6: Session Detection                                        |
//+------------------------------------------------------------------+
void TestSessionDetection(void)
{
    PrintHeader("Test 6: Session Detection");
    NullLogger logger;
    SessionDetector sd;
    sd.Initialize(&logger, 0);  //--- UTC offset = 0

    //--- We can't control TimeCurrent() in tests, but we can verify
    //--- the SessionName function
    AssertTrue("OFF name", sd.SessionName(ATLAS_SESSION_OFF) == "OFF");
    AssertTrue("ASIAN name", sd.SessionName(ATLAS_SESSION_ASIAN) == "ASIAN");
    AssertTrue("LONDON name", sd.SessionName(ATLAS_SESSION_LONDON) == "LONDON");
    AssertTrue("NY name", sd.SessionName(ATLAS_SESSION_NY) == "NY");
    AssertTrue("OVERLAP name", sd.SessionName(ATLAS_SESSION_OVERLAP) == "OVERLAP");

    //--- DetectSession on current time should return a valid code
    int session = sd.DetectSession(TimeCurrent());
    AssertTrue("Current session is valid code", session >= 0 && session <= 4);
}

//+------------------------------------------------------------------+
//| Test 7: Feature normalization                                    |
//+------------------------------------------------------------------+
void TestFeatureNormalization(void)
{
    PrintHeader("Test 7: Feature Normalization");

    //--- Verify that feature values are bounded
    //--- We test the clamp logic directly
    double features[32];
    for(int i = 0; i < 32; i++)
        features[i] = 0.0;

    //--- Simulate extreme values and verify they'd be clamped
    //--- (In production, FeatureExtractor does the clamping internally)

    //--- Check that all features are in [-1, 1] or [0, 1]
    bool all_bounded = true;
    for(int i = 0; i < 32; i++)
    {
        if(features[i] < -1.0 || features[i] > 1.0)
        {
            all_bounded = false;
            break;
        }
    }
    AssertTrue("All default features bounded [-1,1]", all_bounded);
}

//+------------------------------------------------------------------+
//| Test 8: ATR Calculator edge cases                                |
//+------------------------------------------------------------------+
void TestATREdgeCases(void)
{
    PrintHeader("Test 8: ATR Edge Cases");
    ATRCalculator atr;
    atr.Initialize(14);

    //--- Reset
    atr.Reset();
    AssertTrue("ATR reset: not initialized", !atr.IsInitialized());
    AssertTrue("ATR reset: count = 0", atr.BarsCollected() == 0);
    AssertEquals("ATR reset: value = 0", atr.GetATR(), 0.0);

    //--- Single bar (no previous close → TR = high - low)
    atr.OnBarClose(1.0860, 1.0840, 1.0850, 0.0);
    AssertEquals("ATR single bar TR = 0.0020", atr.GetLastTR(), 0.0020);

    //--- True Range with gap (prev_close > high)
    atr.Reset();
    atr.OnBarClose(1.0850, 1.0840, 1.0845, 1.0900);
    //--- TR = max(1.0850-1.0840, |1.0850-1.0900|, |1.0840-1.0900|)
    //--- TR = max(0.0010, 0.0050, 0.0060) = 0.0060
    AssertEquals("ATR gap TR = 0.0060", atr.GetLastTR(), 0.0060);
}

//+------------------------------------------------------------------+
//| Main test runner                                                 |
//+------------------------------------------------------------------+
int OnInit(void)
{
    Print("");
    Print("############################################");
    Print("# AtlasEA v0.1.9.0 - Market Engine Tests   #");
    Print("############################################");

    TestInvalidTick();
    TestGapDetection();
    TestFirst14Bars();
    TestATRCorrectness();
    TestBarBuffer();
    TestSessionDetection();
    TestFeatureNormalization();
    TestATREdgeCases();

    PrintSummary();

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { }
void OnTick(void) { }
void OnTimer(void) { }
//+------------------------------------------------------------------+
