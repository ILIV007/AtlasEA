//+------------------------------------------------------------------+
//|                 Production/ExecutionSafetyManager.mqh            |
//|       AtlasEA v1.0 Step 7 - Execution Safety Manager             |
//+------------------------------------------------------------------+
#ifndef ATLAS_EXECUTION_SAFETY_MQH
#define ATLAS_EXECUTION_SAFETY_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerCompatibilityManager.mqh"

/**
 * @class ExecutionSafetyManager
 * @brief Prevents execution hazards: duplicates, storms, retry loops,
 *        trade context conflicts, excessive slippage, modification loops.
 *
 * SOLE RESPONSIBILITY: track order activity and reject unsafe executions.
 *
 * Tracks:
 *   - Recent request IDs (duplicate detection)
 *   - Order timestamps (storm detection)
 *   - Retry count per request (retry loop detection)
 *   - Modification count per position (modification loop detection)
 *   - Execution times (latency tracking)
 *   - Slippage per fill
 *
 * Performance: O(R) where R = recent request ring size. No allocation.
 */
class ExecutionSafetyManager
{
private:
    ILogger *m_logger;
    SafetyLimits m_limits;

    //--- Duplicate detection ring (request IDs)
    string m_recent_requests[32];
    int    m_request_count;
    int    m_request_next;

    //--- Retry tracking
    int    m_retry_counts[32];
    string m_retry_ids[32];
    int    m_retry_entry_count;

    //--- Order storm detection (timestamp ring, 60 seconds)
    datetime m_order_times[60];
    int      m_order_time_count;
    int      m_order_time_next;

    //--- Modification tracking
    string m_mod_pos_ids[32];
    int    m_mod_counts[32];
    int    m_mod_entry_count;

    //--- Daily counters
    int    m_daily_orders;
    int    m_daily_failed;
    int    m_daily_retries;
    datetime m_daily_reset;

    //--- Trade context busy
    bool   m_trade_context_busy;
    datetime m_context_busy_until;

public:
    ExecutionSafetyManager(void)
    {
        m_logger             = NULL;
        m_request_count      = 0;
        m_request_next       = 0;
        m_retry_entry_count  = 0;
        m_order_time_count   = 0;
        m_order_time_next    = 0;
        m_mod_entry_count    = 0;
        m_daily_orders       = 0;
        m_daily_failed       = 0;
        m_daily_retries      = 0;
        m_daily_reset        = 0;
        m_trade_context_busy = false;
        m_context_busy_until = 0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }
    void SetLimits(const SafetyLimits &limits) { m_limits = limits; }
    const SafetyLimits& GetLimits(void) const { return m_limits; }

    /**
     * @brief Check execution safety for a new order.
     * @param request_id The order request ID.
     * @return ExecutionSafetyResult (OK or rejection code).
     */
    ExecutionSafetyResult Check(const string request_id)
    {
        ExecutionSafetyResult result;

        //--- Daily reset
        CheckDailyReset();

        //--- 1. Duplicate order detection
        for(int i = 0; i < m_request_count; i++)
        {
            if(m_recent_requests[i] == request_id)
            {
                result.code   = ATLAS_ES_DUPLICATE_ORDER;
                result.detail = "Duplicate request_id: " + request_id;
                return result;
            }
        }

        //--- 2. Trade context busy
        if(m_trade_context_busy && TimeCurrent() < m_context_busy_until)
        {
            result.code   = ATLAS_ES_TRADE_CONTEXT;
            result.detail = "Trade context is busy";
            return result;
        }
        else if(m_trade_context_busy)
        {
            m_trade_context_busy = false; // Expired
        }

        //--- 3. Order storm detection (max orders per minute)
        datetime one_min_ago = TimeCurrent() - 60;
        int orders_last_min = 0;
        for(int i = 0; i < m_order_time_count; i++)
        {
            if(m_order_times[i] > one_min_ago) orders_last_min++;
        }
        if(orders_last_min >= m_limits.max_orders_per_minute)
        {
            result.code   = ATLAS_ES_ORDER_STORM;
            result.detail = "Order storm: " + IntegerToString(orders_last_min) +
                            " orders in last minute (max " +
                            IntegerToString(m_limits.max_orders_per_minute) + ")";
            return result;
        }

        //--- 4. Daily trade limit
        if(m_limits.max_daily_trades > 0 && m_daily_orders >= m_limits.max_daily_trades)
        {
            result.code   = ATLAS_ES_ORDER_STORM;
            result.detail = "Daily trade limit reached: " +
                            IntegerToString(m_daily_orders) + " / " +
                            IntegerToString(m_limits.max_daily_trades);
            return result;
        }

        //--- 5. Max failed orders
        if(m_limits.max_failed_orders > 0 &&
           m_daily_failed >= m_limits.max_failed_orders)
        {
            result.code   = ATLAS_ES_ORDER_STORM;
            result.detail = "Max failed orders reached: " +
                            IntegerToString(m_daily_failed) + " / " +
                            IntegerToString(m_limits.max_failed_orders);
            return result;
        }

        //--- 6. Retry loop detection
        for(int i = 0; i < m_retry_entry_count; i++)
        {
            if(m_retry_ids[i] == request_id)
            {
                m_retry_counts[i]++;
                if(m_retry_counts[i] > m_limits.max_retries)
                {
                    result.code   = ATLAS_ES_RETRY_LOOP;
                    result.detail = "Retry loop: " + IntegerToString(m_retry_counts[i]) +
                                    " retries for " + request_id +
                                    " (max " + IntegerToString(m_limits.max_retries) + ")";
                    return result;
                }
                break;
            }
        }

        //--- All checks passed: record the request
        RecordRequest(request_id);
        m_daily_orders++;

        return result;
    }

