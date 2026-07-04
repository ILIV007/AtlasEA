//+------------------------------------------------------------------+
//|                                       Engines/MarketEngine.mqh    |
//|          AtlasEA v0.1.1.0 - Market Data Processing Engine        |
//|                                                                  |
//|  Implements IMarketDataSource.                                   |
//|  Transforms RawTick → MarketState with:                          |
//|    - Tick validation                                             |
//|    - OHLC bar building (100-bar ring buffer)                    |
//|    - ATR(14) / True Range / Volatility Index                    |
//|    - Non-repainting trend detection                             |
//|    - Market regime detection (8 regimes)                        |
//|    - 32 normalized features                                      |
//|    - Session detection (Asia/London/NY/Overlap/Holiday/Weekend) |
//|    - Fast market detection                                       |
//|    - Full diagnostics (latency, feature time, ATR time)         |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_ENGINE_MQH
#define ATLAS_MARKET_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Core/ValidationResult.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IMarketDataSource.mqh"
#include "MarketEngine/BarBuffer.mqh"
#include "MarketEngine/TickValidator.mqh"
#include "MarketEngine/SessionDetector.mqh"
#include "MarketEngine/IndicatorCache.mqh"
#include "MarketEngine/ATRCalculator.mqh"
#include "MarketEngine/TrendDetector.mqh"
#include "MarketEngine/RegimeDetector.mqh"
#include "MarketEngine/FeatureExtractor.mqh"

/**
 * @class MarketEngine
 * @brief Production-grade market data processing engine.
 *
 * Pipeline (per tick):
 *   1. Validate tick (bid/ask/spread/timestamp/duplicate/out-of-order)
 *   2. Update OHLC bar buffer (detect new bar → refresh indicators)
 *   3. Refresh indicator cache (all at shift=1 → non-repainting)
 *   4. Update trend detector (EMA crossover on closed bars)
 *   5. Update regime detector (8 market regimes)
 *   6. Compute volatility index + fast market detection
 *   7. Extract 32 normalized features
 *   8. Build and return immutable MarketState
 *
 * Performance budget: 10 ms per ProcessTick call.
 *   - Tick validation: O(1)
 *   - Bar update: O(1)
 *   - Indicator refresh: O(1) per indicator (9 indicators)
 *   - Trend update: O(1)
 *   - Regime update: O(1)
 *   - Feature extraction: O(1) per feature (32 features)
 *
 * Memory: all components are stack-allocated. Zero dynamic allocation.
 *
 * Non-repainting guarantee: ALL indicator reads use shift=1 (last CLOSED
 * bar). The forming bar is never consulted for indicator values. Trend
 * and regime classifications are stable once a bar closes.
 */
class MarketEngine : public IMarketDataSource
{
private:
    //=== Dependencies (injected, NOT owned) ===
    IBrokerAdapter *m_broker;       ///< Broker adapter (REQUIRED)
    ILogger        *m_logger;       ///< Logger (REQUIRED)
    AtlasConfig     m_config;       ///< Configuration snapshot

    //=== Internal components (stack-allocated, owned) ===
    BarBuffer       m_bar_buffer;       ///< 100-bar OHLC ring buffer
    TickValidator   m_tick_validator;   ///< Tick validation
    SessionDetector m_session_detector; ///< Session detection
    IndicatorCache  m_indicator_cache;  ///< Indicator handle + value cache
    ATRCalculator   m_atr_calculator;   ///< ATR(14) with Wilder smoothing
    TrendDetector   m_trend_detector;   ///< Trend detection
    RegimeDetector  m_regime_detector;  ///< Regime detection
    FeatureExtractor m_feature_extractor; ///< 32-feature extraction

    //=== Current bar state ===
    BarData m_current_bar;       ///< The forming (unclosed) bar
    bool    m_has_current_bar;   ///< true if a forming bar exists
    datetime m_last_bar_time;    ///< Open time of the current forming bar

