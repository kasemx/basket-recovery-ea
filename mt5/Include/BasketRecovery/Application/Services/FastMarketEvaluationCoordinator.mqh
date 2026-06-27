#ifndef BRE_APP_FAST_MARKET_EVALUATION_COORDINATOR_MQH
#define BRE_APP_FAST_MARKET_EVALUATION_COORDINATOR_MQH

#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/FastPath/FastEvaluationTriggerPolicy.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryFastSafetyAuditBuffer.mqh>
#include <BasketRecovery/Application/FastPath/FastPathDiagnosticReporter.mqh>
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
   CFastPathDiagnosticReporter    *m_diagnosticReporter;
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

   int               CountActiveBasketsForSymbol(const string symbol) const
     {
      if(m_symbolIndex==NULL)
         return 0;
      CBasketId ids[];
      return m_symbolIndex.FindActiveBasketIds(symbol,ids,100000);
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

   void              FinalizeTick(const string symbol,
                                  const ulong startMsc,
                                  const int evaluated,
                                  const int deferred,
                                  const int skipped,
                                  const int activeBasketCount,
                                  const ulong quoteSequence,
                                  const double bid,
                                  const double ask,
                                  const ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason)
     {
      if(m_diagnostics==NULL)
         return;

      m_diagnostics.RecordTickRun(symbol,startMsc,evaluated,deferred,skipped,
                                  activeBasketCount,quoteSequence,bid,ask,primaryReason);

      if(m_diagnosticReporter!=NULL)
         m_diagnosticReporter.MaybeEmitTickLine(symbol,*m_diagnostics,primaryReason);
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
                                                      CFastPathDiagnosticReporter *diagnosticReporter,
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
      m_diagnosticReporter=diagnosticReporter;
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
      ENUM_BRE_FAST_PATH_SKIP_REASON primaryReason=BRE_FAST_SKIP_NONE;
      ENUM_BRE_FAST_PATH_SKIP_REASON firstBasketSkip=BRE_FAST_SKIP_NONE;
      int activeBasketCount=0;
      ulong quoteSequence=0;
      double bid=0.0;
      double ask=0.0;

      if(m_repository==NULL || m_evaluateUseCase==NULL || m_marketAdapter==NULL || symbol=="")
        {
         FinalizeTick(symbol,startMsc,0,0,0,0,0,0.0,0.0,BRE_FAST_SKIP_NONE);
         return 0;
        }

      if(m_symbolIndex!=NULL && m_symbolIndex.IsDirty())
         m_symbolIndex.Rebuild(m_repository);

      activeBasketCount=CountActiveBasketsForSymbol(symbol);

      CResult<CMarketQuote> quoteResult=CTickQuoteReader::ReadOnce(symbol);
      if(quoteResult.IsFail())
        {
         RecordDeferredAudit(CBasketId("__symbol__"),quoteResult.ErrorCode());
         primaryReason=BRE_FAST_SKIP_STALE_QUOTE;
         FinalizeTick(symbol,startMsc,0,1,0,activeBasketCount,0,0.0,0.0,primaryReason);
         return 0;
        }

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);
      bid=quote.Bid();
      ask=quote.Ask();

      MqlTick tick;
      SymbolInfoTick(symbol,tick);
      quoteSequence=CTickQuoteReader::QuoteSequence(tick);
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      if(activeBasketCount==0)
        {
         primaryReason=BRE_FAST_SKIP_NO_MATCHING_BASKET;
         FinalizeTick(symbol,startMsc,0,0,0,0,quoteSequence,bid,ask,primaryReason);
         return 0;
        }

      CBasketId basketIds[];
      int basketCount=m_symbolIndex.FindActiveBasketIds(symbol,basketIds,m_config.MaxBasketsPerTick());
      bool budgetExhausted=activeBasketCount>m_config.MaxBasketsPerTick();

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
         ENUM_BRE_FAST_PATH_SKIP_REASON skipReason=BRE_FAST_SKIP_NONE;
         if(m_triggerPolicy!=NULL)
            skipReason=m_triggerPolicy.ResolveSkipReason(basket,state,quote.Bid(),quote.Ask(),
                                                         quote.Point(),ResolvePipSize(quote),
                                                         quoteSequence,nowUtc);

         if(skipReason!=BRE_FAST_SKIP_NONE)
           {
            skipped++;
            if(m_diagnostics!=NULL)
               m_diagnostics.RecordBasketSkip(skipReason);
            if(firstBasketSkip==BRE_FAST_SKIP_NONE)
               firstBasketSkip=skipReason;
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
            if(m_diagnostics!=NULL)
               m_diagnostics.RecordBasketSkip(BRE_FAST_SKIP_STALE_QUOTE);
            if(firstBasketSkip==BRE_FAST_SKIP_NONE)
               firstBasketSkip=BRE_FAST_SKIP_STALE_QUOTE;
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

      if(evaluated>0)
         primaryReason=BRE_FAST_SKIP_NONE;
      else if(budgetExhausted && skipped>0)
         primaryReason=BRE_FAST_SKIP_BUDGET_EXHAUSTED;
      else if(firstBasketSkip!=BRE_FAST_SKIP_NONE)
         primaryReason=firstBasketSkip;
      else if(skipped>0)
         primaryReason=BRE_FAST_SKIP_TRIGGER_POLICY;

      FinalizeTick(symbol,startMsc,evaluated,deferred,skipped,activeBasketCount,
                   quoteSequence,bid,ask,primaryReason);

      return evaluated;
     }
  };

#endif
