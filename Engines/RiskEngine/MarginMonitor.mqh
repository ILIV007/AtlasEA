//+------------------------------------------------------------------+
//|             Engines/RiskEngine/MarginMonitor.mqh                 |
//|       AtlasEA v0.1.11.0 - Margin Safety Monitoring               |
//+------------------------------------------------------------------+
#ifndef ATLAS_MARGIN_MONITOR_MQH
#define ATLAS_MARGIN_MONITOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"

/**
 * @class MarginMonitor
 * @brief Monitors margin level and free margin.
 *
 * Checks:
 *   - Minimum free margin (absolute amount)
 *   - Minimum margin level (percentage)
 *   - Critical margin level (triggers kill switch)
 *
 * All margin data comes from the RiskState (populated by the engine
 * from IContextStore, which is populated by the broker adapter).
 * The RiskEngine does NOT call AccountInfoDouble directly.
 */
class MarginMonitor
{
private:
    ILogger *m_logger;
    double   m_min_free_margin;      ///< Minimum free margin (absolute, in account currency)
    double   m_min_margin_level;     ///< Minimum margin level (%) — default 200%
    double   m_critical_margin_level;///< Critical margin level (%) — triggers kill switch

public:
    /**
     * @brief Constructor.
     */
    MarginMonitor(void)
    {
        m_logger               = NULL;
        m_min_free_margin      = 100.0;    ///< $100 minimum free margin
        m_min_margin_level     = 200.0;    ///< 200% minimum margin level
        m_critical_margin_level = 100.0;   ///< 100% = critical (margin call territory)
    }

    /**
     * @brief Initialize.
     */
    void Initialize(ILogger *logger,
                    const double min_free_margin,
                    const double min_margin_level,
                    const double critical_margin_level)
    {
        m_logger                = logger;
        m_min_free_margin       = (min_free_margin > 0.0) ? min_free_margin : 100.0;
        m_min_margin_level      = (min_margin_level > 0.0) ? min_margin_level : 200.0;
        m_critical_margin_level = (critical_margin_level > 0.0) ? critical_margin_level : 100.0;
    }

    /**
     * @brief Update margin state.
     * @param state Risk state (mutated).
     * @param equity Current equity.
     * @param used_margin Current used margin.
     */
    void Update(RiskState &state, const double equity, const double used_margin)
    {
        state.used_margin = used_margin;
        state.free_margin = equity - used_margin;

        if(used_margin > 0.0)
            state.margin_level = (equity / used_margin) * 100.0;
        else
            state.margin_level = 0.0;  ///< No margin used = infinite level (safe)
    }

    /**
     * @brief Check if margin is safe for a new trade.
     * @param state Risk state.
     * @return true if margin is safe.
     */
    bool IsMarginSafe(const RiskState &state) const
    {
        //--- No existing margin = safe (first trade)
        if(state.used_margin <= 0.0) return true;

        //--- Check margin level
        if(state.margin_level < m_min_margin_level) return false;

        //--- Check free margin
        if(state.free_margin < m_min_free_margin) return false;

        return true;
    }

    /**
     * @brief Check if margin level is critical (triggers kill switch).
     */
    bool IsCritical(const RiskState &state) const
    {
        if(state.used_margin <= 0.0) return false;
        return (state.margin_level < m_critical_margin_level);
    }

    /**
     * @brief Get the reason string for a margin breach.
     */
    string GetBreachReason(const RiskState &state) const
    {
        if(state.used_margin > 0.0 && state.margin_level < m_critical_margin_level)
            return "CRITICAL margin level: " + DoubleToString(state.margin_level, 1) + "%";
        if(state.used_margin > 0.0 && state.margin_level < m_min_margin_level)
            return "Margin level too low: " + DoubleToString(state.margin_level, 1) +
                   "% < " + DoubleToString(m_min_margin_level, 1) + "%";
        if(state.free_margin < m_min_free_margin)
            return "Free margin too low: " + DoubleToString(state.free_margin, 2) +
                   " < " + DoubleToString(m_min_free_margin, 2);
        return "";
    }

    //=== Accessors ===
    double GetMinFreeMargin(void)      const { return m_min_free_margin; }
    double GetMinMarginLevel(void)     const { return m_min_margin_level; }
    double GetCriticalMarginLevel(void) const { return m_critical_margin_level; }
};

#endif // ATLAS_MARGIN_MONITOR_MQH
//+------------------------------------------------------------------+
