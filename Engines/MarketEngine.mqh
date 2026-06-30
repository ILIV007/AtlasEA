//+------------------------------------------------------------------+
//|                                          Engines/MarketEngine.mqh|
//|                AtlasEA v1.0 - Market Data Processing Engine      |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_ENGINE_MQH
#define ATLAS_MARKET_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"

//+------------------------------------------------------------------+
//| BarData - one OHLCV bar held in the internal ring                |
//+------------------------------------------------------------------+
struct BarData
{
    datetime time;
    double   open;
    double   high;
    double   low;
    double   close;
    long     tick_volume;
    long     real_volume;
};

//+------------------------------------------------------------------+
//| MarketEngine                                                     |
//|   - builds OHLC bars from ticks (real bar builder)               |
//|   - computes ATR(14) via indicator handle (non-repainting)       |
//|   - detects trend from EMA(20/50) crossover on CLOSED bars       |
//|   - emits 32 normalized features for strategy layer              |
//+------------------------------------------------------------------+
class MarketEngine
{
private:
    AtlasConfig m_config;
    BarData     m_bars[ATLAS_BAR_BUFFER_SIZE];
    int         m_bar_count;
    BarData     m_current_bar;
    bool        m_has_current_bar;

    //--- indicator handles
    int         m_handle_atr;
    int         m_handle_ma_fast;
    int         m_handle_ma_slow;
    int         m_handle_rsi;
    int         m_handle_macd;
    int         m_handle_stoch;
    int         m_handle_cci;
    int         m_handle_adx;
    int         m_handle_bands;

    //--- cached indicator values (from last closed bar -> non-repainting)
    double      m_atr;
    double      m_ema_fast;
    double      m_ema_slow;
    double      m_rsi;
    double      m_macd_main;
    double      m_macd_signal;
    double      m_stoch_k;
    double      m_stoch_d;
    double      m_cci;
    double      m_adx;
    double      m_di_plus;
    double      m_di_minus;
    double      m_bb_upper;
    double      m_bb_lower;
    double      m_bb_middle;

    //--- trend cache (recomputed only when new bar closes)
    int         m_trend_direction;
    int         m_trend_strength;
    int         m_trend_duration;
    datetime    m_last_trend_recompute;

    //--- private helpers
    bool        ValidateTick(const RawTick &tick);
    void        UpdateBarBuffer(const RawTick &tick);
    void        RefreshIndicatorCache(void);
    void        RecomputeTrend(void);
    int         TagSession(void) const;
    double      Clamp(double v, double lo, double hi) const;
    void        PopulateFeatures(double &features[], int &count, const RawTick &tick);
    MarketState BuildMarketState(const RawTick &tick, long snapshot_id);
    bool        DetectAnomalies(const RawTick &tick) const;

public:
                MarketEngine(void);
               ~MarketEngine(void);
    bool        Initialize(const AtlasConfig &config);
    void        Shutdown(void);
    MarketState ProcessTick(const RawTick &tick, long snapshot_id);
};

//+------------------------------------------------------------------+
//| Construction / destruction                                       |
//+------------------------------------------------------------------+
MarketEngine::MarketEngine(void)
{
    m_bar_count            = 0;
    m_has_current_bar      = false;
    m_handle_atr           = INVALID_HANDLE;
    m_handle_ma_fast       = INVALID_HANDLE;
    m_handle_ma_slow       = INVALID_HANDLE;
    m_handle_rsi           = INVALID_HANDLE;
    m_handle_macd          = INVALID_HANDLE;
    m_handle_stoch         = INVALID_HANDLE;
    m_handle_cci           = INVALID_HANDLE;
    m_handle_adx           = INVALID_HANDLE;
    m_handle_bands         = INVALID_HANDLE;
    m_atr                  = 0;
    m_ema_fast             = 0;
    m_ema_slow             = 0;
    m_rsi                  = 0;
    m_macd_main            = 0;
    m_macd_signal          = 0;
    m_stoch_k              = 0;
    m_stoch_d              = 0;
    m_cci                  = 0;
    m_adx                  = 0;
    m_di_plus              = 0;
    m_di_minus             = 0;
    m_bb_upper             = 0;
    m_bb_lower             = 0;
    m_bb_middle            = 0;
    m_trend_direction      = 0;
    m_trend_strength       = 0;
    m_trend_duration       = 0;
    m_last_trend_recompute = 0;
}

