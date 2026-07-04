//+------------------------------------------------------------------+
//|                    Testing/Assertions/Assert.mqh                |
//|       AtlasEA v0.1.15.0 - Assertion Library                      |
//+------------------------------------------------------------------+
#ifndef ATLAS_ASSERT_MQH
#define ATLAS_ASSERT_MQH

#include "../TestingConfig.mqh"

/**
 * @struct AssertResult
 * @brief Result of a single assertion.
 */
struct AssertResult
{
    bool   passed;
    string message;
    string expected;
    string actual;
};

/**
 * @class Assert
 * @brief Static assertion library for unit tests.
 *
 * All methods return AssertResult. The TestRunner collects results
 * and produces a report.
 *
 * Usage:
 *   AssertResult r = Assert.IsTrue("check flag", flag);
 *   if(!r.passed) Print(r.message);
 */
class Assert
{
private:
    static ulong s_pass_count;
    static ulong s_fail_count;

public:
    //=== Counters ===
    static ulong GetPassCount(void) { return s_pass_count; }
    static ulong GetFailCount(void) { return s_fail_count; }
    static void  ResetCounters(void) { s_pass_count = 0; s_fail_count = 0; }

    //=== Boolean ===

    /// @brief Assert that a condition is true.
    static AssertResult IsTrue(const string name, const bool condition)
    {
        AssertResult r;
        r.passed = condition;
        r.message = name;
        r.expected = "true";
        r.actual = condition ? "true" : "false";
        if(condition) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that a condition is false.
    static AssertResult IsFalse(const string name, const bool condition)
    {
        AssertResult r;
        r.passed = !condition;
        r.message = name;
        r.expected = "false";
        r.actual = condition ? "true" : "false";
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    //=== Equality ===

    /// @brief Assert that two integers are equal.
    static AssertResult AreEqual(const string name, const int expected, const int actual)
    {
        AssertResult r;
        r.passed = (expected == actual);
        r.message = name;
        r.expected = IntegerToString(expected);
        r.actual = IntegerToString(actual);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that two doubles are equal.
    static AssertResult AreEqual(const string name, const double expected, const double actual)
    {
        AssertResult r;
        r.passed = (expected == actual);
        r.message = name;
        r.expected = DoubleToString(expected, 8);
        r.actual = DoubleToString(actual, 8);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that two strings are equal.
    static AssertResult AreEqual(const string name, const string expected, const string actual)
    {
        AssertResult r;
        r.passed = (expected == actual);
        r.message = name;
        r.expected = expected;
        r.actual = actual;
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that two integers are NOT equal.
    static AssertResult AreNotEqual(const string name, const int expected, const int actual)
    {
        AssertResult r;
        r.passed = (expected != actual);
        r.message = name;
        r.expected = "!= " + IntegerToString(expected);
        r.actual = IntegerToString(actual);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that two doubles are NOT equal.
    static AssertResult AreNotEqual(const string name, const double expected, const double actual)
    {
        AssertResult r;
        r.passed = (expected != actual);
        r.message = name;
        r.expected = "!= " + DoubleToString(expected, 8);
        r.actual = DoubleToString(actual, 8);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    //=== Near (floating point) ===

    /// @brief Assert that two doubles are within a tolerance.
    static AssertResult AreNear(const string name, const double expected,
                                 const double actual, const double tolerance)
    {
        AssertResult r;
        double diff = MathAbs(expected - actual);
        r.passed = (diff <= tolerance);
        r.message = name;
        r.expected = DoubleToString(expected, 8) + " ±" + DoubleToString(tolerance, 8);
        r.actual = DoubleToString(actual, 8) + " (diff=" + DoubleToString(diff, 8) + ")";
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    //=== Validity ===

    /// @brief Assert that a double is a valid number (not NaN/INF).
    static AssertResult IsValid(const string name, const double value)
    {
        AssertResult r;
        r.passed = MathIsValidNumber(value);
        r.message = name;
        r.expected = "valid number";
        r.actual = MathIsValidNumber(value) ? DoubleToString(value, 8) : "NaN/INF";
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that a pointer is not NULL.
    static AssertResult NotNull(const string name, void *ptr)
    {
        AssertResult r;
        r.passed = (ptr != NULL);
        r.message = name;
        r.expected = "not NULL";
        r.actual = (ptr != NULL) ? "not NULL" : "NULL";
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that a pointer is NULL.
    static AssertResult IsNull(const string name, void *ptr)
    {
        AssertResult r;
        r.passed = (ptr == NULL);
        r.message = name;
        r.expected = "NULL";
        r.actual = (ptr != NULL) ? "not NULL" : "NULL";
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    //=== Range ===

    /// @brief Assert that a value is within a range [lo, hi].
    static AssertResult InRange(const string name, const double value,
                                 const double lo, const double hi)
    {
        AssertResult r;
        r.passed = (value >= lo && value <= hi);
        r.message = name;
        r.expected = "[" + DoubleToString(lo, 6) + ", " + DoubleToString(hi, 6) + "]";
        r.actual = DoubleToString(value, 6);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that a value is greater than a threshold.
    static AssertResult IsGreater(const string name, const double value, const double threshold)
    {
        AssertResult r;
        r.passed = (value > threshold);
        r.message = name;
        r.expected = "> " + DoubleToString(threshold, 6);
        r.actual = DoubleToString(value, 6);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }

    /// @brief Assert that a value is less than a threshold.
    static AssertResult IsLess(const string name, const double value, const double threshold)
    {
        AssertResult r;
        r.passed = (value < threshold);
        r.message = name;
        r.expected = "< " + DoubleToString(threshold, 6);
        r.actual = DoubleToString(value, 6);
        if(r.passed) s_pass_count++; else s_fail_count++;
        return r;
    }
};

//--- Static member initialization
ulong Assert::s_pass_count = 0;
ulong Assert::s_fail_count = 0;

#endif // ATLAS_ASSERT_MQH
//+------------------------------------------------------------------+
