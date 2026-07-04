//+------------------------------------------------------------------+
//|                       tests/RiskEngineTests.mq5                  |
//|       AtlasEA v0.1.11.0 - Risk Engine Unit Tests                 |
//+------------------------------------------------------------------+
#property copyright "AtlasEA v0.1.11.0 - Tests"
#property strict

#include "../Core/NullLogger.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Engines/RiskEngine/RiskState.mqh"
#include "../Engines/RiskEngine/KillSwitch.mqh"
#include "../Engines/RiskEngine/CooldownManager.mqh"
#include "../Engines/RiskEngine/ExposureCalculator.mqh"
#include "../Engines/RiskEngine/PositionSizer.mqh"
#include "../Engines/RiskEngine/DrawdownMonitor.mqh"
#include "../Engines/RiskEngine/MarginMonitor.mqh"
#include "../Engines/RiskEngine/RiskRuleSet.mqh"
#include "../Engines/RiskEngine/RiskEvaluator.mqh"
#include "../Engines/RiskEngine.mqh"

//+------------------------------------------------------------------+
//| Test framework helpers                                           |
//+------------------------------------------------------------------+
int g_tests_run = 0, g_tests_passed = 0, g_tests_failed = 0;

void AssertTrue(const string name, const bool cond)
{
    g_tests_run++;
    if(cond) { g_tests_passed++; Print("  [PASS] ", name); }
    else     { g_tests_failed++; Print("  [FAIL] ", name); }
}

void AssertEquals(const string name, const double actual, const double expected, const double tol = 0.001)
{
    g_tests_run++;
    bool ok = MathAbs(actual - expected) < tol;
    if(ok) { g_tests_passed++; Print("  [PASS] ", name, " (", DoubleToString(actual, 4), ")"); }
    else   { g_tests_failed++; Print("  [FAIL] ", name, " expected=", DoubleToString(expected, 4), " got=", DoubleToString(actual, 4)); }
}

void PrintHeader(const string t) { Print(""); Print("=== ", t, " ==="); }
void PrintSummary(void)
{
    Print(""); Print("=== TEST SUMMARY ===");
    Print("  Total: ", g_tests_run, "  Passed: ", g_tests_passed, "  Failed: ", g_tests_failed);
    if(g_tests_failed == 0) Print("  *** ALL TESTS PASSED ***");
}

//+------------------------------------------------------------------+
//| Helper: build a valid vote                                       |
//+------------------------------------------------------------------+
void BuildVote(AggregatedVote &vote, const int direction = ATLAS_ORDER_BUY,
               const double confidence = 0.7, const double entry = 1.0850,
               const double sl = 1.0800, const double tp = 1.0950,
               const double volume = 0.10, const int strategy_id = 1)
{
    vote.aggregation_id = "AGG_TEST";
    vote.direction      = direction;
    vote.confidence     = confidence;
    vote.vote_count     = 1;
    vote.snapshot_id    = 1;
    vote.votes[0].strategy_id      = strategy_id;
    vote.votes[0].strategy_version = "1.0.0";
    vote.votes[0].direction        = direction;
    vote.votes[0].confidence       = confidence;
    vote.votes[0].suggested_volume = volume;
    vote.votes[0].suggested_entry  = entry;
    vote.votes[0].suggested_sl     = sl;
    vote.votes[0].suggested_tp     = tp;
    vote.votes[0].snapshot_id      = 1;
    vote.votes[0].vote_time        = TimeCurrent();
}

void BuildMarketState(MarketState &state)
{
    ZeroMemory(state);
    state.snapshot_id = 1;
    state.timestamp = TimeCurrent();
    state.symbol = "EURUSD";
    state.bid = 1.0850; state.ask = 1.0851; state.last = 1.0850;
    state.spread = 0.0001; state.point = 0.00001; state.digits = 5;
    state.atr_14 = 0.0020; state.volatility_index = 18.0;
    state.is_fast_market = false;
    state.trend_direction = 1; state.trend_strength = 50;
    state.session_state = ATLAS_SESSION_LONDON;
    state.feature_count = ATLAS_FEATURE_SIZE;
    state.is_valid = true;
}

//+------------------------------------------------------------------+
//| Test 1: Kill Switch                                              |
//+------------------------------------------------------------------+
void TestKillSwitch(void)
{
    PrintHeader("Test 1: Kill Switch");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10000.0);

    KillSwitch ks;
    ks.Initialize(&context, &logger);

    AssertTrue("Kill switch inactive initially", !ks.IsActive());

    ks.Activate(ATLAS_KS_REASON_MANUAL, "Test manual trigger");
    AssertTrue("Kill switch active after activate", ks.IsActive());
    AssertTrue("Reason recorded", context.GetKillSwitchReason() == "Test manual trigger");

    //--- Idempotent
    ks.Activate(ATLAS_KS_REASON_DAILY_DD, "Second trigger");
    AssertTrue("Kill switch still active (idempotent)", ks.IsActive());
    AssertTrue("Reason unchanged (idempotent)", context.GetKillSwitchReason() == "Test manual trigger");

    ks.Deactivate();
    AssertTrue("Kill switch inactive after deactivate", !ks.IsActive());
}

