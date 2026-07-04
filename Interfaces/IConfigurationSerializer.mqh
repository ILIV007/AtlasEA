//+------------------------------------------------------------------+
//|               Interfaces/IConfigurationSerializer.mqh           |
//|       AtlasEA v0.1.18.0 - Configuration Serializer Interface   |
//+------------------------------------------------------------------+
#ifndef ATLAS_ICONFIGURATION_SERIALIZER_MQH
#define ATLAS_ICONFIGURATION_SERIALIZER_MQH

#include "../Config/Settings.mqh"

//--- Forward
struct AtlasConfiguration;

/**
 * @brief Serialization format codes.
 */
#define ATLAS_CFG_FORMAT_BINARY  0
#define ATLAS_CFG_FORMAT_INI     1
#define ATLAS_CFG_FORMAT_JSON    2
#define ATLAS_CFG_FORMAT_MEMORY  3

/**
 * @class IConfigurationSerializer
 * @brief Interface for serializing/deserializing configuration.
 */
class IConfigurationSerializer
{
public:
    /// @brief Serialize config to a string.
    virtual string Serialize(const AtlasConfiguration &config, const int format) const = 0;

    /// @brief Deserialize config from a string.
    virtual bool Deserialize(const string &data, const int format, AtlasConfiguration &out) const = 0;

    /// @brief Serialize to file.
    virtual bool SerializeToFile(const AtlasConfiguration &config, const int format,
                                  const string filename) const = 0;

    /// @brief Deserialize from file.
    virtual bool DeserializeFromFile(const string filename, const int format,
                                      AtlasConfiguration &out) const = 0;

    virtual ~IConfigurationSerializer(void) {}
};

#endif // ATLAS_ICONFIGURATION_SERIALIZER_MQH
//+------------------------------------------------------------------+
