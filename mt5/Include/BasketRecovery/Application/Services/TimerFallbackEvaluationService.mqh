#ifndef BRE_APP_TIMER_FALLBACK_EVALUATION_SERVICE_MQH
#define BRE_APP_TIMER_FALLBACK_EVALUATION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketContextProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CTimerFallbackEvaluationService
  {
private:
   IBasketRepository              *m_repository;
   CMarketContextProviderAdapter  *m_marketAdapter;
   CEvaluateBasketStrategyUseCase *m_evaluateUseCase;
   CFastCommandStagingBuffer      *m_stagingQueue;
   CSymbolBasketIndex             *m_symbolIndex;
   CFastPathConfig                 m_config;
   ulong                           m_lastTickMsc;

public:
                     CTimerFallbackEvaluationService(IBasketRepository *repository,
                                                     CMarketContextProviderAdapter *marketAdapter,
                                                     CEvaluateBasketStrategyUseCase *evaluateUseCase,
                                                     CFastCommandStagingBuffer *stagingQueue,
                                                     CSymbolBasketIndex *symbolIndex,
                                                     const CFastPathConfig &config)
     {
      m_repository=repository;
      m_marketAdapter=marketAdapter;
      m_evaluateUseCase=evaluateUseCase;
      m_stagingQueue=stagingQueue;
      m_symbolIndex=symbolIndex;
      m_config=config;
      m_lastTickMsc=GetTickCount64();
     }

   void              NotifyTick(void)
     {
      m_lastTickMsc=GetTickCount64();
     }

   int               RunIfDue(void)
     {
      if(m_config.TickSilenceFallbackMs()<=0)
         return 0;

      ulong elapsed=GetTickCount64()-m_lastTickMsc;
      if(elapsed<(ulong)m_config.TickSilenceFallbackMs())
         return 0;

      if(m_repository==NULL || m_marketAdapter==NULL || m_evaluateUseCase==NULL || m_stagingQueue==NULL)
         return 0;

      if(m_symbolIndex!=NULL && m_symbolIndex.IsDirty())
         m_symbolIndex.Rebuild(m_repository);

      CBasketAggregate baskets[];
      int basketCount=m_repository.LoadAll(baskets);
      int evaluated=0;
      for(int i=0;i<basketCount && evaluated<m_config.MaxBasketsPerTick();i++)
        {
         CBasketAggregate basket=baskets[i];
         if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
            continue;
         if(!basket.HasStrategyProfile() || basket.StrategyMigrationRequired())
            continue;

         CMarketContext market;
         CRiskRuntimeContext riskContext;
         if(!m_marketAdapter.TryBuildForBasket(basket,market,riskContext))
            continue;

         if(m_evaluateUseCase.ExecuteFastPath(basket,market,riskContext,m_stagingQueue,
                                              basket.CorrelationKey()).IsOk())
            evaluated++;
        }

      return evaluated;
     }
  };

#endif