    //=== Diagnostics ===
    /// @struct MarketDiagnostics
    /// @brief Per-call timing measurements (microseconds via GetTickCount64).
    struct MarketDiagnostics
    {
        ulong total_calls;         ///< Lifetime ProcessTick calls
        ulong total_valid_ticks;   ///< Lifetime valid ticks
        ulong total_invalid_ticks; ///< Lifetime rejected ticks
        ulong total_new_bars;      ///< Lifetime new-bar events
        double avg_latency_ms;     ///< Running average latency
        double peak_latency_ms;    ///< Peak latency
        double avg_feature_ms;     ///< Running average feature extraction time
        double avg_atr_ms;         ///< Running average ATR refresh time
        double avg_trend_ms;       ///< Running average trend calc time
    };
    MarketDiagnostics m_diag;

    /// @brief Update the forming bar with a new tick.
    void UpdateCurrentBar(const RawTick &tick);

    /// @brief Detect if a new bar has started; if so, close the old one.
    bool CheckNewBar(const RawTick &tick);

    /// @brief Close the current forming bar and push it to the ring buffer.
    void CloseCurrentBar(void);

    /// @brief Compute the volatility index (ATR / price * 10000).
    double ComputeVolatilityIndex(const double atr, const double price) const;

    /// @brief Detect fast market (ATR spike vs historical average).
    bool DetectFastMarket(void) const;

    /// @brief Compute bar progress (0.0 = just opened, 1.0 = about to close).
    double ComputeBarProgress(void) const;

    /// @brief Build the final immutable MarketState.
    MarketState BuildMarketState(const RawTick &tick, const long snapshot_id);

    /// @brief Build an invalid MarketState with a rejection reason.
    MarketState BuildInvalidState(const RawTick &tick, const long snapshot_id,
                                  const string reason);

    /// @brief Update diagnostics with a new latency sample.
    void UpdateDiagnostics(const double latency_ms, const double feature_ms,
                           const double atr_ms, const double trend_ms,
                           const bool valid);

public:
    /**
     * @brief Constructor.
     */
    MarketEngine(void);

    /**
     * @brief Destructor — calls Shutdown.
     */
    ~MarketEngine(void);

    /**
     * @brief Set dependencies. Must be called BEFORE Initialize().
     * @param broker Broker adapter (REQUIRED).
     * @param logger Logger (REQUIRED).
     * @param config EA configuration.
     */
    void SetDependencies(IBrokerAdapter *broker, ILogger *logger, const AtlasConfig &config);

    //=== IMarketDataSource implementation ===

    /**
     * @brief Process a raw tick and produce a MarketState snapshot.
     *
     * Pipeline: validate → update bars → refresh indicators →
     *           update trend → update regime → extract features → build state.
     *
     * @param tick        Raw tick from the broker adapter.
     * @param snapshot_id Monotonic snapshot ID from SnapshotManager.
     * @return Fully populated MarketState (check is_valid before use).
     */
    virtual MarketState ProcessTick(const RawTick &tick, const long snapshot_id) override;

    /**
     * @brief Initialize the market engine. Requires SetDependencies() first.
     * @return true if initialization succeeded.
     */
    virtual bool Initialize(void) override;

    /**
     * @brief Shutdown — release all indicator handles.
     */
    virtual void Shutdown(void) override;

    //=== Diagnostics accessors ===

    /// @brief Total ProcessTick calls.
    ulong TotalCalls(void) const { return m_diag.total_calls; }

    /// @brief Total valid ticks processed.
    ulong TotalValidTicks(void) const { return m_diag.total_valid_ticks; }

    /// @brief Total rejected ticks.
    ulong TotalInvalidTicks(void) const { return m_diag.total_invalid_ticks; }

    /// @brief Average latency in milliseconds.
    double AvgLatencyMs(void) const { return m_diag.avg_latency_ms; }

    /// @brief Peak latency in milliseconds.
    double PeakLatencyMs(void) const { return m_diag.peak_latency_ms; }

    /// @brief Average feature extraction time in milliseconds.
    double AvgFeatureMs(void) const { return m_diag.avg_feature_ms; }

