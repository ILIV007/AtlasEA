//+------------------------------------------------------------------+
//|                    Core/ValidationResult.mqh                     |
//|       AtlasEA v0.1.26.x - Canonical Validation Result            |
//+------------------------------------------------------------------+
#ifndef ATLAS_VALIDATION_RESULT_MQH
#define ATLAS_VALIDATION_RESULT_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Validation severity / error codes.
 *
 * Used by ValidationResult.code to categorize failures.
 * Values are stable for logging and diagnostics.
 */
#define ATLAS_V_OK              0   ///< Validation passed
#define ATLAS_V_EMPTY_FIELD     1   ///< Required field is empty
#define ATLAS_V_INVALID_RANGE   2   ///< Value outside valid range
#define ATLAS_V_NAN             3   ///< Value is NaN / INF
#define ATLAS_V_INCONSISTENT    4   ///< Fields are mutually inconsistent
#define ATLAS_V_INVALID_ENUM    5   ///< Enum value out of range
#define ATLAS_V_MONOTONICITY    6   ///< Monotonic counter violated
#define ATLAS_V_DUPLICATE       7   ///< Duplicate identifier detected
#define ATLAS_V_CORRUPT         8   ///< Data corruption detected
#define ATLAS_V_OVERFLOW        9   ///< Buffer overflow / capacity exceeded
#define ATLAS_V_UNDERFLOW      10   ///< Read from empty structure
#define ATLAS_V_NOT_INITIALIZED 11  ///< Object not initialized

/**
 * @struct ValidationResult
 * @brief Canonical result returned by every Validate() method.
 *
 * Design by contract: every critical object exposes Validate() returning
 * this struct. The caller decides the failure policy, but the struct
 * always carries a precise reason.
 *
 * Failure policy:
 *   - Never crash (no exceptions in MQL5).
 *   - Never silently continue (always log the reason if logger available).
 *   - Return explicit result with code + reason + field name.
 *
 * Memory: fixed-size (~1 KB max for reason + field strings). No allocation
 * on the hot path beyond the struct itself.
 */
struct ValidationResult
{
    bool   valid;          ///< true if validation passed
    int    code;           ///< ATLAS_V_* error code (ATLAS_V_OK if valid)
    string reason;         ///< Human-readable explanation
    string field;          ///< Name of the offending field (if applicable)

    /**
     * @brief Default constructor — produces a "valid" result.
     */
    ValidationResult(void)
    {
        valid   = true;
        code    = ATLAS_V_OK;
        reason  = "";
        field   = "";
    }

    /**
     * @brief Construct a failed result with code + reason.
     */
    static ValidationResult Fail(const int err_code,
                                 const string err_reason,
                                 const string err_field = "")
    {
        ValidationResult r;
        r.valid  = false;
        r.code   = err_code;
        r.reason = err_reason;
        r.field  = err_field;
        return r;
    }

    /**
     * @brief Construct a passing result.
     */
    static ValidationResult Ok(void)
    {
        ValidationResult r;
        r.valid = true;
        r.code  = ATLAS_V_OK;
        return r;
    }

    /**
     * @brief Format a one-line summary for logging.
     */
    string Summary(void) const
    {
        if(valid) return "OK";
        string s = "FAIL code=" + IntegerToString(code) + " field='" + field + "' " + reason;
        return s;
    }
};

#endif // ATLAS_VALIDATION_RESULT_MQH
//+------------------------------------------------------------------+
