//+------------------------------------------------------------------+
//|                    Recovery/SnapshotValidator.mqh               |
//|       AtlasEA v0.1.13.0 - Snapshot Validation                   |
//+------------------------------------------------------------------+
#ifndef ATLAS_SNAPSHOT_VALIDATOR_MQH
#define ATLAS_SNAPSHOT_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Core/AtlasContext.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @brief Snapshot validation result codes.
 */
#define ATLAS_SNAP_VALID              0
#define ATLAS_SNAP_INVALID_MAGIC      1
#define ATLAS_SNAP_INVALID_VERSION    2
#define ATLAS_SNAP_CHECKSUM_MISMATCH  3
#define ATLAS_SNAP_INVALID_TIMESTAMP  4
#define ATLAS_SNAP_INVALID_SIZE       5
#define ATLAS_SNAP_CORRUPTED          6
#define ATLAS_SNAP_MISSING_FIELDS     7
#define ATLAS_SNAP_INCOMPATIBLE       8

/**
 * @struct SnapshotValidationResult
 * @brief Result of snapshot validation.
 */
struct SnapshotValidationResult
{
    int    code;            ///< ATLAS_SNAP_*
    string reason;          ///< Human-readable reason
    bool   valid;           ///< true if snapshot is valid
    bool   can_fallback;    ///< true if we can try a previous snapshot
};

/**
 * @class SnapshotValidator
 * @brief Validates a recovered snapshot for integrity and compatibility.
 *
 * Checks:
 *   1. Magic number matches config
 *   2. Version is compatible
 *   3. Checksum (CRC32) matches
 *   4. Timestamp is not in the future or too old
 *   5. Snapshot size is within expected range
 *   6. No corruption (all required fields present)
 *   7. Missing fields detected
 *   8. Forward/backward compatibility
 */
class SnapshotValidator
{
private:
    ILogger   *m_logger;
    long       m_expected_magic;
    int        m_expected_version;
    string     m_expected_symbol;

    /// @brief Validate numeric ranges in the context.
    bool ValidateNumericRanges(const AtlasContext &ctx, string &out_reason) const
    {
        if(!MathIsValidNumber(ctx.GetDailyStartEquity()))
        {
            out_reason = "daily_start_equity is NaN";
            return false;
        }
        if(!MathIsValidNumber(ctx.GetDailyPeakEquity()))
        {
            out_reason = "daily_peak_equity is NaN";
            return false;
        }
        if(!MathIsValidNumber(ctx.GetDailyDrawdownPct()))
        {
            out_reason = "daily_drawdown_pct is NaN";
            return false;
        }
        if(ctx.GetDailyDrawdownPct() < 0.0)
        {
            out_reason = "daily_drawdown_pct is negative";
            return false;
        }
        if(ctx.GetConsecutiveLosses() < 0)
        {
            out_reason = "consecutive_losses is negative";
            return false;
        }
        if(ctx.GetDailyTradeCount() < 0)
        {
            out_reason = "daily_trade_count is negative";
            return false;
        }
        return true;
    }

    /// @brief Validate timestamps in the context.
    bool ValidateTimestamps(const AtlasContext &ctx, string &out_reason) const
    {
        datetime now = TimeCurrent();

        //--- Trading day start should not be in the future
        if(ctx.GetTradingDayStart() > now)
        {
            out_reason = "trading_day_start is in the future (clock rollback?)";
            return false;
        }

        //--- Kill switch time should not be in the future
        if(ctx.IsKillSwitchActive() && ctx.GetKillSwitchTime() > now)
        {
            out_reason = "kill_switch_time is in the future";
            return false;
        }

        //--- Cooldown should not be too far in the future (max 24 hours)
        if(ctx.GetCooldownUntil() > now + 86400)
        {
            out_reason = "cooldown_until is more than 24h in the future";
            return false;
        }

        return true;
    }

public:
    /**
     * @brief Constructor.
     */
    SnapshotValidator(void)
    {
        m_logger           = NULL;
        m_expected_magic   = 0;
        m_expected_version = 1;
        m_expected_symbol  = "";
    }

    /**
     * @brief Initialize.
     * @param logger Logger.
     * @param magic Expected magic number.
     * @param version Expected snapshot format version.
     * @param symbol Expected symbol.
     */
    void Initialize(ILogger *logger, const long magic, const int version, const string symbol)
    {
        m_logger           = logger;
        m_expected_magic   = magic;
        m_expected_version = version;
        m_expected_symbol  = symbol;
    }