    /// @brief Average ATR refresh time in milliseconds.
    double AvgAtrMs(void) const { return m_diag.avg_atr_ms; }

    /// @brief Average trend calculation time in milliseconds.
    double AvgTrendMs(void) const { return m_diag.avg_trend_ms; }

    /// @brief Log diagnostics summary.
    void LogDiagnostics(void) const;

    //=== Design by Contract (v0.1.26.x) ===

    /**
     * @brief Validate internal state for consistency.
     * @return ValidationResult — Ok() if all invariants hold, Fail() otherwise.
     *
     * Invariants checked:
     *   - m_broker != NULL (required dependency)
     *   - m_logger != NULL (required dependency)
     *   - m_indicator_cache.IsInitialized() (lifecycle proxy for the
     *     engine itself — MarketEngine has no explicit m_initialized flag,
     *     so the indicator cache state serves as the init sentinel)
     *   - m_bar_buffer.Count() in [0, ATLAS_BAR_BUFFER_CAPACITY]
     *
     * Note: MarketEngine does NOT cache the last MarketState (it builds a
     * fresh immutable snapshot per ProcessTick call), so there is no
     * cached-state validation to delegate to here. MarketState invariants
     * are enforced inside ProcessTick via BuildMarketState().
     *
     * Non-throwing (MQL5 has no exceptions).
     */
    ValidationResult Validate(void) const
    {
        if(m_broker == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "broker adapter is NULL", "m_broker");
        if(m_logger == NULL)
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "logger is NULL", "m_logger");
        if(!m_indicator_cache.IsInitialized())
            return ValidationResult::Fail(ATLAS_V_NOT_INITIALIZED,
                "indicator cache not initialized (engine not initialized)",
                "m_indicator_cache");
        int bar_count = m_bar_buffer.Count();
        if(bar_count < 0 || bar_count > ATLAS_BAR_BUFFER_CAPACITY)
            return ValidationResult::Fail(ATLAS_V_INVALID_RANGE,
                "bar buffer count out of range [0, " +
                IntegerToString(ATLAS_BAR_BUFFER_CAPACITY) + "]",
                "m_bar_buffer");
        return ValidationResult::Ok();
    }

    /// @brief Convenience wrapper — true if Validate() passes.
    bool IsValid(void) const { return Validate().valid; }
};

//+------------------------------------------------------------------+
//| MarketEngine implementation                                       |
//+------------------------------------------------------------------+

MarketEngine::MarketEngine(void)
{
    m_broker          = NULL;
    m_logger          = NULL;
    m_has_current_bar = false;
    m_last_bar_time   = 0;
    ZeroMemory(m_current_bar);
    ZeroMemory(m_diag);
}

//+------------------------------------------------------------------+
MarketEngine::~MarketEngine(void)
{
    Shutdown();
}

//+------------------------------------------------------------------+
void MarketEngine::SetDependencies(IBrokerAdapter *broker, ILogger *logger, const AtlasConfig &config)
{
    m_broker = broker;
    m_logger = logger;
    m_config = config;
}

