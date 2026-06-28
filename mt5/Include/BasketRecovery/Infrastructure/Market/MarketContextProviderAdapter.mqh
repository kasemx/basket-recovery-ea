#ifndef BRE_INF_MARKET_CONTEXT_PROVIDER_ADAPTER_MQH
#define BRE_INF_MARKET_CONTEXT_PROVIDER_ADAPTER_MQH

#include <BasketRecovery/Application/Ports/IMarketContextProvider.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Risk/BasketRiskReadModelService.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketSafetyGuard.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>

class CMarketContextProviderAdapter : public IMarketContextProvider
  {
private:
   IMarketDataProvider      *m_marketData;
   IPositionSnapshotStore   *m_snapshotStore;
   CMarketSafetyGuard        m_safetyGuard;
   bool                       m_ownsMarketData;

   double            ResolvePipSize(const CMarketQuote &quote) const
     {
      int digits=quote.Digits();
      double point=quote.Point();
      if(point<=0.0)
         return 0.01;
      if(digits==3 || digits==5)
         return point*10.0;
      return point;
     }

public:
                     CMarketContextProviderAdapter(IMarketDataProvider *marketData,
                                                   const CMarketSafetyConfig &safetyConfig,
                                                   IPositionSnapshotStore *snapshotStore=NULL,
                                                   const bool takeMarketDataOwnership=false)
     {
      m_marketData=marketData;
      m_snapshotStore=snapshotStore;
      m_safetyGuard=CMarketSafetyGuard(safetyConfig);
      m_ownsMarketData=takeMarketDataOwnership;
     }

   virtual          ~CMarketContextProviderAdapter(void)
     {
      if(m_ownsMarketData && m_marketData!=NULL)
        {
         delete m_marketData;
         m_marketData=NULL;
        }
     }

   virtual bool      TryBuildForBasket(const CBasketAggregate &basket,
                                       CMarketContext &outMarket,
                                       CRiskRuntimeContext &outRiskContext)
     {
      if(m_marketData==NULL)
         return false;

      string symbol=basket.Symbol();
      CResult<CMarketQuote> quoteResult=m_marketData.TryGetQuote(symbol);
      if(quoteResult.IsFail())
         return false;

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);
      return TryBuildFromQuote(basket,quote,outMarket,outRiskContext);
     }

   bool              TryBuildFromQuote(const CBasketAggregate &basket,
                                       const CMarketQuote &quote,
                                       CMarketContext &outMarket,
                                       CRiskRuntimeContext &outRiskContext)
     {
      if(m_marketData==NULL)
         return false;

      CResult<CAccountContextSnapshot> accountResult=m_marketData.TryGetAccountSnapshot();
      if(accountResult.IsFail())
         return false;

      CAccountContextSnapshot account;
      accountResult.TryGetValue(account);

      string warningKey="";
      if(m_safetyGuard.ValidateForEvaluation(quote,account,warningKey).IsFail())
         return false;

      outMarket=CMarketContext::Create(quote.Symbol(),quote.Bid(),quote.Ask(),ResolvePipSize(quote));

      outRiskContext=CBasketRiskReadModelService::TryBuildRiskRuntimeContext(basket,
                                                                           quote,
                                                                           account,
                                                                           m_snapshotStore,
                                                                           CRiskCalculationSettings::CreateDefault());
      return true;
     }

   bool              TryBuildRiskGateInput(const CBasketAggregate &basket,
                                           const string correlationKey,
                                           const datetime timestampUtc,
                                           const ulong quoteSequence,
                                           CRecoveryRiskGateInput &outInput)
     {
      if(m_marketData==NULL)
         return false;

      string symbol=basket.Symbol();
      CResult<CMarketQuote> quoteResult=m_marketData.TryGetQuote(symbol);
      if(quoteResult.IsFail())
         return false;

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      CResult<CAccountContextSnapshot> accountResult=m_marketData.TryGetAccountSnapshot();
      if(accountResult.IsFail())
         return false;

      CAccountContextSnapshot account;
      accountResult.TryGetValue(account);

      string warningKey="";
      if(m_safetyGuard.ValidateForEvaluation(quote,account,warningKey).IsFail())
         return false;

      outInput=CRecoveryRiskGateInput::Create(quote,
                                              account,
                                              quoteSequence,
                                              m_safetyGuard.Config().QuoteStaleThresholdMs(),
                                              basket.StrategyProfileHash(),
                                              correlationKey,
                                              timestampUtc);
      return true;
     }
  };

#endif