    /**
     * @brief Record a retry for a request ID.
     */
    void RecordRetry(const string request_id)
    {
        //--- Check if already tracking
        for(int i = 0; i < m_retry_entry_count; i++)
        {
            if(m_retry_ids[i] == request_id)
            {
                m_retry_counts[i]++;
                m_daily_retries++;
                return;
            }
        }
        //--- Add new
        if(m_retry_entry_count < 32)
        {
            m_retry_ids[m_retry_entry_count]    = request_id;
            m_retry_counts[m_retry_entry_count] = 1;
            m_retry_entry_count++;
            m_daily_retries++;
        }
    }

    /**
     * @brief Record an order result.
     */
    void RecordResult(const bool success, const ulong execution_ms)
    {
        if(!success)
        {
            m_daily_failed++;

            //--- Check for trade context busy (common MT5 error)
            if(execution_ms > 1000 || !success)
            {
                m_trade_context_busy  = true;
                m_context_busy_until  = TimeCurrent() + 5; // 5 second cooldown
            }
        }
    }

    /**
     * @brief Check if a modification is safe (no modification loop).
     * @param position_id Position being modified.
     * @return ExecutionSafetyResult.
     */
    ExecutionSafetyResult CheckModification(const string position_id)
    {
        ExecutionSafetyResult result;

        for(int i = 0; i < m_mod_entry_count; i++)
        {
            if(m_mod_pos_ids[i] == position_id)
            {
                m_mod_counts[i]++;
                if(m_mod_counts[i] > m_limits.max_modification_per_position)
                {
                    result.code   = ATLAS_ES_MODIFICATION_LOOP;
                    result.detail = "Modification loop: " + IntegerToString(m_mod_counts[i]) +
                                    " modifications for " + position_id;
                    return result;
                }
                break;
            }
        }

        return result;
    }

    /**
     * @brief Record a modification for a position.
     */
    void RecordModification(const string position_id)
    {
        for(int i = 0; i < m_mod_entry_count; i++)
        {
            if(m_mod_pos_ids[i] == position_id)
            {
                m_mod_counts[i]++;
                return;
            }
        }
        if(m_mod_entry_count < 32)
        {
            m_mod_pos_ids[m_mod_entry_count] = position_id;
            m_mod_counts[m_mod_entry_count]  = 1;
            m_mod_entry_count++;
        }
    }

    /**
     * @brief Check slippage against limit.
     */
    bool IsSlippageAcceptable(const double slippage_points) const
    {
        if(m_limits.max_slippage_points <= 0.0) return true;
        return slippage_points <= m_limits.max_slippage_points;
    }

    /**
     * @brief Reset daily counters.
     */
    void ResetDaily(void)
    {
        m_daily_orders  = 0;
        m_daily_failed  = 0;
        m_daily_retries = 0;
        m_daily_reset   = TimeCurrent();
        m_mod_entry_count = 0;
    }

    int GetDailyOrders(void) const { return m_daily_orders; }
    int GetDailyFailed(void) const { return m_daily_failed; }
    int GetDailyRetries(void) const { return m_daily_retries; }

private:
    void RecordRequest(const string request_id)
    {
        m_recent_requests[m_request_next] = request_id;
        m_request_next = (m_request_next + 1) % 32;
        if(m_request_count < 32) m_request_count++;

        //--- Record timestamp for storm detection
        m_order_times[m_order_time_next] = TimeCurrent();
        m_order_time_next = (m_order_time_next + 1) % 60;
        if(m_order_time_count < 60) m_order_time_count++;
    }

    void CheckDailyReset(void)
    {
        if(m_daily_reset == 0)
        {
            m_daily_reset = TimeCurrent();
            return;
        }
        MqlDateTime dt_now, dt_reset;
        TimeToStruct(TimeCurrent(), dt_now);
        TimeToStruct(m_daily_reset, dt_reset);
        if(dt_now.day != dt_reset.day || dt_now.mon != dt_reset.mon)
            ResetDaily();
    }
};

#endif // ATLAS_EXECUTION_SAFETY_MQH
//+------------------------------------------------------------------+
