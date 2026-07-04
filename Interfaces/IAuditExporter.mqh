//+------------------------------------------------------------------+
//|                   Interfaces/IAuditExporter.mqh                 |
//|       AtlasEA v0.1.19.0 - Audit Exporter Interface              |
//+------------------------------------------------------------------+
#ifndef ATLAS_IAUDIT_EXPORTER_MQH
#define ATLAS_IAUDIT_EXPORTER_MQH

#include "../Config/Settings.mqh"

//--- Forward
struct AuditEntry;

/**
 * @brief Audit export format codes.
 */
#define ATLAS_AUDIT_EXPORT_CSV      0
#define ATLAS_AUDIT_EXPORT_BINARY   1
#define ATLAS_AUDIT_EXPORT_JSON     2
#define ATLAS_AUDIT_EXPORT_MEMORY   3

/**
 * @class IAuditExporter
 * @brief Interface for exporting audit trail.
 */
class IAuditExporter
{
public:
    /// @brief Export audit entries to a string.
    virtual string Export(const AuditEntry entries[], const int count,
                           const int format) const = 0;

    /// @brief Export to a file.
    virtual bool ExportToFile(const AuditEntry entries[], const int count,
                               const int format, const string filename) const = 0;

    virtual ~IAuditExporter(void) {}
};

#endif // ATLAS_IAUDIT_EXPORTER_MQH
//+------------------------------------------------------------------+
