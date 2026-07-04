//+------------------------------------------------------------------+
//|                 Config/ConfigurationValidator.mqh               |
//|       AtlasEA v0.1.22.0 - Configuration Validator                |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_VALIDATOR_MQH
#define ATLAS_CONFIGURATION_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IConfigurationValidator.mqh"
#include "../Interfaces/ILogger.mqh"
#include "ConfigurationDefaults.mqh"

/**
 * @class ConfigurationValidator
 * @brief Concrete implementation of IConfigurationValidator.
 *
 * Validates every configuration field against min/max ranges and
 * production-safety constraints. Rejects invalid configurations.
 *
 * Validation categories:
 *   - Risk parameters (drawdown, exposure)
 *   - Broker limits (retries, slippage, spread)
 *   - Lot sizes (volume, min, max, step)
 *   - Timeouts (ms per tick, retry delay)
 *   - Buffer sizes (event queue, max events)
 *   - Snapshot frequency
 *   - Log settings
 */
class ConfigurationValidator : public IConfigurationValidator
{
private:
    ILogger *m_logger;

    void AddError(ConfigValidationReport &report, const string msg) const
    {
        if(report.error_idx < 24)
        {
            report.errors[report.error_idx] = msg;
            report.error_idx++;
            report.error_count++;
        }
    }

    void AddWarning(ConfigValidationReport &report, const string msg) const
    {
        if(report.warning_idx < 24)
        {
            report.warnings[report.warning_idx] = msg;
            report.warning_idx++;
            report.warning_count++;
        }
    }

public:
    ConfigurationValidator(void) { m_logger = NULL; }
    void SetLogger(ILogger *logger) { m_logger = logger; }

