//+------------------------------------------------------------------+
//|                   Replay/ReplayValidator.mqh                    |
//|       AtlasEA v0.1.23.0 - Replay Data Validator                 |
//+------------------------------------------------------------------+
#ifndef ATLAS_REPLAY_VALIDATOR_MQH
#define ATLAS_REPLAY_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Events/EventMetadata.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct ReplayValidationReport
 * @brief Result of validating replay data.
 */
struct ReplayValidationReport
{
    bool   valid;
    int    error_count;
    int    warning_count;
    string errors[16];
    string warnings[16];
    int    error_idx;
    int    warning_idx;
    long   first_sequence;
    long   last_sequence;
    int    total_events;
    int    missing_events;       ///< Gaps in sequence
    int    duplicate_events;     ///< Duplicate sequence numbers
    int    invalid_timestamps;   ///< Zero or out-of-order timestamps
};

/**
 * @class ReplayValidator
 * @brief Validates event data before replay.
 *
 * Checks:
 *   - Snapshot consistency (checksum verification)
 *   - Sequence continuity (no gaps)
 *   - Missing events (gaps in sequence)
 *   - Invalid timestamps (zero, out-of-order)
 *   - Duplicate sequence IDs
 */
class ReplayValidator
{
private:
    ILogger *m_logger;

    void AddError(ReplayValidationReport &report, const string msg) const
    {
        if(report.error_idx < 16)
        {
            report.errors[report.error_idx] = msg;
            report.error_idx++;
            report.error_count++;
        }
    }

    void AddWarning(ReplayValidationReport &report, const string msg) const
    {
        if(report.warning_idx < 16)
        {
            report.warnings[report.warning_idx] = msg;
            report.warning_idx++;
            report.warning_count++;
        }
    }

public:
    /**
     * @brief Constructor.
     */
    ReplayValidator(void) { m_logger = NULL; }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Validate an array of sourced events.
     * @param events Array of sourced events.
     * @param count Number of events.
     * @return ReplayValidationReport with details.
     */
    ReplayValidationReport Validate(const SourcedEvent &events[], const int count) const
    {
        ReplayValidationReport report;
        report.valid             = true;
        report.error_count       = 0;
        report.warning_count     = 0;
        report.error_idx         = 0;
        report.warning_idx       = 0;
        report.first_sequence    = 0;
        report.last_sequence     = 0;
        report.total_events      = count;
        report.missing_events    = 0;
        report.duplicate_events  = 0;
        report.invalid_timestamps = 0;

        if(count == 0)
        {
            report.valid = false;
            AddError(report, "No events to validate");
            return report;
        }

        report.first_sequence = events[0].metadata.sequence;
        report.last_sequence  = events[count - 1].metadata.sequence;

        datetime prev_timestamp = 0;
        long     prev_sequence  = 0;
        datetime first_ts = events[0].event.timestamp;
        datetime last_ts  = events[count - 1].event.timestamp;

        for(int i = 0; i < count; i++)
        {
            const SourcedEvent &se = events[i];

            //=== Check 1: Sequence continuity ===
            if(i > 0)
            {
                long expected = prev_sequence + 1;
                if(se.metadata.sequence != expected)
                {
                    if(se.metadata.sequence == prev_sequence)
                    {
                        //--- Duplicate
                        report.duplicate_events++;
                        AddError(report,
                            "Duplicate sequence: " + IntegerToString(se.metadata.sequence) +
                            " at index " + IntegerToString(i));
                        report.valid = false;
                    }
                    else if(se.metadata.sequence > expected)
                    {
                        //--- Gap
                        int gap = (int)(se.metadata.sequence - expected);
                        report.missing_events += gap;
                        AddWarning(report,
                            "Sequence gap: expected " + IntegerToString(expected) +
                            " got " + IntegerToString(se.metadata.sequence) +
                            " (" + IntegerToString(gap) + " missing)");
                    }
                    else
                    {
                        //--- Out of order / backward
                        AddError(report,
                            "Out-of-order sequence: " + IntegerToString(se.metadata.sequence) +
                            " after " + IntegerToString(prev_sequence));
                        report.valid = false;
                    }
                }
            }

            //=== Check 2: Timestamp validity ===
            if(se.event.timestamp <= 0)
            {
                report.invalid_timestamps++;
                AddError(report,
                    "Invalid timestamp (zero) at sequence " + IntegerToString(se.metadata.sequence));
                report.valid = false;
            }
            else if(i > 0 && se.event.timestamp < prev_timestamp)
            {
                report.invalid_timestamps++;
                AddError(report,
                    "Backward timestamp at sequence " + IntegerToString(se.metadata.sequence) +
                    " (" + IntegerToString((long)se.event.timestamp) +
                    " < " + IntegerToString((long)prev_timestamp) + ")");
                report.valid = false;
            }

            //=== Check 2b: Future timestamp beyond replay range ===
            if(se.event.timestamp > last_ts)
            {
                report.invalid_timestamps++;
                AddError(report,
                    "Future timestamp beyond replay range at sequence " + IntegerToString(se.metadata.sequence));
                report.valid = false;
            }

            //=== Check 3: Event type validity ===
            if(se.event.type < EV_TICK_RECEIVED || se.event.type > EV_KILL_SWITCH_ACTIVATED)
            {
                AddError(report,
                    "Invalid event type at sequence " + IntegerToString(se.metadata.sequence) +
                    ": " + IntegerToString((int)se.event.type));
                report.valid = false;
            }

            //=== Check 4: Checksum (if payload present) ===
            if(se.event.payload_size > 0 && se.metadata.checksum == 0)
            {
                AddWarning(report,
                    "Missing checksum at sequence " + IntegerToString(se.metadata.sequence));
            }

            prev_sequence  = se.metadata.sequence;
            prev_timestamp = se.event.timestamp;
        }

        //=== Log result ===
        if(m_logger != NULL)
        {
            if(report.valid)
                m_logger.Info("ReplayValidator",
                    "Validation PASSED: " + IntegerToString(count) + " events, " +
                    IntegerToString(report.missing_events) + " missing, " +
                    IntegerToString(report.duplicate_events) + " duplicates, " +
                    IntegerToString(report.invalid_timestamps) + " bad timestamps");
            else
                m_logger.Error("ReplayValidator",
                    "Validation FAILED: " + IntegerToString(report.error_count) + " errors");
        }

        return report;
    }
};

#endif // ATLAS_REPLAY_VALIDATOR_MQH
//+------------------------------------------------------------------+
