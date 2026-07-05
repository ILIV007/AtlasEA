//+------------------------------------------------------------------+
//|                     Interfaces/ICacheManager.mqh                 |
//|       AtlasEA v1.0 Step 8 - Cache Manager Interface              |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICACHE_MANAGER_MQH
#define ATLAS_ICACHE_MANAGER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Cache entry type codes.
 */
#define ATLAS_CACHE_BROKER_CAPS      0   ///< Broker capabilities
#define ATLAS_CACHE_SYMBOL_PROPS     1   ///< Symbol properties
#define ATLAS_CACHE_INDICATOR_HANDLES 2  ///< Indicator handles
#define ATLAS_CACHE_VALIDATION       3   ///< Validation results
#define ATLAS_CACHE_OPTIMIZATION     4   ///< Optimization reports
#define ATLAS_CACHE_REPLAY_META      5   ///< Replay metadata
#define ATLAS_CACHE_CONFIG           6   ///< Configuration lookups
#define ATLAS_CACHE_COUNT            7   ///< Total cache types

/**
 * @struct CacheEntryStats
 * @brief Statistics for a single cache entry type.
 */
struct CacheEntryStats
{
    int    type;               ///< ATLAS_CACHE_*
    string name;               ///< Human-readable name
    ulong  hits;               ///< Cache hits
    ulong  misses;             ///< Cache misses
    ulong  invalidations;      ///< Manual invalidations
    ulong  expirations;        ///< TTL expirations
    ulong  refreshes;          ///< Manual refreshes
    datetime last_access;      ///< Last access time
    datetime last_refresh;     ///< Last refresh time
    int    age_sec;            ///< Current age in seconds
    bool   valid;              ///< Is the cache entry valid?

    CacheEntryStats(void)
    {
        type          = 0;
        name          = "";
        hits          = 0;
        misses        = 0;
        invalidations = 0;
        expirations   = 0;
        refreshes     = 0;
        last_access   = 0;
        last_refresh  = 0;
        age_sec       = 0;
        valid         = false;
    }

    double HitRatio(void) const
    {
        ulong total = hits + misses;
        return (total > 0) ? (double)hits / (double)total : 0.0;
    }
};

/**
 * @struct CacheStats
 * @brief Aggregated cache statistics.
 */
struct CacheStats
{
    CacheEntryStats entries[ATLAS_CACHE_COUNT];
    ulong total_hits;
    ulong total_misses;
    ulong total_invalidations;
    ulong total_expirations;
    ulong total_refreshes;
    int   valid_count;          ///< Number of currently valid entries

    CacheStats(void)
    {
        total_hits          = 0;
        total_misses        = 0;
        total_invalidations = 0;
        total_expirations   = 0;
        total_refreshes     = 0;
        valid_count         = 0;
    }

    double OverallHitRatio(void) const
    {
        ulong total = total_hits + total_misses;
        return (total > 0) ? (double)total_hits / (double)total : 0.0;
    }
};

/**
 * @class ICacheManager
 * @brief The ONLY interface for cache management.
 *
 * Implemented by CacheManager (Performance/). Consumed by CoreEngine
 * and any module that needs cached data.
 *
 * Contract:
 *   - Fixed-size, no heap allocation.
 *   - TTL-based expiration (configurable per cache type).
 *   - Supports Invalidate(), Refresh(), GetStats().
 *   - Hit/miss counters for monitoring.
 */
class ICacheManager
{
public:
    /**
     * @brief Check if a cache entry is valid (exists and not expired).
     */
    virtual bool IsValid(const int type) const = 0;

    /**
     * @brief Record a cache hit.
     */
    virtual void RecordHit(const int type) = 0;

    /**
     * @brief Record a cache miss.
     */
    virtual void RecordMiss(const int type) = 0;

    /**
     * @brief Invalidate a cache entry (force refresh on next access).
     */
    virtual void Invalidate(const int type) = 0;

    /**
     * @brief Invalidate all cache entries.
     */
    virtual void InvalidateAll(void) = 0;

    /**
     * @brief Refresh a cache entry (mark as refreshed, reset TTL).
     */
    virtual void Refresh(const int type) = 0;

    /**
     * @brief Check for expired entries and mark them invalid.
     * Called on maintenance interval.
     * @return Number of entries expired.
     */
    virtual int CheckExpirations(void) = 0;

    /**
     * @brief Get cache statistics.
     */
    virtual CacheStats GetStats(void) const = 0;

    /**
     * @brief Get statistics for a specific cache type.
     */
    virtual CacheEntryStats GetEntryStats(const int type) const = 0;

    /**
     * @brief Set the maximum cache age (TTL) for all entries.
     */
    virtual void SetMaxCacheAge(const int seconds) = 0;

    /**
     * @brief Log cache statistics.
     */
    virtual void LogStats(void) const = 0;

    virtual ~ICacheManager(void) {}
};

/**
 * @brief Get the name of a cache type.
 */
string CacheTypeName(const int type)
{
    switch(type)
    {
        case ATLAS_CACHE_BROKER_CAPS:      return "BrokerCaps";
        case ATLAS_CACHE_SYMBOL_PROPS:     return "SymbolProps";
        case ATLAS_CACHE_INDICATOR_HANDLES: return "IndicatorHandles";
        case ATLAS_CACHE_VALIDATION:       return "Validation";
        case ATLAS_CACHE_OPTIMIZATION:     return "Optimization";
        case ATLAS_CACHE_REPLAY_META:      return "ReplayMeta";
        case ATLAS_CACHE_CONFIG:           return "Config";
    }
    return "Unknown";
}

#endif // ATLAS_ICACHE_MANAGER_MQH
//+------------------------------------------------------------------+
