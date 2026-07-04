//+------------------------------------------------------------------+
//|                       Interfaces/IStrategy.mqh                   |
//|       AtlasEA v0.1.20.0 - Strategy Plugin Interface (v2)        |
//+------------------------------------------------------------------+
#ifndef ATLAS_ISTRATEGY_MQH
#define ATLAS_ISTRATEGY_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/MarketState.mqh"
#include "../Contracts/RiskDecision.mqh"

//--- Forward declaration — StrategyContext lives in Strategy/
class StrategyContext;

/**
 * @brief Strategy health status codes.
 */
#define ATLAS_STRAT_HEALTH_GREEN   0
#define ATLAS_STRAT_HEALTH_YELLOW  1
#define ATLAS_STRAT_HEALTH_RED     2

/**
 * @class IStrategy
 * @brief Interface that every strategy plugin must implement.
 *
 * Lifecycle:
 *   1. Constructed (by factory or manually)
 *   2. Initialize() — called once at startup
 *   3. OnTick() — called on every market tick (if enabled)
 *   4. OnBar() — called on bar close
 *   5. Evaluate() — called to produce a StrategyVote
 *   6. Reset() — called on daily reset
 *   7. Shutdown() — called at EA shutdown
 *
 * Restrictions:
 *   - No broker API calls
 *   - No file access
 *   - No direct logging (use StrategyContext)
 *   - No access to CoreEngine
 *   - No access to other strategies
 *   - No static mutable state
 *   - No access to RiskEngine or ExecutionEngine
 *
 * Performance: Evaluate() must complete in ≤ 5 ms.
 */
class IStrategy
{
public:
    //=== Lifecycle ===
    virtual bool Initialize(void) = 0;
    virtual void Shutdown(void) = 0;
    virtual void Reset(void) = 0;

    //=== Callbacks ===
    virtual void OnTick(const StrategyContext &ctx) = 0;
    virtual void OnBar(const StrategyContext &ctx) = 0;
    virtual StrategyVote Evaluate(const StrategyContext &ctx) = 0;

    //=== Metadata ===
    virtual string Name(void) const = 0;
    virtual string Version(void) const = 0;
    virtual int    Priority(void) const = 0;
    virtual double Weight(void) const = 0;
    virtual bool   Enabled(void) const = 0;

    //=== Health ===
    virtual int    Health(void) const = 0;  ///< ATLAS_STRAT_HEALTH_*

    //=== Capability queries ===
    virtual bool   SupportsSymbol(const string symbol) const = 0;
    virtual bool   SupportsTimeframe(const string timeframe) const = 0;

    virtual ~IStrategy(void) {}
};

#endif // ATLAS_ISTRATEGY_MQH
//+------------------------------------------------------------------+
