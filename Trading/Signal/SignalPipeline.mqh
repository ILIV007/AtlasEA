//+------------------------------------------------------------------+
//|                   Trading/Signal/SignalPipeline.mqh              |
//|       AtlasEA v0.2.1 - Signal Pipeline Orchestrator              |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_PIPELINE_MQH
#define ATLAS_SIGNAL_PIPELINE_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Core/ValidationResult.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"
#include "SignalCollector.mqh"
#include "SignalNormalizer.mqh"
#include "SignalValidator.mqh"
#include "SignalScoring.mqh"
#include "SignalPriorityQueue.mqh"
#include "SignalRouter.mqh"

/**
 * @struct SignalPipelineStats
 * @brief Aggregated statistics for the entire pipeline.
 */
struct SignalPipelineStats
{
    int   total_cycles;          ///< Total ProcessCycle() calls
    int   total_collected;       ///< Signals collected from strategies
    int   total_normalized;      ///< Signals normalized
    int   total_validated;       ///< Signals that passed validation
    int   total_rejected;        ///< Signals rejected by validator
    int   total_scored;          ///< Signals scored
    int   total_queued;          ///< Signals pushed to priority queue
    int   total_routed;          ///< Signals forwarded to lifecycle
    int   total_accepted;        ///< Signals accepted by lifecycle
    int   total_empty_cycles;    ///< Cycles with no signals collected

    SignalPipelineStats(void)
    {
        total_collected    = 0;
        total_normalized   = 0;
        total_validated    = 0;
        total_rejected     = 0;
        total_scored       = 0;
        total_queued       = 0;
        total_routed       = 0;
        total_accepted     = 0;
        total_empty_cycles = 0;
        total_cycles       = 0;
    }
};

/**
 * @class SignalPipeline
 * @brief Orchestrates the complete signal pipeline.
 *
 * The pipeline is the DETERMINISTIC path every strategy signal must
 * follow before reaching the TradeLifecycle:
 *
 *   Strategies
 *     ↓
 *   Collector      (collect from all producers, no filtering)
 *     ↓
 *   Normalizer     (normalize SL/TP/confidence/direction/time)
 *     ↓
 *   Validator      (reject duplicates, expired, invalid)
 *     ↓
 *   Scoring        (deterministic score: confidence + freshness + priority + quality)
 *     ↓
 *   Priority Queue (highest score first, stable, fixed-size)
 *     ↓
 *   Router         (forward to TradeLifecycle)
 *
 * The pipeline owns all 6 sub-components (stack-allocated, no dynamic
 * allocation). It exposes a single ProcessCycle() method that runs
 * the full pipeline once per tick.
 *
 * CONFIGURATION:
 *   - Collector: register strategy producers via GetCollector().RegisterProducer()
 *   - Normalizer: configure via GetNormalizer().SetConfig()
 *   - Validator: configure via GetValidator().SetConfig()
 *   - Scoring: configure via GetScoring().SetConfig() + SetStrategyPriority()
 *   - Router: configure via GetRouter().SetConfig() + SetForwarder()
 *
 * INTEGRATION:
 *   - Input: MarketState (from CoreEngine/PhaseScheduler)
 *   - Output: TradeSignal forwarded to TradeLifecycle via the router's forwarder
 *
 * DETERMINISM:
 *   - No randomness
 *   - No AI/ML
 *   - No time-of-day dependence (except freshness scoring, which is deterministic)
 *   - Same input → same output, always
 *
 * Memory: ~10 KB (all sub-components are fixed-size, stack-allocated).
 */
class SignalPipeline
{
private:
    ILogger             *m_logger;
    SignalCollector      m_collector;
    SignalNormalizer     m_normalizer;
    SignalValidator      m_validator;
    SignalScoring        m_scoring;
    SignalPriorityQueue  m_queue;
    SignalRouter         m_router;

    SignalPipelineStats  m_stats;
    bool                 m_initialized;

public:
    /**
     * @brief Constructor.
     */
    SignalPipeline(void)
    {
        m_logger      = NULL;
        m_initialized = false;
    }