MarketEngine::~MarketEngine(void) { Shutdown(); }

//+------------------------------------------------------------------+
//| Initialize - create indicator handles, prefill bar buffer        |
//+------------------------------------------------------------------+
bool MarketEngine::Initialize(const AtlasConfig &config)
{
    m_config = config;

    m_handle_atr     = iATR(m_config.symbol, PERIOD_CURRENT, m_config.atr_period);
    m_handle_ma_fast = iMA(m_config.symbol, PERIOD_CURRENT, m_config.ma_fast_period, 0, MODE_EMA, PRICE_CLOSE);
    m_handle_ma_slow = iMA(m_config.symbol, PERIOD_CURRENT, m_config.ma_slow_period, 0, MODE_EMA, PRICE_CLOSE);
    m_handle_rsi     = iRSI(m_config.symbol, PERIOD_CURRENT, m_config.rsi_period, PRICE_CLOSE);
    m_handle_macd    = iMACD(m_config.symbol, PERIOD_CURRENT, m_config.macd_fast, m_config.macd_slow, m_config.macd_signal, PRICE_CLOSE);
    m_handle_stoch   = iStochastic(m_config.symbol, PERIOD_CURRENT, m_config.stoch_k, m_config.stoch_d, m_config.stoch_slow, MODE_SMA, STO_LOWHIGH);
    m_handle_cci     = iCCI(m_config.symbol, PERIOD_CURRENT, m_config.cci_period, PRICE_TYPICAL);
    m_handle_adx     = iADX(m_config.symbol, PERIOD_CURRENT, m_config.adx_period);
    m_handle_bands   = iBands(m_config.symbol, PERIOD_CURRENT, m_config.bb_period, 0, m_config.bb_deviation, PRICE_CLOSE);

    if(m_handle_atr     == INVALID_HANDLE ||
       m_handle_ma_fast == INVALID_HANDLE ||
       m_handle_ma_slow == INVALID_HANDLE ||
       m_handle_rsi     == INVALID_HANDLE ||
       m_handle_macd    == INVALID_HANDLE ||
       m_handle_stoch   == INVALID_HANDLE ||
       m_handle_cci     == INVALID_HANDLE ||
       m_handle_adx     == INVALID_HANDLE ||
       m_handle_bands   == INVALID_HANDLE)
    {
        Print("[MarketEngine] Failed to create one or more indicator handles");
        return false;
    }

    //--- prefill bar buffer from history (closed bars only)
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(m_config.symbol, PERIOD_CURRENT, 0, ATLAS_BAR_BUFFER_SIZE + 1, rates);
    if(copied > 1)
    {
        for(int i = copied - 1; i >= 1; i--)
        {
            if(m_bar_count >= ATLAS_BAR_BUFFER_SIZE) break;
            int idx = m_bar_count;
            m_bars[idx].time         = rates[i].time;
            m_bars[idx].open         = rates[i].open;
            m_bars[idx].high         = rates[i].high;
            m_bars[idx].low          = rates[i].low;
            m_bars[idx].close        = rates[i].close;
            m_bars[idx].tick_volume  = (long)rates[i].tick_volume;
            m_bars[idx].real_volume  = (long)rates[i].real_volume;
            m_bar_count++;
        }
        //--- current (forming) bar
        m_current_bar.time         = rates[0].time;
        m_current_bar.open         = rates[0].open;
        m_current_bar.high         = rates[0].high;
        m_current_bar.low          = rates[0].low;
        m_current_bar.close        = rates[0].close;
        m_current_bar.tick_volume  = (long)rates[0].tick_volume;
        m_current_bar.real_volume  = (long)rates[0].real_volume;
        m_has_current_bar = true;
    }

    RefreshIndicatorCache();
    RecomputeTrend();

    Print("[MarketEngine] Initialized. Historical bars=", m_bar_count,
          " ATR=", DoubleToString(m_atr, _Digits),
          " Trend=", m_trend_direction);
    return true;
}

