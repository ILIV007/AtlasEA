//+------------------------------------------------------------------+
//|                     Production/SymbolValidator.mqh               |
//|       AtlasEA v1.0 Step 7 - Pre-Order Symbol Validation           |
//+------------------------------------------------------------------+
#ifndef ATLAS_SYMBOL_VALIDATOR_MQH
#define ATLAS_SYMBOL_VALIDATOR_MQH

#include "../Config/Settings.mqh"
#include "../Interfaces/ILogger.mqh"
#include "../Interfaces/IBrokerAdapter.mqh"
#include "../Interfaces/IBrokerCompatibilityManager.mqh"

/**
 * @class SymbolValidator
 * @brief Validates symbol conditions before every order.
 *
 * SOLE RESPONSIBILITY: check 10 pre-order conditions.
 * Uses cached BrokerCapabilities + current market data.
 *
 * Checks:
 *   1. Trading enabled
 *   2. Session open
 *   3. Spread acceptable
 *   4. Volume valid (min/max/step)
 *   5. Stops valid (SL/TP > 0, correct side)
 *   6. Price normalized (to digits)
 *   7. Freeze level respected
 *   8. Stop level respected
 *   9. Margin available
 *  10. Symbol synchronized
 *
 * Performance: O(1) — all cached except current bid/ask.
 */
class SymbolValidator
{
private:
    ILogger              *m_logger;
    IBrokerAdapter       *m_broker;
    BrokerCapabilities    m_caps;
    double                m_max_spread_points;

public:
    SymbolValidator(void)
    {
        m_logger            = NULL;
        m_broker            = NULL;
        m_max_spread_points = 50.0;
    }

    void SetLogger(ILogger *logger) { m_logger = logger; }
    void SetBroker(IBrokerAdapter *broker) { m_broker = broker; }
    void SetCapabilities(const BrokerCapabilities &caps) { m_caps = caps; }
    void SetMaxSpreadPoints(const double pts) { m_max_spread_points = pts; }

