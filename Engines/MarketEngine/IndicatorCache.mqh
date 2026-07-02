//+------------------------------------------------------------------+
//|                     Engines/MarketEngine/IndicatorCache.mqh       |
//|          AtlasEA v0.1.1.0 - Indicator Handle & Cache Manager     |
//+------------------------------------------------------------------+
#ifndef ATLAS_INDICATOR_CACHE_MQH
#define ATLAS_INDICATOR_CACHE_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/IBrokerAdapter.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @class IndicatorCache
 * @brief Manages indicator handles and caches values from CLOSED bars.
 *
 * All indicator values are read at shift=1 (the last CLOSED bar) to
 * guarantee NON-REPAINTING behavior. The forming bar is never used.
 *
 * Indicators managed:
 *   - ATR(period)
 *   - EMA fast(period) + EMA slow(period)
 *   - RSI(period)
 *   - MACD(fast, slow, signal)
 *   - Stochastic(k, d, slow)
 *   - CCI(period)
 *   - ADX(period)  (+ DI+, DI-)
 *   - Bollinger Bands(period, deviation)
 *
 * Memory: all cached values are scalar doubles on the stack. No allocation.
 * Performance: all reads are O(1) after cache refresh.
 *
 * The cache must be Refreshed() once per closed bar (when a new bar opens).
 * Calling Refresh() on every tick is wasteful but harmless.
 */
class IndicatorCache
{
private:
    IBrokerAdapter *m_broker;       ///< Broker adapter (for indicator ops)
    ILogger        *m_logger;       ///< Logger
    AtlasConfig     m_config;       ///< Configuration

    //--- Indicator handles
    int m_h_atr;       ///< ATR handle
    int m_h_ma_fast;   ///< EMA fast handle
    int m_h_ma_slow;   ///< EMA slow handle
    int m_h_rsi;       ///< RSI handle
    int m_h_macd;      ///< MACD handle
    int m_h_stoch;     ///< Stochastic handle
    int m_h_cci;       ///< CCI handle
    int m_h_adx;       ///< ADX handle
    int m_h_bands;     ///< Bollinger Bands handle

    //--- Cached values (from shift=1 = last closed bar)
    double m_atr;          ///< ATR(14) value
    double m_atr_prev;     ///< ATR previous bar (for slope)
    double m_ema_fast;     ///< EMA fast value
    double m_ema_fast_prev; ///< EMA fast previous bar
    double m_ema_slow;     ///< EMA slow value
    double m_ema_slow_prev; ///< EMA slow previous bar
    double m_rsi;          ///< RSI value
    double m_rsi_prev;     ///< RSI previous bar
    double m_macd_main;    ///< MACD main line
    double m_macd_signal;  ///< MACD signal line
    double m_macd_main_prev;    ///< MACD main previous bar
    double m_macd_signal_prev;  ///< MACD signal previous bar
    double m_stoch_k;      ///< Stochastic %K
    double m_stoch_d;      ///< Stochastic %D
    double m_cci;          ///< CCI value
    double m_adx;          ///< ADX value
    double m_di_plus;      ///< DI+ value
    double m_di_minus;     ///< DI- value
    double m_bb_upper;     ///< Bollinger upper band
    double m_bb_middle;    ///< Bollinger middle band
    double m_bb_lower;     ///< Bollinger lower band

    bool m_initialized;    ///< true after handles created
    bool m_cache_valid;    ///< true after first successful refresh

    /// @brief Safe copy from a buffer to a scalar.
    bool SafeCopy(const int handle, const int buf_num, const int shift,
                  const int count, double &out);

public:
    /**
     * @brief Constructor.
     */
    IndicatorCache(void);

    /**
     * @brief Initialize — create all indicator handles.
     * @param broker Broker adapter.
     * @param logger Logger.
     * @param config Configuration (periods, deviations).
     * @return true if all handles created successfully.
     */
    bool Initialize(IBrokerAdapter *broker, ILogger *logger, const AtlasConfig &config);

    /**
     * @brief Shutdown — release all indicator handles.
     */
    void Shutdown(void);

    /**
     * @brief Refresh all cached values from the last CLOSED bar (shift=1).
     * Must be called when a new bar opens (or every tick — harmless).
     */
    void Refresh(void);

