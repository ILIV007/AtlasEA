//+------------------------------------------------------------------+
//|                Interfaces/IConfigurationValidator.mqh           |
//|       AtlasEA v0.1.22.0 - Configuration Validator Interface     |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONFIGURATION_VALIDATOR_V2_MQH
#define ATLAS_ICONFIGURATION_VALIDATOR_V2_MQH

#include "../Config/Settings.mqh"

//--- Forward
struct AtlasConfig;

/**
 * @struct ConfigValidationReport
 * @brief Result of configuration validation.
 */
struct ConfigValidationReport
{
    bool   valid;
    int    error_count;
    int    warning_count;
    string errors[24];
    string warnings[24];
    int    error_idx;
    int    warning_idx;
};

/**
 * @class IConfigurationValidator
 * @brief Interface for validating configuration.
 */
class IConfigurationValidator
{
public:
    virtual ConfigValidationReport Validate(const AtlasConfig &config) const = 0;
    virtual ~IConfigurationValidator(void) {}
};

#endif // ATLAS_ICONFIGURATION_VALIDATOR_V2_MQH
//+------------------------------------------------------------------+
