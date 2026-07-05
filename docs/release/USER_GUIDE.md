# AtlasEA v1.0.0 — User Guide

## 1. Installation Guide

1. Copy the `AtlasEA/` folder to `MQL5/Experts/` in your MetaTrader 5 data directory
2. Ensure all subfolders maintain their structure (Core/, Engines/, Interfaces/, etc.)
3. Restart MetaTrader 5 or refresh the Navigator panel

## 2. MT5 Setup Guide

1. Open MetaTrader 5 terminal
2. Enable AutoTrading (button in toolbar)
3. Allow Algorithmic Trading (Tools → Options → Expert Advisors → Allow Algorithmic Trading)
4. Allow DLL imports if required (Tools → Options → Expert Advisors → Allow DLL imports)
5. Ensure the symbol you want to trade is in Market Watch
6. Verify account has Expert trading permission (not investor password)

## 3. Compilation Guide

1. Open MetaEditor 5 (F4 from MT5)
2. Navigate to `MQL5/Experts/AtlasEA/AtlasEA.mq5`
3. Press F7 to compile
4. Verify no errors in the Errors panel
5. The compiled EA will appear in the Navigator panel under Expert Advisors

## 4. Configuration Guide

1. Drag AtlasEA from Navigator onto a chart
2. Configure inputs in the "Inputs" tab:
   - Magic Number: unique per chart instance
   - Base Volume: starting lot size
   - Max Drawdown: daily drawdown limit
   - Log Level: 2=Info (recommended for production)
3. See `docs/release/CONFIGURATION_REFERENCE.md` for all fields

## 5. First Launch Guide

1. Attach AtlasEA to a chart (e.g., EURUSD H1)
2. Check the "Experts" tab for initialization messages
3. Verify: "AtlasEA v1.0 RC initialized successfully on EURUSD"
4. Monitor the "Journal" tab for any warnings
5. The EA will begin processing ticks immediately

## 6. Forward Testing Guide

1. Start with a demo account
2. Use the Balanced preset (default)
3. Monitor for at least 1 week before live deployment
4. Check the Experts tab for:
   - Profile switches (regime changes)
   - Trade lifecycle actions (trailing, BE, partial close)
   - Broker health status
5. Verify no errors in the Journal tab

## 7. Backtesting Guide

1. Use the Validation Framework (via CoreEngine or script)
2. Collect trade records during replay
3. Run `ValidationManager.RunBacktest(from_time, to_time)`
4. Review the ValidationReport:
   - Verdict: PASS/FAIL
   - Score: [0, 100]
   - Confidence: LOW/MEDIUM/HIGH/VERY_HIGH
5. Export CSV for detailed analysis

## 8. Optimization Guide

1. Configure ParameterSpace (which parameters to optimize)
2. Set OptimizationConfig (search mode, objective, anti-overfitting)
3. Run `OptimizationManager.RunOptimization(config)`
4. Review top 10 parameter sets
5. Check rejected sets for validation/anti-overfitting reasons
6. Always validate with walk-forward before deploying

## 9. Recovery Guide

1. After crash/restart, AtlasEA auto-recovers on OnInit
2. RecoveryManager loads the latest snapshot
3. Validates snapshot integrity
4. Reconciles with broker positions
5. If recovery fails (RED): enters safe mode (no new trades)
6. Clear safe mode manually after verifying health

## 10. Replay Guide

1. Load events via ReplayEngine.LoadEvents(from_seq, to_seq)
2. Play at desired speed: Play(speed)
3. Speeds: 1X (real-time), 10X, 100X, MAX (no delay), STEP (manual)
4. Use ReplayValidator to check data integrity before replay
5. Replay is deterministic (same events → same results)

## 11. Log Guide

1. Logs are in `MQL5/Files/AtlasEA_*.log` (FileSink)
2. Also visible in MT5 Experts tab (ConsoleSink)
3. Log levels: 0=Trace, 1=Debug, 2=Info, 3=Warn, 4=Error, 5=Fatal
4. For production: use level 2 (Info)
5. For debugging: use level 1 (Debug) or 0 (Trace)
6. LogRetention cleans files older than 30 days on startup

## 12. Upgrade Guide

### From v0.x to v1.0
1. Backup your current AtlasEA folder
2. Replace with v1.0 source code
3. Recompile AtlasEA.mq5
4. Old configuration files may need updating (new mm_*, tcm_*, profile_* fields)
5. Old snapshots are backward compatible (persistence format unchanged)
6. Old event logs are backward compatible (format unchanged)

### Version Migration
- v0.1.x → v1.0: Add mm_*, tcm_*, profile_*, production safety, performance fields to config
- All persistence formats are backward compatible
- All event formats are backward compatible

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| EA not trading | AutoTrading disabled | Enable AutoTrading in MT5 |
| "broker is NULL" | Not initialized | Check OnInit log for errors |
| No trades generated | All strategies filtered | Check log for filter rejections |
| High memory usage | Too many trades in validation | Reduce ATLAS_VAL_MAX_TRADES |
| Order rejected | Spread/volume/stops invalid | Check SymbolValidator log |
| Trading paused | Broker unhealthy | Check BrokerHealthStatus log |
| Recovery RED | Corrupt snapshot | Delete snapshot file, cold start |
| Timer drift | Server lag | Check RuntimeStatistics timer_drift_ms |

## FAQ

**Q: Can AtlasEA run on multiple symbols simultaneously?**
A: No. v1.0 is single-symbol. Attach to one chart per symbol. Each instance has its own magic number.

**Q: Does AtlasEA support hedging accounts?**
A: Yes. Both hedging and netting accounts are supported (auto-detected).

**Q: What is the minimum deposit?**
A: $1,000 for conservative, $5,000 for balanced. Depends on risk % and broker min lot.

**Q: Can I use custom strategies?**
A: Yes. Implement IStrategy (or extend BaseStrategy) and register with StrategyEngine.

**Q: How long can AtlasEA run continuously?**
A: Designed for weeks. All arrays are fixed-size, all counters use ulong, no memory growth.

**Q: Does AtlasEA work with ECN brokers?**
A: Yes. ECN is auto-detected (small min lot, no freeze level).

**Q: Can I optimize parameters?**
A: Yes. Use the Optimization Framework with grid or random search. Anti-overfitting checks prevent bad parameters.

**Q: What happens during weekend?**
A: Trading pauses automatically (ATLAS_PAUSE_WEEKEND). Resumes Sunday 22:00 (configurable).
