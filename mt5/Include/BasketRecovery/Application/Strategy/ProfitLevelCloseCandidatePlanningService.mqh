#ifndef BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNING_SERVICE_MQH
#define BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNING_SERVICE_MQH

#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Events/ProfitLevelCloseCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

class CProfitLevelCloseCandidatePlanningService
  {
private:
   CProfitLevelCloseCandidatePlanner      m_planner;
   CProfitLevelCloseCandidateEventBuffer *m_eventBuffer;
   CPendingExecutionRegistry             *m_pendingRegistry;
   int                                    m_quoteStaleThresholdMs;

   CProfitLevelEvaluationContext BuildEvaluationContext(const CBasketAggregate &basket,
                                                        const CStrategyEvaluationContext &evalContext,
                                                        const CRecoveryRiskGateInput &gateInput) const
     {
      CStrategyProfile profile=evalContext.Profile();
      CStrategyProfileValidator validator;
      bool profileValid=validator.Validate(profile).IsOk();

      bool unresolved=m_pendingRegistry!=NULL &&
                      CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id());

      CPositionRuntimeView positions[];
      int positionCount=evalContext.PositionCount();
      ArrayResize(positions,positionCount);
      for(int i=0;i<positionCount;i++)
         positions[i]=evalContext.PositionAt(i);

      CBasketProfitLevelProgress levelProgress[];
      int progressCount=basket.ProfitLevelProgressCount();
      ArrayResize(levelProgress,progressCount);
      for(int i=0;i<progressCount;i++)
         basket.ProfitLevelProgressAt(i,levelProgress[i]);

      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
      bool marketSessionValid=true;
      int freshnessAgeMs=0;
      ulong quoteSequence=0;
      datetime timestampUtc=gateInput.TimestampUtc();
      double equity=0.0;

      if(gateInput.HasQuote())
        {
         constraints=gateInput.Quote().Constraints();
         marketSessionValid=gateInput.Quote().SessionStatus()==BRE_TRADING_SESSION_OPEN;
         freshnessAgeMs=gateInput.Quote().FreshnessAgeMs();
         quoteSequence=gateInput.QuoteSequence();
         equity=gateInput.Account().Equity();
        }

      double targetRiskMoney=0.0;
      if(equity>0.0)
         targetRiskMoney=equity*profile.RiskPlan().TargetRiskPct()/100.0;

      return CProfitLevelEvaluationContext::Create(basket.Id(),
                                                 basket.Version(),
                                                 basket.StrategyProfileHash(),
                                                 basket.Symbol(),
                                                 basket.Direction(),
                                                 basket.LifecycleState(),
                                                 basket.ModeFlags().Locked(),
                                                 profile,
                                                 evalContext.Market(),
                                                 positions,
                                                 positionCount,
                                                 levelProgress,
                                                 progressCount,
                                                 evalContext.FloatingProfitUsd(),
                                                 equity,
                                                 targetRiskMoney,
                                                 constraints,
                                                 quoteSequence,
                                                 freshnessAgeMs,
                                                 gateInput.HasQuote() ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs,
                                                 unresolved,
                                                 profileValid,
                                                 marketSessionValid,
                                                 timestampUtc);
     }

   ENUM_BRE_EVENT_TYPE ResolveEventType(const CProfitLevelCloseCandidate &candidate) const
     {
      switch(candidate.Status())
        {
         case BRE_PROFIT_LEVEL_CLOSE_DUE:
            return BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_AVAILABLE;
         case BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN:
            return BRE_EVENT_PROFIT_LEVEL_CLOSE_PLAN_INVALID;
         case BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_PENDING_EXECUTION:
         case BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_SAFETY:
         case BRE_PROFIT_LEVEL_CLOSE_INVALID_PROFILE:
         case BRE_PROFIT_LEVEL_CLOSE_INVALID_MARKET_CONTEXT:
         case BRE_PROFIT_LEVEL_CLOSE_NOT_IMPLEMENTED:
            return BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_BLOCKED;
         default:
            return BRE_EVENT_PROFIT_LEVEL_EVALUATED;
        }
     }

   void              EmitCandidateEvent(const CBasketAggregate &basket,
                                          const CProfitLevelCloseCandidate &candidate,
                                          const string correlationKey) const
     {
      if(m_eventBuffer==NULL)
         return;

      ENUM_BRE_EVENT_TYPE eventType=ResolveEventType(candidate);
      CProfitLevelCloseCandidateDomainEvent event=CProfitLevelCloseCandidateDomainEvent::Create(eventType,
                                                                                              basket.Id(),
                                                                                              correlationKey,
                                                                                              candidate.Audit().TimestampUtc(),
                                                                                              candidate.Audit(),
                                                                                              candidate.Audit().QuoteSequence());
      m_eventBuffer.TryEmit(event);
     }

public:
                     CProfitLevelCloseCandidatePlanningService(CPendingExecutionRegistry *pendingRegistry,
                                                               CProfitLevelCloseCandidateEventBuffer *eventBuffer,
                                                               const int quoteStaleThresholdMs=5000)
     {
      m_pendingRegistry=pendingRegistry;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CProfitLevelCloseCandidate EvaluateAndEmit(const CBasketAggregate &basket,
                                              const CStrategyEvaluationContext &evalContext,
                                              const CRecoveryRiskGateInput &gateInput) const
     {
      CProfitLevelEvaluationContext planContext=BuildEvaluationContext(basket,evalContext,gateInput);
      string levelId="";
      CProfitDistributionPlan plan=planContext.Profile().ProfitDistributionPlan();
      if(plan.LevelCount()>0)
         levelId=plan.LevelAt(0).LevelId();

      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         if(level.Enabled())
           {
            CBasketProfitLevelProgress progress;
            if(planContext.FindLevelProgress(level.LevelId(),progress) && !progress.CloseCompleted())
              {
               levelId=level.LevelId();
               break;
              }
            if(!planContext.FindLevelProgress(level.LevelId(),progress))
              {
               levelId=level.LevelId();
               break;
              }
           }
        }

      bool duplicate=m_eventBuffer!=NULL &&
                     levelId!="" &&
                     m_eventBuffer.HasSeenQuoteSequence(basket.Id(),levelId,planContext.QuoteSequence());

      CProfitLevelCloseCandidate candidate=m_planner.Plan(planContext,duplicate);
      EmitCandidateEvent(basket,candidate,gateInput.CorrelationKey());
      return candidate;
     }
  };

#endif
