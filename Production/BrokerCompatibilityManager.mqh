//+------------------------------------------------------------------+
//|                Production/BrokerCompatibilityManager.mqh         |
//|       AtlasEA v1.0 Step 7 - Broker Compatibility Manager         |
//+------------------------------------------------------------------+
#ifndef ATLAS_BROKER_COMPATIBILITY_MANAGER_MQH
#define ATLAS_BROKER_COMPATIBILITY_MANAGER_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IBrokerCompatibilityManager.mqh"
#include "BrokerCapabilities.mqh"
#include "SymbolValidator.mqh"
#include "ExecutionSafetyManager.mqh"
#include "TradingSessionManager.mqh"
#include "TradingEnvironmentValidator.mqh"

/**
 * @class BrokerCompatibilityManager
 * @brief The ONLY component that manages broker compatibility, safety,
 *        and health.
 *
 * Implements IBrokerCompatibilityManager. Orchestrates:
 *   - Broker capability detection (cached)
 *   - Pre-order symbol validation (10 checks)
 *   - Execution safety (duplicates, storms, retries, modifications)
 *   - Environment validation (terminal, account, permissions)
 *   - Session management (weekend, rollover, DST, restart)
 *   - Health monitoring (latency, rejections, spread, connection)
 *   - Self-protection (pause when unhealthy, resume when healthy)
 *
 * SELF-PROTECTION:
 *   Pauses trading when:
 *     - Broker unhealthy (disconnected, degraded)
 *     - Connection unstable
 *     - Spread abnormal (> max_spread_multiplier × average)
 *     - Latency excessive (> max_execution_latency_ms)
 *     - Too many rejected orders (> max_failed_orders)
 *     - Trading session unavailable (weekend, closed)
 *   Resumes only when ALL conditions are healthy.
 *
 * Performance: O(1) per check (all cached). No heap allocation.
 */
class BrokerCompatibilityManager : public IBrokerCompatibilityManager
{
private:
    ILogger              *m_logger;
    IBrokerAdapter       *m_broker;
    bool                  m_initialized;

    //--- Owned components (stack-allocated)
    BrokerCapabilityDetector  m_capability_detector;
    SymbolValidator            m_symbol_validator;
    ExecutionSafetyManager     m_execution_safety;
    TradingSessionManager      m_session_manager;
    TradingEnvironmentValidator m_env_validator;

    //--- State
    BrokerCapabilities  m_caps;
    BrokerHealthStatus  m_health;
    SafetyLimits        m_limits;
    bool                m_trading_paused;
    int                 m_pause_reason;

    //--- Health tracking
    double m_spread_sum;       ///< Sum of spreads for average
    int    m_spread_count;     ///< Spread samples
    double m_max_spread_today; ///< Max spread today
    double m_avg_spread;       ///< Running average spread
    ulong  m_execution_time_sum; ///< Sum of execution times
    int    m_execution_time_count;
    datetime m_daily_reset;

public:
    BrokerCompatibilityManager(void)
    {
        m_logger         = NULL;
        m_broker         = NULL;
        m_initialized    = false;
        m_trading_paused  = false;
        m_pause_reason    = ATLAS_PAUSE_NONE;
        m_spread_sum      = 0.0;
        m_spread_count    = 0;
        m_max_spread_today = 0.0;
        m_avg_spread      = 0.0;
        m_execution_time_sum   = 0;
        m_execution_time_count = 0;
        m_daily_reset     = 0;
    }

    void SetLogger(ILogger *logger)
    {
        m_logger = logger;
        m_capability_detector.SetLogger(logger);
        m_symbol_validator.SetLogger(logger);
        m_session_manager.SetLogger(logger);
        m_env_validator.SetLogger(logger);
    }

    void SetBroker(IBrokerAdapter *broker)
    {
        m_broker = broker;
        m_capability_detector.SetBroker(broker);
        m_symbol_validator.SetBroker(broker);
        m_env_validator.SetBroker(broker);
    }