    virtual ConfigValidationReport Validate(const AtlasConfig &cfg) const override
    {
        ConfigValidationReport report;
        report.valid         = true;
        report.error_count   = 0;
        report.warning_count = 0;
        report.error_idx     = 0;
        report.warning_idx   = 0;

        //=== Risk parameters ===
        if(cfg.max_daily_drawdown_pct <= 0.0)
        {
            report.valid = false;
            AddError(report, "max_daily_drawdown_pct must be > 0 (got " +
                     DoubleToString(cfg.max_daily_drawdown_pct, 1) + ")");
        }
        if(cfg.max_daily_drawdown_pct > 50.0)
        {
            report.valid = false;
            AddError(report, "max_daily_drawdown_pct must be <= 50% (got " +
                     DoubleToString(cfg.max_daily_drawdown_pct, 1) + ")");
        }
        if(cfg.max_exposure_limit <= 0.0)
        {
            report.valid = false;
            AddError(report, "max_exposure_limit must be > 0 (got " +
                     DoubleToString(cfg.max_exposure_limit, 2) + ")");
        }
        if(cfg.max_exposure_limit > 5.0)
        {
            report.valid = false;
            AddError(report, "max_exposure_limit must be <= 5.0 (got " +
                     DoubleToString(cfg.max_exposure_limit, 2) + ")");
        }

        //=== Broker limits ===
        if(cfg.max_retries < 0)
        {
            report.valid = false;
            AddError(report, "max_retries must be >= 0 (got " +
                     IntegerToString(cfg.max_retries) + ")");
        }
        if(cfg.max_retries > 10)
        {
            AddWarning(report, "max_retries > 10 is excessive (got " +
                       IntegerToString(cfg.max_retries) + ")");
        }
        if(cfg.retry_delay_ms < 0)
        {
            report.valid = false;
            AddError(report, "retry_delay_ms must be >= 0");
        }
        if(cfg.max_spread_points <= 0.0)
        {
            report.valid = false;
            AddError(report, "max_spread_points must be > 0");
        }
        if(cfg.slippage_points < 0)
        {
            report.valid = false;
            AddError(report, "slippage_points must be >= 0");
        }

        //=== Lot sizes ===
        if(cfg.base_volume <= 0.0)
        {
            report.valid = false;
            AddError(report, "base_volume must be > 0 (got " +
                     DoubleToString(cfg.base_volume, 2) + ")");
        }
        if(cfg.min_volume <= 0.0)
        {
            report.valid = false;
            AddError(report, "min_volume must be > 0");
        }
        if(cfg.max_volume < cfg.min_volume)
        {
            report.valid = false;
            AddError(report, "max_volume must be >= min_volume");
        }
        if(cfg.base_volume > cfg.max_volume)
        {
            AddWarning(report, "base_volume > max_volume — will be clamped at runtime");
        }

        //=== Timeouts ===
        if(cfg.max_ms_per_tick <= 0)
        {
            report.valid = false;
            AddError(report, "max_ms_per_tick must be > 0");
        }
        if(cfg.max_ms_per_tick > 1000)
        {
            AddWarning(report, "max_ms_per_tick > 1000ms — may cause terminal freeze");
        }

        //=== Buffer sizes ===
        if(cfg.max_events_per_tick <= 0)
        {
            report.valid = false;
            AddError(report, "max_events_per_tick must be > 0");
        }
        if(cfg.max_events_per_tick > 1000)
        {
            AddWarning(report, "max_events_per_tick > 1000 — high memory usage");
        }

        //=== Snapshot frequency ===
        if(cfg.snapshot_interval_sec < 0)
        {
            report.valid = false;
            AddError(report, "snapshot_interval_sec must be >= 0");
        }
        if(cfg.snapshot_interval_sec > 0 && cfg.snapshot_interval_sec < 10)
        {
            AddWarning(report, "snapshot_interval_sec < 10 — excessive disk I/O");
        }

        //=== Heartbeat ===
        if(cfg.heartbeat_interval_sec <= 0)
        {
            report.valid = false;
            AddError(report, "heartbeat_interval_sec must be > 0");
        }

        //=== Log settings ===
        if(cfg.log_level < ATLAS_LOG_TRACE || cfg.log_level > ATLAS_LOG_FATAL)
        {
            report.valid = false;
            AddError(report, "log_level out of range [0, 5] (got " +
                     IntegerToString(cfg.log_level) + ")");
        }

        //=== Magic number ===
        if(cfg.magic_number <= 0)
        {
            report.valid = false;
            AddError(report, "magic_number must be > 0");
        }

        //=== Symbol ===
        if(StringLen(cfg.symbol) == 0)
        {
            report.valid = false;
            AddError(report, "symbol must not be empty");
        }

        //=== Strategy limits ===
        if(cfg.max_active_strategies <= 0)
        {
            report.valid = false;
            AddError(report, "max_active_strategies must be > 0");
        }
        if(cfg.max_active_strategies > ATLAS_MAX_STRATEGIES)
        {
            report.valid = false;
            AddError(report, "max_active_strategies exceeds ATLAS_MAX_STRATEGIES (" +
                     IntegerToString(ATLAS_MAX_STRATEGIES) + ")");
        }

        //=== Indicator periods ===
        if(cfg.atr_period <= 0)
        {
            report.valid = false;
            AddError(report, "atr_period must be > 0");
        }
        if(cfg.ma_fast_period <= 0 || cfg.ma_slow_period <= 0)
        {
            report.valid = false;
            AddError(report, "MA periods must be > 0");
        }
        if(cfg.ma_fast_period >= cfg.ma_slow_period)
        {
            AddWarning(report, "ma_fast_period >= ma_slow_period — trend detection may not work");
        }

        //=== SL/TP multipliers ===
        if(cfg.sl_atr_multiplier <= 0)
        {
            report.valid = false;
            AddError(report, "sl_atr_multiplier must be > 0");
        }
        if(cfg.tp_atr_multiplier <= 0)
        {
            report.valid = false;
            AddError(report, "tp_atr_multiplier must be > 0");
        }

        //=== Log result ===
        if(m_logger != NULL)
        {
            if(report.valid)
                m_logger.Info("ConfigurationValidator",
                    "Config VALID (" + IntegerToString(report.error_count) + " errors, " +
                    IntegerToString(report.warning_count) + " warnings)");
            else
                m_logger.Error("ConfigurationValidator",
                    "Config INVALID (" + IntegerToString(report.error_count) + " errors)");
        }

        return report;
    }
};

#endif // ATLAS_CONFIGURATION_VALIDATOR_MQH
//+------------------------------------------------------------------+
