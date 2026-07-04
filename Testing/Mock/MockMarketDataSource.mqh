//+------------------------------------------------------------------+
//|              Testing/Mock/MockMarketDataSource.mqh              |
//|       AtlasEA v0.1.15.0 - Mock Market Data Source               |
//+------------------------------------------------------------------+
#ifndef ATLAS_MOCK_MARKET_DATA_SOURCE_MQH
#define ATLAS_MOCK_MARKET_DATA_SOURCE_MQH

#include "../TestingConfig.mqh"
#include "../../Contracts/MarketState.mqh"
#include "MockBrokerAdapter.mqh"

/**
 * @class MockMarketDataSource
 * @brief Generates synthetic market ticks for testing.
 *
 * Modes:
 *   - FAST: No delay, high frequency
 *   - SLOW: Delay between ticks
 *   - RANDOM: Random walk with configurable volatility
 *   - TREND: Directional bias
 *   - RANGE: Mean-reverting within a range
 *   - GAP: Sudden price jump
 *   - FLASH: Flash crash + recovery
 */
class MockMarketDataSource
{
private:
    TestingConfig      m_config;
    MockBrokerAdapter *m_broker;
    double             m_current_price;
    double             m_volatility;
    int                m_mode;
    ulong              m_tick_count;
    ulong              m_random_seed;
    datetime           m_start_time;

    /// @brief Deterministic LCG random.
    double Random(void)
    {
        m_random_seed = m_random_seed * 6364136223846793005 + 1442695040888963407;
        return (double)(m_random_seed % 1000000) / 1000000.0;
    }

    /// @brief Generate the next price based on the current mode.
    double GenerateNextPrice(void)
    {
        double change = 0.0;

        switch(m_mode)
        {
            case ATLAS_TEST_MODE_FAST:
            case ATLAS_TEST_MODE_SLOW:
            case ATLAS_TEST_MODE_RANDOM:
            {
                //--- Random walk
                double range = m_current_price * m_volatility * 0.001;
                change = (Random() - 0.5) * 2.0 * range;
                break;
            }

            case ATLAS_TEST_MODE_TREND:
            {
                //--- Trending: bias upward or downward
                double trend = (m_config.trend_strength - 0.5) * 2.0;  ///< -1..+1
                double range = m_current_price * m_volatility * 0.001;
                change = trend * range * 0.5 + (Random() - 0.5) * range;
                break;
            }

            case ATLAS_TEST_MODE_RANGE:
            {
                //--- Mean-reverting: pull toward midpoint
                double mid = (m_config.range_low + m_config.range_high) / 2.0;
                double pull = (mid - m_current_price) * 0.05;
                double range = m_current_price * m_volatility * 0.0005;
                change = pull + (Random() - 0.5) * range;
                break;
            }

            case ATLAS_TEST_MODE_GAP:
            {
                //--- Sudden gap every 100 ticks
                if(m_tick_count > 0 && m_tick_count % 100 == 0)
                {
                    double gap_size = m_current_price * 0.005;  ///< 0.5% gap
                    change = (Random() > 0.5) ? gap_size : -gap_size;
                }
                else
                {
                    change = (Random() - 0.5) * m_current_price * 0.0001;
                }
                break;
            }

            case ATLAS_TEST_MODE_FLASH:
            {
                //--- Flash crash at tick 500, recovery at tick 600
                if(m_tick_count == 500)
                {
                    change = -m_current_price * 0.02;  ///< -2% crash
                }
                else if(m_tick_count == 600)
                {
                    change = m_current_price * 0.018;  ///< +1.8% recovery
                }
                else
                {
                    change = (Random() - 0.5) * m_current_price * 0.0001;
                }
                break;
            }

            default:
                change = (Random() - 0.5) * m_current_price * 0.0001;
                break;
        }

        return m_current_price + change;
    }

public:
    /**
     * @brief Constructor.
     */
    MockMarketDataSource(void)
    {
        m_broker        = NULL;
        m_current_price = 1.0850;
        m_volatility    = 0.3;
        m_mode          = ATLAS_TEST_MODE_RANDOM;
        m_tick_count    = 0;
        m_random_seed   = 12345;
        m_start_time    = 0;
    }

    /**
     * @brief Initialize from config.
     * @param config Test configuration.
     * @param broker Mock broker adapter (receives price updates).
     */
    void Initialize(const TestingConfig &config, MockBrokerAdapter *broker)
    {
        m_config        = config;
        m_broker        = broker;
        m_current_price = config.initial_price;
        m_volatility    = config.volatility;
        m_mode          = config.market_mode;
        m_random_seed   = config.random_seed;
        m_start_time    = TimeCurrent();
        m_tick_count    = 0;
    }

    /**
     * @brief Set the market mode.
     */
    void SetMode(const int mode) { m_mode = mode; }

    /**
     * @brief Generate the next tick and update the mock broker.
     * @return RawTick for the generated tick.
     */
    RawTick GenerateTick(void)
    {
        m_current_price = GenerateNextPrice();

        double spread = m_config.spread_points * m_config.point;
        double bid = m_current_price;
        double ask = m_current_price + spread;

        //--- Update broker prices
        if(m_broker != NULL)
            m_broker.SetPrices(bid, ask);

        RawTick tick;
        tick.bid       = bid;
        tick.ask       = ask;
        tick.last      = m_current_price;
        tick.volume    = (long)(Random() * 1000) + 1;
        tick.timestamp = TimeCurrent();

        m_tick_count++;

        //--- Simulate slow mode
        if(m_mode == ATLAS_TEST_MODE_SLOW && m_config.tick_speed_ms > 0)
            Sleep(m_config.tick_speed_ms);

        return tick;
    }

    /**
     * @brief Get current price.
     */
    double GetPrice(void) const { return m_current_price; }

    /**
     * @brief Get tick count.
     */
    ulong GetTickCount(void) const { return m_tick_count; }

    /**
     * @brief Set volatility (0..1).
     */
    void SetVolatility(const double vol) { m_volatility = vol; }

    /**
     * @brief Force a price jump (for testing gap scenarios).
     */
    void ForceJump(const double pct)
    {
        m_current_price *= (1.0 + pct);
        if(m_broker != NULL)
        {
            double spread = m_config.spread_points * m_config.point;
            m_broker.SetPrices(m_current_price, m_current_price + spread);
        }
    }
};

#endif // ATLAS_MOCK_MARKET_DATA_SOURCE_MQH
//+------------------------------------------------------------------+
