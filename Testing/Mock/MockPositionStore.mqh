//+------------------------------------------------------------------+
//|                 Testing/Mock/MockPositionStore.mqh              |
//|       AtlasEA v0.1.15.0 - Mock Position Store for Testing       |
//+------------------------------------------------------------------+
#ifndef ATLAS_MOCK_POSITION_STORE_MQH
#define ATLAS_MOCK_POSITION_STORE_MQH

#include "../TestingConfig.mqh"
#include "../../Contracts/Events.mqh"

/**
 * @struct MockPosition
 * @brief Extended position with mock-specific fields.
 */
struct MockPosition
{
    ulong    ticket;
    string   symbol;
    int      type;           ///< POSITION_TYPE_BUY / SELL
    double   volume;
    double   open_price;
    double   current_sl;
    double   current_tp;
    double   pnl;
    double   swap;
    double   commission;
    datetime open_time;
    bool     is_closed;
    datetime close_time;
    double   close_price;
    double   realized_pnl;
};

/**
 * @class MockPositionStore
 * @brief In-memory position store for testing.
 *
 * Supports: open, close, modify, partial close, history, PnL calculation.
 * No broker API calls — pure in-memory simulation.
 */
class MockPositionStore
{
private:
    MockPosition m_positions[ATLAS_MAX_POSITIONS];
    MockPosition m_history[ATLAS_MAX_POSITIONS * 4];  ///< Closed positions
    int          m_open_count;
    int          m_history_count;
    ulong        m_next_ticket;
    long         m_magic;
    double       m_contract_size;

public:
    /**
     * @brief Constructor.
     */
    MockPositionStore(void)
    {
        m_open_count   = 0;
        m_history_count = 0;
        m_next_ticket   = 100000;
        m_magic         = 999999;
        m_contract_size = 100000.0;
        for(int i = 0; i < ATLAS_MAX_POSITIONS; i++)
        {
            m_positions[i].ticket = 0;
            m_positions[i].is_closed = true;
        }
    }

    /**
     * @brief Initialize from config.
     */
    void Initialize(const TestingConfig &config)
    {
        m_magic         = config.magic_number;
        m_contract_size = config.contract_size;
        Reset();
    }

    /**
     * @brief Reset to empty state.
     */
    void Reset(void)
    {
        m_open_count    = 0;
        m_history_count = 0;
        m_next_ticket   = 100000;
    }

    /**
     * @brief Open a new position.
     * @return Ticket (>0) on success, 0 on failure (max positions reached).
     */
    ulong OpenPosition(const string symbol, const int type, const double volume,
                       const double price, const double sl, const double tp)
    {
        if(m_open_count >= ATLAS_MAX_POSITIONS) return 0;

        MockPosition &pos = m_positions[m_open_count];
        pos.ticket      = m_next_ticket++;
        pos.symbol      = symbol;
        pos.type        = type;
        pos.volume      = volume;
        pos.open_price  = price;
        pos.current_sl  = sl;
        pos.current_tp  = tp;
        pos.pnl         = 0.0;
        pos.swap        = 0.0;
        pos.commission  = 0.0;
        pos.open_time   = TimeCurrent();
        pos.is_closed   = false;
        pos.close_time  = 0;
        pos.close_price = 0.0;
        pos.realized_pnl = 0.0;

        m_open_count++;
        return pos.ticket;
    }

    /**
     * @brief Close a position by ticket.
     * @return true on success, false if ticket not found.
     */
    bool ClosePosition(const ulong ticket, const double close_price)
    {
        for(int i = 0; i < m_open_count; i++)
        {
            if(m_positions[i].ticket == ticket)
            {
                m_positions[i].is_closed   = true;
                m_positions[i].close_time  = TimeCurrent();
                m_positions[i].close_price = close_price;

                //--- Calculate realized PnL
                double diff;
                if(m_positions[i].type == POSITION_TYPE_BUY)
                    diff = close_price - m_positions[i].open_price;
                else
                    diff = m_positions[i].open_price - close_price;

                m_positions[i].realized_pnl = diff * m_positions[i].volume * m_contract_size;
                m_positions[i].pnl = m_positions[i].realized_pnl;

                //--- Move to history
                if(m_history_count < ATLAS_MAX_POSITIONS * 4)
                {
                    m_history[m_history_count] = m_positions[i];
                    m_history_count++;
                }

                //--- Shift remaining open positions
                for(int j = i + 1; j < m_open_count; j++)
                    m_positions[j-1] = m_positions[j];
                m_open_count--;
                m_positions[m_open_count].ticket = 0;

                return true;
            }
        }
        return false;
    }

