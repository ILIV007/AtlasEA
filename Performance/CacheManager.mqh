//+------------------------------------------------------------------+
//|                     Performance/CacheManager.mqh                 |
//|       AtlasEA v1.0 Step 8 - Cache Manager Implementation         |
//+------------------------------------------------------------------+
#ifndef ATLAS_CACHE_MANAGER_MQH
#define ATLAS_CACHE_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/ICacheManager.mqh"

/**
 * @class CacheManager
 * @brief Reusable cache layer with TTL, hit/miss tracking, and statistics.
 *
 * Implements ICacheManager. Provides a unified cache for:
 *   - Broker capabilities
 *   - Symbol properties
 *   - Indicator handles
 *   - Validation results
 *   - Optimization reports
 *   - Replay metadata
 *   - Configuration lookups
 *
 * Features:
 *   - TTL-based expiration (configurable per cache type or global)
 *   - Hit/miss/invalidation/expiration/refresh counters
 *   - Invalidate() / Refresh() / CheckExpirations()
 *   - Overall hit ratio monitoring
 *   - No heap allocation (fixed-size structs)
 *
 * Performance: O(1) per operation. No allocation.
 * Memory: ~1 KB (7 CacheEntryStats × ~120 bytes + overhead).
 */
class CacheManager : public ICacheManager
{
private:
    ILogger       *m_logger;
    CacheEntryStats m_entries[ATLAS_CACHE_COUNT];
    int            m_max_cache_age_sec;  ///< Global TTL
    bool           m_initialized;

public:
    CacheManager(void)
    {
        m_logger         = NULL;
        m_max_cache_age_sec = 300; // 5 minutes default
        m_initialized    = false;

        //--- Initialize entry names
        for(int i = 0; i < ATLAS_CACHE_COUNT; i++)
        {
            m_entries[i].type  = i;
            m_entries[i].name  = CacheTypeName(i);
            m_entries[i].valid = false;
        }
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    bool Initialize(void)
    {
        m_initialized = true;
        if(m_logger != NULL)
            m_logger.Info("CacheManager",
                "Initialized. TTL=" + IntegerToString(m_max_cache_age_sec) + "s");
        return true;
    }

    void Shutdown(void)
    {
        InvalidateAll();
        m_initialized = false;
    }

    //=== ICacheManager implementation ===

    virtual bool IsValid(const int type) const override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT) return false;
        if(!m_entries[type].valid) return false;
        //--- Check TTL
        if(m_max_cache_age_sec > 0 && m_entries[type].last_refresh > 0)
        {
            long age = (long)TimeCurrent() - (long)m_entries[type].last_refresh;
            if(age > m_max_cache_age_sec) return false;
        }
        return true;
    }

    virtual void RecordHit(const int type) override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT) return;
        m_entries[type].hits++;
        m_entries[type].last_access = TimeCurrent();
        m_entries[type].age_sec = (m_entries[type].last_refresh > 0)
            ? (int)((long)TimeCurrent() - (long)m_entries[type].last_refresh) : 0;
    }

    virtual void RecordMiss(const int type) override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT) return;
        m_entries[type].misses++;
    }

    virtual void Invalidate(const int type) override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT) return;
        if(m_entries[type].valid)
            m_entries[type].invalidations++;
        m_entries[type].valid = false;
    }

    virtual void InvalidateAll(void) override
    {
        for(int i = 0; i < ATLAS_CACHE_COUNT; i++)
        {
            if(m_entries[i].valid)
                m_entries[i].invalidations++;
            m_entries[i].valid = false;
        }
    }

    virtual void Refresh(const int type) override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT) return;
        m_entries[type].valid        = true;
        m_entries[type].last_refresh = TimeCurrent();
        m_entries[type].refreshes++;
        m_entries[type].age_sec      = 0;
    }

    virtual int CheckExpirations(void) override
    {
        int expired = 0;
        if(m_max_cache_age_sec <= 0) return 0;

        datetime now = TimeCurrent();
        for(int i = 0; i < ATLAS_CACHE_COUNT; i++)
        {
            if(!m_entries[i].valid) continue;
            if(m_entries[i].last_refresh > 0)
            {
                long age = (long)now - (long)m_entries[i].last_refresh;
                if(age > m_max_cache_age_sec)
                {
                    m_entries[i].valid = false;
                    m_entries[i].expirations++;
                    expired++;
                }
            }
        }

        if(expired > 0 && m_logger != NULL)
            m_logger.Debug("CacheManager",
                "Expired " + IntegerToString(expired) + " cache entries");
        return expired;
    }

    virtual CacheStats GetStats(void) const override
    {
        CacheStats stats;
        stats.valid_count = 0;

        for(int i = 0; i < ATLAS_CACHE_COUNT; i++)
        {
            stats.entries[i] = m_entries[i];
            stats.total_hits          += m_entries[i].hits;
            stats.total_misses        += m_entries[i].misses;
            stats.total_invalidations += m_entries[i].invalidations;
            stats.total_expirations   += m_entries[i].expirations;
            stats.total_refreshes     += m_entries[i].refreshes;
            if(m_entries[i].valid) stats.valid_count++;
        }
        return stats;
    }

    virtual CacheEntryStats GetEntryStats(const int type) const override
    {
        if(type < 0 || type >= ATLAS_CACHE_COUNT)
        {
            CacheEntryStats empty;
            return empty;
        }
        return m_entries[type];
    }

    virtual void SetMaxCacheAge(const int seconds) override
    {
        m_max_cache_age_sec = seconds;
    }

    virtual void LogStats(void) const override
    {
        if(m_logger == NULL) return;

        CacheStats stats = GetStats();
        m_logger.Info("CacheManager",
            "Overall hit ratio: " + DoubleToString(stats.OverallHitRatio() * 100.0, 1) + "%" +
            " hits=" + IntegerToString((long)stats.total_hits) +
            " misses=" + IntegerToString((long)stats.total_misses) +
            " valid=" + IntegerToString(stats.valid_count) + "/" +
            IntegerToString(ATLAS_CACHE_COUNT) +
            " expirations=" + IntegerToString((long)stats.total_expirations));

        for(int i = 0; i < ATLAS_CACHE_COUNT; i++)
        {
            const CacheEntryStats &e = stats.entries[i];
            m_logger.Info("CacheManager",
                "  " + e.name +
                " valid=" + (e.valid ? "Y" : "N") +
                " hits=" + IntegerToString((long)e.hits) +
                " misses=" + IntegerToString((long)e.misses) +
                " ratio=" + DoubleToString(e.HitRatio() * 100.0, 1) + "%" +
                " age=" + IntegerToString(e.age_sec) + "s");
        }
    }
};

#endif // ATLAS_CACHE_MANAGER_MQH
//+------------------------------------------------------------------+