//+------------------------------------------------------------------+
//| Shutdown - release indicator handles                             |
//+------------------------------------------------------------------+
void MarketEngine::Shutdown(void)
{
    if(m_handle_atr     != INVALID_HANDLE) { IndicatorRelease(m_handle_atr);     m_handle_atr     = INVALID_HANDLE; }
    if(m_handle_ma_fast != INVALID_HANDLE) { IndicatorRelease(m_handle_ma_fast); m_handle_ma_fast = INVALID_HANDLE; }
    if(m_handle_ma_slow != INVALID_HANDLE) { IndicatorRelease(m_handle_ma_slow); m_handle_ma_slow = INVALID_HANDLE; }
    if(m_handle_rsi     != INVALID_HANDLE) { IndicatorRelease(m_handle_rsi);     m_handle_rsi     = INVALID_HANDLE; }
    if(m_handle_macd    != INVALID_HANDLE) { IndicatorRelease(m_handle_macd);    m_handle_macd    = INVALID_HANDLE; }
    if(m_handle_stoch   != INVALID_HANDLE) { IndicatorRelease(m_handle_stoch);   m_handle_stoch   = INVALID_HANDLE; }
    if(m_handle_cci     != INVALID_HANDLE) { IndicatorRelease(m_handle_cci);     m_handle_cci     = INVALID_HANDLE; }
    if(m_handle_adx     != INVALID_HANDLE) { IndicatorRelease(m_handle_adx);     m_handle_adx     = INVALID_HANDLE; }
    if(m_handle_bands   != INVALID_HANDLE) { IndicatorRelease(m_handle_bands);   m_handle_bands   = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| ValidateTick - reject obviously broken ticks                     |
//+------------------------------------------------------------------+
bool MarketEngine::ValidateTick(const RawTick &tick)
{
    if(tick.bid <= 0.0 || tick.ask <= 0.0) return false;
    if(tick.ask < tick.bid)                return false;
    if(tick.timestamp <= 0)                return false;
    return true;
}

//+------------------------------------------------------------------+
//| UpdateBarBuffer - real OHLC bar builder                          |
//+------------------------------------------------------------------+
void MarketEngine::UpdateBarBuffer(const RawTick &tick)
{
    int    period_sec = PeriodSeconds(PERIOD_CURRENT);
    datetime bar_time = (datetime)((long)tick.timestamp / period_sec * period_sec);
    double  mid       = (tick.bid + tick.ask) / 2.0;

    if(!m_has_current_bar)
    {
        m_current_bar.time         = bar_time;
        m_current_bar.open         = mid;
        m_current_bar.high         = mid;
        m_current_bar.low          = mid;
        m_current_bar.close        = mid;
        m_current_bar.tick_volume  = tick.volume;
        m_current_bar.real_volume  = 0;
        m_has_current_bar = true;
        return;
    }

    if(bar_time > m_current_bar.time)
    {
        //--- new bar: push previous (now closed) bar to ring
        if(m_bar_count >= ATLAS_BAR_BUFFER_SIZE)
        {
            for(int i = 1; i < ATLAS_BAR_BUFFER_SIZE; i++)
                m_bars[i-1] = m_bars[i];
            m_bar_count = ATLAS_BAR_BUFFER_SIZE - 1;
        }
        m_bars[m_bar_count] = m_current_bar;
        m_bar_count++;

        //--- start new bar
        m_current_bar.time         = bar_time;
        m_current_bar.open         = mid;
        m_current_bar.high         = mid;
        m_current_bar.low          = mid;
        m_current_bar.close        = mid;
        m_current_bar.tick_volume  = tick.volume;
        m_current_bar.real_volume  = 0;

        //--- closed bar => safe to refresh indicator cache & recompute trend
        RefreshIndicatorCache();
        RecomputeTrend();
    }
    else
    {
        //--- update forming bar
        if(tick.ask > m_current_bar.high) m_current_bar.high = tick.ask;
        if(tick.bid < m_current_bar.low)  m_current_bar.low  = tick.bid;
        m_current_bar.close       = mid;
        m_current_bar.tick_volume += tick.volume;
    }
}

//+------------------------------------------------------------------+
//| RefreshIndicatorCache - read indicator values at shift=1         |
//| (last CLOSED bar -> guaranteed non-repainting)                   |
//+------------------------------------------------------------------+
void MarketEngine::RefreshIndicatorCache(void)
{
    double buf[];
    ArraySetAsSeries(buf, true);

    if(m_handle_atr != INVALID_HANDLE && CopyBuffer(m_handle_atr, 0, 1, 1, buf) > 0)
        m_atr = buf[0];

    if(m_handle_ma_fast != INVALID_HANDLE && CopyBuffer(m_handle_ma_fast, 0, 1, 1, buf) > 0)
        m_ema_fast = buf[0];

    if(m_handle_ma_slow != INVALID_HANDLE && CopyBuffer(m_handle_ma_slow, 0, 1, 1, buf) > 0)
        m_ema_slow = buf[0];

    if(m_handle_rsi != INVALID_HANDLE && CopyBuffer(m_handle_rsi, 0, 1, 1, buf) > 0)
        m_rsi = buf[0];

    if(m_handle_macd != INVALID_HANDLE)
    {
        if(CopyBuffer(m_handle_macd, 0, 1, 1, buf) > 0) m_macd_main   = buf[0];
        if(CopyBuffer(m_handle_macd, 1, 1, 1, buf) > 0) m_macd_signal = buf[0];
    }

    if(m_handle_stoch != INVALID_HANDLE)
    {
        if(CopyBuffer(m_handle_stoch, 0, 1, 1, buf) > 0) m_stoch_k = buf[0];
        if(CopyBuffer(m_handle_stoch, 1, 1, 1, buf) > 0) m_stoch_d = buf[0];
    }

    if(m_handle_cci != INVALID_HANDLE && CopyBuffer(m_handle_cci, 0, 1, 1, buf) > 0)
        m_cci = buf[0];

    if(m_handle_adx != INVALID_HANDLE)
    {
        if(CopyBuffer(m_handle_adx, 0, 1, 1, buf) > 0) m_adx      = buf[0];
        if(CopyBuffer(m_handle_adx, 1, 1, 1, buf) > 0) m_di_plus  = buf[0];
        if(CopyBuffer(m_handle_adx, 2, 1, 1, buf) > 0) m_di_minus = buf[0];
    }

    if(m_handle_bands != INVALID_HANDLE)
    {
        if(CopyBuffer(m_handle_bands, 1, 1, 1, buf) > 0) m_bb_upper  = buf[0];
        if(CopyBuffer(m_handle_bands, 2, 1, 1, buf) > 0) m_bb_lower  = buf[0];
        if(CopyBuffer(m_handle_bands, 0, 1, 1, buf) > 0) m_bb_middle = buf[0];
    }
}

//+------------------------------------------------------------------+
//| RecomputeTrend - non-repainting EMA(20/50) crossover logic       |
//| Uses only CLOSED bars (shift>=1). Threshold = 0.25 * ATR.        |
//+------------------------------------------------------------------+
void MarketEngine::RecomputeTrend(void)
{
    if(m_handle_ma_fast == INVALID_HANDLE || m_handle_ma_slow == INVALID_HANDLE)
    {
        m_trend_direction = 0; m_trend_strength = 0; return;
    }
    if(m_bar_count < 2) return;

    double fast[], slow[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);
    if(CopyBuffer(m_handle_ma_fast, 0, 1, 2, fast) <= 0) return;
    if(CopyBuffer(m_handle_ma_slow, 0, 1, 2, slow) <= 0) return;

    double separation = m_ema_fast - m_ema_slow;
    double threshold  = (m_atr > 0.0) ? m_atr * 0.25 : 0.0;

    int new_dir = 0;
    if(separation >  threshold) new_dir =  1;
    else if(separation < -threshold) new_dir = -1;

    if(new_dir == m_trend_direction && new_dir != 0)
        m_trend_duration++;
    else if(new_dir != m_trend_direction)
        m_trend_duration = (new_dir != 0) ? 1 : 0;

    m_trend_direction = new_dir;

    //--- strength: separation normalized by ATR, scaled 0..100
    if(m_atr > 0.0)
    {
        double ratio = MathAbs(separation) / m_atr;
        m_trend_strength = (int)MathMin(100.0, ratio * 50.0);
    }
    else
    {
        m_trend_strength = 0;
    }

    m_last_trend_recompute = TimeCurrent();
}

//+------------------------------------------------------------------+
//| TagSession - classify trading session from server hour           |
//+------------------------------------------------------------------+
int MarketEngine::TagSession(void) const
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h = dt.hour;
    if(h >= 0  && h < 7)  return ATLAS_SESSION_ASIAN;
    if(h >= 7  && h < 13) return ATLAS_SESSION_LONDON;
    if(h >= 13 && h < 17) return ATLAS_SESSION_OVERLAP;
    if(h >= 17 && h < 21) return ATLAS_SESSION_NY;
    return ATLAS_SESSION_OFF;
}

double MarketEngine::Clamp(double v, double lo, double hi) const
{
    if(v < lo) return lo;
    if(v > hi) return hi;
    return v;
}

//+------------------------------------------------------------------+
//| PopulateFeatures - build the 32-element normalized feature       |
//| vector. Every value is bounded to [0,1] or [-1,1].               |
//+------------------------------------------------------------------+
void MarketEngine::PopulateFeatures(double &features[], int &count, const RawTick &tick)
{
    count = 0;
    for(int i = 0; i < ATLAS_FEATURE_SIZE; i++) features[i] = 0.0;

    double price = (tick.bid + tick.ask) / 2.0;
    double atr   = (m_atr > 0.0) ? m_atr : price * 0.001;
    double norm  = atr;

    //--- 0: price vs EMA20 (z-score-like, clamped)
    features[0] = Clamp((price - m_ema_fast) / norm, -1.0, 1.0);
    //--- 1: price vs EMA50
    features[1] = Clamp((price - m_ema_slow) / norm, -1.0, 1.0);

    //--- 2,3: EMA slopes (use two closed bars)
    double fast2[], slow2[];
    ArraySetAsSeries(fast2, true);
    ArraySetAsSeries(slow2, true);
    if(CopyBuffer(m_handle_ma_fast, 0, 1, 3, fast2) > 0)
        features[2] = Clamp((fast2[0] - fast2[2]) / norm, -1.0, 1.0);
    if(CopyBuffer(m_handle_ma_slow, 0, 1, 3, slow2) > 0)
        features[3] = Clamp((slow2[0] - slow2[2]) / norm, -1.0, 1.0);

    //--- 4: ATR / price
    features[4] = (price > 0.0) ? Clamp(m_atr / price, 0.0, 1.0) : 0.0;

    //--- 5: ATR ratio (current vs 20-bar avg)
    double atr_arr[];
    ArraySetAsSeries(atr_arr, true);
    if(CopyBuffer(m_handle_atr, 0, 1, 20, atr_arr) > 0)
    {
        double sum = 0.0; int n = MathMin(20, ArraySize(atr_arr));
        for(int i = 0; i < n; i++) sum += atr_arr[i];
        double avg = sum / n;
        features[5] = (avg > 0.0) ? Clamp(m_atr / avg / 5.0, 0.0, 1.0) : 0.0;
    }

    //--- 6: RSI / 100
    features[6] = Clamp(m_rsi / 100.0, 0.0, 1.0);

    //--- 7: RSI direction
    double rsi_arr[];
    ArraySetAsSeries(rsi_arr, true);
    if(CopyBuffer(m_handle_rsi, 0, 1, 3, rsi_arr) > 0)
        features[7] = Clamp((rsi_arr[0] - rsi_arr[2]) / 100.0, -1.0, 1.0);

    //--- 8: MACD histogram normalized by ATR
    double hist = m_macd_main - m_macd_signal;
    features[8] = Clamp(hist / norm, -1.0, 1.0);

    //--- 9: MACD signal cross direction (closed bars)
    double macd_m[], macd_s[];
    ArraySetAsSeries(macd_m, true);
    ArraySetAsSeries(macd_s, true);
    if(CopyBuffer(m_handle_macd, 0, 1, 2, macd_m) > 0 &&
       CopyBuffer(m_handle_macd, 1, 1, 2, macd_s) > 0)
    {
        double d_now  = macd_m[0] - macd_s[0];
        double d_prev = macd_m[1] - macd_s[1];
        if(d_now > 0 && d_prev <= 0)      features[9] =  1.0;
        else if(d_now < 0 && d_prev >= 0) features[9] = -1.0;
        else                              features[9] =  0.0;
    }

    //--- 10: Bollinger %B
    double bb_range = m_bb_upper - m_bb_lower;
    features[10] = (bb_range > 0.0) ? Clamp((price - m_bb_lower) / bb_range, 0.0, 1.0) : 0.5;

    //--- 11: Bollinger width normalized
    features[11] = (m_bb_middle > 0.0) ? Clamp(bb_range / m_bb_middle * 10.0, 0.0, 1.0) : 0.0;

    //--- 12,13: Stochastic K, D
    features[12] = Clamp(m_stoch_k / 100.0, 0.0, 1.0);
    features[13] = Clamp(m_stoch_d / 100.0, 0.0, 1.0);

    //--- 14: Momentum (close - close[10]) normalized
    if(m_bar_count >= 11)
    {
        double mom = m_bars[m_bar_count-1].close - m_bars[m_bar_count-11].close;
        features[14] = Clamp(mom / (norm * 3.0), -1.0, 1.0);
    }

    //--- 15: Rate of change
    if(m_bar_count >= 11)
    {
        double past = m_bars[m_bar_count-11].close;
        if(past > 0.0)
        {
            double roc = (m_bars[m_bar_count-1].close - past) / past;
            features[15] = Clamp(roc * 100.0, -1.0, 1.0);
        }
    }

    //--- 16: CCI normalized
    features[16] = Clamp(m_cci / 200.0, -1.0, 1.0);

    //--- 17: ADX / 100
    features[17] = Clamp(m_adx / 100.0, 0.0, 1.0);

    //--- 18,19: DI+ / (DI+ + DI-) and DI- / (DI+ + DI-)
    double di_sum = m_di_plus + m_di_minus;
    features[18] = (di_sum > 0.0) ? Clamp(m_di_plus  / di_sum, 0.0, 1.0) : 0.5;
    features[19] = (di_sum > 0.0) ? Clamp(m_di_minus / di_sum, 0.0, 1.0) : 0.5;

    //--- 20,21,22: Trend direction, strength, duration
    features[20] = (double)m_trend_direction;
    features[21] = Clamp((double)m_trend_strength / 100.0, 0.0, 1.0);
    features[22] = Clamp((double)m_trend_duration / 50.0, 0.0, 1.0);

    //--- 23: Volume change rate
    if(m_bar_count >= 2)
    {
        long v_prev = m_bars[m_bar_count-2].tick_volume;
        long v_curr = m_bars[m_bar_count-1].tick_volume;
        if(v_prev > 0)
            features[23] = Clamp((double)(v_curr - v_prev) / (double)v_prev, -1.0, 1.0);
    }

    //--- 24: Spread normalized
    double point = SymbolInfoDouble(m_config.symbol, SYMBOL_POINT);
    if(point > 0.0)
        features[24] = Clamp((tick.ask - tick.bid) / point / 100.0, 0.0, 1.0);

    //--- 25: Tick volume normalized
    features[25] = Clamp((double)tick.volume / 1000.0, 0.0, 1.0);

    //--- 26..29: Bar geometry (last closed bar)
    if(m_bar_count >= 1)
    {
        BarData b = m_bars[m_bar_count-1];
        double range = b.high - b.low;
        if(range > 0.0)
        {
            features[26] = Clamp(MathAbs(b.close - b.open) / range, 0.0, 1.0);            // body
            features[27] = Clamp((b.high - MathMax(b.close, b.open)) / range, 0.0, 1.0);  // upper shadow
            features[28] = Clamp((MathMin(b.close, b.open) - b.low) / range, 0.0, 1.0);   // lower shadow
        }
        features[29] = (atr > 0.0) ? Clamp(range / atr / 2.0, 0.0, 1.0) : 0.0;
    }

    //--- 30: Session state
    features[30] = (double)TagSession() / 4.0;

    //--- 31: Hour of day
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    features[31] = (double)dt.hour / 24.0;

    count = ATLAS_FEATURE_SIZE;
}

//+------------------------------------------------------------------+
//| DetectAnomalies - spread / stale-tick checks                     |
//+------------------------------------------------------------------+
bool MarketEngine::DetectAnomalies(const RawTick &tick) const
{
    double point = SymbolInfoDouble(m_config.symbol, SYMBOL_POINT);
    if(point > 0.0)
    {
        double spread_pts = (tick.ask - tick.bid) / point;
        if(spread_pts > m_config.max_spread_points) return true;
    }
    if((TimeCurrent() - tick.timestamp) > 30) return true;  // stale tick
    return false;
}

//+------------------------------------------------------------------+
//| BuildMarketState - assemble final immutable MarketState          |
//+------------------------------------------------------------------+
MarketState MarketEngine::BuildMarketState(const RawTick &tick, long snapshot_id)
{
    MarketState s;
    s.snapshot_id   = snapshot_id;
    s.timestamp     = tick.timestamp;
    s.symbol        = m_config.symbol;
    s.bid           = tick.bid;
    s.ask           = tick.ask;
    s.last          = tick.last;
    s.spread        = tick.ask - tick.bid;
    s.point         = SymbolInfoDouble(m_config.symbol, SYMBOL_POINT);
    s.digits        = (int)SymbolInfoInteger(m_config.symbol, SYMBOL_DIGITS);
    s.tick_volume   = tick.volume;
    s.bar_volume    = m_has_current_bar ? m_current_bar.tick_volume : 0;
    s.real_volume   = m_has_current_bar ? m_current_bar.real_volume : 0;
    s.atr_14        = m_atr;

    double price    = (tick.bid + tick.ask) / 2.0;
    s.volatility_index = (price > 0.0) ? (m_atr / price) * 10000.0 : 0.0;

    //--- fast market: ATR jump vs historical average
    s.is_fast_market = false;
    double atr_arr[];
    ArraySetAsSeries(atr_arr, true);
    if(CopyBuffer(m_handle_atr, 0, 1, 20, atr_arr) > 0)
    {
        double sum = 0.0; int n = MathMin(20, ArraySize(atr_arr));
        for(int i = 0; i < n; i++) sum += atr_arr[i];
        double avg = sum / n;
        if(avg > 0.0 && m_atr > avg * m_config.fast_market_atr_mult)
            s.is_fast_market = true;
    }

    s.trend_direction     = m_trend_direction;
    s.trend_strength      = m_trend_strength;
    s.trend_duration_bars = m_trend_duration;

    if(m_has_current_bar)
    {
        s.open    = m_current_bar.open;
        s.high    = m_current_bar.high;
        s.low     = m_current_bar.low;
        s.close   = m_current_bar.close;
        s.bar_time= m_current_bar.time;
    }
    else
    {
        s.open = s.high = s.low = s.close = price;
        s.bar_time = 0;
    }

    s.session_state = TagSession();

    PopulateFeatures(s.features, s.feature_count, tick);

    s.is_valid       = !DetectAnomalies(tick);
    s.invalid_reason = s.is_valid ? "" : "anomaly_detected";
    return s;
}

//+------------------------------------------------------------------+
//| ProcessTick - entry point called by CoreEngine each tick         |
//+------------------------------------------------------------------+
MarketState MarketEngine::ProcessTick(const RawTick &tick, long snapshot_id)
{
    if(!ValidateTick(tick))
    {
        MarketState bad;
        bad.snapshot_id     = snapshot_id;
        bad.timestamp       = tick.timestamp;
        bad.symbol          = m_config.symbol;
        bad.bid             = tick.bid;
        bad.ask             = tick.ask;
        bad.is_valid        = false;
        bad.invalid_reason  = "invalid_tick";
        bad.feature_count   = 0;
        bad.atr_14          = m_atr;
        bad.trend_direction = m_trend_direction;
        bad.trend_strength  = m_trend_strength;
        return bad;
    }
    UpdateBarBuffer(tick);
    return BuildMarketState(tick, snapshot_id);
}

#endif // ATLAS_MARKET_ENGINE_MQH
//+------------------------------------------------------------------+
