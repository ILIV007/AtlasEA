//+------------------------------------------------------------------+
//|             Engines/RiskEngine/PositionSizer.mqh                 |
//|       AtlasEA v0.1.11.0 - Position Sizing                        |
//+------------------------------------------------------------------+
#ifndef ATLAS_POSITION_SIZER_MQH
#define ATLAS_POSITION_SIZER_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @struct SizerConfig
 * @brief Configuration for the position sizer.
 */
struct SizerConfig
{
    int    method;             ///< ATLAS_SIZER_*
    double fixed_lot;          ///< Fixed lot size (for ATLAS_SIZER_FIXED_LOT)
    double risk_percent;       ///< Risk % of equity (for ATLAS_SIZER_RISK_PERCENT)
    double fixed_money_risk;   ///< Fixed money risk (for ATLAS_SIZER_FIXED_MONEY)
    double min_lot;            ///< Minimum lot size
    double max_lot;            ///< Maximum lot size
    double lot_step;           ///< Lot step size
    double sl_atr_multiplier;  ///< SL = ATR × multiplier (for ATR-based risk)

    /**
     * @brief Default constructor.
     */
    SizerConfig(void)
    {
        method            = ATLAS_SIZER_FIXED_LOT;
        fixed_lot         = 0.10;
        risk_percent      = 1.0;     ///< 1% of equity
        fixed_money_risk  = 100.0;   ///< $100
        min_lot           = 0.01;
        max_lot           = 10.0;
        lot_step          = 0.01;
        sl_atr_multiplier = 2.0;
    }
};

/**
 * @class PositionSizer
 * @brief Calculates trade volume based on the configured sizing method.
 *
 * Methods:
 *   - Fixed Lot: always use the same volume
 *   - Risk Percent: volume = (equity × risk%) / (sl_distance × contract_size)
 *   - Fixed Money: volume = fixed_risk / (sl_distance × contract_size)
 *   - ATR Multiplier: (placeholder) volume based on ATR
 *   - Kelly: (placeholder) volume based on Kelly criterion
 *
 * All methods normalize the result to [min_lot, max_lot] and round to lot_step.
 */
class PositionSizer
{
private:
    ILogger    *m_logger;
    SizerConfig m_config;
    double      m_contract_size;

    /// @brief Round volume to lot step.
    double RoundToStep(const double volume) const
    {
        if(m_config.lot_step <= 0.0) return volume;
        return MathRound(volume / m_config.lot_step) * m_config.lot_step;
    }

    /// @brief Clamp volume to [min, max].
    double Clamp(const double volume) const
    {
        double v = volume;
        if(v < m_config.min_lot) v = m_config.min_lot;
        if(v > m_config.max_lot) v = m_config.max_lot;
        return v;
    }

    /// @brief Normalize: round to step + clamp.
    double Normalize(const double volume) const
    {
        return Clamp(RoundToStep(volume));
    }

public:
    /**
     * @brief Constructor.
     */
    PositionSizer(void)
    {
        m_logger        = NULL;
        m_contract_size = 100000.0;
    }

    /**
     * @brief Initialize.
     * @param logger Logger.
     * @param config Sizer configuration.
     * @param contract_size Symbol contract size.
     */
    void Initialize(ILogger *logger, const SizerConfig &config, const double contract_size)
    {
        m_logger        = logger;
        m_config        = config;
        m_contract_size = (contract_size > 0.0) ? contract_size : 100000.0;
    }

    /**
     * @brief Calculate the position size.
     * @param equity Current account equity.
     * @param sl_distance Stop-loss distance in price units (entry - SL for BUY).
     * @param atr Current ATR value (for ATR-based methods).
     * @param win_rate Historical win rate (for Kelly, 0..1).
     * @return Normalized volume in lots.
     */
    double Calculate(const double equity, const double sl_distance,
                     const double atr = 0.0, const double win_rate = 0.5) const
    {
        double raw_volume = 0.0;

        switch(m_config.method)
        {
            case ATLAS_SIZER_FIXED_LOT:
                raw_volume = m_config.fixed_lot;
                break;

            case ATLAS_SIZER_RISK_PERCENT:
                raw_volume = CalculateRiskPercent(equity, sl_distance);
                break;

            case ATLAS_SIZER_FIXED_MONEY:
                raw_volume = CalculateFixedMoney(sl_distance);
                break;

            case ATLAS_SIZER_ATR_MULTIPLIER:
                //--- Placeholder: use risk_percent with ATR-based SL distance
                if(atr > 0.0)
                    raw_volume = CalculateRiskPercent(equity, atr * m_config.sl_atr_multiplier);
                else
                    raw_volume = m_config.fixed_lot;
                break;

            case ATLAS_SIZER_KELLY:
                //--- Placeholder: simplified Kelly
                raw_volume = CalculateKelly(equity, sl_distance, win_rate);
                break;

            default:
                raw_volume = m_config.fixed_lot;
                break;
        }

        return Normalize(raw_volume);
    }

    /**
     * @brief Get the current sizer configuration.
     */
    const SizerConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Set the sizer configuration (runtime change).
     */
    void SetConfig(const SizerConfig &config) { m_config = config; }

private:
    /// @brief Risk Percent method: volume = (equity × risk%) / (sl_dist × contract_size)
    double CalculateRiskPercent(const double equity, const double sl_distance) const
    {
        if(equity <= 0.0 || sl_distance <= 0.0 || m_contract_size <= 0.0)
            return m_config.min_lot;

        double risk_amount = equity * (m_config.risk_percent / 100.0);
        double sl_value_per_lot = sl_distance * m_contract_size;
        if(sl_value_per_lot <= 0.0) return m_config.min_lot;

        return risk_amount / sl_value_per_lot;
    }

    /// @brief Fixed Money method: volume = fixed_risk / (sl_dist × contract_size)
    double CalculateFixedMoney(const double sl_distance) const
    {
        if(sl_distance <= 0.0 || m_contract_size <= 0.0)
            return m_config.min_lot;

        double sl_value_per_lot = sl_distance * m_contract_size;
        if(sl_value_per_lot <= 0.0) return m_config.min_lot;

        return m_config.fixed_money_risk / sl_value_per_lot;
    }

    /// @brief Kelly criterion (simplified placeholder).
    /// f = win_rate - (1 - win_rate) / win_loss_ratio
    /// Volume = equity × f / sl_value_per_lot
    double CalculateKelly(const double equity, const double sl_distance, const double win_rate) const
    {
        if(equity <= 0.0 || sl_distance <= 0.0 || m_contract_size <= 0.0)
            return m_config.min_lot;

        //--- Simplified: assume 1:1 win/loss ratio for placeholder
        double w = win_rate;
        if(w <= 0.0 || w >= 1.0) return m_config.min_lot;

        double kelly_fraction = w - (1.0 - w);  ///< Simplified (1:1 ratio)
        if(kelly_fraction <= 0.0) return m_config.min_lot;

        //--- Use half-Kelly for safety
        kelly_fraction *= 0.5;

        double risk_amount = equity * kelly_fraction;
        double sl_value_per_lot = sl_distance * m_contract_size;
        if(sl_value_per_lot <= 0.0) return m_config.min_lot;

        return risk_amount / sl_value_per_lot;
    }
};

#endif // ATLAS_POSITION_SIZER_MQH
//+------------------------------------------------------------------+
