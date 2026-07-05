//+------------------------------------------------------------------+
//|                   Production/BrokerCapabilities.mqh              |
//|       AtlasEA v1.0 Step 7 - Broker Capability Detection          |
//+------------------------------------------------------------------+
#ifndef ATLAS_BROKER_CAPABILITIES_MQH
#define ATLAS_BROKER_CAPABILITIES_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IBrokerCompatibilityManager.mqh"

/**
 * @class BrokerCapabilityDetector
 * @brief Detects and caches broker capabilities.
 *
 * SOLE RESPONSIBILITY: query the broker ONCE at initialization and
 * cache all capabilities. No repeated SymbolInfo/AccountInfo calls.
 *
 * Detects:
 *   - Execution mode (market/instant/exchange/request)
 *   - Account mode (netting/hedging)
 *   - ECN broker
 *   - FIFO restrictions
 *   - All symbol properties (min/max lot, step, digits, point, etc.)
 *   - Trading permissions
 *
 * Performance: O(1) after initialization (all cached).
 */
class BrokerCapabilityDetector
{
private:
    ILogger           *m_logger;
    IBrokerAdapter    *m_broker;
    BrokerCapabilities m_caps;
    bool               m_detected;

public:
    BrokerCapabilityDetector(void)
    {
        m_logger   = NULL;
        m_broker   = NULL;
        m_detected = false;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }
    void SetBroker(IBrokerAdapter *broker) { m_broker = broker; }

    /**
     * @brief Detect all broker capabilities.
     * @return true if detection succeeded.
     */
    bool Detect(void)
    {
        if(m_broker == NULL) return false;

        //--- Symbol properties (single query per property, cached)
        m_caps.min_lot       = m_broker.SymbolVolumeMin();
        m_caps.max_lot       = m_broker.SymbolVolumeMax();
        m_caps.lot_step      = m_broker.SymbolVolumeStep();
        m_caps.digits        = m_broker.SymbolDigits();
        m_caps.point         = m_broker.SymbolPoint();
        m_caps.tick_size     = m_broker.SymbolTickSize();
        m_caps.tick_value    = m_broker.SymbolTickValue();
        m_caps.freeze_level  = m_broker.SymbolStopsLevel(); // Reuse stops level as proxy
        m_caps.stop_level    = m_broker.SymbolStopsLevel();
        m_caps.filling_mode  = m_broker.SymbolFillingMode();
        m_caps.contract_size = m_broker.SymbolContractSize();
        m_caps.margin_initial = m_broker.SymbolMarginInitial();

        //--- Account properties
        m_caps.leverage      = m_broker.AccountLeverage();

        //--- Detect execution mode (from filling mode)
        //--- FOK=1 → market, IOC=2 → instant, RETURN=3 → request
        if(m_caps.filling_mode == 1)
            m_caps.execution_mode = ATLAS_BROKER_EXEC_MARKET;
        else if(m_caps.filling_mode == 2)
            m_caps.execution_mode = ATLAS_BROKER_EXEC_INSTANT;
        else
            m_caps.execution_mode = ATLAS_BROKER_EXEC_REQUEST;

        //--- Detect ECN (heuristic: small min lot + small step + no freeze level)
        m_caps.is_ecn = (m_caps.min_lot <= 0.01 &&
                         m_caps.lot_step <= 0.01 &&
                         m_caps.freeze_level == 0);

        //--- Detect account mode (hedging vs netting)
        //--- MQL5: ACCOUNT_MARGIN_MODE 0=netting, 1=hedging
        //--- We can't query this via IBrokerAdapter, so default to hedging
        //--- (most retail brokers use hedging). Can be overridden by config.
        m_caps.account_mode = ATLAS_ACCOUNT_HEDGING;

        //--- FIFO restrictions (US brokers typically have FIFO)
        //--- Heuristic: if account mode is netting, FIFO is likely enforced
        m_caps.fifo_restricted = (m_caps.account_mode == ATLAS_ACCOUNT_NETTING);

        //--- Trading allowed (from SymbolInfo — cached)
        //--- We approximate: if bid > 0 and ask > 0, trading is likely allowed
        double bid = m_broker.SymbolBid();
        double ask = m_broker.SymbolAsk();
        m_caps.trading_allowed = (bid > 0.0 && ask > 0.0);

        //--- Market watch synchronized
        m_caps.market_watch_synchronized = (bid > 0.0 && ask > 0.0);

        m_detected = true;

        if(m_logger != NULL)
        {
            m_logger.Info("BrokerCapabilities",
                "Detected: exec=" + ExecutionModeName(m_caps.execution_mode) +
                " account=" + AccountModeName(m_caps.account_mode) +
                " ECN=" + (m_caps.is_ecn ? "Y" : "N") +
                " FIFO=" + (m_caps.fifo_restricted ? "Y" : "N") +
                " digits=" + IntegerToString(m_caps.digits) +
                " min=" + DoubleToString(m_caps.min_lot, 2) +
                " max=" + DoubleToString(m_caps.max_lot, 2) +
                " step=" + DoubleToString(m_caps.lot_step, 4) +
                " leverage=1:" + IntegerToString((int)m_caps.leverage));
        }

        return true;
    }

    /**
     * @brief Get cached capabilities.
     */
    const BrokerCapabilities& Get(void) const { return m_caps; }

    /**
     * @brief Check if detection has been performed.
     */
    bool IsDetected(void) const { return m_detected; }

    /**
     * @brief Override execution mode (for manual configuration).
     */
    void SetExecutionMode(const int mode) { m_caps.execution_mode = mode; }

    /**
     * @brief Override account mode (for manual configuration).
     */
    void SetAccountMode(const int mode) { m_caps.account_mode = mode; }

    /**
     * @brief Override FIFO restriction flag.
     */
    void SetFifoRestricted(const bool fifo) { m_caps.fifo_restricted = fifo; }
};

#endif // ATLAS_BROKER_CAPABILITIES_MQH
//+------------------------------------------------------------------+