//+------------------------------------------------------------------+
//| Test 2: Drawdown                                                 |
//+------------------------------------------------------------------+
void TestDrawdown(void)
{
    PrintHeader("Test 2: Drawdown");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10500.0);

    DrawdownMonitor dd;
    dd.Initialize(&logger, 5.0, 4.0, 8.0);

    RiskState state;
    //--- Equity dropped from 10500 to 10200 → DD = (10500-10200)/10000 = 3%
    bool ok = dd.Update(state, &context, 10200.0, 0.0);
    AssertTrue("3% DD within limits", ok);
    AssertEquals("Daily DD = 3.0%", state.daily_drawdown_pct, 3.0);

    //--- Equity dropped to 9800 → DD = (10500-9800)/10000 = 7% → exceeds 5%
    ok = dd.Update(state, &context, 9800.0, 0.0);
    AssertTrue("7% DD exceeds limit", !ok);

    //--- Equity dropped to 9500 → DD = 10% → critical (8%)
    ok = dd.Update(state, &context, 9500.0, 0.0);
    AssertTrue("10% DD is critical", dd.IsCritical(state));
}

//+------------------------------------------------------------------+
//| Test 3: Exposure                                                 |
//+------------------------------------------------------------------+
void TestExposure(void)
{
    PrintHeader("Test 3: Exposure");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();

    //--- Add 2 positions
    PositionState pos[2];
    pos[0].symbol = "EURUSD"; pos[0].type = POSITION_TYPE_BUY;
    pos[0].volume = 0.50; pos[0].broker_verified = true;
    pos[1].symbol = "EURUSD"; pos[1].type = POSITION_TYPE_SELL;
    pos[1].volume = 0.30; pos[1].broker_verified = true;
    context.SetPositions(pos, 2);

    ExposureCalculator ec;
    ec.Initialize(&context, &logger, 100000.0, "EURUSD");

    double equity = 10000.0;
    double current = ec.CalculateCurrentExposure(equity);
    //--- 0.80 lots × 100000 / 10000 × 100 = 800%
    AssertEquals("Current exposure = 800%", current, 800.0);

    double projected = ec.CalculateProjectedExposure(equity, 0.10);
    //--- 0.90 × 100000 / 10000 × 100 = 900%
    AssertEquals("Projected exposure = 900%", projected, 900.0);

    double dir_exp = ec.CalculateDirectionalExposure(equity);
    //--- Net = 0.50 - 0.30 = 0.20 long → 0.20 × 100000 / 10000 × 100 = 200%
    AssertEquals("Directional exposure = 200%", dir_exp, 200.0);
}

//+------------------------------------------------------------------+
//| Test 4: Cooldown                                                 |
//+------------------------------------------------------------------+
void TestCooldown(void)
{
    PrintHeader("Test 4: Cooldown");
    NullLogger logger;
    CooldownManager cm;
    cm.Initialize(&logger, 3, 1800);

    RiskState state;
    AssertTrue("No cooldown initially", !cm.IsGlobalCooldownActive(state));

    //--- Apply global cooldown
    cm.ApplyGlobalCooldown(state, 300);
    AssertTrue("Global cooldown active", cm.IsGlobalCooldownActive(state));

    //--- Per-strategy cooldown
    cm.ApplyStrategyCooldown(state, 1, 600);
    AssertTrue("Strategy 1 in cooldown", cm.IsStrategyInCooldown(state, 1));
    AssertTrue("Strategy 2 also blocked by global", cm.IsStrategyInCooldown(state, 2));

    //--- Clear global, strategy 1 still blocked
    state.cooldown_type = ATLAS_COOLDOWN_NONE;
    state.cooldown_until = 0;
    AssertTrue("Strategy 1 still in per-strategy cooldown", cm.IsStrategyInCooldown(state, 1));
    AssertTrue("Strategy 2 not in cooldown after global cleared", !cm.IsStrategyInCooldown(state, 2));

    //--- Loss streak
    state.consecutive_losses = 3;
    bool triggered = cm.CheckLossStreak(state);
    AssertTrue("Loss streak cooldown triggered", triggered);
    AssertTrue("Cooldown type = LOSS_STREAK", state.cooldown_type == ATLAS_COOLDOWN_LOSS_STREAK);
}

