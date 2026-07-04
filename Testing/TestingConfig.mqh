//+------------------------------------------------------------------+
//|                      Testing/TestingConfig.mqh                   |
//|       AtlasEA v0.1.15.0 - Test Configuration                     |
//+------------------------------------------------------------------+
#ifndef ATLAS_TESTING_CONFIG_MQH
#define ATLAS_TESTING_CONFIG_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Market mode codes for MockMarketDataSource.
 */
#define ATLAS_TEST_MODE_FAST      0   ///< Fast playback (no delay)
#define ATLAS_TEST_MODE_SLOW      1   ///< Slow playback (delay between ticks)
#define ATLAS_TEST_MODE_RANDOM    2   ///< Random volatility
#define ATLAS_TEST_MODE_TREND     3   ///< Trending market
#define ATLAS_TEST_MODE_RANGE     4   ///< Ranging market
#define ATLAS_TEST_MODE_GAP       5   ///< Gap simulation
#define ATLAS_TEST_MODE_FLASH     6   ///< Flash crash

/**
 * @brief Broker failure simulation codes.
 */
#define ATLAS_BROKER_FAIL_NONE        0
#define ATLAS_BROKER_FAIL_REQUOTE     1
#define ATLAS_BROKER_FAIL_OFF_QUOTES  2
#define ATLAS_BROKER_FAIL_TIMEOUT     3
#define ATLAS_BROKER_FAIL_REJECTED    4
#define ATLAS_BROKER_FAIL_MARGIN      5
#define ATLAS_BROKER_FAIL_DISCONNECT  6
#define ATLAS_BROKER_FAIL_MARKET_CLOSED 7
#define ATLAS_BROKER_FAIL_STOP_LEVEL  8

/**
 * @struct TestingConfig
 * @brief Configuration for test scenarios.
 */
struct TestingConfig
{
    //--- Random seed (0 = use system time)
    ulong random_seed;

    //--- Tick generation
    int    tick_speed_ms;        ///< Delay between ticks (0 = fast mode)
    double initial_price;        ///< Starting price
    double spread_points;        ///< Spread in points
    double point;                ///< Symbol point size
    int    digits;               ///< Symbol digits
    double volatility;           ///< Volatility (0..1, affects tick range)
    long   simulation_duration;  ///< Duration in seconds (0 = unlimited)

    //--- Broker simulation
    int    broker_delay_ms;      ///< Artificial broker latency
    int    broker_fail_mode;     ///< ATLAS_BROKER_FAIL_* (0 = none)
    double broker_fail_rate;     ///< 0..1, probability of failure
    double slippage_points;      ///< Slippage in points
    double partial_fill_rate;    ///< 0..1, probability of partial fill

    //--- Account simulation
    double initial_balance;      ///< Starting account balance
    double leverage;             ///< Account leverage (e.g., 100 = 1:100)
    double contract_size;        ///< Lot contract size
    double commission_per_lot;   ///< Commission per lot
    double swap_per_lot;         ///< Swap per lot per day

    //--- Market mode
    int    market_mode;          ///< ATLAS_TEST_MODE_*
    double trend_strength;       ///< 0..1 (for trend mode)
    double range_low;            ///< Range lower bound (for range mode)
    double range_high;           ///< Range upper bound (for range mode)

    //--- Stress test parameters
    long   stress_tick_count;    ///< Number of ticks for stress tests
    long   stress_event_count;   ///< Number of events for stress tests
    int    stress_recovery_cycles; ///< Recovery cycles for stress tests
    int    stress_snapshot_count;  ///< Snapshots for stress tests

    //--- Magic number for test EA
    long   magic_number;

    /**
     * @brief Default constructor — sensible test defaults.
     */
    TestingConfig(void)
    {
        random_seed             = 12345;
        tick_speed_ms           = 0;
        initial_price           = 1.0850;
        spread_points           = 10.0;
        point                   = 0.00001;
        digits                  = 5;
        volatility              = 0.3;
        simulation_duration     = 3600;

        broker_delay_ms         = 0;
        broker_fail_mode        = ATLAS_BROKER_FAIL_NONE;
        broker_fail_rate        = 0.0;
        slippage_points         = 0.0;
        partial_fill_rate       = 0.0;

        initial_balance         = 10000.0;
        leverage                = 100.0;
        contract_size           = 100000.0;
        commission_per_lot      = 7.0;
        swap_per_lot            = 0.0;

        market_mode             = ATLAS_TEST_MODE_RANDOM;
        trend_strength          = 0.5;
        range_low               = 1.0800;
        range_high              = 1.0900;

        stress_tick_count       = 1000000;   ///< 1M ticks
        stress_event_count      = 100000;    ///< 100k events
        stress_recovery_cycles  = 1000;      ///< 1000 recovery cycles
        stress_snapshot_count   = 1000;      ///< 1000 snapshots

        magic_number            = 999999;    ///< Test magic
    }
};

#endif // ATLAS_TESTING_CONFIG_MQH
//+------------------------------------------------------------------+
