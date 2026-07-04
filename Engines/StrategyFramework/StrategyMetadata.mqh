//+------------------------------------------------------------------+
//|          Engines/StrategyFramework/StrategyMetadata.mqh          |
//|       AtlasEA v0.1.10.0 - Strategy Metadata Struct               |
//+------------------------------------------------------------------+
#ifndef ATLAS_STRATEGY_METADATA_MQH
#define ATLAS_STRATEGY_METADATA_MQH

#include "../../Config/Settings.mqh"

/**
 * @brief Strategy category codes (informational, for diagnostics).
 */
#define ATLAS_STRAT_CATEGORY_TREND       0
#define ATLAS_STRAT_CATEGORY_REVERSION   1
#define ATLAS_STRAT_CATEGORY_MOMENTUM    2
#define ATLAS_STRAT_CATEGORY_BREAKOUT    3
#define ATLAS_STRAT_CATEGORY_SCALPING    4
#define ATLAS_STRAT_CATEGORY_HEDGE       5
#define ATLAS_STRAT_CATEGORY_CUSTOM      6

/**
 * @brief Maximum lengths for metadata string fields.
 */
#define ATLAS_STRAT_NAME_MAX_LEN        32
#define ATLAS_STRAT_VERSION_MAX_LEN     16
#define ATLAS_STRAT_AUTHOR_MAX_LEN      32
#define ATLAS_STRAT_DESC_MAX_LEN        128
#define ATLAS_STRAT_SYMBOLS_MAX_LEN     64

/**
 * @struct StrategyMetadata
 * @brief Immutable descriptor for a strategy.
 *
 * Populated by the strategy in its constructor or Initialize().
 * Read by the registry, executor, and diagnostics.
 *
 * Memory: fixed-size (no dynamic arrays). All strings are MQL5 strings
 * (heap-managed by the runtime, but short and bounded).
 */
struct StrategyMetadata
{
    int      strategy_id;           ///< Unique strategy ID (> 0)
    string   name;                  ///< Human-readable name (max 32 chars)
    string   version;               ///< Version string, e.g. "1.0.0" (max 16 chars)
    string   author;                ///< Author name (max 32 chars)
    string   description;           ///< Short description (max 128 chars)
    int      required_features[ATLAS_FEATURE_SIZE]; ///< Bitmask: which features this strategy reads (1 = used, 0 = ignored)
    string   supported_symbols;     ///< Comma-separated symbol list, or "*" for all
    int      priority;              ///< Lower = higher priority (executed first)
    double   weight;                ///< Confidence multiplier [0.1, 2.0]
    bool     enabled;               ///< Runtime enable/disable flag
    int      category;              ///< ATLAS_STRAT_CATEGORY_*

    /**
     * @brief Default constructor — initializes to safe defaults.
     */
    StrategyMetadata(void)
    {
        strategy_id = 0;
        name        = "";
        version     = "";
        author      = "";
        description = "";
        supported_symbols = "*";
        priority    = 100;
        weight      = 1.0;
        enabled     = true;
        category    = ATLAS_STRAT_CATEGORY_CUSTOM;
        for(int i = 0; i < ATLAS_FEATURE_SIZE; i++)
            required_features[i] = 0;
    }

    /**
     * @brief Check if this strategy supports a given symbol.
     * @param symbol The symbol to check.
     * @return true if supported_symbols is "*" or contains the symbol.
     */
    bool SupportsSymbol(const string symbol) const
    {
        if(supported_symbols == "*") return true;
        return (StringFind(supported_symbols, symbol) >= 0);
    }

    /**
     * @brief Check if a feature index is marked as required.
     * @param feature_index The feature index (0..ATLAS_FEATURE_SIZE-1).
     * @return true if the strategy reads this feature.
     */
    bool RequiresFeature(const int feature_index) const
    {
        if(feature_index < 0 || feature_index >= ATLAS_FEATURE_SIZE) return false;
        return (required_features[feature_index] != 0);
    }

    /**
     * @brief Validate the metadata for internal consistency.
     * @param out_reason Output: reason string if invalid.
     * @return true if valid.
     */
    bool Validate(string &out_reason) const
    {
        if(strategy_id <= 0)
        {
            out_reason = "strategy_id must be > 0";
            return false;
        }
        if(StringLen(name) == 0)
        {
            out_reason = "name is empty";
            return false;
        }
        if(StringLen(name) > ATLAS_STRAT_NAME_MAX_LEN)
        {
            out_reason = "name exceeds " + IntegerToString(ATLAS_STRAT_NAME_MAX_LEN) + " chars";
            return false;
        }
        if(StringLen(version) == 0)
        {
            out_reason = "version is empty";
            return false;
        }
        if(weight < 0.1 || weight > 2.0)
        {
            out_reason = "weight out of range [0.1, 2.0]";
            return false;
        }
        if(priority < 0)
        {
            out_reason = "priority must be >= 0";
            return false;
        }
        out_reason = "";
        return true;
    }
};

#endif // ATLAS_STRATEGY_METADATA_MQH
//+------------------------------------------------------------------+
