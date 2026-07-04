//+------------------------------------------------------------------+
//|                    Interfaces/IPluginMetadata.mqh               |
//|       AtlasEA v0.1.17.0 - Plugin Metadata Interface             |
//+------------------------------------------------------------------+
#ifndef ATLAS_IPLUGIN_METADATA_MQH
#define ATLAS_IPLUGIN_METADATA_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Plugin category codes.
 */
#define ATLAS_PLUGIN_CAT_STRATEGY     0
#define ATLAS_PLUGIN_CAT_INDICATOR    1
#define ATLAS_PLUGIN_CAT_RISK         2
#define ATLAS_PLUGIN_CAT_EXECUTION    3
#define ATLAS_PLUGIN_CAT_UTILITIES    4
#define ATLAS_PLUGIN_CAT_CUSTOM       5

/**
 * @brief Risk level codes.
 */
#define ATLAS_RISK_CONSERVATIVE   0
#define ATLAS_RISK_MODERATE       1
#define ATLAS_RISK_AGGRESSIVE     2
#define ATLAS_RISK_EXPERIMENTAL   3

/**
 * @brief Capability bit flags.
 */
#define ATLAS_CAP_ON_MARKET       0x0001   ///< Can receive tick-level callbacks
#define ATLAS_CAP_ON_BAR          0x0002   ///< Can receive bar-close callbacks
#define ATLAS_CAP_ON_TIMER        0x0004   ///< Can receive timer callbacks
#define ATLAS_CAP_EVALUATE        0x0008   ///< Can produce trade votes
#define ATLAS_CAP_MULTI_SYMBOL    0x0010   ///< Supports multiple symbols
#define ATLAS_CAP_MULTI_TIMEFRAME 0x0020   ///< Supports multiple timeframes
#define ATLAS_CAP_HEDGE_AWARE     0x0040   ///< Understands hedging
#define ATLAS_CAP_NEWS_AWARE      0x0080   ///< Reacts to news events
#define ATLAS_CAP_STATEFUL        0x0100   ///< Maintains internal state across ticks

/**
 * @struct PluginMetadata
 * @brief Immutable descriptor for a plugin.
 */
struct PluginMetadata
{
    string   name;                  ///< Plugin name (max 64 chars)
    string   version;               ///< Semantic version (e.g., "1.0.0")
    string   author;                ///< Author name
    string   description;           ///< Short description (max 256 chars)
    int      sdk_version;           ///< Minimum SDK version required
    int      atlas_version;         ///< Compatible AtlasEA version
    int      build_number;          ///< Plugin build number
    int      category;              ///< ATLAS_PLUGIN_CAT_*
    int      risk_level;            ///< ATLAS_RISK_*
    string   supported_symbols;     ///< Comma-separated, or "*" for all
    string   supported_timeframes;  ///< Comma-separated (M1,M5,M15,H1,H4,D1), or "*"
    int      capabilities;          ///< Bitmask of ATLAS_CAP_*
    int      priority;              ///< Execution priority (lower = first)
    double   weight;                ///< Confidence multiplier [0.1, 2.0]
    bool     enabled;               ///< Runtime enable/disable
    int      plugin_id;             ///< Unique plugin ID (> 0)

    /**
     * @brief Default constructor.
     */
    PluginMetadata(void)
    {
        name               = "";
        version            = "1.0.0";
        author             = "";
        description        = "";
        sdk_version        = 1;
        atlas_version      = 1;
        build_number       = 1;
        category           = ATLAS_PLUGIN_CAT_STRATEGY;
        risk_level         = ATLAS_RISK_MODERATE;
        supported_symbols  = "*";
        supported_timeframes = "*";
        capabilities       = ATLAS_CAP_EVALUATE;
        priority           = 100;
        weight             = 1.0;
        enabled            = true;
        plugin_id          = 0;
    }

    /**
     * @brief Check if this plugin supports a given symbol.
     */
    bool SupportsSymbol(const string symbol) const
    {
        if(supported_symbols == "*") return true;
        return (StringFind(supported_symbols, symbol) >= 0);
    }

    /**
     * @brief Check if this plugin supports a given timeframe string.
     */
    bool SupportsTimeframe(const string tf) const
    {
        if(supported_timeframes == "*") return true;
        return (StringFind(supported_timeframes, tf) >= 0);
    }

    /**
     * @brief Check if this plugin has a specific capability.
     */
    bool HasCapability(const int cap_flag) const
    {
        return (capabilities & cap_flag) != 0;
    }

    /**
     * @brief Validate the metadata for completeness.
     */
    bool Validate(string &out_reason) const
    {
        if(plugin_id <= 0)
        {
            out_reason = "plugin_id must be > 0";
            return false;
        }
        if(StringLen(name) == 0)
        {
            out_reason = "name is empty";
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

/**
 * @class IPluginMetadata
 * @brief Interface for accessing plugin metadata.
 *
 * Every plugin must expose its metadata through this interface.
 */
class IPluginMetadata
{
public:
    virtual const PluginMetadata& GetMetadata(void) const = 0;
    virtual ~IPluginMetadata(void) {}
};

#endif // ATLAS_IPLUGIN_METADATA_MQH
//+------------------------------------------------------------------+
