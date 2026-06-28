#ifndef BRE_APP_MANUAL_RECOVERY_CANDIDATE_REGISTRATION_SERVICE_MQH
#define BRE_APP_MANUAL_RECOVERY_CANDIDATE_REGISTRATION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Risk/RecoveryProposedTradeRequestBuilder.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryStepStateBuilder.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Domain/Events/ManualRecoveryCandidateDomainEvent.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateValidationArtifact.mqh>

class CManualRecoveryCandidateRegistrationService
  {
private:
   CManualRecoveryCandidateRegistry      *m_registry;
   CManualRecoveryCandidateEventBuffer   *m_eventBuffer;
   IPositionSnapshotStore                *m_snapshotStore;
   CPendingExecutionRegistry             *m_pendingRegistry;
   CRecoveryStepExecutionTracker        *m_stepTracker;
   IClock                                *m_clock;
   IUniqueIdGenerator                    *m_idGenerator;
   int                                   m_candidateExpirySeconds;
   int                                   m_quoteStaleThresholdMs;

   CRecoveryPlanEvaluationContext BuildPlanContext(const CBasketAggregate &basket,
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

public:
                     CManualRecoveryCandidateRegistrationService(CManualRecoveryCandidateRegistry *registry,
                                                                 CManualRecoveryCandidateEventBuffer *eventBuffer,
                                                                 IPositionSnapshotStore *snapshotStore,
                                                                 CPendingExecutionRegistry *pendingRegistry,
                                                                 CRecoveryStepExecutionTracker *stepTracker,
                                                                 IClock *clock,
                                                                 IUniqueIdGenerator *idGenerator,
                                                                 const int candidateExpirySeconds=30,
                                                                 const int quoteStaleThresholdMs=5000)
     {
      m_registry=registry;
      m_eventBuffer=eventBuffer;
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_stepTracker=stepTracker;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_candidateExpirySeconds=candidateExpirySeconds>0 ? candidateExpirySeconds : 30;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   int               TryRegisterFromGatedDecisions(const CBasketAggregate &basket,
                                                   const CStrategyDecisionSet &decisions,
                                                   const CStrategyEvaluationContext &evalContext,
                                                   const CRecoveryRiskGateInput &gateInput,
                                                   const CStrategyRiskEvaluationContext &riskContext)
     {
      if(m_registry==NULL || !gateInput.HasQuote())
         return 0;

      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : gateInput.TimestampUtc();
      m_registry.ExpireStale(nowUtc);

      CRecoveryPlanEvaluationContext planContext=BuildPlanContext(basket,evalContext,gateInput);
      CRecoveryCandidatePlanner planner;
      int registeredCount=0;

      int decisionCount=decisions.Count();
      for(int i=0;i<decisionCount;i++)
        {
         CStrategyDecision decision=decisions.DecisionAt(i);
         if(decision.Type()!=BRE_STRATEGY_DECISION_OPEN_RECOVERY)
            continue;

         COpenRecoveryPositionDecision openDecision=decision.OpenRecovery();
         CRecoveryCandidate candidate=planner.Plan(planContext,false);
         if(!candidate.IsDue())
            continue;

         if(m_stepTracker!=NULL &&
            m_stepTracker.IsStepExecuted(basket.Id().Value(),candidate.RecoveryStepIndex()))
            continue;

         CTradeExecutionRequest request=CRecoveryProposedTradeRequestBuilder::Build(basket,
                                                                                    openDecision,
                                                                                    gateInput.CorrelationKey(),
                                                                                    nowUtc);
         CPositionSnapshotEntry riskEntries[];
         int riskEntryCount=0;
         if(m_snapshotStore!=NULL)
           {
            CPositionSnapshot *snapshot=m_snapshotStore.Get(basket.Id());
            if(snapshot!=NULL)
              {
               int total=snapshot.EntryCount();
               ArrayResize(riskEntries,total);
               for(int j=0;j<total;j++)
                 {
                  CPositionSnapshotEntry snapEntry;
                  if(!snapshot.EntryAt(j,snapEntry))
                     continue;
                  if(snapEntry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
                     continue;
                  riskEntries[riskEntryCount]=snapEntry;
                  riskEntryCount++;
                 }
               if(riskEntryCount!=total)
                  ArrayResize(riskEntries,riskEntryCount);
              }
           }

         CStrategyProfile profile=evalContext.Profile();
         CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
         CRiskCalculationContext calcContext=CRiskCalculationContext::Create(gateInput.Account(),
                                                                           gateInput.Quote(),
                                                                           riskProfile,
                                                                           basket.SignalDetails().StopLoss().Value(),
                                                                           basket.Direction(),
                                                                           CRiskCalculationSettings::CreateDefault());
         int staleThreshold=gateInput.QuoteStaleThresholdMs()>0 ? gateInput.QuoteStaleThresholdMs() : m_quoteStaleThresholdMs;
         CRecoveryDecisionRiskGateResult gateResult=CRecoveryDecisionRiskValidator::Validate(basket,
                                                                                             openDecision,
                                                                                             request,
                                                                                             riskEntries,
                                                                                             riskEntryCount,
                                                                                             calcContext,
                                                                                             riskContext,
                                                                                             staleThreshold,
                                                                                             gateInput.ExpectedStrategyProfileHash(),
                                                                                             nowUtc);
         if(!gateResult.Allowed())
            continue;

         CRecoveryCandidateAudit audit=candidate.Audit();
         CRecoveryRiskDecisionAudit riskAudit=gateResult.Audit();
         string executionRequestId=m_idGenerator!=NULL ? "recovery-manual:"+m_idGenerator.NewGuid() : "recovery-manual:unknown";
         datetime expiresAt=nowUtc+m_candidateExpirySeconds;

         CManualRecoveryCandidateEntry entry=CManualRecoveryCandidateEntry::Create(audit.IdempotencyKey(),
                                                                                   executionRequestId,
                                                                                   openDecision.IdempotencyKey(),
                                                                                   audit.IdempotencyKey(),
                                                                                   basket.Id(),
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
                                                                                   riskAudit.CurrentSlRisk(),
                                                                                   riskAudit.ProjectedSlRisk(),
                                                                                   riskAudit.TargetRisk(),
                                                                                   riskAudit.MaxRisk(),
                                                                                   audit.QuoteSequence(),
                                                                                   nowUtc,
                                                                                   expiresAt);
         if(!m_registry.TryRegister(entry))
            continue;

         CManualRecoveryCandidateValidationArtifact::WriteEntry(entry,"true","DUE");
         Print("BRE manual_recovery_candidate_available | candidate_id=",entry.CandidateId(),
               " | execution_request_id=",entry.ExecutionRequestId(),
               " | basket_id=",entry.BasketId().Value(),
               " | step=",entry.RecoveryStepIndex(),
               " | symbol=",entry.Symbol(),
               " | volume=",DoubleToString(entry.ProposedVolume(),8),
               " | projected_sl_risk=",DoubleToString(entry.ProjectedSlRisk(),4),
               " | max_risk=",DoubleToString(entry.MaxRisk(),4),
               " | status=DUE | projected_max_risk_allowed=true");

         if(m_eventBuffer!=NULL)
           {
            CManualRecoveryCandidateDomainEvent event=CManualRecoveryCandidateDomainEvent::Create(
               BRE_EVENT_RECOVERY_CANDIDATE_AVAILABLE,
               basket.Id(),
               gateInput.CorrelationKey(),
               nowUtc,
               entry.CandidateId(),
               entry.ExecutionRequestId(),
               "manual-review-candidate");
            m_eventBuffer.TryEmit(event);
           }
         registeredCount++;
        }

      return registeredCount;
     }
  };

#endif
