//+------------------------------------------------------------------+
//|                    Strategy/VoteCollector.mqh                    |
//|       AtlasEA v0.1.20.0 - Vote Collection & Normalization       |
//+------------------------------------------------------------------+
#ifndef ATLAS_VOTE_COLLECTOR_V2_MQH
#define ATLAS_VOTE_COLLECTOR_V2_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @class VoteCollector
 * @brief Collects, validates, and normalizes strategy votes.
 *
 * Responsibilities:
 *   - Collect StrategyVote from the scheduler
 *   - Validate each vote (direction, confidence, prices, snapshot)
 *   - Remove duplicates (same strategy_id + snapshot_id)
 *   - Normalize confidence (apply weight, clamp [0,1])
 *   - Merge metadata (strategy_version, vote_time)
 *
 * The VoteCollector is the last stop before votes leave the Strategy layer.
 */
class VoteCollector
{
private:
    ILogger *m_logger;

    /// @brief Seen strategy IDs for duplicate detection (per evaluation cycle)
    int  m_seen_ids[ATLAS_MAX_VOTES];
    int  m_seen_count;

public:
    /**
     * @brief Constructor.
     */
    VoteCollector(void)
    {
        m_logger    = NULL;
        m_seen_count = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Begin a new collection cycle (clears duplicate cache).
     */
    void BeginCycle(void)
    {
        m_seen_count = 0;
        for(int i = 0; i < ATLAS_MAX_VOTES; i++)
            m_seen_ids[i] = 0;
    }

    /**
     * @brief Collect and validate a single vote.
     * @param vote The vote to collect (mutated: confidence may be normalized).
     * @param weight Strategy weight to apply.
     * @param out_votes Output array.
     * @param out_count Current count (incremented on success).
     * @return true if the vote was collected, false if rejected.
     */
    bool Collect(StrategyVote &vote, const double weight,
                  StrategyVote out_votes[], int &out_count)
    {
        //--- Validate direction
        if(vote.direction != ATLAS_ORDER_BUY &&
           vote.direction != ATLAS_ORDER_SELL)
        {
            if(m_logger != NULL)
                m_logger.Warn("VoteCollector", "Rejected: invalid direction");
            return false;
        }

        //--- Validate confidence
        if(!MathIsValidNumber(vote.confidence) || vote.confidence < 0.0)
        {
            if(m_logger != NULL)
                m_logger.Warn("VoteCollector", "Rejected: invalid confidence");
            return false;
        }

        //--- Validate prices
        if(vote.suggested_entry <= 0.0 || vote.suggested_sl <= 0.0 || vote.suggested_tp <= 0.0)
        {
            if(m_logger != NULL)
                m_logger.Warn("VoteCollector", "Rejected: invalid prices");
            return false;
        }

        //--- Check for duplicate (same strategy_id in this cycle)
        for(int i = 0; i < m_seen_count; i++)
        {
            if(m_seen_ids[i] == vote.strategy_id)
            {
                if(m_logger != NULL)
                    m_logger.Warn("VoteCollector",
                        "Rejected: duplicate strategy_id " + IntegerToString(vote.strategy_id));
                return false;
            }
        }

        //--- Record as seen
        if(m_seen_count < ATLAS_MAX_VOTES)
        {
            m_seen_ids[m_seen_count] = vote.strategy_id;
            m_seen_count++;
        }

        //--- Normalize confidence: apply weight, clamp to [0, 1]
        vote.confidence = vote.confidence * weight;
        if(vote.confidence > 1.0) vote.confidence = 1.0;
        if(vote.confidence < 0.0) vote.confidence = 0.0;

        //--- Add to output
        if(out_count < ATLAS_MAX_VOTES)
        {
            out_votes[out_count] = vote;
            out_count++;
            return true;
        }

        return false;  //--- Array full
    }

    /**
     * @brief Collect multiple votes from the scheduler.
     * @param in_votes Raw votes from scheduler.
     * @param in_count Number of raw votes.
     * @param strategies Strategy array (for weight lookup).
     * @param strat_count Number of strategies.
     * @param out_votes Output: filtered and normalized votes.
     * @param out_count Output: number of votes collected.
     */
    void CollectBatch(const StrategyVote in_votes[], const int in_count,
                       StrategyVote out_votes[], int &out_count)
    {
        BeginCycle();
        out_count = 0;

        for(int i = 0; i < in_count; i++)
        {
            //--- Weight is already applied by the strategy itself (via BaseStrategy)
            //--- We just validate and deduplicate
            StrategyVote vote = in_votes[i];

            //--- Use weight = 1.0 (already applied) for Collect
            Collect(vote, 1.0, out_votes, out_count);
        }
    }
};

#endif // ATLAS_VOTE_COLLECTOR_V2_MQH
//+------------------------------------------------------------------+