//+------------------------------------------------------------------+
bool MarketEngine::Initialize(void)
{
    if(m_broker == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("MarketEngine", "Initialize: broker adapter is NULL");
        return false;
    }
    if(m_logger == NULL)
    {
        //--- Cannot log this since logger is NULL, but return false
        return false;
    }

    //--- Initialize internal components
    double pt = (m_broker != NULL) ? m_broker.SymbolPoint() : 0.00001;
    m_tick_validator.Initialize(m_logger, m_config.max_spread_points, pt, 30, 5);
    m_session_detector.Initialize(m_logger, 0);  //--- Server UTC offset = 0 (adjust per broker)

    if(!m_indicator_cache.Initialize(m_broker, m_logger, m_config))
    {
        m_logger.Error("MarketEngine", "IndicatorCache initialization failed");
        return false;
    }

    m_atr_calculator.Initialize(m_config.atr_period);
    m_trend_detector.Initialize(m_logger, 0.25);
    m_regime_detector.Initialize(m_logger);
    m_feature_extractor.Initialize(m_logger);

    //--- Prefill bar buffer from history (closed bars only)
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int period_sec = m_broker.PeriodSeconds();
    if(period_sec <= 0) period_sec = 60;

    int copied = m_broker.CopyRates(0, ATLAS_BAR_BUFFER_CAPACITY + 1, rates);
    if(copied > 1)
    {
        double running_prev_close = 0.0;
        for(int i = copied - 1; i >= 1; i--)
        {
            BarData bar;
            bar.time        = rates[i].time;
            bar.open        = rates[i].open;
            bar.high        = rates[i].high;
            bar.low         = rates[i].low;
            bar.close       = rates[i].close;
            bar.tick_volume = (long)rates[i].tick_volume;
            bar.real_volume = (long)rates[i].real_volume;
            m_bar_buffer.AddBar(bar);

            //--- Seed ATR calculator with historical bars
            m_atr_calculator.OnBarClose(bar.high, bar.low, bar.close, running_prev_close);
            running_prev_close = bar.close;
        }

        //--- Set up the forming bar from the most recent rate
        m_current_bar.time        = rates[0].time;
        m_current_bar.open        = rates[0].open;
        m_current_bar.high        = rates[0].high;
        m_current_bar.low         = rates[0].low;
        m_current_bar.close       = rates[0].close;
        m_current_bar.tick_volume = (long)rates[0].tick_volume;
        m_current_bar.real_volume = (long)rates[0].real_volume;
        m_has_current_bar = true;
        m_last_bar_time   = rates[0].time;
    }

    //--- Initial indicator refresh + trend/regime update
    m_indicator_cache.Refresh();
    m_trend_detector.Update(m_indicator_cache);
    double price = m_broker.SymbolBid() + m_broker.SymbolAsk();
    price = price / 2.0;
    m_regime_detector.Update(m_indicator_cache, m_trend_detector, m_bar_buffer, price);

    m_logger.Info("MarketEngine",
        "Initialized. Bars=" + IntegerToString(m_bar_buffer.Count()) +
        " ATR=" + DoubleToString(m_indicator_cache.ATR(), m_config.volume_digits) +
        " Trend=" + IntegerToString(m_trend_detector.Direction()) +
        " Regime=" + m_regime_detector.RegimeName(m_regime_detector.CurrentRegime()));

    return true;
}

//+------------------------------------------------------------------+
void MarketEngine::Shutdown(void)
{
    m_indicator_cache.Shutdown();
    m_has_current_bar = false;
    m_last_bar_time   = 0;
    m_bar_buffer.Reset();

    //--- Clear diagnostics so a re-Initialize() starts with zeroed counters.
    //    Without this, lifetime totals carry over across restart.
    ZeroMemory(m_diag);

    if(m_logger != NULL)
        m_logger.Info("MarketEngine", "Shutdown complete");
}

//+------------------------------------------------------------------+
bool MarketEngine::CheckNewBar(const RawTick &tick)
{
    int period_sec = m_broker.PeriodSeconds();
    if(period_sec <= 0) period_sec = 60;

    datetime bar_time = (datetime)(((long)tick.timestamp / period_sec) * period_sec);

    if(!m_has_current_bar)
    {
        //--- Start a new forming bar
        double mid = (tick.bid + tick.ask) / 2.0;
        m_current_bar.time        = bar_time;
        m_current_bar.open        = mid;
        m_current_bar.high        = mid;
        m_current_bar.low         = mid;
        m_current_bar.close       = mid;
        m_current_bar.tick_volume = tick.volume;
        m_current_bar.real_volume = 0;
        m_has_current_bar = true;
        m_last_bar_time   = bar_time;
        return false;
    }

    if(bar_time > m_last_bar_time)
    {
        //--- New bar — close the current one and push to buffer
        CloseCurrentBar();

        //--- Start new forming bar
        double mid = (tick.bid + tick.ask) / 2.0;
        m_current_bar.time        = bar_time;
        m_current_bar.open        = mid;
        m_current_bar.high        = mid;
        m_current_bar.low         = mid;
        m_current_bar.close       = mid;
        m_current_bar.tick_volume = tick.volume;
        m_current_bar.real_volume = 0;
        m_last_bar_time           = bar_time;

        return true;  //--- New bar event
    }

    return false;
}

