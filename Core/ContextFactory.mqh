//+------------------------------------------------------------------+
//|                                         Core/ContextFactory.mqh
//|                AtlasEA v2.0 - Context Factory / Resetter          |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONTEXT_FACTORY_MQH
#define ATLAS_CONTEXT_FACTORY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IContextStore.mqh"
#include "../Interfaces/ILogger.mqh"
#include "AtlasContext.mqh"

/**
 * @class ContextFactory
 * @brief Creates and resets AtlasContext instances.
 *
 * Separates initialization logic from the AtlasContext data class,
 * keeping AtlasContext a lean data holder.
 *
 * ResetDaily: seeds daily risk stats from current account equity.
 * ResetAll:   clears everything to zero/empty.
 */
class ContextFactory
{
private:
    ILogger *m_logger;

public:
    /**
     * @brief Constructor.
     * @param logger Optional logger (may be NULL).
     */
    ContextFactory(ILogger *logger = NULL) { m_logger = logger; }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Initialize a fresh context to safe defaults.
     * @param ctx The context to initialize.
     */
    void InitializeFresh(AtlasContext &ctx);

    /**
     * @brief Reset daily risk stats for a new trading day.
     * Seeds daily_start_equity and daily_peak_equity from the provided value.
     * @param ctx     The context to reset.
     * @param equity  Current account equity (from IBrokerAdapter::AccountEquity()).
     */
    void ResetDaily(AtlasContext &ctx, const double equity);

    /**
     * @brief Reset ALL state on a context (full wipe).
     * @param ctx The context to wipe.
     */
    void ResetAll(AtlasContext &ctx);

    /**
     * @brief Check if a new trading day has started since the last reset.
     * @param ctx The context to check.
     * @return true if the calendar day differs from trading_day_start.
     */
    bool IsNewTradingDay(const AtlasContext &ctx) const;
};

//+------------------------------------------------------------------+
//| ContextFactory implementation                                    |
//+------------------------------------------------------------------+

void ContextFactory::InitializeFresh(AtlasContext &ctx)
{
    ctx.ResetAll();
    if(m_logger != NULL)
        m_logger.Info("ContextFactory", "Context initialized fresh");
}

//+------------------------------------------------------------------+
void ContextFactory::ResetDaily(AtlasContext &ctx, const double equity)
{
    ctx.ResetDaily();
    ctx.SetDailyStartEquity(equity);
    ctx.UpdateDailyPeakEquity(equity);
    if(m_logger != NULL)
        m_logger.Info("ContextFactory", "Daily reset: start_equity=" + DoubleToString(equity, 2));
}

//+------------------------------------------------------------------+
void ContextFactory::ResetAll(AtlasContext &ctx)
{
    ctx.ResetAll();
    if(m_logger != NULL)
        m_logger.Info("ContextFactory", "Context fully reset");
}

//+------------------------------------------------------------------+
bool ContextFactory::IsNewTradingDay(const AtlasContext &ctx) const
{
    datetime last = ctx.GetTradingDayStart();
    if(last == 0)
        return true;

    MqlDateTime now_dt, last_dt;
    TimeToStruct(TimeCurrent(), now_dt);
    TimeToStruct(last, last_dt);

    return (now_dt.day != last_dt.day ||
            now_dt.mon != last_dt.mon ||
            now_dt.year != last_dt.year);
}

#endif // ATLAS_CONTEXT_FACTORY_MQH
//+------------------------------------------------------------------+
