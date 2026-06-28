#ifndef BRE_APP_RECOVERY_CANDIDATE_PLANNING_SERVICE_MQH
#define BRE_APP_RECOVERY_CANDIDATE_PLANNING_SERVICE_MQH

#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Risk/RecoveryProposedTradeRequestBuilder.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryStepStateBuilder.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Domain/Events/RecoveryCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>

class CRecoveryCandidatePlanningService
  {
private:
   CRecoveryCandidatePlanner         m_planner;
   CRecoveryCandidateEventBuffer      *m_eventBuffer;
   IPositionSnapshotStore            *m_snapshotStore;
   CPendingExecutionRegistry         *m_pendingRegistry;
   int                               m_quoteStaleThresholdMs;

   CRecoveryPlanEvaluationContext BuildEvaluationContext(const CBasketAggregate &basket,
                                                         const CStrategyEvaluationContext &evalContext,
                                                         const CRecoveryRiskGateInput &gateInput) const
     {
      CStrategyProfile profile=evalContext.Profile();
      CStrategyProfileValidator validator;
      bool profileValid=validator.Validate(profile).IsOk();

      bool unresolved=m_pendingRegistry!=NULL &&
                      CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id());

      CPositionSnapshotEntry entries[];
      int entryCount=0;
      if(m_snapshotStore!=NULL)
        {
         CPositionSnapshot *snapshot=m_snapshotStore.Get(basket.Id());
         if(snapshot!=NULL)
           {
            int total=snapshot.EntryCount();
            ArrayResize(entries,total);
            for(int i=0;i<total;i++)
              {
               CPositionSnapshotEntry entry;
               if(!snapshot.EntryAt(i,entry))
                  continue;
               entries[entryCount]=entry;
               entryCount++;
              }
            if(entryCount!=total)
               ArrayResize(entries,entryCount);
           }
        }

      CRecoveryStepState stepState=CRecoveryStepStateBuilder::BuildFromEntries(basket.Direction(),
                                                                              evalContext.BasketState().SignalRangeLow(),
                                                                              evalContext.BasketState().SignalRangeHigh(),
                                                                              entries,
                                                                              entryCount);

      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
      bool marketSessionValid=true;
      int freshnessAgeMs=0;
      ulong quoteSequence=0;
      datetime timestampUtc=gateInput.TimestampUtc();

      if(gateInput.HasQuote())
        {
         constraints=gateInput.Quote().Constraints();
         marketSessionValid=gateInput.Quote().SessionStatus()==BRE_TRADING_SESSION_OPEN;
         freshnessAgeMs=gateInput.Quote().FreshnessAgeMs();
         quoteSequence=gateInput.QuoteSequence();
        }

      return CRecoveryPlanEvaluationContext::Create(basket.Id(),
                                                    basket.Version(),
                                                    basket.StrategyProfileHash(),
                                                    basket.Symbol(),
                                                    basket.Direction(),
                                                    basket.LifecycleState(),
                                                    basket.ModeFlags().RecoveryActive(),
                                                    basket.RecoveryPermanentlyDisabled(),
                                                    basket.ModeFlags().Locked(),
                                                    basket.SignalDetails().StopLoss().Value(),
                                                    profile,
                                                    evalContext.Market(),
                                                    evalContext.BasketState(),
                                                    stepState,
                                                    constraints,
                                                    quoteSequence,
                                                    freshnessAgeMs,
                                                    gateInput.HasQuote() ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs,
                                                    unresolved,
                                                    profileValid,
                                                    marketSessionValid,
                                                    timestampUtc);
     }

   void              EmitCandidateEvent(const CBasketAggregate &basket,
                                          const CRecoveryCandidate &candidate,
                                          const string correlationKey) const
     {
      if(m_eventBuffer==NULL)
         return;

      ENUM_BRE_EVENT_TYPE eventType=BRE_EVENT_RECOVERY_CANDIDATE_EVALUATED;
      if(candidate.Status()==BRE_RECOVERY_CANDIDATE_DUE)
         eventType=BRE_EVENT_RECOVERY_CANDIDATE_DUE;
      else if(candidate.Status()==BRE_RECOVERY_CANDIDATE_BLOCKED_BY_RISK)
         eventType=BRE_EVENT_RECOVERY_CANDIDATE_BLOCKED_BY_RISK;

      CRecoveryCandidateDomainEvent event=CRecoveryCandidateDomainEvent::Create(eventType,
                                                                                basket.Id(),
                                                                                correlationKey,
                                                                                candidate.Audit().TimestampUtc(),
                                                                                candidate.Audit(),
                                                                                candidate.Audit().QuoteSequence());
      m_eventBuffer.TryEmit(event);
     }

   CRecoveryCandidate ApplyRiskPreview(const CBasketAggregate &basket,
                                       const CRecoveryCandidate &candidate,
                                       const COpenRecoveryPositionDecision &openDecision,
                                       const CRecoveryRiskGateInput &gateInput,
                                       const CStrategyRiskEvaluationContext &riskContext) const
     {
      if(!candidate.IsDue() || !gateInput.HasQuote())
         return candidate;

      CPositionSnapshotEntry entries[];
      int entryCount=0;
      if(m_snapshotStore!=NULL)
        {
         CPositionSnapshot *snapshot=m_snapshotStore.Get(basket.Id());
         if(snapshot!=NULL)
           {
            int total=snapshot.EntryCount();
            ArrayResize(entries,total);
            for(int i=0;i<total;i++)
              {
               CPositionSnapshotEntry entry;
               if(!snapshot.EntryAt(i,entry))
                  continue;
               if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
                  continue;
               entries[entryCount]=entry;
               entryCount++;
              }
            if(entryCount!=total)
               ArrayResize(entries,entryCount);
           }
        }

      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CRiskCalculationContext calcContext=CRiskCalculationContext::Create(gateInput.Account(),
                                                                        gateInput.Quote(),
                                                                        riskProfile,
                                                                        basket.SignalDetails().StopLoss().Value(),
                                                                        basket.Direction(),
                                                                        CRiskCalculationSettings::CreateDefault());
      CTradeExecutionRequest request=CRecoveryProposedTradeRequestBuilder::Build(basket,
                                                                                 openDecision,
                                                                                 gateInput.CorrelationKey(),
                                                                                 gateInput.TimestampUtc());
      int staleThreshold=gateInput.QuoteStaleThresholdMs()>0 ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs;
      CRecoveryDecisionRiskGateResult gateResult=CRecoveryDecisionRiskValidator::Validate(basket,
                                                                                          openDecision,
                                                                                          request,
                                                                                          entries,
                                                                                          entryCount,
                                                                                          calcContext,
                                                                                          riskContext,
                                                                                          staleThreshold,
                                                                                          gateInput.ExpectedStrategyProfileHash(),
                                                                                          gateInput.TimestampUtc());
      if(gateResult.Allowed())
         return candidate;

      CRecoveryCandidateAudit audit=candidate.Audit();
      audit=CRecoveryCandidateAudit::Create(audit.BasketId(),
                                          audit.StrategyProfileHash(),
                                          audit.BasketVersion(),
                                          audit.Symbol(),
                                          audit.Direction(),
                                          audit.RecoveryStepIndex(),
                                          audit.TriggerReferencePrice(),
                                          audit.Bid(),
                                          audit.Ask(),
                                          audit.ZoneLow(),
                                          audit.ZoneHigh(),
                                          audit.ProposedVolume(),
                                          audit.BasketStopLoss(),
                                          audit.QuoteSequence(),
                                          BRE_RECOVERY_CANDIDATE_BLOCKED_BY_RISK,
                                          BRE_RECOVERY_CANDIDATE_REASON_PROJECTED_RISK_EXCEEDED,
                                          audit.IdempotencyKey(),
                                          audit.TimestampUtc());
      return CRecoveryCandidate::FromAudit(audit);
     }

   COpenRecoveryPositionDecision RefineDecision(const COpenRecoveryPositionDecision &original,
                                                const CRecoveryCandidate &candidate) const
     {
      return COpenRecoveryPositionDecision::Create(original.IdempotencyKey(),
                                                   candidate.RecoveryStepIndex(),
                                                   original.DistancePips(),
                                                   candidate.ProposedVolume(),
                                                   candidate.Audit().Ask()>0.0 && candidate.Audit().Direction()==BRE_DIRECTION_BUY
                                                      ? candidate.Audit().Ask()
                                                      : candidate.Audit().Bid(),
                                                   original.TradeRole());
     }

