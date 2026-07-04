//+------------------------------------------------------------------+
//|           Engines/RiskEngine/ExposureCalculator.mqh              |
//|       AtlasEA v0.1.11.0 - Exposure Calculation                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_EXPOSURE_CALCULATOR_MQH
#define ATLAS_EXPOSURE_CALCULATOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/Events.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"

/**
 * @class ExposureCalculator
 * @brief Calculates current and projected exposure.
 *
 * Exposure = (volume × contract_size) / equity × 100 (as percentage)
 *
 * Calculates:
 *   - Current exposure (from open positions)
 *   - Projected exposure (current + new trade)
 *   - Exposure by symbol (filtered)
 *   - Exposure by direction (net long vs short)
 *   - Portfolio exposure (total)
 *
 * All data comes from IContextStore (position mirror). No broker queries.
 */
class ExposureCalculator
{
private:
    ILogger       *m_logger;
    IContextStore *m_context;
    double         m_contract_size;  ///< From config
    string         m_symbol;         ///< Trading symbol

public:
    /**
     * @brief Constructor.
     */
    ExposureCalculator(void)
    {
        m_logger        = NULL;
        m_context       = NULL;
        m_contract_size = 100000.0;  ///< Default for FX
        m_symbol        = "";
    }

    /**
     * @brief Initialize.
     */
    void Initialize(IContextStore *context, ILogger *logger,
                    const double contract_size, const string symbol)
    {
        m_context       = context;
        m_logger        = logger;
        m_contract_size = (contract_size > 0.0) ? contract_size : 100000.0;
        m_symbol        = symbol;
    }

    /**
     * @brief Calculate current total exposure as percentage of equity.
     * @param equity Current account equity.
     * @return Exposure percentage (0.0 if equity <= 0).
     */
    double CalculateCurrentExposure(const double equity) const
    {
        if(equity <= 0.0 || m_context == NULL) return 0.0;

        double total_volume = SumPositionVolume();
        double exposure_value = total_volume * m_contract_size;
        return (exposure_value / equity) * 100.0;
    }

    /**
     * @brief Calculate projected exposure if a new trade is added.
     * @param equity Current equity.
     * @param new_volume Volume of the proposed new trade.
     * @return Projected exposure percentage.
     */
    double CalculateProjectedExposure(const double equity, const double new_volume) const
    {
        if(equity <= 0.0 || m_context == NULL) return 0.0;

        double total_volume = SumPositionVolume() + new_volume;
        double exposure_value = total_volume * m_contract_size;
        return (exposure_value / equity) * 100.0;
    }

    /**
     * @brief Calculate exposure for a specific symbol.
     * @param equity Current equity.
     * @param symbol Symbol to filter.
     * @return Exposure percentage for that symbol.
     */
    double CalculateExposureBySymbol(const double equity, const string symbol) const
    {
        if(equity <= 0.0 || m_context == NULL) return 0.0;

        double symbol_volume = SumPositionVolumeForSymbol(symbol);
        double exposure_value = symbol_volume * m_contract_size;
        return (exposure_value / equity) * 100.0;
    }

    /**
     * @brief Calculate net directional exposure.
     * Positive = net long, negative = net short.
     * @param equity Current equity.
     * @return Net exposure percentage (signed).
     */
    double CalculateDirectionalExposure(const double equity) const
    {
        if(equity <= 0.0 || m_context == NULL) return 0.0;

        double long_volume  = 0.0;
        double short_volume = 0.0;

        int count = m_context.GetPositionCount();
        for(int i = 0; i < count; i++)
        {
            PositionState pos;
            m_context.GetPosition(i, pos);
            if(!pos.broker_verified) continue;

            if(pos.type == POSITION_TYPE_BUY)
                long_volume += pos.volume;
            else if(pos.type == POSITION_TYPE_SELL)
                short_volume += pos.volume;
        }

        double net_volume = long_volume - short_volume;
        double exposure_value = MathAbs(net_volume) * m_contract_size;
        double sign = (net_volume >= 0.0) ? 1.0 : -1.0;
        return sign * (exposure_value / equity) * 100.0;
    }

    /**
     * @brief Count open positions matching the EA's symbol.
     * @return Position count.
     */
    int CountPositions(void) const
    {
        if(m_context == NULL) return 0;
        return m_context.GetPositionCount();
    }

    /**
     * @brief Update the RiskState with current exposure values.
     * @param state Risk state (mutated).
     * @param equity Current equity.
     */
    void UpdateState(RiskState &state, const double equity) const
    {
        state.current_exposure_pct   = CalculateCurrentExposure(equity);
        state.exposure_by_symbol     = CalculateExposureBySymbol(equity, m_symbol);
        state.exposure_by_direction  = CalculateDirectionalExposure(equity);
        state.current_equity         = equity;
    }

private:
    /// @brief Sum volume of all positions.
    double SumPositionVolume(void) const
    {
        if(m_context == NULL) return 0.0;
        double total = 0.0;
        int count = m_context.GetPositionCount();
        for(int i = 0; i < count; i++)
        {
            PositionState pos;
            m_context.GetPosition(i, pos);
            if(!pos.broker_verified) continue;
            total += pos.volume;
        }
        return total;
    }

    /// @brief Sum volume of positions for a specific symbol.
    double SumPositionVolumeForSymbol(const string symbol) const
    {
        if(m_context == NULL) return 0.0;
        double total = 0.0;
        int count = m_context.GetPositionCount();
        for(int i = 0; i < count; i++)
        {
            PositionState pos;
            m_context.GetPosition(i, pos);
            if(!pos.broker_verified) continue;
            if(pos.symbol != symbol) continue;
            total += pos.volume;
        }
        return total;
    }
};

#endif // ATLAS_EXPOSURE_CALCULATOR_MQH
//+------------------------------------------------------------------+
