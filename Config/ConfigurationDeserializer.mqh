//+------------------------------------------------------------------+
//|              Config/ConfigurationDeserializer.mqh               |
//|       AtlasEA v0.1.18.0 - Configuration Deserializer             |
//+------------------------------------------------------------------+
#ifndef ATLAS_CONFIGURATION_DESERIALIZER_MQH
#define ATLAS_CONFIGURATION_DESERIALIZER_MQH

#include "AtlasConfiguration.mqh"
#include "ConfigurationSerializer.mqh"

/**
 * @class ConfigurationDeserializer
 * @brief Concrete deserializer — delegates to ConfigurationSerializer.Deserialize().
 *
 * Kept as a separate class for interface segregation (future: independent impl).
 */
class ConfigurationDeserializer
{
private:
    const ConfigurationSerializer *m_serializer;

public:
    ConfigurationDeserializer(void) { m_serializer = NULL; }

    void SetSerializer(const ConfigurationSerializer *serializer)
    {
        m_serializer = serializer;
    }

    bool Deserialize(const string &data, const int format, AtlasConfiguration &out) const
    {
        if(m_serializer == NULL) return false;
        return m_serializer.Deserialize(data, format, out);
    }

    bool DeserializeFromFile(const string filename, const int format,
                              AtlasConfiguration &out) const
    {
        if(m_serializer == NULL) return false;
        return m_serializer.DeserializeFromFile(filename, format, out);
    }
};

#endif // ATLAS_CONFIGURATION_DESERIALIZER_MQH
//+------------------------------------------------------------------+
