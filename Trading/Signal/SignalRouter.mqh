//+------------------------------------------------------------------+
//|                    Trading/Signal/SignalRouter.mqh               |
//|       AtlasEA v0.2.1 - Signal Router                             |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_ROUTER_MQH
#define ATLAS_SIGNAL_ROUTER_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"
#include "SignalPriorityQueue.mqh"

/**
 * @brief Router mode: how many signals to forward per cycle.
 */
#define ATLAS_ROUTER_MODE_SINGLE    0   ///< Forward only the single best signal
#define ATLAS_ROUTER_MODE_TOP_N     1   ///< Forward top N signals
#define ATLAS_ROUTER_MODE_ALL       2   ///< Forward all valid signals

/**
 * @struct RouterConfig
 * @brief Configuration for the signal router.
 */
struct RouterConfig
{
    int    mode;               ///< ATLAS_ROUTER_MODE_*
    int    top_n;              ///< Number of signals to forward in TOP_N mode
    double min_score_threshold; ///< Minimum score to forward (0 = forward all)
    bool   forward_on_collect; ///< If true, forward immediately during Route()

    RouterConfig(void)
    {
        mode                = ATLAS_ROUTER_MODE_SINGLE;
        top_n               = 1;
        min_score_threshold = 0.0;
        forward_on_collect  = true;
    }
};

/**
 * @struct RouterStatistics
 * @brief Statistics for the signal router.
 */
struct RouterStatistics
{
    int total_routed;         ///< Total signals forwarded
    int total_skipped;        ///< Signals skipped (below threshold)
    int total_cycles;         ///< Number of Route() calls
    int total_empty;          ///< Cycles with no signals to route

    RouterStatistics(void)
    {
        total_routed  = 0;
        total_skipped = 0;
        total_cycles  = 0;
        total_empty   = 0;
    }
};

/**
 * @brief Signal forwarding callback type.
 *
 * The router forwards signals via this callback. The TradeLifecycle
 * registers its ProcessSignal method as the forward target.
 *
 * @param signal The signal to forward.
 * @param market Current market state.
 * @return true if the signal was accepted by the lifecycle.
 */
typedef bool (*SignalForwarder)(const TradeSignal &signal, const MarketState &market);

/**
 * @class SignalRouter
 * @brief Forwards the highest-priority valid signals to the TradeLifecycle.
 *
 * SOLE RESPONSIBILITY: pop signals from the priority queue (highest first)
 * and forward them to the TradeLifecycle via a callback.
 *
 * The router does NOT:
 *   - Score signals (that's the scorer's job)
 *   - Validate signals (that's the validator's job)
 *   - Execute trades (that's the lifecycle's job)
 *
 * Routing modes:
 *   - SINGLE: forward only the single highest-scoring signal per cycle
 *   - TOP_N: forward the top N signals per cycle
 *   - ALL: forward all signals in the queue
 *
 * The router applies a minimum score threshold — signals below the
 * threshold are skipped (not forwarded).
 *
 * Memory: ~200 bytes (config + callback + stats).
 */
class SignalRouter
{
private:
    ILogger          *m_logger;
    RouterConfig      m_config;
    SignalForwarder   m_forwarder;
    RouterStatistics  m_stats;

public:
    /**
     * @brief Constructor.
     */
    SignalRouter(void)
    {
        m_logger   = NULL;
        m_forwarder = NULL;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Set the router configuration.
     */
    void SetConfig(const RouterConfig &config) { m_config = config; }

    /**
     * @brief Get the current configuration.
     */
    const RouterConfig& GetConfig(void) const { return m_config; }

    /**
     * @brief Set the forwarder callback.
     *
     * The TradeLifecycle registers its ProcessSignal method here.
     *
     * @param forwarder The callback function.
     */
    void SetForwarder(SignalForwarder forwarder) { m_forwarder = forwarder; }

    /**
     * @brief Route signals from the priority queue to the lifecycle.
     *
     * Pops signals from the queue (highest first), applies the score
     * threshold, and forwards via the callback.
     *
     * @param queue The priority queue to drain.
     * @param market Current market state (passed to the forwarder).
     * @return Number of signals forwarded.
     */
    int Route(SignalPriorityQueue &queue, const MarketState &market)
    {
        m_stats.total_cycles++;

        if(m_forwarder == NULL)
        {
            if(m_logger != NULL)
                m_logger.Warn("SignalRouter", "No forwarder set — skipping route");
            return 0;
        }

        if(queue.IsEmpty())
        {
            m_stats.total_empty++;
            return 0;
        }

        int forwarded = 0;
        int max_forward = GetMaxForward(queue.Count());

        for(int i = 0; i < max_forward; i++)
        {
            if(queue.IsEmpty()) break;

            ScoredSignal item;
            if(!queue.Pop(item)) break;

            //--- Apply score threshold
            if(item.score < m_config.min_score_threshold)
            {
                m_stats.total_skipped++;
                if(m_logger != NULL)
                    m_logger.Debug("SignalRouter",
                        "Skipped " + item.signal.signal_id +
                        " score=" + DoubleToString(item.score, 1) +
                        " < threshold=" + DoubleToString(m_config.min_score_threshold, 1));
                continue;
            }

            //--- Forward to the lifecycle
            bool accepted = m_forwarder(item.signal, market);
            if(accepted)
            {
                forwarded++;
                m_stats.total_routed++;
                if(m_logger != NULL)
                    m_logger.Info("SignalRouter",
                        "Routed " + item.signal.signal_id +
                        " score=" + DoubleToString(item.score, 1) +
                        " (accepted)");
            }
            else
            {
                m_stats.total_skipped++;
                if(m_logger != NULL)
                    m_logger.Debug("SignalRouter",
                        "Forwarded " + item.signal.signal_id +
                        " but lifecycle rejected it");
            }
        }

        return forwarded;
    }

    /**
     * @brief Get the router statistics.
     */
    const RouterStatistics& GetStatistics(void) const { return m_stats; }

    /**
     * @brief Reset statistics.
     */
    void ResetStats(void)
    {
        m_stats.total_routed  = 0;
        m_stats.total_skipped = 0;
        m_stats.total_cycles  = 0;
        m_stats.total_empty   = 0;
    }

private:
    /**
     * @brief Get the maximum number of signals to forward this cycle.
     */
    int GetMaxForward(const int queue_count) const
    {
        switch(m_config.mode)
        {
            case ATLAS_ROUTER_MODE_SINGLE:
                return 1;
            case ATLAS_ROUTER_MODE_TOP_N:
                return (m_config.top_n > 0) ? m_config.top_n : 1;
            case ATLAS_ROUTER_MODE_ALL:
                return queue_count;
        }
        return 1; // Default to single
    }
};

#endif // ATLAS_SIGNAL_ROUTER_MQH
//+------------------------------------------------------------------+