    //--- Accessors (all return values from the last closed bar) ---
    double ATR(void)           const { return m_atr; }
    double ATRPrev(void)       const { return m_atr_prev; }
    double EMAFast(void)       const { return m_ema_fast; }
    double EMAFastPrev(void)   const { return m_ema_fast_prev; }
    double EMASlow(void)       const { return m_ema_slow; }
    double EMASlowPrev(void)   const { return m_ema_slow_prev; }
    double RSI(void)           const { return m_rsi; }
    double RSIPrev(void)       const { return m_rsi_prev; }
    double MACDMain(void)      const { return m_macd_main; }
    double MACDSignal(void)    const { return m_macd_signal; }
    double MACDMainPrev(void)  const { return m_macd_main_prev; }
    double MACDSignalPrev(void) const { return m_macd_signal_prev; }
    double StochK(void)        const { return m_stoch_k; }
    double StochD(void)        const { return m_stoch_d; }
    double CCI(void)           const { return m_cci; }
    double ADX(void)           const { return m_adx; }
    double DIPlus(void)        const { return m_di_plus; }
    double DIMinus(void)       const { return m_di_minus; }
    double BBUpper(void)       const { return m_bb_upper; }
    double BBMiddle(void)      const { return m_bb_middle; }
    double BBLower(void)       const { return m_bb_lower; }

    /// @brief true if handles are created and cache has been refreshed.
    bool IsValid(void) const { return m_initialized && m_cache_valid; }

    /// @brief true if handles are created.
    bool IsInitialized(void) const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| IndicatorCache implementation                                     |
//+------------------------------------------------------------------+

IndicatorCache::IndicatorCache(void)
{
    m_broker = NULL;
    m_logger = NULL;
    ZeroMemory(m_config);

    m_h_atr     = INVALID_HANDLE;
    m_h_ma_fast = INVALID_HANDLE;
    m_h_ma_slow = INVALID_HANDLE;
    m_h_rsi     = INVALID_HANDLE;
    m_h_macd    = INVALID_HANDLE;
    m_h_stoch   = INVALID_HANDLE;
    m_h_cci     = INVALID_HANDLE;
    m_h_adx     = INVALID_HANDLE;
    m_h_bands   = INVALID_HANDLE;

    m_atr = m_atr_prev = 0.0;
    m_ema_fast = m_ema_fast_prev = 0.0;
    m_ema_slow = m_ema_slow_prev = 0.0;
    m_rsi = m_rsi_prev = 0.0;
    m_macd_main = m_macd_signal = 0.0;
    m_macd_main_prev = m_macd_signal_prev = 0.0;
    m_stoch_k = m_stoch_d = 0.0;
    m_cci = 0.0;
    m_adx = m_di_plus = m_di_minus = 0.0;
    m_bb_upper = m_bb_middle = m_bb_lower = 0.0;

    m_initialized = false;
    m_cache_valid = false;
}

//+------------------------------------------------------------------+
bool IndicatorCache::SafeCopy(const int handle, const int buf_num, const int shift,
                              const int count, double &out)
{
    if(m_broker == NULL || handle == INVALID_HANDLE) return false;
    double buf[];
    ArraySetAsSeries(buf, true);
    int copied = m_broker.CopyBuffer(handle, buf_num, shift, count, buf);
    if(copied <= 0) return false;
    out = buf[0];
    return true;
}

//+------------------------------------------------------------------+
bool IndicatorCache::Initialize(IBrokerAdapter *broker, ILogger *logger, const AtlasConfig &config)
{
    m_broker = broker;
    m_logger = logger;
    m_config = config;

    if(m_broker == NULL)
    {
        if(m_logger != NULL)
            m_logger.Error("IndicatorCache", "Initialize: broker adapter is NULL");
        return false;
    }

    //--- Create indicator handles via broker adapter
    m_h_atr     = m_broker.CreateATR(m_config.atr_period);
    m_h_ma_fast = m_broker.CreateMA(m_config.ma_fast_period, MODE_EMA, PRICE_CLOSE);
    m_h_ma_slow = m_broker.CreateMA(m_config.ma_slow_period, MODE_EMA, PRICE_CLOSE);
    m_h_rsi     = m_broker.CreateRSI(m_config.rsi_period, PRICE_CLOSE);
    m_h_macd    = m_broker.CreateMACD(m_config.macd_fast, m_config.macd_slow, m_config.macd_signal, PRICE_CLOSE);
    m_h_stoch   = m_broker.CreateStochastic(m_config.stoch_k, m_config.stoch_d, m_config.stoch_slow, MODE_SMA, STO_LOWHIGH);
    m_h_cci     = m_broker.CreateCCI(m_config.cci_period, PRICE_TYPICAL);
    m_h_adx     = m_broker.CreateADX(m_config.adx_period);
    m_h_bands   = m_broker.CreateBands(m_config.bb_period, m_config.bb_deviation, PRICE_CLOSE);

    //--- Validate all handles
    if(m_h_atr == INVALID_HANDLE || m_h_ma_fast == INVALID_HANDLE ||
       m_h_ma_slow == INVALID_HANDLE || m_h_rsi == INVALID_HANDLE ||
       m_h_macd == INVALID_HANDLE || m_h_stoch == INVALID_HANDLE ||
       m_h_cci == INVALID_HANDLE || m_h_adx == INVALID_HANDLE ||
       m_h_bands == INVALID_HANDLE)
    {
        if(m_logger != NULL)
            m_logger.Error("IndicatorCache", "Failed to create one or more indicator handles");
        Shutdown();
        return false;
    }

    m_initialized = true;

    //--- Initial refresh
    Refresh();

    if(m_logger != NULL)
        m_logger.Info("IndicatorCache", "Initialized with 9 indicator handles. ATR=" + DoubleToString(m_atr, _Digits));

    return true;
}

//+------------------------------------------------------------------+
void IndicatorCache::Shutdown(void)
{
    if(m_broker != NULL)
    {
        if(m_h_atr     != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_atr);     m_h_atr     = INVALID_HANDLE; }
        if(m_h_ma_fast != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_ma_fast); m_h_ma_fast = INVALID_HANDLE; }
        if(m_h_ma_slow != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_ma_slow); m_h_ma_slow = INVALID_HANDLE; }
        if(m_h_rsi     != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_rsi);     m_h_rsi     = INVALID_HANDLE; }
        if(m_h_macd    != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_macd);    m_h_macd    = INVALID_HANDLE; }
        if(m_h_stoch   != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_stoch);   m_h_stoch   = INVALID_HANDLE; }
        if(m_h_cci     != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_cci);     m_h_cci     = INVALID_HANDLE; }
        if(m_h_adx     != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_adx);     m_h_adx     = INVALID_HANDLE; }
        if(m_h_bands   != INVALID_HANDLE) { m_broker.ReleaseIndicator(m_h_bands);   m_h_bands   = INVALID_HANDLE; }
    }
    m_initialized = false;
    m_cache_valid = false;
}

