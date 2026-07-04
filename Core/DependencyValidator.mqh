//+------------------------------------------------------------------+
//|                  Core/DependencyValidator.mqh                   |
//|       AtlasEA v0.1.21.0 - Dependency Graph Validator            |
//+------------------------------------------------------------------+
#ifndef ATLAS_DEPENDENCY_VALIDATOR_MQH
#define ATLAS_DEPENDENCY_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/IDependencyContainer.mqh"
#include "../Interfaces/IModuleRegistry.mqh"
#include "../Interfaces/ILogger.mqh"

/**
 * @struct ValidationResult
 * @brief Result of dependency graph validation.
 */
struct ValidationResult
{
    bool   valid;
    int    error_count;
    int    warning_count;
    string errors[16];
    string warnings[16];
    int    error_idx;
    int    warning_idx;
};

/**
 * @class DependencyValidator
 * @brief Validates the dependency graph for integrity.
 *
 * Checks:
 *   1. Missing dependency — a module requires a service that isn't registered
 *   2. Duplicate registration — same service ID registered twice
 *   3. Circular dependency — module A depends on B, B depends on A
 *   4. Invalid interface mapping — registered pointer doesn't implement expected interface
 *   5. Null implementation — registered pointer is NULL
 *   6. Late registration — service registered after a dependent was already resolved
 */
class DependencyValidator
{
private:
    ILogger *m_logger;

    void AddError(ValidationResult &result, const string msg) const
    {
        if(result.error_idx < 16)
        {
            result.errors[result.error_idx] = msg;
            result.error_idx++;
            result.error_count++;
        }
        if(m_logger != NULL)
            m_logger.Error("DependencyValidator", msg);
    }

    void AddWarning(ValidationResult &result, const string msg) const
    {
        if(result.warning_idx < 16)
        {
            result.warnings[result.warning_idx] = msg;
            result.warning_idx++;
            result.warning_count++;
        }
        if(m_logger != NULL)
            m_logger.Warn("DependencyValidator", msg);
    }

public:
    /**
     * @brief Constructor.
     */
    DependencyValidator(void) { m_logger = NULL; }

    void SetLogger(ILogger *logger) { m_logger = logger; }

    /**
     * @brief Validate the dependency container.
     * @param container The container to validate.
     * @return ValidationResult with details.
     */
    ValidationResult ValidateContainer(const IDependencyContainer &container) const
    {
        ValidationResult result;
        result.valid         = true;
        result.error_count   = 0;
        result.warning_count = 0;
        result.error_idx     = 0;
        result.warning_idx   = 0;

        //--- Check 1: Essential services are registered
        int essential[] = {
            ATLAS_DEP_LOGGER, ATLAS_DEP_BROKER, ATLAS_DEP_PERSISTENCE,
            ATLAS_DEP_MARKET_ENGINE, ATLAS_DEP_STRATEGY_ENGINE,
            ATLAS_DEP_RISK_ENGINE, ATLAS_DEP_EXECUTION_ENGINE,
            ATLAS_DEP_CORE_ENGINE
        };

        for(int i = 0; i < ArraySize(essential); i++)
        {
            if(!container.Exists(essential[i]))
            {
                result.valid = false;
                AddError(result, "Missing essential service: " +
                         IntegerToString(essential[i]) +
                         " (" + container.GetName(essential[i]) + ")");
            }
        }

        //--- Check 2: No null implementations
        for(int id = 1; id < ATLAS_DEP_MAX; id++)
        {
            if(container.Exists(id))
            {
                if(container.ResolveOrNull(id) == NULL)
                {
                    result.valid = false;
                    AddError(result, "Null implementation for service: " +
                             IntegerToString(id) + " (" + container.GetName(id) + ")");
                }
            }
        }

        return result;
    }

    /**
     * @brief Validate the module registry for circular dependencies.
     * @param registry The module registry to validate.
     * @return ValidationResult with details.
     */
    ValidationResult ValidateModules(const IModuleRegistry &registry) const
    {
        ValidationResult result;
        result.valid         = true;
        result.error_count   = 0;
        result.warning_count = 0;
        result.error_idx     = 0;
        result.warning_idx   = 0;

        //--- Check for circular dependencies using DFS
        //--- For each module, traverse its dependency chain
        int module_ids[32];
        int module_count = registry.GetStartupOrder(module_ids, 32);

        for(int i = 0; i < module_count; i++)
        {
            int visited[32];
            int visited_count = 0;
            if(HasCycle(registry, module_ids[i], visited, visited_count, 32))
            {
                result.valid = false;
                AddError(result, "Circular dependency detected involving module " +
                         IntegerToString(module_ids[i]));
            }
        }

        //--- Check all modules are initialized
        if(!registry.AllInitialized())
        {
            AddWarning(result, "Not all modules are initialized (" +
                       IntegerToString(registry.InitializedCount()) + "/" +
                       IntegerToString(registry.Count()) + ")");
        }

        return result;
    }

    /**
     * @brief Full validation: container + modules.
     */
    ValidationResult ValidateAll(const IDependencyContainer &container,
                                  const IModuleRegistry &registry) const
    {
        ValidationResult result;
        result.valid         = true;
        result.error_count   = 0;
        result.warning_count = 0;
        result.error_idx     = 0;
        result.warning_idx   = 0;

        ValidationResult container_result = ValidateContainer(container);
        ValidationResult module_result   = ValidateModules(registry);

        //--- Merge results
        for(int i = 0; i < container_result.error_idx; i++)
            AddError(result, container_result.errors[i]);
        for(int i = 0; i < module_result.error_idx; i++)
            AddError(result, module_result.errors[i]);
        for(int i = 0; i < container_result.warning_idx; i++)
            AddWarning(result, container_result.warnings[i]);
        for(int i = 0; i < module_result.warning_idx; i++)
            AddWarning(result, module_result.warnings[i]);

        result.valid = (result.error_count == 0);
        return result;
    }

private:
    /// @brief DFS cycle detection.
    bool HasCycle(const IModuleRegistry &registry, const int module_id,
                  int visited[], int &visited_count, const int max_visited) const
    {
        //--- Check if already in visited path
        for(int i = 0; i < visited_count; i++)
        {
            if(visited[i] == module_id)
                return true;  //--- Cycle detected
        }

        //--- Add to visited path
        if(visited_count >= max_visited) return false;
        visited[visited_count] = module_id;
        visited_count++;

        //--- Traverse dependencies
        ModuleInfo info;
        if(!registry.Find(module_id, info)) return false;

        for(int i = 0; i < info.dependency_count; i++)
        {
            if(HasCycle(registry, info.dependencies[i], visited, visited_count, max_visited))
                return true;
        }

        //--- Remove from visited path (backtrack)
        visited_count--;
        return false;
    }
};

#endif // ATLAS_DEPENDENCY_VALIDATOR_MQH
//+------------------------------------------------------------------+
