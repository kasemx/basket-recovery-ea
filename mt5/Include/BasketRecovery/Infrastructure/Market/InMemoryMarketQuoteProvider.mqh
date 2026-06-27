#ifndef BRE_INF_IN_MEMORY_MARKET_QUOTE_PROVIDER_MQH
#define BRE_INF_IN_MEMORY_MARKET_QUOTE_PROVIDER_MQH

#include <BasketRecovery/Application/Ports/IMarketContextProvider.mqh>

class CInMemoryMarketQuoteProvider : public IMarketContextProvider
  {
private:
   string m_symbol;
   double m_bid;
   double m_ask;
   double m_pipSize;
   bool   m_hasQuote;

public:
                     CInMemoryMarketQuoteProvider(void)
     {
      m_symbol="";
      m_bid=0.0;
      m_ask=0.0;
      m_pipSize=0.01;
      m_hasQuote=false;
     }

   void              SetQuote(const string symbol,const double bid,const double ask,const double pipSize)
     {
      m_symbol=symbol;
      m_bid=bid;
      m_ask=ask;
      m_pipSize=pipSize;
      m_hasQuote=(symbol!="" && bid>0.0 && ask>0.0);
     }

   virtual bool      TryBuildForBasket(const CBasketAggregate &basket,
                                       CMarketContext &outMarket,
                                       CRiskRuntimeContext &outRiskContext) const
     {
      if(!m_hasQuote || basket.Symbol()!=m_symbol)
         return false;

      outMarket=CMarketContext::Create(m_symbol,m_bid,m_ask,m_pipSize);

      CStrategyProfile profile;
      if(!basket.StrategyProfile(profile))
         return false;

      CRiskPlan riskPlan=profile.RiskPlan();
      outRiskContext=CRiskRuntimeContext::Create(0.0,
                                                 riskPlan.TargetRiskPct(),
                                                 riskPlan.MaxRiskPct(),
                                                 basket.Metadata().RealizedProfit().Amount(),
                                                 !basket.RecoveryPermanentlyDisabled(),
                                                 false);
      return true;
     }
  };

#endif
