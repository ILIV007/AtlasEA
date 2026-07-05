//+------------------------------------------------------------------+
//|                  Validation/DatasetFingerprint.mqh               |
//|       AtlasEA v1.0 Step 5.5 - Dataset Fingerprint                |
//+------------------------------------------------------------------+
#ifndef ATLAS_DATASET_FINGERPRINT_MQH
#define ATLAS_DATASET_FINGERPRINT_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IValidationManager.mqh"

/**
 * @struct DatasetFingerprint
 * @brief Deterministic fingerprint of the validation dataset.
 *
 * Used for:
 *   - Cache lookup (skip recomputation if fingerprint + config match)
 *   - Report provenance (which dataset was analyzed)
 *   - Reproducibility (same fingerprint → same results)
 *
 * The fingerprint is a hash of:
 *   - Symbol
 *   - Timeframe
 *   - Date range (from/to timestamps)
 *   - Trade count
 *   - First/last trade timestamps
 *   - Replay ID (if available)
 *
 * The hash is a simple deterministic CRC-like function (no cryptographic
 * guarantees, but sufficient for cache lookup and provenance).
 */
struct DatasetFingerprint
{
    string   symbol;              ///< Symbol analyzed
    int      timeframe_minutes;   ///< Timeframe in minutes
    datetime data_from;           ///< Dataset start time
    datetime data_to;             ///< Dataset end time
    int      trade_count;         ///< Number of trades
    datetime first_trade_time;    ///< First trade timestamp
    datetime last_trade_time;     ///< Last trade timestamp
    string   replay_id;           ///< Replay session ID (if available)
    ulong    dataset_hash;        ///< Deterministic hash of the dataset
    int      schema_version;      ///< Schema version used for this fingerprint

    DatasetFingerprint(void)
    {
        symbol            = "";
        timeframe_minutes = 0;
        data_from         = 0;
        data_to           = 0;
        trade_count       = 0;
        first_trade_time  = 0;
        last_trade_time   = 0;
        replay_id         = "";
        dataset_hash      = 0;
        schema_version    = 0;
    }
};

/**
 * @class FingerprintGenerator
 * @brief Generates deterministic dataset fingerprints.
 *
 * O(N) where N = number of trades. No heap allocation.
 */
class FingerprintGenerator
{
public:
    /**
     * @brief Generate a fingerprint from trade records.
     * @param trades Array of trade records.
     * @param count Number of trades.
     * @param symbol Symbol name.
     * @param timeframe_minutes Timeframe in minutes.
     * @param replay_id Replay session ID (empty if none).
     * @return DatasetFingerprint.
     */
    static DatasetFingerprint Generate(const TradeRecord &trades[], const int count,
                                        const string symbol,
                                        const int timeframe_minutes,
                                        const string replay_id)
    {
        DatasetFingerprint fp;
        fp.symbol            = symbol;
        fp.timeframe_minutes = timeframe_minutes;
        fp.trade_count       = count;
        fp.replay_id         = replay_id;
        fp.schema_version    = ATLAS_VALIDATION_SCHEMA_VERSION;

        if(count > 0)
        {
            fp.first_trade_time = trades[0].open_time;
            fp.last_trade_time  = trades[count - 1].close_time;
            fp.data_from        = trades[0].open_time;
            fp.data_to          = trades[count - 1].close_time;

            //--- Find actual min/max timestamps
            for(int i = 0; i < count; i++)
            {
                if(trades[i].open_time < fp.data_from || fp.data_from == 0)
                    fp.data_from = trades[i].open_time;
                if(trades[i].close_time > fp.data_to)
                    fp.data_to = trades[i].close_time;
            }
        }

        //--- Compute deterministic hash
        fp.dataset_hash = ComputeHash(trades, count, symbol, timeframe_minutes,
                                       fp.data_from, fp.data_to, replay_id);

        return fp;
    }

    /**
     * @brief Check if two fingerprints match.
     */
    static bool Matches(const DatasetFingerprint &a, const DatasetFingerprint &b)
    {
        return (a.dataset_hash == b.dataset_hash &&
                a.trade_count  == b.trade_count &&
                a.symbol       == b.symbol &&
                a.schema_version == b.schema_version);
    }

    /**
     * @brief Format fingerprint as a string for logging.
     */
    static string ToString(const DatasetFingerprint &fp)
    {
        return "FP[" + fp.symbol + " TF=" + IntegerToString(fp.timeframe_minutes) +
               "m trades=" + IntegerToString(fp.trade_count) +
               " hash=" + IntegerToString((long)fp.dataset_hash) +
               " schema=" + IntegerToString(fp.schema_version) + "]";
    }

private:
    /**
     * @brief Compute a deterministic hash of the dataset.
     *
     * Uses a simple FNV-1a-like hash over symbol + timeframe + date range
     * + trade count + trade PnLs. This is NOT cryptographically secure,
     * but is deterministic and sufficient for cache lookup.
     */
    static ulong ComputeHash(const TradeRecord &trades[], const int count,
                              const string symbol, const int timeframe,
                              const datetime from, const datetime to,
                              const string replay_id)
    {
        ulong hash = 14695981039346656037UL; // FNV offset basis (64-bit)

        //--- Hash symbol
        for(int i = 0; i < StringLen(symbol); i++)
        {
            hash ^= (ulong)StringGetCharacter(symbol, i);
            hash *= 1099511628211UL; // FNV prime
        }

        //--- Hash timeframe
        hash ^= (ulong)timeframe;
        hash *= 1099511628211UL;

        //--- Hash date range
        hash ^= (ulong)from;
        hash *= 1099511628211UL;
        hash ^= (ulong)to;
        hash *= 1099511628211UL;

        //--- Hash trade count
        hash ^= (ulong)count;
        hash *= 1099511628211UL;

        //--- Hash replay ID
        for(int i = 0; i < StringLen(replay_id); i++)
        {
            hash ^= (ulong)StringGetCharacter(replay_id, i);
            hash *= 1099511628211UL;
        }

        //--- Hash a sample of trade PnLs (first, middle, last for speed)
        if(count > 0)
        {
            //--- Hash first trade
            HashTrade(hash, trades[0]);
            //--- Hash middle trade
            if(count > 2) HashTrade(hash, trades[count / 2]);
            //--- Hash last trade
            if(count > 1) HashTrade(hash, trades[count - 1]);
        }

        return hash;
    }

    static void HashTrade(ulong &hash, const TradeRecord &t)
    {
        //--- Hash key fields (deterministic)
        hash ^= (ulong)(t.direction + 128);
        hash *= 1099511628211UL;
        //--- Hash PnL as integer (multiply to preserve precision)
        long pnl_int = (long)(t.realized_pnl * 100.0);
        hash ^= (ulong)pnl_int;
        hash *= 1099511628211UL;
        //--- Hash open time
        hash ^= (ulong)t.open_time;
        hash *= 1099511628211UL;
    }
};

#endif // ATLAS_DATASET_FINGERPRINT_MQH
//+------------------------------------------------------------------+