//+------------------------------------------------------------------+
void MarketEngine::CloseCurrentBar(void)
{
    if(!m_has_current_bar) return;

    //--- Get previous close for ATR True Range calculation
    double prev_close = 0.0;
    BarData prev_bar;
    if(m_bar_buffer.GetNewest(prev_bar))
        prev_close = prev_bar.close;

    //--- Add to ring buffer
    m_bar_buffer.AddBar(m_current_bar);

    //--- Update ATR calculator with the newly closed bar
    m_atr_calculator.OnBarClose(m_current_bar.high, m_current_bar.low,
                                 m_current_bar.close, prev_close);

    m_diag.total_new_bars++;
}

//+------------------------------------------------------------------+
void MarketEngine::UpdateCurrentBar(const RawTick &tick)
{
    if(!m_has_current_bar) return;

    if(tick.ask > m_current_bar.high) m_current_bar.high = tick.ask;
    if(tick.bid < m_current_bar.low)  m_current_bar.low  = tick.bid;

    double mid = (tick.bid + tick.ask) / 2.0;
    m_current_bar.close       = mid;
    m_current_bar.tick_volume += tick.volume;
}

//+------------------------------------------------------------------+
double MarketEngine::ComputeVolatilityIndex(const double atr, const double price) const
{
    if(price <= 0.0) return 0.0;
    return (atr / price) * 10000.0;
}

//+------------------------------------------------------------------+
bool MarketEngine::DetectFastMarket(void) const
{
    if(!m_indicator_cache.IsValid()) return false;
    double atr     = m_indicator_cache.ATR();
    double atr_avg = (m_indicator_cache.ATR() + m_indicator_cache.ATRPrev()) / 2.0;
    if(atr_avg <= 0.0) return false;
    return (atr > atr_avg * m_config.fast_market_atr_mult);
}

//+------------------------------------------------------------------+
double MarketEngine::ComputeBarProgress(void) const
{
    if(!m_has_current_bar) return 0.0;
    int period_sec = m_broker.PeriodSeconds();
    if(period_sec <= 0) return 0.0;

    datetime now = TimeCurrent();
    long elapsed = (long)now - (long)m_current_bar.time;
    if(elapsed < 0) return 0.0;
    double progress = (double)elapsed / (double)period_sec;
    if(progress < 0.0) progress = 0.0;
    if(progress > 1.0) progress = 1.0;
    return progress;
}

//+------------------------------------------------------------------+
MarketState MarketEngine::BuildInvalidState(const RawTick &tick, const long snapshot_id,
                                             const string reason)
{
    MarketState state;
    state.snapshot_id   = snapshot_id;
    state.timestamp     = tick.timestamp;
    state.symbol        = m_config.symbol;
    state.bid           = tick.bid;
    state.ask           = tick.ask;
    state.last          = tick.last;
    state.spread        = tick.ask - tick.bid;
    state.point         = m_broker.SymbolPoint();
    state.digits        = m_broker.SymbolDigits();
    state.tick_volume   = tick.volume;
    state.bar_volume    = 0;
    state.real_volume   = 0;
    state.atr_14        = m_indicator_cache.ATR();
    state.volatility_index = 0.0;
    state.is_fast_market   = false;
    state.trend_direction  = m_trend_detector.Direction();
    state.trend_strength   = m_trend_detector.Strength();
    state.trend_duration_bars = m_trend_detector.Duration();
    state.open    = m_current_bar.open;
    state.high    = m_current_bar.high;
    state.low     = m_current_bar.low;
    state.close   = m_current_bar.close;
    state.bar_time = m_current_bar.time;
    state.session_state = m_session_detector.DetectSession(tick.timestamp);
    state.feature_count = 0;
    for(int i = 0; i < ATLAS_FEATURE_SIZE; i++)
        state.features[i] = 0.0;
    state.is_valid       = false;
    state.invalid_reason = reason;
    return state;
}

