#ifndef BRE_APP_RECOVERY_CANDIDATE_SUBMISSION_VALIDATOR_MQH
#define BRE_APP_RECOVERY_CANDIDATE_SUBMISSION_VALIDATOR_MQH

#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Risk/RecoveryProposedTradeRequestBuilder.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateEntry.mqh>
#include <BasketRecovery/Domain/Execution/Enums/ManualRecoveryCandidateRegistryStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryStepStateBuilder.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RecoveryPlanEvaluationContext.mqh>
#include <BasketRecovery/Domain/Risk/Services/RecoveryDecisionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>
#include <BasketRecovery/Domain/Strategy/Context/BasketStrategyState.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Enums/TradeRole.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CRecoveryCandidateSubmissionValidator
  {
private:
   IPositionSnapshotStore       *m_snapshotStore;
   CPendingExecutionRegistry    *m_pendingRegistry;
   CRecoveryStepExecutionTracker *m_stepTracker;
   int                           m_quoteStaleThresholdMs;

   CRecoveryPlanEvaluationContext BuildPlanContext(const CBasketAggregate &basket,
                                                   const CManualRecoveryCandidateEntry &entry,
                                                   const CMarketQuote &quote,
                                                   const datetime nowUtc) const
     {
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
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
               CPositionSnapshotEntry snapEntry;
               if(!snapshot.EntryAt(i,snapEntry))
                  continue;
               entries[entryCount]=snapEntry;
               entryCount++;
              }
            if(entryCount!=total)
               ArrayResize(entries,entryCount);
           }
        }

      double signalLow=basket.SignalDetails().RangeLow().Value();
      double signalHigh=basket.SignalDetails().RangeHigh().Value();
      CRecoveryStepState stepState=CRecoveryStepStateBuilder::BuildFromEntries(basket.Direction(),
                                                                              signalLow,
                                                                              signalHigh,
                                                                              entries,
                                                                              entryCount);
      CMarketContext market=CMarketContext::Create(entry.Symbol(),quote.Bid(),quote.Ask(),
                                                   quote.TickSize()>0.0 ? quote.TickSize() : quote.Point());
      CBasketStrategyState basketState=CBasketStrategyState::Create(basket.Id(),
                                                                  basket.Direction(),
                                                                  signalLow,
                                                                  signalHigh,
                                                                  (signalLow+signalHigh)*0.5,
                                                                  stepState.LastAcceptedStepIndex(),
                                                                  basket.RecoveryPermanentlyDisabled(),
                                                                  basket.ModeFlags().Locked(),
                                                                  false);
      return CRecoveryPlanEvaluationContext::Create(basket.Id(),
                                                    basket.Version(),
                                                    basket.StrategyProfileHash(),
                                                    entry.Symbol(),
                                                    basket.Direction(),
                                                    basket.LifecycleState(),
                                                    basket.ModeFlags().RecoveryActive(),
                                                    basket.RecoveryPermanentlyDisabled(),
                                                    basket.ModeFlags().Locked(),
                                                    basket.SignalDetails().StopLoss().Value(),
                                                    profile,
                                                    market,
                                                    basketState,
                                                    stepState,
                                                    quote.Constraints(),
                                                    entry.QuoteSequence(),
                                                    quote.FreshnessAgeMs(),
                                                    m_quoteStaleThresholdMs,
                                                    unresolved,
                                                    profileValid,
                                                    quote.SessionStatus()==BRE_TRADING_SESSION_OPEN,
                                                    nowUtc);
     }

