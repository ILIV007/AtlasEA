//+------------------------------------------------------------------+
//|                                          Contracts/MarketState.mqh|
//|                            AtlasEA v1.0 - Market Data Contracts  |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARKET_STATE_MQH
#define ATLAS_MARKET_STATE_MQH

#include "../Config/Settings.mqh"

//+------------------------------------------------------------------+
//| RawTick - normalized broker tick                                 |
//+------------------------------------------------------------------+
struct RawTick
{
    double   bid;
    double   ask;
    double   last;
    long     volume;
    datetime timestamp;
};

//+------------------------------------------------------------------+
//| MarketState - immutable market snapshot (per snapshot_id)        |
//+------------------------------------------------------------------+
struct MarketState
{
    long     snapshot_id;
    datetime timestamp;
    string   symbol;

    double   bid;
    double   ask;
    double   last;
    double   spread;
    double   point;
    int      digits;

    long     tick_volume;
    long     bar_volume;
    long     real_volume;

    double   atr_14;
    double   volatility_index;
    bool     is_fast_market;

    int      trend_direction;     // -1, 0, 1
    int      trend_strength;      // 0..100
    int      trend_duration_bars;

    double   open;
    double   high;
    double   low;
    double   close;
    datetime bar_time;
    int      session_state;

    double   features[ATLAS_FEATURE_SIZE];
    int      feature_count;

    bool     is_valid;
    string   invalid_reason;
};

#endif // ATLAS_MARKET_STATE_MQH
//+------------------------------------------------------------------+
