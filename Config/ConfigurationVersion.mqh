//+------------------------------------------------------------------+
//|                   Config/ConfigurationVersion.mqh               |
//|       AtlasEA v0.1.22.0 - Configuration Versioning              |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_VERSION_MQH
#define ATLAS_CONFIGURATION_VERSION_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Current configuration schema version.
 */
#define ATLAS_CONFIG_SCHEMA_VERSION  2

/**
 * @brief Current build number.
 */
#define ATLAS_CONFIG_BUILD_NUMBER    1

/**
 * @struct ConfigurationVersion
 * @brief Version information for the configuration.
 */
struct ConfigurationVersion
{
    int    schema_version;    ///< Configuration schema version
    int    build_number;      ///< Build that produced this config
    int    migration_number;  ///< Last migration applied
    int    compatibility;     ///< Minimum compatible engine version

    /**
     * @brief Default constructor — current version.
     */
    ConfigurationVersion(void)
    {
        schema_version   = ATLAS_CONFIG_SCHEMA_VERSION;
        build_number     = ATLAS_CONFIG_BUILD_NUMBER;
        migration_number = 0;
        compatibility    = 1;
    }

    /**
     * @brief Check if this version is compatible with the current engine.
     */
    bool IsCompatible(void) const
    {
        return (schema_version <= ATLAS_CONFIG_SCHEMA_VERSION &&
                compatibility  <= ATLAS_CONFIG_SCHEMA_VERSION);
    }

    /**
     * @brief Check if migration is needed.
     */
    bool NeedsMigration(void) const
    {
        return (schema_version < ATLAS_CONFIG_SCHEMA_VERSION);
    }

    /**
     * @brief Get version string.
     */
    string ToString(void) const
    {
        return "v" + IntegerToString(schema_version) +
               "." + IntegerToString(build_number) +
               "." + IntegerToString(migration_number);
    }
};

/**
 * @class ConfigurationMigration
 * @brief Handles configuration version upgrades.
 */
class ConfigurationMigration
{
public:
    /**
     * @brief Migrate a configuration from an older version.
     * @param config The config to migrate.
     * @param from_version The current schema version.
     * @return true if migration succeeded.
     */
    static bool Migrate(AtlasConfig &config, const int from_version)
    {
        if(from_version >= ATLAS_CONFIG_SCHEMA_VERSION)
            return true;  //--- Already current

        //--- v1 → v2: add new fields with defaults
        if(from_version <= 1)
        {
            //--- v2 fields are already in AtlasConfig struct (from Settings.mqh)
            //--- No additional fields needed — just update version tracking
        }

        return true;
    }

    /**
     * @brief Get the current schema version.
     */
    static int GetSchemaVersion(void) { return ATLAS_CONFIG_SCHEMA_VERSION; }
};

#endif // ATLAS_CONFIGURATION_VERSION_MQH
//+------------------------------------------------------------------+