//+------------------------------------------------------------------+
MarketState MarketEngine::BuildMarketState(const RawTick &tick, const long snapshot_id)
{
    MarketState state;
    state.snapshot_id   = snapshot_id;
    state.timestamp     = tick.timestamp;
    state.symbol        = m_config.symbol;
    state.bid           = tick.bid;
    state.ask           = tick.ask;
    state.last          = tick.last;
    state.spread        = tick.ask - tick.bid;
    state.point         = m_broker.SymbolPoint();
    state.digits        = m_broker.SymbolDigits();
    state.tick_volume   = tick.volume;
    state.bar_volume    = m_has_current_bar ? m_current_bar.tick_volume : 0;
    state.real_volume   = m_has_current_bar ? m_current_bar.real_volume : 0;

    //--- ATR + volatility
    state.atr_14 = m_indicator_cache.ATR();
    double price = (tick.bid + tick.ask) / 2.0;
    state.volatility_index = ComputeVolatilityIndex(state.atr_14, price);

    //--- Fast market detection
    state.is_fast_market = DetectFastMarket();

    //--- Trend
    state.trend_direction     = m_trend_detector.Direction();
    state.trend_strength      = m_trend_detector.Strength();
    state.trend_duration_bars = m_trend_detector.Duration();

    //--- Current bar OHLC
    if(m_has_current_bar)
    {
        state.open     = m_current_bar.open;
        state.high     = m_current_bar.high;
        state.low      = m_current_bar.low;
        state.close    = m_current_bar.close;
        state.bar_time = m_current_bar.time;
    }
    else
    {
        state.open = state.high = state.low = state.close = price;
        state.bar_time = 0;
    }

    //--- Session
    state.session_state = m_session_detector.DetectSession(tick.timestamp);

    //--- Extract 32 features
    double spread    = tick.ask - tick.bid;
    double max_spread = m_config.max_spread_points * state.point;
    double bar_progress = ComputeBarProgress();

    m_feature_extractor.Extract(
        state.features, state.feature_count,
        m_indicator_cache, m_trend_detector, m_regime_detector,
        m_bar_buffer, price, spread, max_spread,
        state.session_state, bar_progress);

    //--- Validity
    state.is_valid       = true;
    state.invalid_reason = "";

    return state;
}

//+------------------------------------------------------------------+
void MarketEngine::UpdateDiagnostics(const double latency_ms, const double feature_ms,
                                     const double atr_ms, const double trend_ms,
                                     const bool valid)
{
    m_diag.total_calls++;
    if(valid) m_diag.total_valid_ticks++;
    else      m_diag.total_invalid_ticks++;

    //--- Running average (exponential smoothing: alpha = 0.01)
    double alpha = 0.01;
    if(m_diag.total_calls == 1)
    {
        m_diag.avg_latency_ms = latency_ms;
        m_diag.avg_feature_ms = feature_ms;
        m_diag.avg_atr_ms     = atr_ms;
        m_diag.avg_trend_ms   = trend_ms;
    }
    else
    {
        m_diag.avg_latency_ms = m_diag.avg_latency_ms * (1.0 - alpha) + latency_ms * alpha;
        m_diag.avg_feature_ms = m_diag.avg_feature_ms * (1.0 - alpha) + feature_ms * alpha;
        m_diag.avg_atr_ms     = m_diag.avg_atr_ms     * (1.0 - alpha) + atr_ms     * alpha;
        m_diag.avg_trend_ms   = m_diag.avg_trend_ms   * (1.0 - alpha) + trend_ms   * alpha;
    }

    if(latency_ms > m_diag.peak_latency_ms)
        m_diag.peak_latency_ms = latency_ms;
}