//+------------------------------------------------------------------+
//| Test 5: Margin                                                   |
//+------------------------------------------------------------------+
void TestMargin(void)
{
    PrintHeader("Test 5: Margin");
    NullLogger logger;
    MarginMonitor mm;
    mm.Initialize(&logger, 100.0, 200.0, 100.0);

    RiskState state;
    mm.Update(state, 10000.0, 4000.0);
    //--- margin_level = 10000/4000 × 100 = 250%
    AssertEquals("Margin level = 250%", state.margin_level, 250.0);
    AssertEquals("Free margin = 6000", state.free_margin, 6000.0);
    AssertTrue("Margin safe (250% > 200%)", mm.IsMarginSafe(state));

    mm.Update(state, 7000.0, 4000.0);
    //--- margin_level = 7000/4000 × 100 = 175%
    AssertEquals("Margin level = 175%", state.margin_level, 175.0);
    AssertTrue("Margin unsafe (175% < 200%)", !mm.IsMarginSafe(state));

    mm.Update(state, 3500.0, 4000.0);
    //--- margin_level = 3500/4000 × 100 = 87.5%
    AssertTrue("Margin critical (87.5% < 100%)", mm.IsCritical(state));
}

//+------------------------------------------------------------------+
//| Test 6: Position Sizing                                          |
//+------------------------------------------------------------------+
void TestPositionSizing(void)
{
    PrintHeader("Test 6: Position Sizing");
    NullLogger logger;

    //--- Fixed Lot
    SizerConfig cfg;
    cfg.method = ATLAS_SIZER_FIXED_LOT;
    cfg.fixed_lot = 0.20;
    PositionSizer sizer;
    sizer.Initialize(&logger, cfg, 100000.0);
    AssertEquals("Fixed lot = 0.20", sizer.Calculate(10000.0, 0.0050), 0.20);

    //--- Risk Percent: equity=10000, risk=1%, SL=50 pips (0.0050), contract=100000
    //--- risk_amount = 10000 × 0.01 = 100
    //--- sl_value_per_lot = 0.0050 × 100000 = 500
    //--- volume = 100 / 500 = 0.20
    cfg.method = ATLAS_SIZER_RISK_PERCENT;
    cfg.risk_percent = 1.0;
    sizer.SetConfig(cfg);
    AssertEquals("Risk % = 0.20", sizer.Calculate(10000.0, 0.0050), 0.20);

    //--- Risk Percent with different SL
    //--- risk_amount = 100, sl_value_per_lot = 0.0025 × 100000 = 250
    //--- volume = 100 / 250 = 0.40
    AssertEquals("Risk % with tighter SL = 0.40", sizer.Calculate(10000.0, 0.0025), 0.40);

    //--- Fixed Money: risk=$50, SL=0.0050
    //--- sl_value_per_lot = 500
    //--- volume = 50 / 500 = 0.10
    cfg.method = ATLAS_SIZER_FIXED_MONEY;
    cfg.fixed_money_risk = 50.0;
    sizer.SetConfig(cfg);
    AssertEquals("Fixed money = 0.10", sizer.Calculate(10000.0, 0.0050), 0.10);

    //--- Clamping: very small SL → huge volume → clamped to max
    cfg.method = ATLAS_SIZER_RISK_PERCENT;
    cfg.risk_percent = 10.0;
    cfg.max_lot = 5.0;
    sizer.SetConfig(cfg);
    double vol = sizer.Calculate(100000.0, 0.0001);
    AssertTrue("Volume clamped to max", vol <= 5.0);
}

//+------------------------------------------------------------------+
//| Test 7: Approved Decision                                       |
//+------------------------------------------------------------------+
void TestApprovedDecision(void)
{
    PrintHeader("Test 7: Approved Decision");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10000.0);

    RiskRuleConfig rule_cfg;
    SizerConfig sizer_cfg;
    AtlasConfig atlas_cfg;
    AtlasConfigDefaults(atlas_cfg);

    RiskEvaluator evaluator;
    evaluator.Initialize(&context, &logger, atlas_cfg, rule_cfg, sizer_cfg);
    evaluator.UpdateState(10000.0, 0.0, 0.0);

    MarketState market;
    BuildMarketState(market);

    AggregatedVote vote;
    BuildVote(vote, ATLAS_ORDER_BUY, 0.8, 1.0850, 1.0800, 1.0950, 0.10);

    RiskDecision d = evaluator.Evaluate(vote, market, 1);

    AssertTrue("Decision APPROVED", d.status == ATLAS_DECISION_APPROVED);
    AssertTrue("Reason OK", d.reason_code == ATLAS_RISK_REASON_OK);
    AssertTrue("Direction = BUY", d.order_type == ATLAS_ORDER_BUY);
    AssertTrue("Volume > 0", d.approved_volume > 0.0);
    AssertTrue("SL > 0", d.approved_sl > 0.0);
    AssertTrue("TP > 0", d.approved_tp > 0.0);
    AssertTrue("Kill switch not triggered", !d.kill_switch_triggered);
}

