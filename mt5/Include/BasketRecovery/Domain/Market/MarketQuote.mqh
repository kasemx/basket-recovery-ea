#ifndef BRE_DOMAIN_MARKET_QUOTE_MQH
#define BRE_DOMAIN_MARKET_QUOTE_MQH

#include <BasketRecovery/Domain/Market/TradingSessionStatus.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CMarketQuote
  {
private:
   string                        m_symbol;
   double                        m_bid;
   double                        m_ask;
   int                           m_spreadPoints;
   double                        m_point;
   int                           m_digits;
   double                        m_tickSize;
   double                        m_tickValue;
   datetime                      m_timestampUtc;
   int                           m_freshnessAgeMs;
   ENUM_BRE_TRADING_SESSION_STATUS m_sessionStatus;
   CSymbolTradingConstraints     m_constraints;

public:
                     CMarketQuote(void) { m_freshnessAgeMs=0; m_sessionStatus=BRE_TRADING_SESSION_UNKNOWN; }

                     CMarketQuote(const CMarketQuote &other)
     {
      m_symbol=other.m_symbol;
      m_bid=other.m_bid;
      m_ask=other.m_ask;
      m_spreadPoints=other.m_spreadPoints;
      m_point=other.m_point;
      m_digits=other.m_digits;
      m_tickSize=other.m_tickSize;
      m_tickValue=other.m_tickValue;
      m_timestampUtc=other.m_timestampUtc;
      m_freshnessAgeMs=other.m_freshnessAgeMs;
      m_sessionStatus=other.m_sessionStatus;
      m_constraints=other.m_constraints;
     }

   string                        Symbol(void) const { return m_symbol; }
   double                        Bid(void) const { return m_bid; }
   double                        Ask(void) const { return m_ask; }
   int                           SpreadPoints(void) const { return m_spreadPoints; }
   double                        Point(void) const { return m_point; }
   int                           Digits(void) const { return m_digits; }
   double                        TickSize(void) const { return m_tickSize; }
   double                        TickValue(void) const { return m_tickValue; }
   datetime                      TimestampUtc(void) const { return m_timestampUtc; }
   int                           FreshnessAgeMs(void) const { return m_freshnessAgeMs; }
   ENUM_BRE_TRADING_SESSION_STATUS SessionStatus(void) const { return m_sessionStatus; }
   CSymbolTradingConstraints     Constraints(void) const { return m_constraints; }

   static CMarketQuote           Create(const string symbol,
                                        const double bid,
                                        const double ask,
                                        const int spreadPoints,
                                        const double point,
                                        const int digits,
                                        const double tickSize,
                                        const double tickValue,
                                        const datetime timestampUtc,
                                        const int freshnessAgeMs,
                                        const ENUM_BRE_TRADING_SESSION_STATUS sessionStatus,
                                        const CSymbolTradingConstraints &constraints)
     {
      CMarketQuote quote;
      quote.m_symbol=symbol;
      quote.m_bid=bid;
      quote.m_ask=ask;
      quote.m_spreadPoints=spreadPoints;
      quote.m_point=point;
      quote.m_digits=digits;
      quote.m_tickSize=tickSize;
      quote.m_tickValue=tickValue;
      quote.m_timestampUtc=timestampUtc;
      quote.m_freshnessAgeMs=freshnessAgeMs;
      quote.m_sessionStatus=sessionStatus;
      quote.m_constraints=constraints;
      return quote;
     }
  };

#endif
