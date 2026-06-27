#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_MARKET_CONTEXT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_MARKET_CONTEXT_MQH

class CMarketContext
  {
private:
   string m_symbol;
   double m_bid;
   double m_ask;
   double m_pipSize;

                     CMarketContext(void) {}

public:
   string            Symbol(void) const { return m_symbol; }
   double            Bid(void) const { return m_bid; }
   double            Ask(void) const { return m_ask; }
   double            PipSize(void) const { return m_pipSize; }

   static CMarketContext Create(const string symbol,const double bid,const double ask,const double pipSize)
     {
      CMarketContext context;
      context.m_symbol=symbol;
      context.m_bid=bid;
      context.m_ask=ask;
      context.m_pipSize=pipSize;
      return context;
     }
  };

#endif
