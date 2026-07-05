//+------------------------------------------------------------------+
//|                 Testing/Mock/MockBrokerAdapter.mqh              |
//|       AtlasEA v0.1.15.0 - Mock Broker Adapter for Testing       |
//+------------------------------------------------------------------+
#ifndef ATLAS_MOCK_BROKER_ADAPTER_MQH
#define ATLAS_MOCK_BROKER_ADAPTER_MQH

#include "../TestingConfig.mqh"
#include "../../Interfaces/IBrokerAdapter.mqh"
#include "../../Contracts/Events.mqh"
#include "MockAccount.mqh"
#include "MockPositionStore.mqh"

/**
 * @class MockBrokerAdapter
 * @brief Implements IBrokerAdapter for testing without a real MT5 broker.
 *
 * Features:
 *   - Simulate Bid/Ask prices
 *   - Simulate spreads
 *   - Simulate slippage
 *   - Simulate partial fills
 *   - Simulate requotes
 *   - Simulate rejected orders
 *   - Simulate broker latency
 *   - Simulate margin errors
 *   - Simulate market closed
 *   - Simulate stop level violations
 *
 * No MT5 API calls — pure in-memory simulation.
 */
class MockBrokerAdapter : public IBrokerAdapter
{
private:
    TestingConfig     m_config;
    MockAccount       m_account;
    MockPositionStore m_positions;
    double            m_bid;
    double            m_ask;
    double            m_point;
    int               m_digits;
    double            m_contract_size;
    long              m_filling_mode;
    long              m_stops_level;
    double            m_tick_value;
    double            m_tick_size;
    double            m_margin_initial;
    long              m_leverage;
    int               m_period_seconds;
    string            m_symbol;
    long              m_magic;
    bool              m_market_open;
    bool              m_connected;
    bool              m_trading_enabled;

    //--- Indicator handle simulation
    int               m_next_handle;
    int               m_handle_table[32];
    bool              m_handle_valid[32];
    int               m_handle_count;

    //--- Fail simulation
    int               m_fail_mode;
    double            m_fail_rate;
    ulong             m_random_seed;

    /// @brief Simple LCG random number generator (deterministic).
    double Random(void)
    {
        m_random_seed = m_random_seed * 1103515245 + 12345;
        return (double)(m_random_seed % 1000000) / 1000000.0;
    }

    /// @brief Check if we should simulate a failure this call.
    bool ShouldFail(void)
    {
        if(m_fail_mode == ATLAS_BROKER_FAIL_NONE) return false;
        if(m_fail_rate <= 0.0) return false;
        return (Random() < m_fail_rate);
    }

    /// @brief Check if stops are valid relative to entry.
    bool CheckStops(const double entry, const double sl, const double tp, const int direction)
    {
        double min_dist = m_stops_level * m_point;
        if(direction == ATLAS_ORDER_BUY)
        {
            if(entry - sl < min_dist) return false;
            if(tp - entry < min_dist) return false;
        }
        else
        {
            if(sl - entry < min_dist) return false;
            if(entry - tp < min_dist) return false;
        }
        return true;
    }

public:
    /**
     * @brief Constructor.
     */
    MockBrokerAdapter(void)
    {
        m_bid             = 1.0850;
        m_ask             = 1.0851;
        m_point           = 0.00001;
        m_digits          = 5;
        m_contract_size   = 100000.0;
        m_filling_mode    = 1;  ///< FOK
        m_stops_level     = 10;
        m_tick_value      = 1.0;
        m_tick_size       = 0.00001;
        m_margin_initial  = 1000.0;
        m_leverage        = 100;
        m_period_seconds  = 60;
        m_symbol          = "EURUSD";
        m_magic           = 999999;
        m_market_open     = true;
        m_connected       = true;
        m_trading_enabled = true;
        m_next_handle     = 100;
        m_handle_count    = 0;
        m_fail_mode       = ATLAS_BROKER_FAIL_NONE;
        m_fail_rate       = 0.0;
        m_random_seed     = 12345;

        for(int i = 0; i < 32; i++)
        {
            m_handle_table[i] = 0;
            m_handle_valid[i] = false;
        }
    }