    /**
     * @brief Set the logger (wires to all sub-components).
     */
    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_collector.SetLogger(logger);
        m_normalizer.SetLogger(logger);
        m_validator.SetLogger(logger);
        m_scoring.SetLogger(logger);
        m_queue.SetLogger(logger);
        m_router.SetLogger(logger);
    }

    /**
     * @brief Initialize the pipeline.
     */
    bool Initialize(void)
    {
        if(m_logger == NULL) return false;
        m_initialized = true;
        m_logger.Info("SignalPipeline", "Initialized");
        return true;
    }

    /**
     * @brief Shutdown the pipeline.
     */
    void Shutdown(void)
    {
        if(!m_initialized) return;
        LogStats();
        m_queue.Clear();
        m_validator.ClearDedup();
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("SignalPipeline", "Shutdown complete");
    }

    /**
     * @brief Process one pipeline cycle.
     *
     * This is the MAIN ENTRY POINT. Called once per tick (or per
     * strategy evaluation cycle). Runs the full pipeline:
     *   1. Collect signals from all registered producers
     *   2. Normalize each signal
     *   3. Validate each signal (reject invalid)
     *   4. Score each valid signal
     *   5. Push scored signals to the priority queue
     *   6. Route the highest-priority signals to the TradeLifecycle
     *
     * @param market Current market state.
     * @return Number of signals forwarded to the lifecycle.
     */
    int ProcessCycle(const MarketState &market)
    {
        if(!m_initialized) return 0;

        m_stats.total_cycles++;

        //==============================================================
        // STAGE 1: COLLECT
        //==============================================================
        int collected = m_collector.Collect(market);
        m_stats.total_collected += collected;

        if(collected == 0)
        {
            m_stats.total_empty_cycles++;
            //--- Still route any leftover signals from previous cycles
            return m_router.Route(m_queue, market);
        }

        //==============================================================
        // STAGES 2-5: NORMALIZE → VALIDATE → SCORE → QUEUE
        //==============================================================
        for(int i = 0; i < collected; i++)
        {
            TradeSignal raw;
            if(!m_collector.GetCollectedAt(i, raw)) continue;

            //=== Stage 2: Normalize ===
            TradeSignal normalized = m_normalizer.Normalize(raw, market);
            m_stats.total_normalized++;

            //=== Stage 3: Validate ===
            SignalValidationResult vresult = m_validator.Validate(normalized);
            if(!vresult.accepted)
            {
                m_stats.total_rejected++;
                continue;
            }
            m_stats.total_validated++;

            //=== Stage 4: Score ===
            SignalScore score = m_scoring.Score(normalized, market);
            m_stats.total_scored++;

            //=== Stage 5: Push to priority queue ===
            if(m_queue.Push(normalized, score.total))
                m_stats.total_queued++;
        }

        //==============================================================
        // STAGE 6: ROUTE
        //==============================================================
        int routed = m_router.Route(m_queue, market);
        m_stats.total_routed += routed;

        return routed;
    }

    /**
     * @brief Get the aggregated pipeline statistics.
     */
    const SignalPipelineStats& GetStats(void) const { return m_stats; }

    /**
     * @brief Log the pipeline statistics.
     */
    void LogStats(void) const
    {
        if(m_logger == NULL) return;

        m_logger.Info("SignalPipeline",
            "Cycles=" + IntegerToString(m_stats.total_cycles) +
            " Collected=" + IntegerToString(m_stats.total_collected) +
            " Normalized=" + IntegerToString(m_stats.total_normalized) +
            " Validated=" + IntegerToString(m_stats.total_validated) +
            " Rejected=" + IntegerToString(m_stats.total_rejected) +
            " Scored=" + IntegerToString(m_stats.total_scored) +
            " Queued=" + IntegerToString(m_stats.total_queued) +
            " Routed=" + IntegerToString(m_stats.total_routed) +
            " Empty=" + IntegerToString(m_stats.total_empty_cycles));

        //--- Sub-component stats
        m_logger.Info("SignalPipeline",
            "Validator: validated=" + IntegerToString(m_validator.TotalValidated()) +
            " accepted=" + IntegerToString(m_validator.TotalAccepted()) +
            " rejected=" + IntegerToString(m_validator.TotalRejected()));

        m_logger.Info("SignalPipeline",
            "Queue: pushed=" + IntegerToString(m_queue.TotalPushed()) +
            " popped=" + IntegerToString(m_queue.TotalPopped()) +
            " evicted=" + IntegerToString(m_queue.TotalEvicted()) +
            " current=" + IntegerToString(m_queue.Count()));

        m_logger.Info("SignalPipeline",
            "Router: routed=" + IntegerToString(m_router.GetStatistics().total_routed) +
            " skipped=" + IntegerToString(m_router.GetStatistics().total_skipped) +
            " cycles=" + IntegerToString(m_router.GetStatistics().total_cycles));
    }

    /**
     * @brief Reset all pipeline statistics.
     */
    void ResetStats(void)
    {
        m_stats = SignalPipelineStats();
        m_collector.ResetStats();
        m_validator.ResetStats();
        m_queue.ResetStats();
        m_router.ResetStats();
    }

    //=== Sub-component access (for configuration) ===

    SignalCollector&       GetCollector(void)  { return m_collector; }
    SignalNormalizer&      GetNormalizer(void) { return m_normalizer; }
    SignalValidator&       GetValidator(void)  { return m_validator; }
    SignalScoring&         GetScoring(void)    { return m_scoring; }
    SignalPriorityQueue&   GetQueue(void)      { return m_queue; }
    SignalRouter&          GetRouter(void)     { return m_router; }

    /**
     * @brief Check if the pipeline is initialized.
     */
    bool IsInitialized(void) const { return m_initialized; }
};

#endif // ATLAS_SIGNAL_PIPELINE_MQH
//+------------------------------------------------------------------+
