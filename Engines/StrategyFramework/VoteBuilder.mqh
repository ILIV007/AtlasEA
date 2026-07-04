//+------------------------------------------------------------------+
//|             Engines/StrategyFramework/VoteBuilder.mqh            |
//|       AtlasEA v0.1.10.0 - Immutable Vote Construction            |
//+------------------------------------------------------------------+
#ifndef ATLAS_VOTE_BUILDER_MQH
#define ATLAS_VOTE_BUILDER_MQH

#include "../../Config/Settings.mqh"
#include "../../Contracts/MarketState.mqh"
#include "../../Contracts/RiskDecision.mqh"
#include "../../Engines/StrategyFramework/StrategyMetadata.mqh"
#include "../../Interfaces/ILogger.mqh"

/**
 * @class VoteBuilder
 * @brief Constructs validated, immutable StrategyVote objects.
 *
 * The only way to create a StrategyVote is through this builder.
 * It validates and normalizes all fields:
 *   - Confidence clamped to [0.0, 1.0]
 *   - Direction must be ATLAS_ORDER_BUY, ATLAS_ORDER_SELL, or ATLAS_ORDER_NONE
 *   - Prices must be > 0.0 (or 0.0 for abstention)
 *   - Snapshot ID must match the context
 *   - NaN/INF values replaced with 0.0
 *
 * Memory: stateless. No allocation.
 */
class VoteBuilder
{
private:
    ILogger *m_logger;

    /// @brief Clamp a value to [lo, hi]. NaN/INF → lo.
    double Clamp(const double v, const double lo, const double hi) const
    {
        if(!MathIsValidNumber(v)) return lo;
        if(v < lo) return lo;
        if(v > hi) return hi;
        return v;
    }

    /// @brief Sanitize a price: NaN/INF/negative → 0.0.
    double SanitizePrice(const double p) const
    {
        if(!MathIsValidNumber(p)) return 0.0;
        if(p < 0.0) return 0.0;
        return p;
    }

public:
    /**
     * @brief Constructor.
     * @param logger Optional logger (may be NULL).
     */
    VoteBuilder(ILogger *logger = NULL) { m_logger = logger; }

    /**
     * @brief Set the logger.
     */
    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Build a directional vote (BUY or SELL).
     *
     * @param vote        Output: the constructed vote.
     * @param metadata    Strategy metadata (for ID, version, weight).
     * @param direction   ATLAS_ORDER_BUY or ATLAS_ORDER_SELL.
     * @param confidence  Raw confidence (will be clamped to [0,1] and multiplied by weight).
     * @param entry_price Suggested entry price.
     * @param sl          Suggested stop-loss.
     * @param tp          Suggested take-profit.
     * @param volume      Suggested volume (0 = use default).
     * @param snapshot_id Current snapshot ID.
     * @return true if a valid directional vote was built, false on invalid input.
     */
    bool BuildDirectional(StrategyVote &vote,
                          const StrategyMetadata &metadata,
                          const int direction,
                          const double confidence,
                          const double entry_price,
                          const double sl,
                          const double tp,
                          const double volume,
                          const long snapshot_id) const;

    /**
     * @brief Build an abstention vote (direction = NONE, confidence = 0).
     *
     * @param vote        Output: the constructed vote.
     * @param metadata    Strategy metadata.
     * @param snapshot_id Current snapshot ID.
     * @return true always (abstention is always valid).
     */
    bool BuildAbstention(StrategyVote &vote,
                         const StrategyMetadata &metadata,
                         const long snapshot_id) const;

    /**
     * @brief Build a neutral vote (same as abstention, but for error recovery).
     * This is what the executor uses when a strategy fails.
     */
    bool BuildNeutral(StrategyVote &vote,
                      const StrategyMetadata &metadata,
                      const long snapshot_id) const
    {
        return BuildAbstention(vote, metadata, snapshot_id);
    }

    /**
     * @brief Validate a fully-constructed vote.
     * @param vote The vote to validate.
     * @param out_reason Output: reason if invalid.
     * @return true if valid.
     */
    bool Validate(const StrategyVote &vote, string &out_reason) const;
};

//+------------------------------------------------------------------+
//| VoteBuilder implementation                                        |
//+------------------------------------------------------------------+