    /**
     * @brief Initialize from config.
     */
    void Initialize(const TestingConfig &config)
    {
        m_config        = config;
        m_bid           = config.initial_price;
        m_ask           = config.initial_price + config.spread_points * config.point;
        m_point         = config.point;
        m_digits        = config.digits;
        m_contract_size = config.contract_size;
        m_symbol        = "EURUSD";
        m_magic         = config.magic_number;
        m_fail_mode     = config.broker_fail_mode;
        m_fail_rate     = config.broker_fail_rate;
        m_random_seed   = config.random_seed;

        m_account.Initialize(config);
        m_positions.Initialize(config);
    }

    /**
     * @brief Set current bid/ask (called by MockMarketDataSource).
     */
    void SetPrices(const double bid, const double ask)
    {
        m_bid = bid;
        m_ask = ask;
        //--- Update position PnL
        m_positions.UpdatePnl(m_bid, m_ask);
        //--- Update account floating PnL
        m_account.SetFloatingPnl(m_positions.GetTotalPnl());
    }

    /**
     * @brief Get the mock account (for test assertions).
     */
    MockAccount& GetAccount(void) { return m_account; }

    /**
     * @brief Get the mock position store (for test assertions).
     */
    MockPositionStore& GetPositions(void) { return m_positions; }

    /**
     * @brief Set market open/closed.
     */
    void SetMarketOpen(const bool open) { m_market_open = open; }

    /**
     * @brief Set connected/disconnected.
     */
    void SetConnected(const bool connected) { m_connected = connected; }

    //=== IBrokerAdapter implementation ===

    virtual RawTick CaptureTick(void) override
    {
        RawTick tick;
        tick.bid       = m_bid;
        tick.ask       = m_ask;
        tick.last      = (m_bid + m_ask) / 2.0;
        tick.volume    = (long)(Random() * 1000);
        tick.timestamp = TimeCurrent();
        return tick;
    }

    virtual bool SendOrder(const OrderRequest &req) override
    {
        //--- Check connection
        if(!m_connected) return false;

        //--- Check market open
        if(!m_market_open) return false;

        //--- Check trading enabled
        if(!m_trading_enabled) return false;

        //--- Simulate broker latency
        if(m_config.broker_delay_ms > 0)
            Sleep(m_config.broker_delay_ms);

        //--- Simulate failures
        if(ShouldFail())
        {
            return false;  ///< Order failed
        }

        //--- Validate stops
        if(!CheckStops(req.entry_price, req.stop_loss, req.take_profit, req.direction))
            return false;

        //--- Check margin
        double margin_needed = (req.volume * m_contract_size * req.entry_price) / m_account.GetLeverage();
        if(margin_needed > m_account.GetFreeMargin())
            return false;

        //--- Apply slippage
        double fill_price = req.entry_price;
        if(m_config.slippage_points > 0)
        {
            double slippage = m_config.slippage_points * m_point;
            if(req.direction == ATLAS_ORDER_BUY)
                fill_price += slippage;
            else
                fill_price -= slippage;
        }

        //--- Open position
        ulong ticket = m_positions.OpenPosition(req.symbol, req.order_type,
                                                 req.volume, fill_price,
                                                 req.stop_loss, req.take_profit);
        if(ticket == 0) return false;

        //--- Check partial fill BEFORE reserving margin
        double actual_fill_volume = req.volume;
        if(m_config.partial_fill_rate > 0 && Random() < m_config.partial_fill_rate)
        {
            //--- Simulate partial fill (half volume)
            actual_fill_volume = req.volume * 0.5;
            m_positions.PartialClose(ticket, req.volume * 0.5, fill_price);
        }

        //--- Reserve margin only for the actually filled volume
        m_account.ReserveMargin(actual_fill_volume, fill_price);

        return true;
    }

    virtual int CloseAllPositionsForMagic(const string reason) override
    {
        return m_positions.CloseAll(m_bid, m_ask);
    }

    virtual bool ModifyPositionSLTP(const string position_id, double sl, double tp) override
    {
        //--- Mock: accept all modifications
        return (StringLen(position_id) > 0);
    }

    virtual bool ClosePosition(const string position_id) override
    {
        //--- Mock: accept close, return true (test harness handles state)
        return (StringLen(position_id) > 0);
    }

    virtual bool ClosePartialPosition(const string position_id, double volume) override
    {
        //--- Mock: accept partial close if volume is valid
        return (StringLen(position_id) > 0 && volume > 0.0);
    }

    virtual PositionSnapshotEvent QueryBrokerPositions(void) override
    {
        return m_positions.ToSnapshotEvent();
    }

