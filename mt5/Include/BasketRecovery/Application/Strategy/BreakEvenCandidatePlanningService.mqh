#ifndef BRE_APP_BREAK_EVEN_CANDIDATE_PLANNING_SERVICE_MQH
#define BRE_APP_BREAK_EVEN_CANDIDATE_PLANNING_SERVICE_MQH

#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidateEventBuffer.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Events/BreakEvenCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

class CBreakEvenCandidatePlanningService
  {
private:
   CBreakEvenCandidatePlanner      m_planner;
   CBreakEvenCandidateEventBuffer *m_eventBuffer;
   CPendingExecutionRegistry     *m_pendingRegistry;
   int                            m_quoteStaleThresholdMs;

   CBreakEvenEvaluationContext BuildEvaluationContext(const CBasketAggregate &basket,
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

      CProfitLevelRuntimeState profitLevelStates[];
      int profitLevelStateCount=evalContext.ProfitLevelStateCount();
      ArrayResize(profitLevelStates,profitLevelStateCount);
      for(int i=0;i<profitLevelStateCount;i++)
         profitLevelStates[i]=evalContext.ProfitLevelStateAt(i);

      CBasketProfitLevelProgress levelProgress[];
      int progressCount=basket.ProfitLevelProgressCount();
      ArrayResize(levelProgress,progressCount);
      for(int i=0;i<progressCount;i++)
         basket.ProfitLevelProgressAt(i,levelProgress[i]);

      string executedRuleIds[];
      int executedRuleCount=0;
      CBasketStrategyState basketState=evalContext.BasketState();
      for(int i=0;i<profile.BreakEvenPlan().RuleCount();i++)
        {
         CBreakEvenRule rule=profile.BreakEvenPlan().RuleAt(i);
         if(basketState.HasExecutedBreakEvenRule(rule.RuleId()))
           {
            ArrayResize(executedRuleIds,executedRuleCount+1);
            executedRuleIds[executedRuleCount]=rule.RuleId();
            executedRuleCount++;
           }
        }

      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
      bool marketSessionValid=true;
      int freshnessAgeMs=0;
      ulong quoteSequence=0;
      datetime timestampUtc=gateInput.TimestampUtc();
      double equity=0.0;
      double point=0.0;
      double tickSize=0.0;

      if(gateInput.HasQuote())
        {
         constraints=gateInput.Quote().Constraints();
         marketSessionValid=gateInput.Quote().SessionStatus()==BRE_TRADING_SESSION_OPEN;
         freshnessAgeMs=gateInput.Quote().FreshnessAgeMs();
         quoteSequence=gateInput.QuoteSequence();
         equity=gateInput.Account().Equity();
         point=gateInput.Quote().Point();
         tickSize=gateInput.Quote().TickSize();
        }

      double targetRiskMoney=0.0;
      if(equity>0.0)
         targetRiskMoney=equity*profile.RiskPlan().TargetRiskPct()/100.0;

      return CBreakEvenEvaluationContext::Create(basket.Id(),
                                                 basket.Version(),
                                                 basket.StrategyProfileHash(),
                                                 basket.Symbol(),
                                                 basket.Direction(),
                                                 basket.LifecycleState(),
                                                 basket.ModeFlags().Locked(),
                                                 basketState.BreakEvenActivated(),
                                                 basketState.ManualBreakEvenRequested(),
                                                 false,
                                                 executedRuleIds,
                                                 executedRuleCount,
                                                 profile,
                                                 evalContext.Market(),
                                                 positions,
                                                 positionCount,
                                                 profitLevelStates,
                                                 profitLevelStateCount,
                                                 levelProgress,
                                                 progressCount,
                                                 evalContext.FloatingProfitUsd(),
                                                 evalContext.RiskContext().RealizedProfitUsd(),
                                                 equity,
                                                 targetRiskMoney,
                                                 evalContext.RiskContext().TargetRiskReached(),
                                                 basket.SignalDetails().StopLoss().Value(),
                                                 point,
                                                 tickSize,
                                                 constraints,
                                                 quoteSequence,
                                                 freshnessAgeMs,
                                                 gateInput.HasQuote() ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs,
                                                 unresolved,
                                                 profileValid,
                                                 marketSessionValid,
                                                 timestampUtc);
     }

   ENUM_BRE_EVENT_TYPE ResolveEventType(const CBreakEvenCandidate &candidate) const
     {
      switch(candidate.Status())
        {
         case BRE_BREAK_EVEN_CANDIDATE_DUE:
            return BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE;
         case BRE_BREAK_EVEN_CANDIDATE_INVALID_STOP_PRICE:
            return BRE_EVENT_BREAK_EVEN_STOP_PRICE_INVALID;
         case BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_PENDING_EXECUTION:
         case BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY:
         case BRE_BREAK_EVEN_CANDIDATE_INVALID_PROFILE:
         case BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT:
         case BRE_BREAK_EVEN_CANDIDATE_NOT_IMPLEMENTED:
            return BRE_EVENT_BREAK_EVEN_CANDIDATE_BLOCKED;
         default:
            return BRE_EVENT_BREAK_EVEN_EVALUATED;
        }
     }

   void              EmitCandidateEvent(const CBasketAggregate &basket,
                                        const CBreakEvenCandidate &candidate,
                                        const string correlationKey) const
     {
      if(m_eventBuffer==NULL)
         return;

      ENUM_BRE_EVENT_TYPE eventType=ResolveEventType(candidate);
      CBreakEvenCandidateDomainEvent event=CBreakEvenCandidateDomainEvent::Create(eventType,
                                                                                basket.Id(),
                                                                                correlationKey,
                                                                                candidate.Audit().TimestampUtc(),
                                                                                candidate.Audit(),
                                                                                candidate.Audit().QuoteSequence());
      m_eventBuffer.TryEmit(event);
     }

public:
                     CBreakEvenCandidatePlanningService(CPendingExecutionRegistry *pendingRegistry,
                                                        CBreakEvenCandidateEventBuffer *eventBuffer,
                                                        const int quoteStaleThresholdMs=5000)
     {
      m_pendingRegistry=pendingRegistry;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CBreakEvenCandidate EvaluateAndEmit(const CBasketAggregate &basket,
                                       const CStrategyEvaluationContext &evalContext,
                                       const CRecoveryRiskGateInput &gateInput) const
     {
      CBreakEvenEvaluationContext planContext=BuildEvaluationContext(basket,evalContext,gateInput);
      bool duplicate=m_eventBuffer!=NULL &&
                     m_eventBuffer.HasSeenQuoteSequence(basket.Id(),planContext.QuoteSequence());
      CBreakEvenCandidate candidate=m_planner.Plan(planContext,duplicate);
      EmitCandidateEvent(basket,candidate,gateInput.CorrelationKey());
      return candidate;
     }
  };

#endif