//+------------------------------------------------------------------+
//| Test 8: Rejected Decision (Drawdown)                            |
//+------------------------------------------------------------------+
void TestRejectedDecision(void)
{
    PrintHeader("Test 8: Rejected Decision (Drawdown)");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10000.0);

    RiskRuleConfig rule_cfg;
    rule_cfg.max_daily_dd_pct = 5.0;
    SizerConfig sizer_cfg;
    AtlasConfig atlas_cfg;
    AtlasConfigDefaults(atlas_cfg);

    RiskEvaluator evaluator;
    evaluator.Initialize(&context, &logger, atlas_cfg, rule_cfg, sizer_cfg);

    //--- Simulate 7% drawdown (exceeds 5%)
    evaluator.UpdateState(9300.0, 0.0, 0.0);

    MarketState market;
    BuildMarketState(market);

    AggregatedVote vote;
    BuildVote(vote);

    RiskDecision d = evaluator.Evaluate(vote, market, 1);

    AssertTrue("Decision REJECTED", d.status == ATLAS_DECISION_REJECTED);
    AssertTrue("Reason = DRAWDOWN", d.reason_code == ATLAS_RISK_REASON_DRAWDOWN);
    AssertTrue("Volume = 0", d.approved_volume == 0.0);
}

//+------------------------------------------------------------------+
//| Test 9: Modified Decision (Volume reduced)                      |
//+------------------------------------------------------------------+
void TestModifiedDecision(void)
{
    PrintHeader("Test 9: Modified Decision (Volume)");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10000.0);

    RiskRuleConfig rule_cfg;
    rule_cfg.max_lot = 0.50;  ///< Max 0.50 lots
    SizerConfig sizer_cfg;
    AtlasConfig atlas_cfg;
    AtlasConfigDefaults(atlas_cfg);

    RiskEvaluator evaluator;
    evaluator.Initialize(&context, &logger, atlas_cfg, rule_cfg, sizer_cfg);
    evaluator.UpdateState(10000.0, 0.0, 0.0);

    MarketState market;
    BuildMarketState(market);

    //--- Vote with volume 1.0 (exceeds max 0.50)
    AggregatedVote vote;
    BuildVote(vote, ATLAS_ORDER_BUY, 0.8, 1.0850, 1.0800, 1.0950, 1.0);

    RiskDecision d = evaluator.Evaluate(vote, market, 1);

    AssertTrue("Decision APPROVED (modified)", d.status == ATLAS_DECISION_APPROVED);
    AssertEquals("Volume reduced to 0.50", d.approved_volume, 0.50);
}

//+------------------------------------------------------------------+
//| Test 10: Kill Switch blocks everything                          |
//+------------------------------------------------------------------+
void TestKillSwitchBlocks(void)
{
    PrintHeader("Test 10: Kill Switch Blocks All");
    NullLogger logger;
    AtlasContext context;
    context.ResetAll();
    context.SetDailyStartEquity(10000.0);
    context.UpdateDailyPeakEquity(10000.0);
    context.ActivateKillSwitch("Test kill switch");

    RiskRuleConfig rule_cfg;
    SizerConfig sizer_cfg;
    AtlasConfig atlas_cfg;
    AtlasConfigDefaults(atlas_cfg);

    RiskEvaluator evaluator;
    evaluator.Initialize(&context, &logger, atlas_cfg, rule_cfg, sizer_cfg);
    evaluator.UpdateState(10000.0, 0.0, 0.0);

    MarketState market;
    BuildMarketState(market);

    AggregatedVote vote;
    BuildVote(vote);

    RiskDecision d = evaluator.Evaluate(vote, market, 1);

    AssertTrue("Decision REJECTED", d.status == ATLAS_DECISION_REJECTED);
    AssertTrue("Reason = KILLSWITCH", d.reason_code == ATLAS_RISK_REASON_KILLSWITCH);
    AssertTrue("Kill switch triggered flag set", d.kill_switch_triggered);
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
int OnInit(void)
{
    Print("");
    Print("############################################");
    Print("# AtlasEA v0.1.11.0 - Risk Engine Tests   #");
    Print("############################################");

    TestKillSwitch();
    TestDrawdown();
    TestExposure();
    TestCooldown();
    TestMargin();
    TestPositionSizing();
    TestApprovedDecision();
    TestRejectedDecision();
    TestModifiedDecision();
    TestKillSwitchBlocks();

    PrintSummary();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}
void OnTick(void) {}
void OnTimer(void) {}
//+------------------------------------------------------------------+