    virtual int CountPositionsForMagic(void) override
    {
        return m_positions.GetOpenCount();
    }

    //--- Account queries ---
    virtual double AccountEquity(void) override      { return m_account.GetEquity(); }
    virtual double AccountBalance(void) override     { return m_account.GetBalance(); }
    virtual double AccountMargin(void) override      { return m_account.GetMargin(); }
    virtual double AccountMarginLevel(void) override { return m_account.GetMarginLevel(); }

    //--- Symbol queries ---
    virtual double SymbolPoint(void) override          { return m_point; }
    virtual int    SymbolDigits(void) override         { return m_digits; }
    virtual double SymbolBid(void) override            { return m_bid; }
    virtual double SymbolAsk(void) override            { return m_ask; }
    virtual double SymbolVolumeMin(void) override      { return 0.01; }
    virtual double SymbolVolumeMax(void) override      { return 100.0; }
    virtual double SymbolVolumeStep(void) override     { return 0.01; }
    virtual long   SymbolStopsLevel(void) override     { return m_stops_level; }
    virtual double SymbolContractSize(void) override   { return m_contract_size; }
    virtual long   SymbolFillingMode(void) override    { return m_filling_mode; }
    virtual double SymbolTickValue(void) override      { return m_tick_value; }
    virtual double SymbolTickSize(void) override       { return m_tick_size; }
    virtual double SymbolMarginInitial(void) override  { return m_margin_initial; }
    virtual long   AccountLeverage(void) override      { return m_leverage; }

    //--- Indicator management (mock) ---
    virtual int CreateATR(int period) override              { return AllocHandle(); }
    virtual int CreateMA(int period, int ma_method, int applied_price) override { return AllocHandle(); }
    virtual int CreateRSI(int period, int applied_price) override { return AllocHandle(); }
    virtual int CreateMACD(int fast, int slow, int signal, int applied_price) override { return AllocHandle(); }
    virtual int CreateStochastic(int k, int d, int slow, int ma_method, int price_field) override { return AllocHandle(); }
    virtual int CreateCCI(int period, int applied_price) override { return AllocHandle(); }
    virtual int CreateADX(int period) override { return AllocHandle(); }
    virtual int CreateBands(int period, double deviation, int applied_price) override { return AllocHandle(); }

    virtual int CopyBuffer(int handle, int buffer_num, int start, int count, double &buffer[]) override
    {
        if(!IsHandleValid(handle)) return 0;
        ArraySetAsSeries(buffer, true);
        for(int i = 0; i < count; i++)
            buffer[i] = 0.001;  ///< Mock value
        return count;
    }

    virtual int CopyRates(int start, int count, MqlRates &rates[]) override
    {
        ArraySetAsSeries(rates, true);
        for(int i = 0; i < count; i++)
        {
            rates[i].time = TimeCurrent() - i * m_period_seconds;
            rates[i].open = m_bid;
            rates[i].high = m_ask;
            rates[i].low  = m_bid;
            rates[i].close = (m_bid + m_ask) / 2.0;
            rates[i].tick_volume = 1000;
            rates[i].real_volume = 0;
            rates[i].spread = (int)(m_config.spread_points);
        }
        return count;
    }

    virtual void ReleaseIndicator(int handle) override
    {
        for(int i = 0; i < m_handle_count; i++)
        {
            if(m_handle_table[i] == handle)
            {
                m_handle_valid[i] = false;
                return;
            }
        }
    }

    virtual int PeriodSeconds(void) override { return m_period_seconds; }

    //--- Lifecycle ---
    virtual void CaptureTrade(void) override { /* No-op in mock */ }
    virtual bool Initialize(void) override { return true; }
    virtual void Shutdown(void) override { /* No-op */ }

private:
    int AllocHandle(void)
    {
        int handle = m_next_handle++;
        if(m_handle_count < 32)
        {
            m_handle_table[m_handle_count] = handle;
            m_handle_valid[m_handle_count] = true;
            m_handle_count++;
        }
        return handle;
    }

    bool IsHandleValid(int handle)
    {
        for(int i = 0; i < m_handle_count; i++)
        {
            if(m_handle_table[i] == handle && m_handle_valid[i])
                return true;
        }
        return false;
    }
};

#endif // ATLAS_MOCK_BROKER_ADAPTER_MQH
//+------------------------------------------------------------------+