    /**
     * @brief Validate symbol before sending an order.
     * @param volume      Order volume.
     * @param sl          Stop loss price.
     * @param tp          Take profit price.
     * @param entry_price Entry price.
     * @param direction   ATLAS_ORDER_BUY or ATLAS_ORDER_SELL.
     * @return SymbolValidationResult.
     */
    SymbolValidationResult Validate(const double volume,
                                     const double sl,
                                     const double tp,
                                     const double entry_price,
                                     const int direction)
    {
        SymbolValidationResult result;

        if(m_broker == NULL)
        {
            result.code   = ATLAS_SV_TRADING_DISABLED;
            result.detail = "Broker adapter is NULL";
            return result;
        }

        //=== 1. Trading enabled ===
        if(!m_caps.trading_allowed)
        {
            result.code   = ATLAS_SV_TRADING_DISABLED;
            result.detail = "Symbol trading is disabled";
            return result;
        }

        //=== 2. Session open (bid/ask > 0) ===
        double bid = m_broker.SymbolBid();
        double ask = m_broker.SymbolAsk();
        if(bid <= 0.0 || ask <= 0.0)
        {
            result.code   = ATLAS_SV_SESSION_CLOSED;
            result.detail = "No bid/ask (session likely closed)";
            return result;
        }

        //=== 3. Spread acceptable ===
        double spread = ask - bid;
        double spread_pts = (m_caps.point > 0.0) ? spread / m_caps.point : 0.0;
        result.spread_points = spread_pts;
        if(m_max_spread_points > 0.0 && spread_pts > m_max_spread_points)
        {
            result.code   = ATLAS_SV_SPREAD_TOO_HIGH;
            result.detail = "Spread " + DoubleToString(spread_pts, 1) +
                            " > max " + DoubleToString(m_max_spread_points, 1);
            return result;
        }

        //=== 4. Volume valid ===
        if(volume < m_caps.min_lot || volume > m_caps.max_lot)
        {
            result.code   = ATLAS_SV_VOLUME_INVALID;
            result.detail = "Volume " + DoubleToString(volume, 4) +
                            " outside [" + DoubleToString(m_caps.min_lot, 2) +
                            ", " + DoubleToString(m_caps.max_lot, 2) + "]";
            return result;
        }
        //--- Check step alignment
        if(m_caps.lot_step > 0.0)
        {
            double remainder = MathAbs(volume / m_caps.lot_step -
                                        MathRound(volume / m_caps.lot_step));
            if(remainder > 0.001)
            {
                result.code   = ATLAS_SV_VOLUME_INVALID;
                result.detail = "Volume not aligned to step " +
                                DoubleToString(m_caps.lot_step, 4);
                return result;
            }
        }

        //=== 5. Stops valid ===
        if(sl <= 0.0 || tp <= 0.0)
        {
            result.code   = ATLAS_SV_STOPS_INVALID;
            result.detail = "SL and TP must be > 0";
            return result;
        }
        if(direction == 1) // BUY
        {
            if(sl >= entry_price || tp <= entry_price)
            {
                result.code   = ATLAS_SV_STOPS_INVALID;
                result.detail = "BUY: SL must be < entry, TP must be > entry";
                return result;
            }
        }
        else // SELL
        {
            if(sl <= entry_price || tp >= entry_price)
            {
                result.code   = ATLAS_SV_STOPS_INVALID;
                result.detail = "SELL: SL must be > entry, TP must be < entry";
                return result;
            }
        }

        //=== 6. Price normalized ===
        if(entry_price > 0.0 && m_caps.point > 0.0)
        {
            double normalized = NormalizeDouble(entry_price, m_caps.digits);
            if(MathAbs(entry_price - normalized) > m_caps.point * 0.5)
            {
                result.code   = ATLAS_SV_PRICE_NOT_NORMALIZED;
                result.detail = "Entry price not normalized to " +
                                IntegerToString(m_caps.digits) + " digits";
                return result;
            }
        }

        //=== 7. Freeze level respected ===
        result.freeze_level_pts = (double)m_caps.freeze_level;
        if(m_caps.freeze_level > 0 && m_caps.point > 0.0)
        {
            double freeze_dist = m_caps.freeze_level * m_caps.point;
            if(direction == 1) // BUY
            {
                if(MathAbs(sl - bid) < freeze_dist || MathAbs(tp - bid) < freeze_dist)
                {
                    result.code   = ATLAS_SV_FREEZE_LEVEL;
                    result.detail = "SL/TP within freeze level of current price";
                    return result;
                }
            }
            else
            {
                if(MathAbs(sl - ask) < freeze_dist || MathAbs(tp - ask) < freeze_dist)
                {
                    result.code   = ATLAS_SV_FREEZE_LEVEL;
                    result.detail = "SL/TP within freeze level of current price";
                    return result;
                }
            }
        }

        //=== 8. Stop level respected ===
        result.stop_level_pts = (double)m_caps.stop_level;
        if(m_caps.stop_level > 0 && m_caps.point > 0.0)
        {
            double stop_dist = m_caps.stop_level * m_caps.point;
            if(direction == 1) // BUY
            {
                if((entry_price - sl) < stop_dist || (tp - entry_price) < stop_dist)
                {
                    result.code   = ATLAS_SV_STOP_LEVEL;
                    result.detail = "SL/TP closer than stop level " +
                                    IntegerToString((int)m_caps.stop_level) + " points";
                    return result;
                }
            }
            else
            {
                if((sl - entry_price) < stop_dist || (entry_price - tp) < stop_dist)
                {
                    result.code   = ATLAS_SV_STOP_LEVEL;
                    result.detail = "SL/TP closer than stop level " +
                                    IntegerToString((int)m_caps.stop_level) + " points";
                    return result;
                }
            }
        }

        //=== 9. Margin available ===
        double equity = m_broker.AccountEquity();
        double margin = m_broker.AccountMargin();
        double free_margin = equity - margin;
        if(m_caps.margin_initial > 0.0)
        {
            double required = m_caps.margin_initial * volume;
            if(required > free_margin)
            {
                result.code   = ATLAS_SV_MARGIN_INSUFFICIENT;
                result.detail = "Margin required " + DoubleToString(required, 2) +
                                " > free " + DoubleToString(free_margin, 2);
                return result;
            }
        }

        //=== 10. Symbol synchronized ===
        if(!m_caps.market_watch_synchronized)
        {
            result.code   = ATLAS_SV_NOT_SYNCHRONIZED;
            result.detail = "Symbol not synchronized in Market Watch";
            return result;
        }

        //--- All checks passed
        result.code   = ATLAS_SV_OK;
        result.detail = "All symbol checks passed";
        return result;
    }
};

#endif // ATLAS_SYMBOL_VALIDATOR_MQH
//+------------------------------------------------------------------+