//+------------------------------------------------------------------+
MarketState MarketEngine::ProcessTick(const RawTick &tick, const long snapshot_id)
{
    //--- Start timing
    ulong start_ms = GetTickCount64();

    if(m_broker == NULL || m_logger == NULL)
    {
        //--- Cannot operate — return invalid state
        return BuildInvalidState(tick, snapshot_id, "not_initialized");
    }

    //==============================================================
    // STEP 1: TICK VALIDATION
    //==============================================================
    string reject_reason;
    bool valid = m_tick_validator.Validate(tick, reject_reason);
    if(!valid)
    {
        MarketState bad = BuildInvalidState(tick, snapshot_id, reject_reason);
        ulong elapsed = GetTickCount64() - start_ms;
        UpdateDiagnostics((double)elapsed, 0.0, 0.0, 0.0, false);
        return bad;
    }

    //==============================================================
    // STEP 2: BAR BUFFER UPDATE (detect new bar)
    //==============================================================
    bool new_bar = CheckNewBar(tick);
    if(!new_bar)
        UpdateCurrentBar(tick);

    //==============================================================
    // STEP 3: INDICATOR REFRESH (only on new bar — non-repainting)
    //==============================================================
    ulong atr_start = GetTickCount64();
    if(new_bar)
        m_indicator_cache.Refresh();
    ulong atr_elapsed = GetTickCount64() - atr_start;

    //==============================================================
    // STEP 4: TREND UPDATE (only on new bar)
    //==============================================================
    ulong trend_start = GetTickCount64();
    if(new_bar)
        m_trend_detector.Update(m_indicator_cache);
    ulong trend_elapsed = GetTickCount64() - trend_start;

    //==============================================================
    // STEP 5: REGIME UPDATE (only on new bar)
    //==============================================================
    if(new_bar)
    {
        double price = (tick.bid + tick.ask) / 2.0;
        m_regime_detector.Update(m_indicator_cache, m_trend_detector,
                                  m_bar_buffer, price);
    }

    //==============================================================
    // STEP 6: FEATURE EXTRACTION + BUILD MARKET STATE
    //==============================================================
    ulong feature_start = GetTickCount64();
    MarketState state = BuildMarketState(tick, snapshot_id);
    ulong feature_elapsed = GetTickCount64() - feature_start;

    //==============================================================
    // STEP 7: DIAGNOSTICS
    //==============================================================
    ulong total_elapsed = GetTickCount64() - start_ms;
    UpdateDiagnostics((double)total_elapsed,
                      (double)feature_elapsed,
                      (double)atr_elapsed,
                      (double)trend_elapsed,
                      true);

    //--- Log new bar events
    if(new_bar && m_logger != NULL)
    {
        m_logger.Debug("MarketEngine",
            "New bar: " + IntegerToString((long)state.bar_time) +
            " ATR=" + DoubleToString(state.atr_14, m_config.volume_digits) +
            " Trend=" + IntegerToString(state.trend_direction) +
            " Regime=" + m_regime_detector.RegimeName(m_regime_detector.CurrentRegime()));
    }

    return state;
}

//+------------------------------------------------------------------+
void MarketEngine::LogDiagnostics(void) const
{
    if(m_logger == NULL) return;

    m_logger.Info("MarketEngine",
        "calls=" + IntegerToString((long)m_diag.total_calls) +
        " valid=" + IntegerToString((long)m_diag.total_valid_ticks) +
        " invalid=" + IntegerToString((long)m_diag.total_invalid_ticks) +
        " new_bars=" + IntegerToString((long)m_diag.total_new_bars));
    m_logger.Info("MarketEngine",
        "latency avg=" + DoubleToString(m_diag.avg_latency_ms, 3) +
        " peak=" + DoubleToString(m_diag.peak_latency_ms, 3) + " ms");
    m_logger.Info("MarketEngine",
        "feature avg=" + DoubleToString(m_diag.avg_feature_ms, 3) +
        " atr avg=" + DoubleToString(m_diag.avg_atr_ms, 3) +
        " trend avg=" + DoubleToString(m_diag.avg_trend_ms, 3) + " ms");

    m_tick_validator.LogStats();
}

#endif // ATLAS_MARKET_ENGINE_MQH
//+------------------------------------------------------------------+
