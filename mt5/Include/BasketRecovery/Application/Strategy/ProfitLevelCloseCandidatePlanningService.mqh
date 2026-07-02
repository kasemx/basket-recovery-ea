#ifndef BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNING_SERVICE_MQH
#define BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_PLANNING_SERVICE_MQH

#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
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
   IPendingExecutionStore                *m_pendingStore;
   int                                    m_quoteStaleThresholdMs;

   CProfitLevelEvaluationContext BuildEvaluationContext(const CBasketAggregate &basket,
                                                        const CStrategyEvaluationContext &evalContext,
                                                        const CRecoveryRiskGateInput &gateInput) const
     {
      CStrategyProfile profile=evalContext.Profile();
      CStrategyProfileValidator validator;
      bool profileValid=validator.Validate(profile).IsOk();

      bool unresolved=false;
      if(m_pendingRegistry!=NULL)
        {
         ulong openTickets[];
         int openTicketCount=evalContext.PositionCount();
         ArrayResize(openTickets,openTicketCount);
         for(int ticketIndex=0;ticketIndex<openTicketCount;ticketIndex++)
            openTickets[ticketIndex]=evalContext.PositionAt(ticketIndex).Ticket();
         unresolved=CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(*m_pendingRegistry,
                                                                                          basket.Id(),
                                                                                          openTickets,
                                                                                          openTicketCount,
                                                                                          m_pendingStore);
        }

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
#define BRE_PROFIT_LEVEL_CLOSE_PLANNING_BUILD_MARKER "S8C_TICKET_SCOPED_PLANNER_V2"

                     CProfitLevelCloseCandidatePlanningService(CPendingExecutionRegistry *pendingRegistry,
                                                               CProfitLevelCloseCandidateEventBuffer *eventBuffer,
                                                               const int quoteStaleThresholdMs=5000,
                                                               IPendingExecutionStore *pendingStore=NULL)
     {
      m_pendingRegistry=pendingRegistry;
      m_pendingStore=pendingStore;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   static string     BuildMarker(void) { return BRE_PROFIT_LEVEL_CLOSE_PLANNING_BUILD_MARKER; }

   static bool       SelectFirstEligibleLevel(const string &levelIds[],
                                             const bool &enabled[],
                                             const bool &reached[],
                                             const bool &closeCompleted[],
                                             string &selectedLevelId)
     {
      selectedLevelId="";
      int count=ArraySize(levelIds);
      for(int i=0;i<count;i++)
        {
         if(i>=ArraySize(enabled) || i>=ArraySize(reached) || i>=ArraySize(closeCompleted))
            return false;
         if(enabled[i] && reached[i] && !closeCompleted[i])
           {
            selectedLevelId=levelIds[i];
            return true;
           }
        }
      return false;
     }

   static string     BuildLevelScopedCandidateId(const string basketId,
                                                const string levelId,
                                                const ulong quoteSequence)
     {
      return "profit-level-close:"+basketId+":level:"+levelId+":q:"+(string)quoteSequence;
     }

   CProfitLevelCloseCandidate EvaluateAndEmit(const CBasketAggregate &basket,
                                              const CStrategyEvaluationContext &evalContext,
                                              const CRecoveryRiskGateInput &gateInput) const
     {
      CProfitLevelEvaluationContext planContext=BuildEvaluationContext(basket,evalContext,gateInput);
      string levelId="";
      CProfitDistributionPlan plan=planContext.Profile().ProfitDistributionPlan();
      string levelIds[];
      bool enabled[];
      bool reached[];
      bool closeCompleted[];
      int levelCount=plan.LevelCount();
      ArrayResize(levelIds,levelCount);
      ArrayResize(enabled,levelCount);
      ArrayResize(reached,levelCount);
      ArrayResize(closeCompleted,levelCount);
      for(int i=0;i<levelCount;i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         levelIds[i]=level.LevelId();
         enabled[i]=level.Enabled();
         CBasketProfitLevelProgress progress;
         if(planContext.FindLevelProgress(level.LevelId(),progress))
           {
            reached[i]=progress.Reached();
            closeCompleted[i]=progress.CloseCompleted();
           }
         else
           {
            reached[i]=false;
            closeCompleted[i]=false;
           }
        }
      SelectFirstEligibleLevel(levelIds,enabled,reached,closeCompleted,levelId);

      bool duplicate=m_eventBuffer!=NULL &&
                     levelId!="" &&
                     m_eventBuffer.HasSeenQuoteSequence(basket.Id(),levelId,planContext.QuoteSequence());

      CProfitLevelCloseCandidate candidate=m_planner.Plan(planContext,duplicate);
      EmitCandidateEvent(basket,candidate,gateInput.CorrelationKey());
      return candidate;
     }
  };

#endif
