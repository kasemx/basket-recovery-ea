#ifndef BRE_DOMAIN_MARKET_CONTEXT_SNAPSHOT_MQH
#define BRE_DOMAIN_MARKET_CONTEXT_SNAPSHOT_MQH

#include <BasketRecovery/Domain/Market/MarketQuote.mqh>

class CMarketContextSnapshot
  {
private:
   CMarketQuote m_quote;

public:
                     CMarketContextSnapshot(void) {}

                     CMarketContextSnapshot(const CMarketContextSnapshot &other)
     {
      m_quote=other.m_quote;
     }

   CMarketQuote      Quote(void) const { return m_quote; }

   static CMarketContextSnapshot Create(const CMarketQuote &quote)
     {
      CMarketContextSnapshot snapshot;
      snapshot.m_quote=quote;
      return snapshot;
     }
  };

#endif
