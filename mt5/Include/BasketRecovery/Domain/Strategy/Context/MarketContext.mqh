#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_MARKET_CONTEXT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_MARKET_CONTEXT_MQH

class CMarketContext
  {
private:
   string m_symbol;
   double m_bid;
   double m_ask;
   double m_pipSize;

public:
                     CMarketContext(void) {}

                     CMarketContext(const CMarketContext &other)
     {
      m_symbol=other.m_symbol;
      m_bid=other.m_bid;
      m_ask=other.m_ask;
      m_pipSize=other.m_pipSize;
     }

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