    //=== IBrokerCompatibilityManager implementation ===

    virtual bool Initialize(void) override
    {
        if(m_logger == NULL || m_broker == NULL) return false;

        //--- Detect capabilities (cached for lifetime)
        if(!m_capability_detector.Detect()) return false;
        m_caps = m_capability_detector.Get();

        //--- Wire capabilities to sub-components
        m_symbol_validator.SetCapabilities(m_caps);
        m_session_manager.Initialize();

        m_health.status = ATLAS_BROKER_HEALTHY;
        m_health.status_name = BrokerHealthName(ATLAS_BROKER_HEALTHY);
        m_health.last_check_time = TimeCurrent();
        m_daily_reset = TimeCurrent();

        m_initialized = true;
        m_logger.Info("BrokerCompatibilityManager",
            "Initialized. Broker: " + ExecutionModeName(m_caps.execution_mode) +
            " " + AccountModeName(m_caps.account_mode) +
            (m_caps.is_ecn ? " ECN" : "") +
            (m_caps.fifo_restricted ? " FIFO" : "") +
            " digits=" + IntegerToString(m_caps.digits));
        return true;
    }

    virtual void Shutdown(void) override
    {
        if(!m_initialized) return;
        m_session_manager.Shutdown();
        m_initialized = false;
        if(m_logger != NULL)
            m_logger.Info("BrokerCompatibilityManager", "Shutdown complete");
    }

    virtual bool DetectCapabilities(void) override
    {
        return m_capability_detector.Detect();
    }

    virtual const BrokerCapabilities& GetCapabilities(void) const override
    {
        return m_caps;
    }

    virtual SymbolValidationResult ValidateSymbol(const double volume,
                                                    const double sl,
                                                    const double tp,
                                                    const double entry_price,
                                                    const int direction) override
    {
        return m_symbol_validator.Validate(volume, sl, tp, entry_price, direction);
    }

    virtual EnvironmentValidationResult ValidateEnvironment(void) override
    {
        return m_env_validator.Validate();
    }

    virtual ExecutionSafetyResult CheckExecutionSafety(const string request_id) override
    {
        return m_execution_safety.Check(request_id);
    }

    virtual void RecordOrderResult(const bool success, const ulong execution_ms) override
    {
        m_execution_safety.RecordResult(success, execution_ms);

        //--- Track execution time
        m_execution_time_sum += execution_ms;
        m_execution_time_count++;
        m_health.avg_execution_ms = (m_execution_time_count > 0)
            ? (double)m_execution_time_sum / (double)m_execution_time_count : 0.0;
        m_health.total_orders++;

        if(!success)
            m_health.rejected_orders++;
    }

