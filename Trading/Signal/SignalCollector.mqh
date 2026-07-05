//+------------------------------------------------------------------+
//|                  Trading/Signal/SignalCollector.mqh              |
//|       AtlasEA v0.2.1 - Signal Collector                          |
//+------------------------------------------------------------------+
#ifndef ATLAS_SIGNAL_COLLECTOR_MQH
#define ATLAS_SIGNAL_COLLECTOR_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Interfaces/ILogger.mqh"
#include "../TradeSignal.mqh"

/**
 * @brief Maximum signals collected per cycle.
 * Must be >= ATLAS_MAX_STRATEGIES (8) to hold one signal per strategy.
 */
#define ATLAS_COLLECTOR_CAPACITY 16

/**
 * @brief Signal producer callback type.
 *
 * A signal producer is a function that generates a TradeSignal. The
 * collector calls each registered producer once per Collect() call.
 *
 * @param market Current market state (read-only).
 * @param out    Output: the produced signal.
 * @return true if a signal was produced, false if no signal this cycle.
 */
typedef bool (*SignalProducer)(const MarketState &market, TradeSignal &out);

/**
 * @struct ProducerEntry
 * @brief A registered signal producer.
 */
struct ProducerEntry
{
    int             strategy_id;   ///< Strategy ID for this producer
    SignalProducer  producer;      ///< The callback function
    bool            enabled;       ///< Is this producer enabled?

    ProducerEntry(void)
    {
        strategy_id = 0;
        producer    = NULL;
        enabled     = true;
    }
};

/**
 * @class SignalCollector
 * @brief Collects signals from all registered producers.
 *
 * SOLE RESPONSIBILITY: collect signals from all registered strategy
 * producers. NO filtering. NO validation. NO scoring.
 *
 * The collector maintains a list of registered signal producers
 * (one per strategy). On each Collect() call, it invokes every
 * enabled producer and stores all produced signals in a fixed-size
 * buffer.
 *
 * Registration: strategies register their producer callback via
 * RegisterProducer(). A strategy can also be disabled/enabled at
 * runtime via SetEnabled().
 *
 * Memory: ~300 bytes (producer table + collected buffer).
 */
class SignalCollector
{
private:
    ILogger     *m_logger;
    ProducerEntry m_producers[ATLAS_MAX_STRATEGIES];
    int          m_producer_count;

    //--- Collected signals (output of the last Collect() call)
    TradeSignal  m_collected[ATLAS_COLLECTOR_CAPACITY];
    int          m_collected_count;

    //--- Statistics
    int m_total_collect_calls;
    int m_total_signals_collected;

public:
    /**
     * @brief Constructor.
     */
    SignalCollector(void)
    {
        m_logger               = NULL;
        m_producer_count       = 0;
        m_collected_count      = 0;
        m_total_collect_calls  = 0;
        m_total_signals_collected = 0;
    }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Register a signal producer.
     *
     * @param strategy_id  The strategy ID.
     * @param producer     The callback function.
     * @return true if registered, false if table full or producer is NULL.
     */
    bool RegisterProducer(const int strategy_id, SignalProducer producer)
    {
        if(producer == NULL) return false;

        //--- Check for duplicate
        for(int i = 0; i < m_producer_count; i++)
        {
            if(m_producers[i].strategy_id == strategy_id)
            {
                m_producers[i].producer = producer;
                m_producers[i].enabled  = true;
                return true;
            }
        }

        if(m_producer_count >= ATLAS_MAX_STRATEGIES) return false;

        m_producers[m_producer_count].strategy_id = strategy_id;
        m_producers[m_producer_count].producer    = producer;
        m_producers[m_producer_count].enabled     = true;
        m_producer_count++;

        if(m_logger != NULL)
            m_logger.Info("SignalCollector",
                "Registered producer for strategy " + IntegerToString(strategy_id));

        return true;
    }

    /**
     * @brief Unregister a signal producer.
     */
    bool UnregisterProducer(const int strategy_id)
    {
        for(int i = 0; i < m_producer_count; i++)
        {
            if(m_producers[i].strategy_id == strategy_id)
            {
                //--- Shift left
                for(int j = i + 1; j < m_producer_count; j++)
                    m_producers[j - 1] = m_producers[j];
                m_producer_count--;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Enable or disable a producer.
     */
    void SetProducerEnabled(const int strategy_id, const bool enabled)
    {
        for(int i = 0; i < m_producer_count; i++)
        {
            if(m_producers[i].strategy_id == strategy_id)
            {
                m_producers[i].enabled = enabled;
                return;
            }
        }
    }

    /**
     * @brief Collect signals from all enabled producers.
     *
     * Calls every enabled producer. Stores all produced signals in the
     * internal buffer. NO filtering. NO validation.
     *
     * @param market Current market state (passed to each producer).
     * @return Number of signals collected (0 if no producer generated one).
     */
    int Collect(const MarketState &market)
    {
        m_collected_count = 0;
        m_total_collect_calls++;

        for(int i = 0; i < m_producer_count; i++)
        {
            if(!m_producers[i].enabled) continue;
            if(m_producers[i].producer == NULL) continue;
            if(m_collected_count >= ATLAS_COLLECTOR_CAPACITY) break;

            TradeSignal signal;
            if(m_producers[i].producer(market, signal))
            {
                m_collected[m_collected_count] = signal;
                m_collected_count++;
                m_total_signals_collected++;
            }
        }

        if(m_logger != NULL && m_collected_count > 0)
            m_logger.Debug("SignalCollector",
                "Collected " + IntegerToString(m_collected_count) +
                " signals from " + IntegerToString(m_producer_count) +
                " producers");

        return m_collected_count;
    }

    /**
     * @brief Get the collected signals from the last Collect() call.
     * @param out  Output array (caller-allocated, capacity >= ATLAS_COLLECTOR_CAPACITY).
     * @param count Output: number of signals.
     */
    void GetCollected(TradeSignal &out[], int &count) const
    {
        count = m_collected_count;
        for(int i = 0; i < m_collected_count && i < ATLAS_COLLECTOR_CAPACITY; i++)
            out[i] = m_collected[i];
    }

    /**
     * @brief Get the number of collected signals from the last Collect() call.
     */
    int CollectedCount(void) const { return m_collected_count; }

    /**
     * @brief Get a specific collected signal.
     */
    bool GetCollectedAt(const int index, TradeSignal &out) const
    {
        if(index < 0 || index >= m_collected_count) return false;
        out = m_collected[index];
        return true;
    }

    /**
     * @brief Get the number of registered producers.
     */
    int ProducerCount(void) const { return m_producer_count; }

    /**
     * @brief Get the number of enabled producers.
     */
    int EnabledProducerCount(void) const
    {
        int n = 0;
        for(int i = 0; i < m_producer_count; i++)
            if(m_producers[i].enabled) n++;
        return n;
    }

    //=== Statistics ===
    int TotalCollectCalls(void)     const { return m_total_collect_calls; }
    int TotalSignalsCollected(void) const { return m_total_signals_collected; }

    void ResetStats(void)
    {
        m_total_collect_calls    = 0;
        m_total_signals_collected = 0;
    }
};

#endif // ATLAS_SIGNAL_COLLECTOR_MQH
//+------------------------------------------------------------------+