public:
                     CRecoveryCandidatePlanningService(IPositionSnapshotStore *snapshotStore,
                                                       CPendingExecutionRegistry *pendingRegistry,
                                                       CRecoveryCandidateEventBuffer *eventBuffer,
                                                       const int quoteStaleThresholdMs=5000)
     {
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_eventBuffer=eventBuffer;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CStrategyDecisionSet ApplyPlanning(const CBasketAggregate &basket,
                                    const CStrategyDecisionSet &decisions,
                                    const CStrategyEvaluationContext &evalContext,
                                    const CRecoveryRiskGateInput &gateInput,
                                    const CStrategyRiskEvaluationContext &riskContext)
     {
      CStrategyDecisionSet planned=CStrategyDecisionSet::Create();
      CRecoveryPlanEvaluationContext planContext=BuildEvaluationContext(basket,evalContext,gateInput);

      int decisionCount=decisions.Count();
      for(int i=0;i<decisionCount;i++)
        {
         CStrategyDecision decision=decisions.DecisionAt(i);
         if(decision.Type()!=BRE_STRATEGY_DECISION_OPEN_RECOVERY)
           {
            planned.Add(decision);
            continue;
           }

         COpenRecoveryPositionDecision openDecision=decision.OpenRecovery();
         int stepIndex=openDecision.StepIndex();
         bool duplicate=m_eventBuffer!=NULL &&
                        m_eventBuffer.HasSeen(basket.Id(),stepIndex,planContext.QuoteSequence());

         CRecoveryCandidate candidate=m_planner.Plan(planContext,duplicate);
         candidate=ApplyRiskPreview(basket,candidate,openDecision,gateInput,riskContext);
         EmitCandidateEvent(basket,candidate,gateInput.CorrelationKey());

         if(!candidate.IsDue())
            continue;

         COpenRecoveryPositionDecision refined=RefineDecision(openDecision,candidate);
         planned.Add(CStrategyDecision::FromOpenRecovery(refined));
        }

      return planned;
     }
  };

#endif
