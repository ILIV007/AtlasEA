//+------------------------------------------------------------------+
//|            Engines/RiskEngine/DrawdownMonitor.mqh                |
//|       AtlasEA v0.1.11.0 - Drawdown Monitoring                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_DRAWDOWN_MONITOR_MQH
#define ATLAS_DRAWDOWN_MONITOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "RiskState.mqh"

/**
 * @class DrawdownMonitor
 * @brief Monitors daily and floating drawdown.
 *
 * Daily drawdown: peak equity today vs current equity.
 * Floating drawdown: peak equity vs current floating equity (unrealized).
 *
 * Triggers kill switch when thresholds are exceeded.
 */
class DrawdownMonitor
{
private:
    ILogger *m_logger;
    double   m_max_daily_dd_pct;       ///< Max daily drawdown % (e.g., 5.0)
    double   m_max_floating_dd_pct;    ///< Max floating drawdown %
    double   m_critical_dd_pct;        ///< Critical (absolute) drawdown % (e.g., 8.0)

public:
    /**
     * @brief Constructor.
     */
    DrawdownMonitor(void)
    {
        m_logger              = NULL;
        m_max_daily_dd_pct    = 5.0;
        m_max_floating_dd_pct = 4.0;
        m_critical_dd_pct     = 8.0;
    }

    /**
     * @brief Initialize.
     */
    void Initialize(ILogger *logger,
                    const double max_daily_dd_pct,
                    const double max_floating_dd_pct,
                    const double critical_dd_pct)
    {
        m_logger              = logger;
        m_max_daily_dd_pct    = (max_daily_dd_pct > 0.0) ? max_daily_dd_pct : 5.0;
        m_max_floating_dd_pct = (max_floating_dd_pct > 0.0) ? max_floating_dd_pct : 4.0;
        m_critical_dd_pct     = (critical_dd_pct > 0.0) ? critical_dd_pct : 8.0;
    }

    /**
     * @brief Update drawdown calculations.
     * @param state Risk state (mutated).
     * @param context Context store (for peak equity).
     * @param equity Current equity.
     * @param floating_pnl Current floating PnL.
     * @return true if drawdown is within limits, false if exceeded.
     */
    bool Update(RiskState &state, IContextStore *context,
                const double equity, const double floating_pnl)
    {
        if(context == NULL) return false;
        if(equity <= 0.0) return false;

        //--- Update peak equity
        double peak = context.GetDailyPeakEquity();
        if(equity > peak)
        {
            context.UpdateDailyPeakEquity(equity);
            peak = equity;
        }
        state.peak_equity = peak;

        //--- Calculate daily drawdown
        double start_equity = context.GetDailyStartEquity();
        if(start_equity > 0.0 && peak > 0.0)
        {
            state.daily_drawdown_pct = ((peak - equity) / start_equity) * 100.0;
            context.SetDailyDrawdownPct(state.daily_drawdown_pct);
        }

        //--- Calculate floating drawdown (from peak to current floating equity)
        double floating_equity = equity + floating_pnl;
        if(peak > 0.0)
        {
            state.floating_drawdown_pct = ((peak - floating_equity) / peak) * 100.0;
            if(state.floating_drawdown_pct < 0.0)
                state.floating_drawdown_pct = 0.0;
        }

        state.current_equity   = equity;
        state.daily_floating_pnl = floating_pnl;

        //--- Check limits
        return IsWithinLimits(state);
    }

    /**
     * @brief Check if drawdown is within configured limits.
     * @param state Risk state.
     * @return true if within limits.
     */
    bool IsWithinLimits(const RiskState &state) const
    {
        if(state.daily_drawdown_pct >= m_critical_dd_pct) return false;
        if(state.daily_drawdown_pct >= m_max_daily_dd_pct) return false;
        if(state.floating_drawdown_pct >= m_max_floating_dd_pct) return false;
        return true;
    }

    /**
     * @brief Check if drawdown exceeds the critical (absolute) limit.
     * This triggers the kill switch immediately.
     */
    bool IsCritical(const RiskState &state) const
    {
        return (state.daily_drawdown_pct >= m_critical_dd_pct);
    }

    /**
     * @brief Get the reason string for a drawdown breach.
     */
    string GetBreachReason(const RiskState &state) const
    {
        if(state.daily_drawdown_pct >= m_critical_dd_pct)
            return "CRITICAL daily drawdown: " + DoubleToString(state.daily_drawdown_pct, 2) + "%";
        if(state.daily_drawdown_pct >= m_max_daily_dd_pct)
            return "Daily drawdown exceeded: " + DoubleToString(state.daily_drawdown_pct, 2) +
                   "% >= " + DoubleToString(m_max_daily_dd_pct, 2) + "%";
        if(state.floating_drawdown_pct >= m_max_floating_dd_pct)
            return "Floating drawdown exceeded: " + DoubleToString(state.floating_drawdown_pct, 2) +
                   "% >= " + DoubleToString(m_max_floating_dd_pct, 2) + "%";
        return "";
    }

    //=== Accessors ===
    double GetMaxDailyDD(void)        const { return m_max_daily_dd_pct; }
    double GetMaxFloatingDD(void)     const { return m_max_floating_dd_pct; }
    double GetCriticalDD(void)        const { return m_critical_dd_pct; }
    double GetDailyDDUtilization(const RiskState &state) const
    {
        if(m_max_daily_dd_pct <= 0.0) return 0.0;
        return (state.daily_drawdown_pct / m_max_daily_dd_pct) * 100.0;
    }
};

#endif // ATLAS_DRAWDOWN_MONITOR_MQH
//+------------------------------------------------------------------+