public:
                     CRecoveryCandidateSubmissionValidator(IPositionSnapshotStore *snapshotStore,
                                                           CPendingExecutionRegistry *pendingRegistry,
                                                           CRecoveryStepExecutionTracker *stepTracker,
                                                           const int quoteStaleThresholdMs=5000)
     {
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_stepTracker=stepTracker;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CVoidResult       ValidateForSubmission(const CManualRecoveryCandidateEntry &entry,
                                           const CBasketAggregate &basket,
                                           const CMarketQuote &quote,
                                           const CRecoveryRiskGateInput &gateInput,
                                           const datetime nowUtc) const
     {
      if(entry.IsExpired(nowUtc))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual recovery candidate expired");

      if(!CManualRecoveryCandidateRegistryStatusText::IsEligibleForManualSubmit(entry.Status()))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual recovery candidate is not eligible for submission");

      if(entry.BasketId().Value()!=basket.Id().Value())
         return CVoidResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Candidate basket mismatch");

      if(entry.BasketVersion()!=basket.Version())
         return CVoidResult::Fail(BRE_ERR_BASKET_VERSION_STALE,"Basket version changed since candidate generation");

      if(entry.StrategyProfileHash()!=basket.StrategyProfileHash())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_HASH_MISMATCH,"Strategy profile hash changed");

      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CVoidResult::Fail(BRE_ERR_BASKET_INVALID,"Basket is not ACTIVE");

      if(!basket.ModeFlags().RecoveryActive())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Recovery is not enabled for basket");

      if(m_pendingRegistry!=NULL &&
         CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id()))
         return CVoidResult::Fail(BRE_ERR_EXEC_TERMINAL_STATE,"Unresolved pending execution blocks recovery submission");

      if(m_stepTracker!=NULL &&
         m_stepTracker.IsStepExecuted(basket.Id().Value(),entry.RecoveryStepIndex()))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Recovery step already executed");

      if(m_quoteStaleThresholdMs>0 && quote.FreshnessAgeMs()>m_quoteStaleThresholdMs)
         return CVoidResult::Fail(BRE_ERR_MARKET_QUOTE_STALE,"Quote is stale");

      if(entry.ProposedVolume()<=0.0 ||
         entry.ProposedVolume()<quote.Constraints().VolumeMin() ||
         entry.ProposedVolume()>quote.Constraints().VolumeMax())
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Planned volume is invalid");

      CRecoveryPlanEvaluationContext planContext=BuildPlanContext(basket,entry,quote,nowUtc);
      CRecoveryCandidatePlanner planner;
      CRecoveryCandidate replanned=planner.Plan(planContext,false);
      if(!replanned.IsDue())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Recovery step is no longer DUE");

      if(replanned.RecoveryStepIndex()!=entry.RecoveryStepIndex())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Recovery step index changed");

      if(MathAbs(replanned.ProposedVolume()-entry.ProposedVolume())>quote.Constraints().VolumeStep()*0.5)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Planned volume changed since candidate generation");

      if(!gateInput.HasQuote())
         return CVoidResult::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Risk gate quote context required");

      COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create(entry.IdempotencyKey(),
                                                                                         entry.RecoveryStepIndex(),
                                                                                         0.0,
                                                                                         entry.ProposedVolume(),
                                                                                         entry.ExecutablePrice(),
                                                                                         BRE_TRADE_ROLE_RECOVERY);
      CTradeExecutionRequest request=CRecoveryProposedTradeRequestBuilder::Build(basket,
                                                                                 openDecision,
                                                                                 entry.CandidateId(),
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
            for(int i=0;i<total;i++)
              {
               CPositionSnapshotEntry snapEntry;
               if(!snapshot.EntryAt(i,snapEntry))
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

      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CRiskCalculationContext calcContext=CRiskCalculationContext::Create(gateInput.Account(),
                                                                        gateInput.Quote(),
                                                                        riskProfile,
                                                                        basket.SignalDetails().StopLoss().Value(),
                                                                        basket.Direction(),
                                                                        CRiskCalculationSettings::CreateDefault());
      CStrategyRiskEvaluationContext riskContext;
      CRecoveryDecisionRiskGateResult gateResult=CRecoveryDecisionRiskValidator::Validate(basket,
                                                                                          openDecision,
                                                                                          request,
                                                                                          riskEntries,
                                                                                          riskEntryCount,
                                                                                          calcContext,
                                                                                          riskContext,
                                                                                          m_quoteStaleThresholdMs,
                                                                                          basket.StrategyProfileHash(),
                                                                                          nowUtc);
      if(!gateResult.Allowed())
         return CVoidResult::Fail(BRE_ERR_EXEC_REJECTED,"Projected max-risk gate blocked submission");

      return CVoidResult::Ok();
     }
  };

#endif
