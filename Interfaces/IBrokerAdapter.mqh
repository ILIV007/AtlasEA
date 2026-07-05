//+------------------------------------------------------------------+
//|                                     Interfaces/IBrokerAdapter.mqh
//|                        AtlasEA v2.0 - Broker Adapter Interface     |
//+------------------------------------------------------------------+
#ifndef ATLAS_IBROKER_ADAPTER_MQH
#define ATLAS_IBROKER_ADAPTER_MQH

#include "../Config/Settings.mqh"
#include "../Contracts/Events.mqh"
#include "../Contracts/RiskDecision.mqh"
#include "../Contracts/MarketState.mqh"

/**
 * @brief Unified broker adapter interface.
 *
 * Implemented by MT5Adapter. Consumed by CoreEngine, RiskEngine, MarketEngine,
 * ExecutionEngine. This is the ONLY interface through which any module may
 * communicate with MetaTrader 5.
 *
 * Consolidates: tick capture, order dispatch, position queries, account queries,
 * symbol queries, and indicator management.
 */
class IBrokerAdapter
{
public:
    //--- Tick capture ---
    /// @brief Capture the latest tick from the terminal.
    virtual RawTick CaptureTick(void) = 0;

    //--- Order dispatch ---
    /**
     * @brief Send an order to the broker with retry logic.
     * @param req Validated OrderRequest from ExecutionEngine.
     * @return true if filled (or partially filled), false on rejection/timeout.
     */
    virtual bool SendOrder(const OrderRequest &req) = 0;

    /**
     * @brief Close all positions matching the EA's magic number (kill switch).
     * @param reason Human-readable reason for the close (logged + sent as comment).
     * @return Number of close orders submitted.
     */
    virtual int CloseAllPositionsForMagic(const string reason) = 0;

    //--- Position modification (v1.0 Step 2: Trade Lifecycle Manager) ---
    /**
     * @brief Modify a position's stop loss and/or take profit.
     * @param position_id The position ticket as a string.
     * @param sl          New stop loss (0 = no change).
     * @param tp          New take profit (0 = no change).
     * @return true if the modification was accepted by the broker.
     */
    virtual bool ModifyPositionSLTP(const string position_id, double sl, double tp) = 0;

    /**
     * @brief Close a position fully at market.
     * @param position_id The position ticket as a string.
     * @return true if the close order was accepted.
     */
    virtual bool ClosePosition(const string position_id) = 0;

    /**
     * @brief Close part of a position (partial close).
     * @param position_id The position ticket as a string.
     * @param volume      Volume to close (must be < position volume).
     * @return true if the partial close was accepted.
     */
    virtual bool ClosePartialPosition(const string position_id, double volume) = 0;

    //--- Position queries ---
    /// @brief Query all broker positions matching the EA's magic number.
    virtual PositionSnapshotEvent QueryBrokerPositions(void) = 0;

    /// @brief Count open positions for the EA's magic number.
    virtual int CountPositionsForMagic(void) = 0;

    //--- Account queries ---
    virtual double AccountEquity(void) = 0;
    virtual double AccountBalance(void) = 0;
    virtual double AccountMargin(void) = 0;
    virtual double AccountMarginLevel(void) = 0;

    //--- Symbol queries ---
    virtual double SymbolPoint(void) = 0;
    virtual int    SymbolDigits(void) = 0;
    virtual double SymbolBid(void) = 0;
    virtual double SymbolAsk(void) = 0;
    virtual double SymbolVolumeMin(void) = 0;
    virtual double SymbolVolumeMax(void) = 0;
    virtual double SymbolVolumeStep(void) = 0;
    virtual long   SymbolStopsLevel(void) = 0;
    virtual double SymbolContractSize(void) = 0;
    virtual long   SymbolFillingMode(void) = 0;

    //--- Tick value / tick size (for accurate money calculations) ---
    /// @brief Symbol tick value in account currency (SYMBOL_TRADE_TICK_VALUE).
    virtual double SymbolTickValue(void) = 0;
    /// @brief Symbol tick size in price units (SYMBOL_TRADE_TICK_SIZE).
    virtual double SymbolTickSize(void) = 0;

    //--- Margin / leverage ---
    /// @brief Initial margin required for 1 lot (SYMBOL_MARGIN_INITIAL).
    virtual double SymbolMarginInitial(void) = 0;
    /// @brief Account leverage (ACCOUNT_LEVERAGE).
    virtual long   AccountLeverage(void) = 0;

    //--- Indicator management ---
    virtual int    CreateATR(int period) = 0;
    virtual int    CreateMA(int period, int ma_method, int applied_price) = 0;
    virtual int    CreateRSI(int period, int applied_price) = 0;
    virtual int    CreateMACD(int fast, int slow, int signal, int applied_price) = 0;
    virtual int    CreateStochastic(int k, int d, int slow, int ma_method, int price_field) = 0;
    virtual int    CreateCCI(int period, int applied_price) = 0;
    virtual int    CreateADX(int period) = 0;
    virtual int    CreateBands(int period, double deviation, int applied_price) = 0;
    virtual int    CopyBuffer(int handle, int buffer_num, int start, int count, double &buffer[]) = 0;
    virtual int    CopyRates(int start, int count, MqlRates &rates[]) = 0;
    virtual void   ReleaseIndicator(int handle) = 0;
    virtual int    PeriodSeconds(void) = 0;

    //--- Lifecycle ---
    /// @brief Handle OnTrade() callback from the terminal.
    virtual void CaptureTrade(void) = 0;

    /// @brief Initialize the adapter.
    virtual bool Initialize(void) = 0;

    /// @brief Shutdown the adapter.
    virtual void Shutdown(void) = 0;

    virtual ~IBrokerAdapter(void) {}
};

#endif // ATLAS_IBROKER_ADAPTER_MQH
//+------------------------------------------------------------------+
