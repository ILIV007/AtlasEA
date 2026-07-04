//+------------------------------------------------------------------+
//|                    Testing/Mock/MockAccount.mqh                 |
//|       AtlasEA v0.1.15.0 - Mock Account for Testing              |
//+------------------------------------------------------------------+
#ifndef ATLAS_MOCK_ACCOUNT_MQH
#define ATLAS_MOCK_ACCOUNT_MQH

#include "../TestingConfig.mqh"

/**
 * @class MockAccount
 * @brief Simulates a trading account for testing.
 *
 * Tracks: balance, equity, margin, margin level, free margin, leverage,
 * swap, commission.
 *
 * No broker API calls — pure in-memory simulation.
 */
class MockAccount
{
private:
    double m_balance;          ///< Account balance (realized)
    double m_equity;           ///< Equity (balance + floating PnL)
    double m_floating_pnl;     ///< Unrealized PnL
    double m_used_margin;      ///< Margin currently in use
    double m_leverage;         ///< Leverage (e.g., 100 = 1:100)
    double m_contract_size;    ///< Contract size per lot
    double m_commission_per_lot;
    double m_swap_per_lot;
    string m_currency;         ///< Account currency

public:
    /**
     * @brief Constructor.
     */
    MockAccount(void)
    {
        m_balance           = 10000.0;
        m_equity            = 10000.0;
        m_floating_pnl      = 0.0;
        m_used_margin       = 0.0;
        m_leverage          = 100.0;
        m_contract_size     = 100000.0;
        m_commission_per_lot = 7.0;
        m_swap_per_lot      = 0.0;
        m_currency          = "USD";
    }

    /**
     * @brief Initialize from config.
     */
    void Initialize(const TestingConfig &config)
    {
        m_balance           = config.initial_balance;
        m_equity            = config.initial_balance;
        m_floating_pnl      = 0.0;
        m_used_margin       = 0.0;
        m_leverage          = config.leverage;
        m_contract_size     = config.contract_size;
        m_commission_per_lot = config.commission_per_lot;
        m_swap_per_lot      = config.swap_per_lot;
    }

    //=== Accessors (mimic AccountInfoDouble) ===
    double GetBalance(void)      const { return m_balance; }
    double GetEquity(void)       const { return m_equity; }
    double GetMargin(void)       const { return m_used_margin; }
    double GetFreeMargin(void)   const { return m_equity - m_used_margin; }
    double GetMarginLevel(void)  const
    {
        if(m_used_margin <= 0.0) return 0.0;
        return (m_equity / m_used_margin) * 100.0;
    }
    double GetLeverage(void)     const { return m_leverage; }
    double GetContractSize(void) const { return m_contract_size; }
    string GetCurrency(void)     const { return m_currency; }

    //=== Mutators ===

    /**
     * @brief Update floating PnL (called on every tick with open positions).
     */
    void SetFloatingPnl(const double pnl)
    {
        m_floating_pnl = pnl;
        m_equity = m_balance + m_floating_pnl;
    }

    /**
     * @brief Add realized PnL (on position close).
     */
    void AddRealizedPnl(const double pnl, const double volume = 0.0)
    {
        m_balance += pnl;
        if(volume > 0.0)
            m_balance -= m_commission_per_lot * volume;
        m_equity = m_balance + m_floating_pnl;
    }

    /**
     * @brief Reserve margin for a new position.
     */
    void ReserveMargin(const double volume, const double entry_price)
    {
        double position_value = volume * m_contract_size * entry_price;
        m_used_margin += position_value / m_leverage;
    }

    /**
     * @brief Release margin when a position closes.
     */
    void ReleaseMargin(const double volume, const double entry_price)
    {
        double position_value = volume * m_contract_size * entry_price;
        double margin = position_value / m_leverage;
        m_used_margin -= margin;
        if(m_used_margin < 0.0) m_used_margin = 0.0;
    }

    /**
     * @brief Apply daily swap to all open positions.
     */
    void ApplySwap(const double total_volume)
    {
        m_balance -= m_swap_per_lot * total_volume;
        m_equity = m_balance + m_floating_pnl;
    }

    /**
     * @brief Reset to initial state.
     */
    void Reset(const double initial_balance)
    {
        m_balance      = initial_balance;
        m_equity       = initial_balance;
        m_floating_pnl = 0.0;
        m_used_margin  = 0.0;
    }
};

#endif // ATLAS_MOCK_ACCOUNT_MQH
//+------------------------------------------------------------------+