    virtual BrokerHealthStatus CheckHealth(void) override
    {
        if(!m_initialized) return m_health;

        datetime now = TimeCurrent();
        m_health.last_check_time = now;

        //--- Daily reset
        CheckDailyReset();

        //--- Check session events
        int session_event = m_session_manager.CheckSessionEvent();
        if(session_event == ATLAS_SESSION_EVENT_WEEKEND_CLOSE)
        {
            PauseTrading(ATLAS_PAUSE_WEEKEND);
        }
        else if(session_event == ATLAS_SESSION_EVENT_WEEKEND_REOPEN)
        {
            //--- Auto-resume from weekend if all other conditions are healthy
            if(m_pause_reason == ATLAS_PAUSE_WEEKEND)
                TryResume();
        }

        //--- Check environment
        EnvironmentValidationResult env = m_env_validator.Validate();
        if(!env.Passed())
        {
            if(env.code == ATLAS_ENV_DISCONNECTED)
            {
                m_health.status = ATLAS_BROKER_DISCONNECTED;
                m_health.status_name = BrokerHealthName(ATLAS_BROKER_DISCONNECTED);
                PauseTrading(ATLAS_PAUSE_CONNECTION);
            }
            else if(env.code == ATLAS_ENV_AUTOTRADING_DISABLED ||
                    env.code == ATLAS_ENV_READ_ONLY ||
                    env.code == ATLAS_ENV_INSUFFICIENT_PERMS)
            {
                m_health.status = ATLAS_BROKER_UNHEALTHY;
                m_health.status_name = BrokerHealthName(ATLAS_BROKER_UNHEALTHY);
                PauseTrading(ATLAS_PAUSE_BROKER_UNHEALTHY);
            }
        }

        //--- Check spread
        if(m_broker != NULL)
        {
            double bid = m_broker.SymbolBid();
            double ask = m_broker.SymbolAsk();
            if(bid > 0.0 && ask > 0.0 && m_caps.point > 0.0)
            {
                double spread_pts = (ask - bid) / m_caps.point;
                m_spread_sum += spread_pts;
                m_spread_count++;
                m_avg_spread = m_spread_sum / (double)m_spread_count;
                m_health.avg_spread_points = m_avg_spread;
                if(spread_pts > m_max_spread_today) m_max_spread_today = spread_pts;
                m_health.max_spread_points = m_max_spread_today;

                //--- Abnormal spread detection
                if(m_limits.max_spread_multiplier > 0.0 && m_avg_spread > 0.0)
                {
                    if(spread_pts > m_avg_spread * m_limits.max_spread_multiplier)
                    {
                        PauseTrading(ATLAS_PAUSE_SPREAD_ABNORMAL);
                    }
                }
            }
            m_health.price_feed_active = (bid > 0.0 && ask > 0.0);
        }

        //--- Check latency
        if(m_limits.max_execution_latency_ms > 0 &&
           m_health.avg_execution_ms > m_limits.max_execution_latency_ms)
        {
            PauseTrading(ATLAS_PAUSE_LATENCY);
        }

        //--- Check rejected orders
        if(m_limits.max_failed_orders > 0 &&
           m_health.rejected_orders >= m_limits.max_failed_orders)
        {
            PauseTrading(ATLAS_PAUSE_REJECTED_ORDERS);
        }

        //--- Check session
        if(!m_session_manager.IsSessionOpen())
        {
            if(m_pause_reason == ATLAS_PAUSE_NONE)
                PauseTrading(ATLAS_PAUSE_SESSION_CLOSED);
        }

        //--- Try to resume if paused (except manual pause)
        if(m_trading_paused && m_pause_reason != ATLAS_PAUSE_MANUAL)
            TryResume();

        m_health.trading_paused = m_trading_paused;
        m_health.pause_reason   = m_pause_reason;

        return m_health;
    }

    virtual bool IsTradingPaused(void) const override
    {
        return m_trading_paused;
    }

    virtual int GetPauseReason(void) const override
    {
        return m_pause_reason;
    }

    virtual const BrokerHealthStatus& GetHealthStatus(void) const override
    {
        return m_health;
    }

    virtual const SafetyLimits& GetSafetyLimits(void) const override
    {
        return m_limits;
    }

    virtual void SetSafetyLimits(const SafetyLimits &limits) override
    {
        m_limits = limits;
        m_execution_safety.SetLimits(limits);
        m_symbol_validator.SetMaxSpreadPoints(limits.max_slippage_points);
    }

    virtual void PauseTrading(const int reason) override
    {
        if(m_trading_paused && m_pause_reason == reason) return;
        m_trading_paused = true;
        m_pause_reason   = reason;
        if(m_logger != NULL)
            m_logger.Warn("BrokerCompatibilityManager",
                "Trading PAUSED: " + PauseReasonName(reason));
    }

    virtual bool ResumeTrading(void) override
    {
        //--- Manual resume only works if all conditions are healthy
        return TryResume();
    }

    virtual bool IsSessionOpen(void) const override
    {
        return m_session_manager.IsSessionOpen();
    }

    virtual int CheckSessionEvent(void) override
    {
        return m_session_manager.CheckSessionEvent();
    }

