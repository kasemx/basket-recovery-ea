#ifndef BRE_APP_FAST_MARKET_EVALUATION_COORDINATOR_MQH
#define BRE_APP_FAST_MARKET_EVALUATION_COORDINATOR_MQH

#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/FastPath/FastEvaluationTriggerPolicy.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryFastSafetyAuditBuffer.mqh>
#include <BasketRecovery/Application/FastPath/ForceReevaluationFlag.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Infrastructure/Market/TickQuoteReader.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/BasketSnapshotLiveRefresh.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFastMarketEvaluationCoordinator
  {
private:
   IBasketRepository              *m_repository;
   IPositionSnapshotStore         *m_snapshotStore;
   CEvaluateBasketStrategyUseCase *m_evaluateUseCase;
   CMarketContextProviderAdapter  *m_marketAdapter;
   CFastCommandStagingBuffer      *m_stagingQueue;
   CBasketFastStateRegistry       *m_fastStateRegistry;
   CSymbolBasketIndex             *m_symbolIndex;
   CFastEvaluationTriggerPolicy   *m_triggerPolicy;
   CInMemoryHotPathDiagnostics    *m_diagnostics;
   CInMemoryFastSafetyAuditBuffer *m_safetyAudit;
   IClock                         *m_clock;
   CFastPathConfig                 m_config;

   double            ResolvePipSize(const CMarketQuote &quote) const
     {
      if(quote.Digits()==3 || quote.Digits()==5)
         return quote.Point()*10.0;
      return quote.Point()<=0.0 ? 0.01 : quote.Point();
     }

   void              RecordDeferredAudit(const CBasketId &basketId,const int errorCode)
     {
      if(m_safetyAudit==NULL)
         return;
      m_safetyAudit.RecordIfNew(basketId.Value()+":"+IntegerToString((long)errorCode),errorCode);
     }

   bool              IsEligibleBasket(const CBasketAggregate &basket) const
     {
      return basket.LifecycleState()==BRE_STATE_ACTIVE &&
             basket.HasStrategyProfile() &&
             !basket.StrategyMigrationRequired();
     }

   void              UpdateStateAfterAttempt(CBasketFastState &state,
                                             const CMarketQuote &quote,
                                             const ulong quoteSequence,
                                             const ENUM_BRE_FAST_EVAL_OUTCOME outcome,
                                             const datetime nowUtc)
     {
      state.SetLastEvaluatedBid(quote.Bid());
      state.SetLastEvaluatedAsk(quote.Ask());
      state.SetLastEvaluatedQuoteSequence(quoteSequence);
      state.SetLastEvaluatedTickTimeMsc(GetTickCount64());
      state.SetLastEvaluationOutcome(outcome);
      state.SetNextAllowedEvaluationUtc(nowUtc+(m_config.MinEvaluationIntervalMs()/1000));
      CForceReevaluationFlag::ClearAfterAttempt(state);
     }

public:
                     CFastMarketEvaluationCoordinator(IBasketRepository *repository,
                                                      IPositionSnapshotStore *snapshotStore,
                                                      CEvaluateBasketStrategyUseCase *evaluateUseCase,
                                                      CMarketContextProviderAdapter *marketAdapter,
                                                      CFastCommandStagingBuffer *stagingQueue,
                                                      CBasketFastStateRegistry *fastStateRegistry,
                                                      CSymbolBasketIndex *symbolIndex,
                                                      CFastEvaluationTriggerPolicy *triggerPolicy,
                                                      CInMemoryHotPathDiagnostics *diagnostics,
                                                      CInMemoryFastSafetyAuditBuffer *safetyAudit,
                                                      IClock *clock,
                                                      const CFastPathConfig &config)
     {
      m_repository=repository;
      m_snapshotStore=snapshotStore;
      m_evaluateUseCase=evaluateUseCase;
      m_marketAdapter=marketAdapter;
      m_stagingQueue=stagingQueue;
      m_fastStateRegistry=fastStateRegistry;
      m_symbolIndex=symbolIndex;
      m_triggerPolicy=triggerPolicy;
      m_diagnostics=diagnostics;
      m_safetyAudit=safetyAudit;
      m_clock=clock;
      m_config=config;
     }

   CFastCommandStagingBuffer* StagingQueue(void) { return m_stagingQueue; }
   CInMemoryHotPathDiagnostics* Diagnostics(void) { return m_diagnostics; }

   int               OnTick(const string symbol)
     {
      ulong startMsc=GetTickCount64();
      int evaluated=0;
      int deferred=0;
      int skipped=0;

      if(m_repository==NULL || m_evaluateUseCase==NULL || m_marketAdapter==NULL || symbol=="")
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.RecordTickRun(symbol,startMsc,0,0,0);
         return 0;
        }

      if(m_symbolIndex!=NULL && m_symbolIndex.IsDirty())
         m_symbolIndex.Rebuild(m_repository);

      CResult<CMarketQuote> quoteResult=CTickQuoteReader::ReadOnce(symbol);
      if(quoteResult.IsFail())
        {
         RecordDeferredAudit(CBasketId("__symbol__"),quoteResult.ErrorCode());
         if(m_diagnostics!=NULL)
            m_diagnostics.RecordTickRun(symbol,startMsc,0,1,0);
         return 0;
        }

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      MqlTick tick;
      SymbolInfoTick(symbol,tick);
      ulong quoteSequence=CTickQuoteReader::QuoteSequence(tick);
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      CBasketId basketIds[];
      int basketCount=0;
      if(m_symbolIndex!=NULL)
         basketCount=m_symbolIndex.FindActiveBasketIds(symbol,basketIds,m_config.MaxBasketsPerTick());

      int processed=0;
      for(int i=0;i<basketCount && processed<m_config.MaxBasketsPerTick();i++)
        {
         CResult<CBasketAggregate> loaded=m_repository.Load(basketIds[i]);
         if(loaded.IsFail())
            continue;

         CBasketAggregate basket;
         if(!loaded.TryGetValue(basket))
            continue;

         if(!IsEligibleBasket(basket))
            continue;

         CBasketFastState state=m_fastStateRegistry.GetOrCreate(basket.Id());
         if(m_triggerPolicy==NULL || !m_triggerPolicy.ShouldEvaluate(basket,state,quote.Bid(),quote.Ask(),
                                                                     quote.Point(),ResolvePipSize(quote),
                                                                     quoteSequence,nowUtc))
           {
            skipped++;
            m_fastStateRegistry.Save(basket.Id(),state);
            continue;
           }

         if(m_snapshotStore!=NULL)
           {
            CVoidResult refreshResult=CBasketSnapshotLiveRefresh::RefreshBasket(m_snapshotStore,basket.Id());
            if(refreshResult.IsFail())
              {
               deferred++;
               RecordDeferredAudit(basket.Id(),refreshResult.ErrorCode());
               UpdateStateAfterAttempt(state,quote,quoteSequence,BRE_FAST_EVAL_OUTCOME_DEFERRED,nowUtc);
               m_fastStateRegistry.Save(basket.Id(),state);
               continue;
              }
           }

         CMarketContext market;
         CRiskRuntimeContext riskContext;
         if(!m_marketAdapter.TryBuildFromQuote(basket,quote,market,riskContext))
           {
            deferred++;
            RecordDeferredAudit(basket.Id(),BRE_ERR_MARKET_QUOTE_STALE);
            UpdateStateAfterAttempt(state,quote,quoteSequence,BRE_FAST_EVAL_OUTCOME_DEFERRED,nowUtc);
            m_fastStateRegistry.Save(basket.Id(),state);
            continue;
           }

         CResult<int> evalResult=m_evaluateUseCase.ExecuteFastPath(basket,market,riskContext,
                                                                   m_stagingQueue,
                                                                   basket.CorrelationKey());
         if(evalResult.IsFail())
           {
            deferred++;
            RecordDeferredAudit(basket.Id(),evalResult.ErrorCode());
            UpdateStateAfterAttempt(state,quote,quoteSequence,BRE_FAST_EVAL_OUTCOME_DEFERRED,nowUtc);
           }
         else
           {
            evaluated++;
            UpdateStateAfterAttempt(state,quote,quoteSequence,BRE_FAST_EVAL_OUTCOME_EXECUTED,nowUtc);
           }

         m_fastStateRegistry.Save(basket.Id(),state);
         processed++;
        }

      if(m_diagnostics!=NULL)
         m_diagnostics.RecordTickRun(symbol,startMsc,evaluated,deferred,skipped);

      return evaluated;
     }
  };

#endif
