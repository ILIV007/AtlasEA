//+------------------------------------------------------------------+
//|                       Trading/Filters/IFilter.mqh                |
//|       AtlasEA v0.2.2 - Entry Filter Interface                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_IFILTER_MQH
#define ATLAS_IFILTER_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Contracts/Events.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../../Interfaces/IBrokerAdapter.mqh"
#include "../../Interfaces/IContextStore.mqh"
#include "../TradeSignal.mqh"
#include "FilterResult.mqh"

/**
 * @struct FilterConfig
 * @brief Base configuration for every filter.
 *
 * Every filter supports:
 *   - Enabled: if false, the filter returns SKIP (no effect)
 *   - Priority: execution order (lower = earlier). Filters with the
 *     same priority run in registration order.
 *   - ReasonCode: the default reason code this filter uses when blocking
 *     (can be overridden per-evaluation for more specific codes)
 */
struct FilterConfig
{
    bool   enabled;       ///< Is this filter active?
    int    priority;      ///< Execution priority (0 = first, higher = later)
    int    reason_code;   ///< Default reason code for BLOCK

    FilterConfig(void)
    {
        enabled     = true;
        priority    = 50;
        reason_code = ATLAS_FR_OK;
    }
};

/**
 * @class IFilter
 * @brief Abstract interface for all entry filters.
 *
 * Every filter implements this interface. The EntryFilterEngine calls
 * Evaluate() on each filter in priority order.
 *
 * Contract:
 *   - Evaluate() must be deterministic (same input → same output)
 *   - Evaluate() must NOT allocate (no dynamic arrays, no new/delete)
 *   - Evaluate() must NOT call MT5 APIs directly — use IBrokerAdapter
 *     or cached MarketState fields
 *   - Evaluate() must return PASS, BLOCK, or SKIP with a reason code
 *   - If the filter is disabled, it must return SKIP immediately
 *
 * Thread safety: MQL5 single-threaded — no synchronization needed.
 */
class IFilter
{
public:
    /**
     * @brief Get the filter's name (for logging).
     */
    virtual string GetName(void) const = 0;

    /**
     * @brief Get the filter's configuration.
     */
    virtual FilterConfig GetConfig(void) const = 0;

    /**
     * @brief Set the filter's configuration.
     */
    virtual void SetConfig(const FilterConfig &config) = 0;

    /**
     * @brief Set the logger.
     */
    virtual void SetLogger(ILogger *logger) = 0;

    /**
     * @brief Evaluate a signal against this filter.
     *
     * @param signal  The signal to evaluate (already normalized + validated).
     * @param market  Current market state (read-only).
     * @param broker  Broker adapter (read-only, for queries if needed).
     * @param context Context store (read-only, for position/cooldown queries).
     * @return FilterResult (PASS / BLOCK / SKIP).
     */
    virtual FilterResult Evaluate(const TradeSignal &signal,
                                   const MarketState &market,
                                   IBrokerAdapter *broker,
                                   IContextStore *context) = 0;

    /**
     * @brief Initialize the filter (called once before first Evaluate).
     * @return true if initialization succeeded.
     */
    virtual bool Initialize(void) = 0;

    /**
     * @brief Shutdown the filter (release resources, clear caches).
     */
    virtual void Shutdown(void) = 0;

    virtual ~IFilter(void) {}
};

#endif // ATLAS_IFILTER_MQH
//+------------------------------------------------------------------+