    virtual void LogStatus(void) const override
    {
        if(m_logger == NULL) return;
        m_logger.Info("BrokerCompatibilityManager",
            "Health: " + m_health.status_name +
            " Paused: " + (m_trading_paused ? "YES" : "NO") +
            " [" + PauseReasonName(m_pause_reason) + "]" +
            " AvgExec: " + DoubleToString(m_health.avg_execution_ms, 0) + "ms" +
            " AvgSpread: " + DoubleToString(m_health.avg_spread_points, 1) + "pts" +
            " Rejected: " + IntegerToString(m_health.rejected_orders) +
            " Total: " + IntegerToString(m_health.total_orders) +
            " Session: " + (m_session_manager.IsSessionOpen() ? "OPEN" : "CLOSED"));
    }

    //=== Extended API ===

    /**
     * @brief Get the session manager (for configuration).
     */
    TradingSessionManager& GetSessionManager(void) { return m_session_manager; }

    /**
     * @brief Get the execution safety manager (for direct access).
     */
    ExecutionSafetyManager& GetExecutionSafety(void) { return m_execution_safety; }

    /**
     * @brief Notify of a tick (updates idle timer).
     */
    void OnTick(void) { m_session_manager.OnTick(); }

private:
    /**
     * @brief Try to resume trading if all conditions are healthy.
     */
    bool TryResume(void)
    {
        if(!m_trading_paused) return true;
        if(m_pause_reason == ATLAS_PAUSE_MANUAL) return false; // Can't auto-resume manual

        //--- Check all conditions
        EnvironmentValidationResult env = m_env_validator.Validate();
        if(!env.Passed()) return false;

        if(!m_session_manager.IsSessionOpen()) return false;

        if(m_limits.max_failed_orders > 0 &&
           m_health.rejected_orders >= m_limits.max_failed_orders)
            return false;

        if(m_limits.max_execution_latency_ms > 0 &&
           m_health.avg_execution_ms > m_limits.max_execution_latency_ms)
            return false;

        //--- Check spread
        if(m_broker != NULL && m_limits.max_spread_multiplier > 0.0 && m_avg_spread > 0.0)
        {
            double bid = m_broker.SymbolBid();
            double ask = m_broker.SymbolAsk();
            if(bid > 0.0 && ask > 0.0 && m_caps.point > 0.0)
            {
                double spread_pts = (ask - bid) / m_caps.point;
                if(spread_pts > m_avg_spread * m_limits.max_spread_multiplier)
                    return false;
            }
        }

        //--- All conditions healthy → resume
        if(m_logger != NULL)
            m_logger.Info("BrokerCompatibilityManager",
                "Trading RESUMED (all conditions healthy)");
        m_trading_paused = false;
        m_pause_reason   = ATLAS_PAUSE_NONE;
        m_health.status  = ATLAS_BROKER_HEALTHY;
        m_health.status_name = BrokerHealthName(ATLAS_BROKER_HEALTHY);
        return true;
    }

    void CheckDailyReset(void)
    {
        if(m_daily_reset == 0) { m_daily_reset = TimeCurrent(); return; }
        MqlDateTime dt_now, dt_reset;
        TimeToStruct(TimeCurrent(), dt_now);
        TimeToStruct(m_daily_reset, dt_reset);
        if(dt_now.day != dt_reset.day || dt_now.mon != dt_reset.mon)
        {
            //--- Daily reset
            m_health.rejected_orders = 0;
            m_health.total_orders    = 0;
            m_spread_sum             = 0.0;
            m_spread_count           = 0;
            m_max_spread_today       = 0.0;
            m_execution_time_sum     = 0;
            m_execution_time_count   = 0;
            m_execution_safety.ResetDaily();
            m_daily_reset = TimeCurrent();
        }
    }
};

#endif // ATLAS_BROKER_COMPATIBILITY_MANAGER_MQH
//+------------------------------------------------------------------+