    /**
     * @brief Partially close a position.
     * @param ticket Position ticket.
     * @param close_volume Volume to close (must be < position volume).
     * @param close_price Price at which to close.
     * @return true on success.
     */
    bool PartialClose(const ulong ticket, const double close_volume, const double close_price)
    {
        for(int i = 0; i < m_open_count; i++)
        {
            if(m_positions[i].ticket == ticket)
            {
                if(close_volume >= m_positions[i].volume) return false;

                //--- Calculate partial PnL
                double diff;
                if(m_positions[i].type == POSITION_TYPE_BUY)
                    diff = close_price - m_positions[i].open_price;
                else
                    diff = m_positions[i].open_price - close_price;

                double partial_pnl = diff * close_volume * m_contract_size;

                //--- Reduce volume
                m_positions[i].volume -= close_volume;

                //--- Record partial close in history
                if(m_history_count < ATLAS_MAX_POSITIONS * 4)
                {
                    m_history[m_history_count] = m_positions[i];
                    m_history[m_history_count].volume = close_volume;
                    m_history[m_history_count].is_closed = true;
                    m_history[m_history_count].close_time = TimeCurrent();
                    m_history[m_history_count].close_price = close_price;
                    m_history[m_history_count].realized_pnl = partial_pnl;
                    m_history_count++;
                }

                return true;
            }
        }
        return false;
    }

    /**
     * @brief Modify SL/TP for a position.
     */
    bool ModifyPosition(const ulong ticket, const double new_sl, const double new_tp)
    {
        for(int i = 0; i < m_open_count; i++)
        {
            if(m_positions[i].ticket == ticket)
            {
                m_positions[i].current_sl = new_sl;
                m_positions[i].current_tp = new_tp;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Update floating PnL for all open positions.
     */
    void UpdatePnl(const double bid, const double ask)
    {
        for(int i = 0; i < m_open_count; i++)
        {
            double diff;
            if(m_positions[i].type == POSITION_TYPE_BUY)
                diff = bid - m_positions[i].open_price;
            else
                diff = m_positions[i].open_price - ask;

            m_positions[i].pnl = diff * m_positions[i].volume * m_contract_size;
        }
    }

    /**
     * @brief Get total floating PnL.
     */
    double GetTotalPnl(void) const
    {
        double total = 0.0;
        for(int i = 0; i < m_open_count; i++)
            total += m_positions[i].pnl;
        return total;
    }

    /**
     * @brief Get total open volume.
     */
    double GetTotalVolume(void) const
    {
        double total = 0.0;
        for(int i = 0; i < m_open_count; i++)
            total += m_positions[i].volume;
        return total;
    }

    /**
     * @brief Get open position count.
     */
    int GetOpenCount(void) const { return m_open_count; }

    /**
     * @brief Get a position by index.
     */
    bool GetPosition(const int index, MockPosition &out) const
    {
        if(index < 0 || index >= m_open_count) return false;
        out = m_positions[index];
        return true;
    }

    /**
     * @brief Convert to PositionSnapshotEvent (for IContextStore compatibility).
     */
    PositionSnapshotEvent ToSnapshotEvent(void) const
    {
        PositionSnapshotEvent snap;
        snap.count = m_open_count;
        snap.timestamp = TimeCurrent();
        for(int i = 0; i < m_open_count && i < ATLAS_MAX_POSITIONS; i++)
        {
            snap.broker_positions[i].position_id     = IntegerToString(m_positions[i].ticket);
            snap.broker_positions[i].symbol          = m_positions[i].symbol;
            snap.broker_positions[i].type            = m_positions[i].type;
            snap.broker_positions[i].volume          = m_positions[i].volume;
            snap.broker_positions[i].open_price      = m_positions[i].open_price;
            snap.broker_positions[i].current_sl      = m_positions[i].current_sl;
            snap.broker_positions[i].current_tp      = m_positions[i].current_tp;
            snap.broker_positions[i].pnl             = m_positions[i].pnl;
            snap.broker_positions[i].open_time       = m_positions[i].open_time;
            snap.broker_positions[i].broker_verified = true;
        }
        return snap;
    }

    /**
     * @brief Close all positions (for kill switch test).
     * @return Number of positions closed.
     */
    int CloseAll(const double bid, const double ask)
    {
        int count = m_open_count;
        for(int i = m_open_count - 1; i >= 0; i--)
        {
            double close_price = (m_positions[i].type == POSITION_TYPE_BUY) ? bid : ask;
            ClosePosition(m_positions[i].ticket, close_price);
        }
        return count;
    }
};

#endif // ATLAS_MOCK_POSITION_STORE_MQH
//+------------------------------------------------------------------+
