//+------------------------------------------------------------------+
//|                      Interfaces/IMetricsExporter.mqh            |
//|       AtlasEA v0.1.12.0 - Metrics Export Interface              |
//+------------------------------------------------------------------+
#ifndef ATLAS_IMETRICS_EXPORTER_MQH
#define ATLAS_IMETRICS_EXPORTER_MQH

#include "../Config/Settings.mqh"

/**
 * @brief Export format codes.
 */
#define ATLAS_EXPORT_CSV      0
#define ATLAS_EXPORT_BINARY   1
#define ATLAS_EXPORT_MEMORY   2

/**
 * @class IMetricsExporter
 * @brief Interface for exporting all statistics.
 *
 * Implementations gather data from all monitoring interfaces and
 * produce an export in the requested format.
 */
class IMetricsExporter
{
public:
    /**
     * @brief Export all metrics in the specified format.
     * @param format ATLAS_EXPORT_CSV, ATLAS_EXPORT_BINARY, or ATLAS_EXPORT_MEMORY.
     * @param out_buffer Output buffer (caller-allocated).
     * @param out_size Output: number of bytes written.
     * @return true if export succeeded.
     */
    virtual bool Export(const int format, string &out_buffer) = 0;

    /**
     * @brief Export to a file.
     * @param format ATLAS_EXPORT_CSV or ATLAS_EXPORT_BINARY.
     * @param filename Output filename (in MQL5/Files/).
     * @return true if file written successfully.
     */
    virtual bool ExportToFile(const int format, const string filename) = 0;

    virtual ~IMetricsExporter(void) {}
};

#endif // ATLAS_IMETRICS_EXPORTER_MQH
//+------------------------------------------------------------------+
