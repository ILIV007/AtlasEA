//+------------------------------------------------------------------+
//|                                       Engines/StrategyEngine.mqh |
//|                AtlasEA v1.0 - Multi-Strategy Voting Engine       |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_ENGINE_MQH
#define ATLAS_STRATEGY_ENGINE_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"

//+------------------------------------------------------------------+
//| StrategyEngine                                                   |
//|   Evaluates N registered strategies against a MarketState and    |
//|   produces StrategyVote[] ready for aggregation.                 |
//+------------------------------------------------------------------+
class StrategyEngine
{
private:
    AtlasConfig m_config;
    int         m_strategy_ids[ATLAS_MAX_STRATEGIES];
    double      m_strategy_weights[ATLAS_MAX_STRATEGIES];
    int         m_strategy_count;

    bool        ValidateMarketState(const MarketState &state) const;
    StrategyVote RunStrategy(int id, const MarketState &state) const;
    bool        RegisterStrategy(int id, double weight);
    double      Clamp01(double v) const { return (v < 0.0) ? 0.0 : ((v > 1.0) ? 1.0 : v); }

public:
                StrategyEngine(void);
    bool        Initialize(const AtlasConfig &config);
    int         EvaluateStrategies(const MarketState &state, StrategyVote &votes[]);
};

//+------------------------------------------------------------------+
StrategyEngine::StrategyEngine(void)
{
    m_strategy_count = 0;
    for(int i = 0; i < ATLAS_MAX_STRATEGIES; i++)
    {
        m_strategy_ids[i]     = 0;
        m_strategy_weights[i] = 0.0;
    }
}

//+------------------------------------------------------------------+
bool StrategyEngine::Initialize(const AtlasConfig &config)
{
    m_config = config;
    m_strategy_count = 0;
    RegisterStrategy(1, 1.0);  // Trend follower
    RegisterStrategy(2, 0.8);  // Mean reversion
    RegisterStrategy(3, 0.9);  // Momentum
    RegisterStrategy(4, 0.7);  // Breakout
    Print("[StrategyEngine] Initialized with ", m_strategy_count, " strategies");
    return true;
}

//+------------------------------------------------------------------+
bool StrategyEngine::RegisterStrategy(int id, double weight)
{
    if(m_strategy_count >= ATLAS_MAX_STRATEGIES) return false;
    m_strategy_ids[m_strategy_count]     = id;
    m_strategy_weights[m_strategy_count] = weight;
    m_strategy_count++;
    return true;
}

//+------------------------------------------------------------------+
bool StrategyEngine::ValidateMarketState(const MarketState &state) const
{
    if(!state.is_valid)                return false;
    if(state.feature_count < ATLAS_FEATURE_SIZE) return false;
    if(state.atr_14 <= 0.0)            return false;
    if(state.kill_switch_triggered)    return false;
    return true;
}