//+------------------------------------------------------------------+
void IndicatorCache::Refresh(void)
{
    if(!m_initialized || m_broker == NULL) return;

    //--- ATR: read shift=1 (last closed) and shift=2 (previous closed)
    SafeCopy(m_h_atr, 0, 1, 1, m_atr);
    SafeCopy(m_h_atr, 0, 2, 1, m_atr_prev);

    //--- EMA fast: shift=1 and shift=2
    SafeCopy(m_h_ma_fast, 0, 1, 1, m_ema_fast);
    SafeCopy(m_h_ma_fast, 0, 2, 1, m_ema_fast_prev);

    //--- EMA slow: shift=1 and shift=2
    SafeCopy(m_h_ma_slow, 0, 1, 1, m_ema_slow);
    SafeCopy(m_h_ma_slow, 0, 2, 1, m_ema_slow_prev);

    //--- RSI: shift=1 and shift=2
    SafeCopy(m_h_rsi, 0, 1, 1, m_rsi);
    SafeCopy(m_h_rsi, 0, 2, 1, m_rsi_prev);

    //--- MACD: main (buf 0) and signal (buf 1) at shift=1 and shift=2
    SafeCopy(m_h_macd, 0, 1, 1, m_macd_main);
    SafeCopy(m_h_macd, 1, 1, 1, m_macd_signal);
    SafeCopy(m_h_macd, 0, 2, 1, m_macd_main_prev);
    SafeCopy(m_h_macd, 1, 2, 1, m_macd_signal_prev);

    //--- Stochastic: %K (buf 0) and %D (buf 1) at shift=1
    SafeCopy(m_h_stoch, 0, 1, 1, m_stoch_k);
    SafeCopy(m_h_stoch, 1, 1, 1, m_stoch_d);

    //--- CCI at shift=1
    SafeCopy(m_h_cci, 0, 1, 1, m_cci);

    //--- ADX: main (buf 0), DI+ (buf 1), DI- (buf 2) at shift=1
    SafeCopy(m_h_adx, 0, 1, 1, m_adx);
    SafeCopy(m_h_adx, 1, 1, 1, m_di_plus);
    SafeCopy(m_h_adx, 2, 1, 1, m_di_minus);

    //--- Bollinger: middle (buf 0), upper (buf 1), lower (buf 2) at shift=1
    SafeCopy(m_h_bands, 0, 1, 1, m_bb_middle);
    SafeCopy(m_h_bands, 1, 1, 1, m_bb_upper);
    SafeCopy(m_h_bands, 2, 1, 1, m_bb_lower);

    m_cache_valid = true;
}

#endif // ATLAS_INDICATOR_CACHE_MQH
//+------------------------------------------------------------------+