bool VoteBuilder::BuildDirectional(StrategyVote &vote,
                                   const StrategyMetadata &metadata,
                                   const int direction,
                                   const double confidence,
                                   const double entry_price,
                                   const double sl,
                                   const double tp,
                                   const double volume,
                                   const long snapshot_id) const
{
    //--- Validate direction
    if(direction != ATLAS_ORDER_BUY && direction != ATLAS_ORDER_SELL)
    {
        if(m_logger != NULL)
            m_logger.Warn("VoteBuilder", "BuildDirectional: invalid direction " + IntegerToString(direction));
        return false;
    }

    //--- Validate snapshot ID
    if(snapshot_id <= 0)
    {
        if(m_logger != NULL)
            m_logger.Warn("VoteBuilder", "BuildDirectional: invalid snapshot_id");
        return false;
    }

    //--- Normalize confidence: clamp to [0,1], multiply by weight, clamp again
    double raw_conf = Clamp(confidence, 0.0, 1.0);
    double weighted = raw_conf * metadata.weight;
    double final_conf = Clamp(weighted, 0.0, 1.0);

    //--- Sanitize prices
    double clean_entry = SanitizePrice(entry_price);
    double clean_sl    = SanitizePrice(sl);
    double clean_tp    = SanitizePrice(tp);
    double clean_vol   = (MathIsValidNumber(volume) && volume >= 0.0) ? volume : 0.0;

    //--- Validate required prices for directional votes
    if(clean_entry <= 0.0)
    {
        if(m_logger != NULL)
            m_logger.Warn("VoteBuilder", "BuildDirectional: entry_price invalid");
        return false;
    }
    if(clean_sl <= 0.0)
    {
        if(m_logger != NULL)
            m_logger.Warn("VoteBuilder", "BuildDirectional: SL invalid");
        return false;
    }
    if(clean_tp <= 0.0)
    {
        if(m_logger != NULL)
            m_logger.Warn("VoteBuilder", "BuildDirectional: TP invalid");
        return false;
    }

    //--- Build the vote
    vote.strategy_id      = metadata.strategy_id;
    vote.strategy_version = metadata.version;
    vote.direction        = direction;
    vote.confidence       = final_conf;
    vote.suggested_volume = clean_vol;
    vote.suggested_entry  = clean_entry;
    vote.suggested_sl     = clean_sl;
    vote.suggested_tp     = clean_tp;
    vote.snapshot_id      = snapshot_id;
    vote.vote_time        = TimeCurrent();

    return true;
}

//+------------------------------------------------------------------+
bool VoteBuilder::BuildAbstention(StrategyVote &vote,
                                  const StrategyMetadata &metadata,
                                  const long snapshot_id) const
{
    vote.strategy_id      = metadata.strategy_id;
    vote.strategy_version = metadata.version;
    vote.direction        = ATLAS_ORDER_NONE;
    vote.confidence       = 0.0;
    vote.suggested_volume = 0.0;
    vote.suggested_entry  = 0.0;
    vote.suggested_sl     = 0.0;
    vote.suggested_tp     = 0.0;
    vote.snapshot_id      = snapshot_id;
    vote.vote_time        = TimeCurrent();
    return true;
}

//+------------------------------------------------------------------+
bool VoteBuilder::Validate(const StrategyVote &vote, string &out_reason) const
{
    out_reason = "";

    if(vote.strategy_id <= 0)
    {
        out_reason = "strategy_id <= 0";
        return false;
    }

    if(StringLen(vote.strategy_version) == 0)
    {
        out_reason = "strategy_version empty";
        return false;
    }

    if(vote.direction != ATLAS_ORDER_BUY &&
       vote.direction != ATLAS_ORDER_SELL &&
       vote.direction != ATLAS_ORDER_NONE)
    {
        out_reason = "invalid direction";
        return false;
    }

    if(!MathIsValidNumber(vote.confidence))
    {
        out_reason = "confidence is NaN/INF";
        return false;
    }

    if(vote.confidence < 0.0 || vote.confidence > 1.0)
    {
        out_reason = "confidence out of [0,1]";
        return false;
    }

    if(vote.snapshot_id <= 0)
    {
        out_reason = "snapshot_id <= 0";
        return false;
    }

    //--- For directional votes, prices must be valid
    if(vote.direction != ATLAS_ORDER_NONE)
    {
        if(!MathIsValidNumber(vote.suggested_entry) || vote.suggested_entry <= 0.0)
        {
            out_reason = "entry price invalid";
            return false;
        }
        if(!MathIsValidNumber(vote.suggested_sl) || vote.suggested_sl <= 0.0)
        {
            out_reason = "SL invalid";
            return false;
        }
        if(!MathIsValidNumber(vote.suggested_tp) || vote.suggested_tp <= 0.0)
        {
            out_reason = "TP invalid";
            return false;
        }
    }

    return true;
}

#endif // ATLAS_VOTE_BUILDER_MQH
//+------------------------------------------------------------------+