//+------------------------------------------------------------------+
//| RunStrategy - dispatch to one of the four built-in strategies    |
//+------------------------------------------------------------------+
StrategyVote StrategyEngine::RunStrategy(int id, const MarketState &state) const
{
    StrategyVote v;
    v.strategy_id      = id;
    v.strategy_version = "1.0.0";
    v.direction        = ATLAS_ORDER_NONE;
    v.confidence       = 0.0;
    v.suggested_volume = m_config.base_volume;
    v.suggested_entry  = (state.bid + state.ask) / 2.0;
    v.suggested_sl     = 0.0;
    v.suggested_tp     = 0.0;
    v.snapshot_id      = state.snapshot_id;
    v.vote_time        = state.timestamp;

    double atr   = state.atr_14;
    double price = v.suggested_entry;
    double sl_mult = (double)m_config.sl_atr_multiplier;
    double tp_mult = (double)m_config.tp_atr_multiplier;

    //--- Strategy 1: Trend follower (EMA20/50 + ADX filter)
    if(id == 1)
    {
        double trend = state.features[20];
        double str   = state.features[21];
        double adx   = state.features[17];
        if(MathAbs(trend) > 0.5 && adx > 0.20 && str > 0.25)
        {
            v.direction  = (trend > 0) ? ATLAS_ORDER_BUY : ATLAS_ORDER_SELL;
            v.confidence = Clamp01(str * 0.6 + adx * 0.4);
            if(v.direction == ATLAS_ORDER_BUY)
            {
                v.suggested_sl = price - atr * sl_mult;
                v.suggested_tp = price + atr * tp_mult;
            }
            else
            {
                v.suggested_sl = price + atr * sl_mult;
                v.suggested_tp = price - atr * tp_mult;
            }
        }
    }
    //--- Strategy 2: Mean reversion (RSI extremes + Bollinger)
    else if(id == 2)
    {
        double rsi    = state.features[6];
        double bb_pct = state.features[10];
        if(rsi < 0.25 && bb_pct < 0.15)
        {
            v.direction  = ATLAS_ORDER_BUY;
            v.confidence = Clamp01((0.5 - rsi) * 1.6);
            v.suggested_sl = price - atr * sl_mult;
            v.suggested_tp = price + atr * (tp_mult * 0.5);
        }
        else if(rsi > 0.75 && bb_pct > 0.85)
        {
            v.direction  = ATLAS_ORDER_SELL;
            v.confidence = Clamp01((rsi - 0.5) * 1.6);
            v.suggested_sl = price + atr * sl_mult;
            v.suggested_tp = price - atr * (tp_mult * 0.5);
        }
    }
    //--- Strategy 3: Momentum (MACD cross + Stochastic confirmation)
    else if(id == 3)
    {
        double macd_hist  = state.features[8];
        double macd_cross = state.features[9];
        double stoch_k    = state.features[12];
        if(macd_cross > 0 && stoch_k > 0.5 && macd_hist > 0)
        {
            v.direction  = ATLAS_ORDER_BUY;
            v.confidence = Clamp01(MathMin(macd_hist + 0.5, 1.0));
            v.suggested_sl = price - atr * sl_mult;
            v.suggested_tp = price + atr * tp_mult;
        }
        else if(macd_cross < 0 && stoch_k < 0.5 && macd_hist < 0)
        {
            v.direction  = ATLAS_ORDER_SELL;
            v.confidence = Clamp01(MathMin(-macd_hist + 0.5, 1.0));
            v.suggested_sl = price + atr * sl_mult;
            v.suggested_tp = price - atr * tp_mult;
        }
    }
    //--- Strategy 4: Breakout (Bollinger band breakout + ADX)
    else if(id == 4)
    {
        double bb_pct   = state.features[10];
        double bb_width = state.features[11];
        double adx      = state.features[17];
        if(bb_width > 0.3 && adx > 0.25)
        {
            if(bb_pct > 0.95)
            {
                v.direction  = ATLAS_ORDER_BUY;
                v.confidence = Clamp01(bb_width * 0.5 + adx * 0.5);
                v.suggested_sl = price - atr * sl_mult;
                v.suggested_tp = price + atr * tp_mult;
            }
            else if(bb_pct < 0.05)
            {
                v.direction  = ATLAS_ORDER_SELL;
                v.confidence = Clamp01(bb_width * 0.5 + adx * 0.5);
                v.suggested_sl = price + atr * sl_mult;
                v.suggested_tp = price - atr * tp_mult;
            }
        }
    }

    return v;
}

//+------------------------------------------------------------------+
//| EvaluateStrategies - run all strategies, collect non-empty votes |
//+------------------------------------------------------------------+
int StrategyEngine::EvaluateStrategies(const MarketState &state, StrategyVote &votes[])
{
    if(!ValidateMarketState(state)) return 0;
    int count = 0;
    for(int i = 0; i < m_strategy_count; i++)
    {
        if(count >= ATLAS_MAX_VOTES) break;
        if(i >= m_config.max_active_strategies) break;
        StrategyVote v = RunStrategy(m_strategy_ids[i], state);
        if(v.direction != ATLAS_ORDER_NONE && v.confidence > 0.0)
        {
            votes[count] = v;
            count++;
        }
    }
    return count;
}

#endif // ATLAS_STRATEGY_ENGINE_MQH
//+------------------------------------------------------------------+
