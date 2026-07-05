//+------------------------------------------------------------------+
//|                     Validation/ValidationCache.mqh               |
//|       AtlasEA v1.0 Step 5.5 - Validation Cache                    |
//+------------------------------------------------------------------+
#ifndef ATLAS_VALIDATION_CACHE_MQH
#define ATLAS_VALIDATION_CACHE_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IValidationManager.mqh"
#include "ValidationConfig.mqh"
#include "DatasetFingerprint.mqh"

/**
 * @brief Maximum cached entries (fixed-size, no heap).
 */
#define ATLAS_VAL_CACHE_MAX_ENTRIES 16

/**
 * @struct CacheEntry
 * @brief A single cache entry.
 */
struct CacheEntry
{
    ulong  fingerprint_hash;     ///< Dataset fingerprint hash
    int    trade_count;          ///< Trade count (secondary match key)
    int    schema_version;       ///< Schema version at cache time
    int    scoring_profile;      ///< Scoring profile used
    double validation_score;     ///< Cached score
    int    confidence_level;     ///< Cached confidence
    int    verdict;              ///< Cached verdict
    datetime cached_at;          ///< When this was cached
    bool   valid;                ///< Is this slot in use?

    CacheEntry(void)
    {
        fingerprint_hash = 0;
        trade_count      = 0;
        schema_version   = 0;
        scoring_profile  = 0;
        validation_score = 0.0;
        confidence_level = 0;
        verdict          = ATLAS_VAL_INCOMPLETE;
        cached_at        = 0;
        valid            = false;
    }
};

/**
 * @class ValidationCache
 * @brief Fingerprint-based validation cache.
 *
 * SOLE RESPONSIBILITY: cache validation results keyed by dataset
 * fingerprint + config + schema version. If the same dataset is
 * analyzed with the same config and schema, reuse cached metrics
 * instead of recomputing.
 *
 * Cache key = (fingerprint_hash, trade_count, schema_version,
 *              scoring_profile)
 *
 * The cache is a fixed-size ring of ATLAS_VAL_CACHE_MAX_ENTRIES.
 * When full, the oldest entry is evicted (FIFO).
 *
 * Performance: O(C) where C = cache entries (max 16). No allocation.
 */
class ValidationCache
{
private:
    ILogger    *m_logger;
    CacheEntry  m_entries[ATLAS_VAL_CACHE_MAX_ENTRIES];
    int         m_count;
    int         m_next_slot;

public:
    ValidationCache(void)
    {
        m_logger   = NULL;
        m_count    = 0;
        m_next_slot = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Try to find a cached result.
     * @param fingerprint Dataset fingerprint.
     * @param config Validation config.
     * @param out_score Output: cached validation score.
     * @param out_confidence Output: cached confidence level.
     * @param out_verdict Output: cached verdict.
     * @return true if a cache hit was found.
     */
    bool TryGet(const DatasetFingerprint &fingerprint,
                const ValidationConfig &config,
                double &out_score, int &out_confidence, int &out_verdict)
    {
        for(int i = 0; i < ATLAS_VAL_CACHE_MAX_ENTRIES; i++)
        {
            if(!m_entries[i].valid) continue;

            //--- Match key: hash + trade_count + schema + scoring_profile
            if(m_entries[i].fingerprint_hash == fingerprint.dataset_hash &&
               m_entries[i].trade_count      == fingerprint.trade_count &&
               m_entries[i].schema_version   == config.schema_version &&
               m_entries[i].scoring_profile  == config.scoring_profile)
            {
                out_score     = m_entries[i].validation_score;
                out_confidence = m_entries[i].confidence_level;
                out_verdict    = m_entries[i].verdict;

                if(m_logger != NULL)
                    m_logger.Debug("ValidationCache",
                        "Cache HIT: hash=" + IntegerToString((long)fingerprint.dataset_hash) +
                        " score=" + DoubleToString(out_score, 1));
                return true;
            }
        }

        if(m_logger != NULL)
            m_logger.Debug("ValidationCache",
                "Cache MISS: hash=" + IntegerToString((long)fingerprint.dataset_hash));
        return false;
    }

    /**
     * @brief Store a result in the cache.
     * @param fingerprint Dataset fingerprint.
     * @param config Validation config.
     * @param score Validation score.
     * @param confidence Confidence level.
     * @param verdict Verdict.
     */
    void Put(const DatasetFingerprint &fingerprint,
             const ValidationConfig &config,
             const double score, const int confidence, const int verdict)
    {
        //--- Check if this entry already exists (update in place)
        for(int i = 0; i < ATLAS_VAL_CACHE_MAX_ENTRIES; i++)
        {
            if(m_entries[i].valid &&
               m_entries[i].fingerprint_hash == fingerprint.dataset_hash &&
               m_entries[i].trade_count      == fingerprint.trade_count &&
               m_entries[i].schema_version   == config.schema_version &&
               m_entries[i].scoring_profile  == config.scoring_profile)
            {
                m_entries[i].validation_score = score;
                m_entries[i].confidence_level = confidence;
                m_entries[i].verdict          = verdict;
                m_entries[i].cached_at        = TimeCurrent();
                return;
            }
        }

        //--- Add new entry (evict oldest if full)
        CacheEntry &entry = m_entries[m_next_slot];
        entry.fingerprint_hash = fingerprint.dataset_hash;
        entry.trade_count      = fingerprint.trade_count;
        entry.schema_version   = config.schema_version;
        entry.scoring_profile  = config.scoring_profile;
        entry.validation_score = score;
        entry.confidence_level = confidence;
        entry.verdict          = verdict;
        entry.cached_at        = TimeCurrent();
        entry.valid            = true;

        m_next_slot = (m_next_slot + 1) % ATLAS_VAL_CACHE_MAX_ENTRIES;
        if(m_count < ATLAS_VAL_CACHE_MAX_ENTRIES) m_count++;

        if(m_logger != NULL)
            m_logger.Debug("ValidationCache",
                "Cache PUT: hash=" + IntegerToString((long)fingerprint.dataset_hash) +
                " score=" + DoubleToString(score, 1) +
                " entries=" + IntegerToString(m_count));
    }

    /**
     * @brief Clear all cache entries.
     */
    void Clear(void)
    {
        for(int i = 0; i < ATLAS_VAL_CACHE_MAX_ENTRIES; i++)
            m_entries[i].valid = false;
        m_count    = 0;
        m_next_slot = 0;
    }

    /**
     * @brief Get the number of valid cache entries.
     */
    int Count(void) const { return m_count; }

    /**
     * @brief Check if caching is enabled.
     */
    static bool IsEnabled(const ValidationConfig &config)
    {
        return config.enable_cache;
    }
};

#endif // ATLAS_VALIDATION_CACHE_MQH
//+------------------------------------------------------------------+