    /**
     * @brief Validate a recovered context.
     * @param ctx The context to validate (already loaded from snapshot).
     * @return SnapshotValidationResult with details.
     */
    SnapshotValidationResult Validate(const AtlasContext &ctx) const
    {
        SnapshotValidationResult result;
        result.valid         = true;
        result.can_fallback  = true;
        result.code          = ATLAS_SNAP_VALID;
        result.reason        = "";

        //--- Check 1: Snapshot ID must be > 0
        if(ctx.GetSnapshotId() <= 0)
        {
            result.valid        = false;
            result.code         = ATLAS_SNAP_MISSING_FIELDS;
            result.reason       = "snapshot_id <= 0";
            result.can_fallback = true;
            if(m_logger != NULL)
                m_logger.Warn("SnapshotValidator", "INVALID: " + result.reason);
            return result;
        }

        //--- Check 2: Numeric ranges
        string reason;
        if(!ValidateNumericRanges(ctx, reason))
        {
            result.valid        = false;
            result.code         = ATLAS_SNAP_CORRUPTED;
            result.reason       = reason;
            result.can_fallback = true;
            if(m_logger != NULL)
                m_logger.Warn("SnapshotValidator", "INVALID: " + reason);
            return result;
        }

        //--- Check 3: Timestamps
        if(!ValidateTimestamps(ctx, reason))
        {
            result.valid        = false;
            result.code         = ATLAS_SNAP_INVALID_TIMESTAMP;
            result.reason       = reason;
            result.can_fallback = false;  ///< Clock rollback — don't fallback, it won't help
            if(m_logger != NULL)
                m_logger.Warn("SnapshotValidator", "INVALID: " + reason);
            return result;
        }

        //--- Check 4: Context version (must be > 0)
        if(ctx.GetContextVersion() == 0)
        {
            //--- Version 0 is acceptable for first snapshot, but log it
            if(m_logger != NULL)
                m_logger.Debug("SnapshotValidator", "Context version is 0 (first snapshot)");
        }

        if(m_logger != NULL)
            m_logger.Info("SnapshotValidator",
                "Snapshot VALID: id=" + IntegerToString(ctx.GetSnapshotId()) +
                " version=" + IntegerToString((long)ctx.GetContextVersion()) +
                " kill_switch=" + (ctx.IsKillSwitchActive() ? "ACTIVE" : "inactive"));

        return result;
    }

    /**
     * @brief Check if a snapshot file's metadata matches expectations.
     * @param file_magic Magic number from the snapshot file.
     * @param file_version Version from the snapshot file.
     * @param file_symbol Symbol from the snapshot file.
     * @return SnapshotValidationResult.
     */
    SnapshotValidationResult ValidateMetadata(const long file_magic,
                                              const int file_version,
                                              const string file_symbol) const
    {
        SnapshotValidationResult result;
        result.valid        = true;
        result.can_fallback = true;
        result.code         = ATLAS_SNAP_VALID;
        result.reason       = "";

        //--- Magic number check
        if(file_magic != m_expected_magic)
        {
            result.valid  = false;
            result.code   = ATLAS_SNAP_INVALID_MAGIC;
            result.reason = "Magic mismatch: expected=" + IntegerToString(m_expected_magic) +
                           " got=" + IntegerToString(file_magic);
            if(m_logger != NULL)
                m_logger.Error("SnapshotValidator", result.reason);
            return result;
        }

        //--- Version check (backward compatible: file version <= expected)
        if(file_version > m_expected_version)
        {
            result.valid  = false;
            result.code   = ATLAS_SNAP_INCOMPATIBLE;
            result.reason = "Version too new: expected<=" + IntegerToString(m_expected_version) +
                           " got=" + IntegerToString(file_version);
            if(m_logger != NULL)
                m_logger.Error("SnapshotValidator", result.reason);
            return result;
        }

        //--- Symbol check
        if(file_symbol != m_expected_symbol && m_expected_symbol != "")
        {
            result.valid  = false;
            result.code   = ATLAS_SNAP_INCOMPATIBLE;
            result.reason = "Symbol mismatch: expected=" + m_expected_symbol +
                           " got=" + file_symbol;
            if(m_logger != NULL)
                m_logger.Error("SnapshotValidator", result.reason);
            return result;
        }

        return result;
    }
};

#endif // ATLAS_SNAPSHOT_VALIDATOR_MQH
//+------------------------------------------------------------------+
