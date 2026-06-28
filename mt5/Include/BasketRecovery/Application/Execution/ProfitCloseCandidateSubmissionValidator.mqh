#ifndef BRE_APP_PROFIT_CLOSE_CANDIDATE_SUBMISSION_VALIDATOR_MQH
#define BRE_APP_PROFIT_CLOSE_CANDIDATE_SUBMISSION_VALIDATOR_MQH

#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Execution/Enums/ManualProfitCloseCandidateRegistryStatus.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CProfitCloseCandidateSubmissionValidator
  {
private:
   IPositionSnapshotStore                *m_snapshotStore;
   CPendingExecutionRegistry             *m_pendingRegistry;
   CProfitLevelCloseExecutionTracker     *m_levelTracker;
   IAccountExecutionEligibilityProvider  *m_eligibilityProvider;
   int                                    m_quoteStaleThresholdMs;

   bool              TryFindOpenPosition(const CBasketId &basketId,
                                         const ulong ticket,
                                         CPositionSnapshotEntry &outEntry) const
     {
      if(m_snapshotStore==NULL)
         return false;
      CPositionSnapshot *snapshot=m_snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return false;
      int total=snapshot.EntryCount();
      for(int i=0;i<total;i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(entry.Ticket()!=ticket)
            continue;
         outEntry=entry;
         return true;
        }
      return false;
     }

   CProfitLevelEvaluationContext BuildPlanContext(const CBasketAggregate &basket,
                                                  const CManualProfitCloseCandidateEntry &entry,
                                                  const CMarketQuote &quote,
                                                  const datetime nowUtc) const
     {
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
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

      CPositionRuntimeView positions[];
      ArrayResize(positions,entryCount);
      for(int i=0;i<entryCount;i++)
        {
         positions[i]=CPositionRuntimeView::Create(entries[i].Ticket(),
                                                   entries[i].EntryPrice(),
                                                   entries[i].Volume(),
                                                   entries[i].FloatingProfit(),
                                                   entries[i].FloatingProfit(),
                                                   entries[i].OpenTimeUtc(),
                                                   entries[i].Direction(),
                                                   entries[i].Role());
        }

      CBasketProfitLevelProgress progress[];
      int progressCount=basket.ProfitLevelProgressCount();
      ArrayResize(progress,progressCount);
      for(int i=0;i<progressCount;i++)
         basket.ProfitLevelProgressAt(i,progress[i]);

      CMarketContext market=CMarketContext::Create(entry.Symbol(),quote.Bid(),quote.Ask(),
                                                   quote.TickSize()>0.0 ? quote.TickSize() : quote.Point());
      double equity=0.0;
      double targetRiskMoney=0.0;

      return CProfitLevelEvaluationContext::Create(basket.Id(),
                                                   basket.Version(),
                                                   basket.StrategyProfileHash(),
                                                   entry.Symbol(),
                                                   basket.Direction(),
                                                   basket.LifecycleState(),
                                                   basket.ModeFlags().Locked(),
                                                   profile,
                                                   market,
                                                   positions,
                                                   entryCount,
                                                   progress,
                                                   progressCount,
                                                   0.0,
                                                   equity,
                                                   targetRiskMoney,
                                                   quote.Constraints(),
                                                   entry.QuoteSequence(),
                                                   quote.FreshnessAgeMs(),
                                                   m_quoteStaleThresholdMs,
                                                   unresolved,
                                                   true,
                                                   quote.SessionStatus()==BRE_TRADING_SESSION_OPEN,
                                                   nowUtc);
     }

   CVoidResult       ValidateVolume(const double volume,const CMarketQuote &quote) const
     {
      if(volume<=0.0)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Close volume must be positive");
      if(volume<quote.Constraints().VolumeMin() || volume>quote.Constraints().VolumeMax())
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Close volume violates broker constraints");
      double step=quote.Constraints().VolumeStep();
      if(step>0.0)
        {
         double remainder=MathMod(volume,step);
         if(remainder>step*0.0001 && MathAbs(remainder-step)>step*0.0001)
            return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Close volume is not normalized to step");
        }
      return CVoidResult::Ok();
     }

public:
                     CProfitCloseCandidateSubmissionValidator(IPositionSnapshotStore *snapshotStore,
                                                              CPendingExecutionRegistry *pendingRegistry,
                                                              CProfitLevelCloseExecutionTracker *levelTracker,
                                                              IAccountExecutionEligibilityProvider *eligibilityProvider,
                                                              const int quoteStaleThresholdMs=5000)
     {
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_levelTracker=levelTracker;
      m_eligibilityProvider=eligibilityProvider;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs;
     }

   CVoidResult       ValidateRegistrationEligible(const CProfitLevelCloseCandidate &candidate,
                                                  const ENUM_BRE_ACCOUNT_POSITION_MODEL positionModel) const
     {
      if(!candidate.IsDue())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit close candidate is not DUE");
      if(candidate.Audit().ReductionCount()!=1)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Multi-instruction profit close plan rejected");
      if(!CAccountPositionModelHelper::SupportsExplicitTicketPartialClose(positionModel))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Account position model does not support explicit ticket partial close");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateForSubmission(const CManualProfitCloseCandidateEntry &entry,
                                           const CBasketAggregate &basket,
                                           const CMarketQuote &quote,
                                           const CRecoveryRiskGateInput &gateInput,
                                           const datetime nowUtc) const
     {
      if(entry.IsExpired(nowUtc))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual profit close candidate expired");

      if(!CManualProfitCloseCandidateRegistryStatusText::IsEligibleForManualSubmit(entry.Status()))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual profit close candidate is not eligible for submission");

      if(entry.BasketId().Value()!=basket.Id().Value())
         return CVoidResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Candidate basket mismatch");

      if(entry.BasketVersion()!=basket.Version())
         return CVoidResult::Fail(BRE_ERR_BASKET_VERSION_STALE,"Basket version changed since candidate generation");

      if(entry.StrategyProfileHash()!=basket.StrategyProfileHash())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_HASH_MISMATCH,"Strategy profile hash changed");

      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CVoidResult::Fail(BRE_ERR_BASKET_INVALID,"Basket is not ACTIVE");

      if(m_pendingRegistry!=NULL &&
         CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*m_pendingRegistry,basket.Id()))
         return CVoidResult::Fail(BRE_ERR_EXEC_TERMINAL_STATE,"Unresolved pending execution blocks profit close submission");

      if(m_levelTracker!=NULL &&
         m_levelTracker.IsLevelCompleted(basket.Id().Value(),entry.ProfitLevelId()))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit level already completed");

      CBasketProfitLevelProgress progress;
      if(basket.FindProfitLevelProgress(entry.ProfitLevelId(),progress) && progress.CloseCompleted())
         return CVoidResult::Fail(BRE_ERR_PROFIT_LEVEL_ALREADY_CLOSED,"Profit level close already completed");

      if(m_quoteStaleThresholdMs>0 && quote.FreshnessAgeMs()>m_quoteStaleThresholdMs)
         return CVoidResult::Fail(BRE_ERR_MARKET_QUOTE_STALE,"Quote is stale");

      if(!CAccountPositionModelHelper::SupportsExplicitTicketPartialClose(entry.AccountPositionModel()))
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Account position model does not support explicit ticket partial close");

      if(m_eligibilityProvider!=NULL)
        {
         CAccountExecutionEligibilitySnapshot eligibility=m_eligibilityProvider.Capture();
         if(!eligibility.IsExplicitDemo())
            return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Manual profit close requires DEMO account");
        }

      CPositionSnapshotEntry position;
      if(!TryFindOpenPosition(basket.Id(),entry.PositionTicket(),position))
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Selected position is missing");

      if(position.Symbol()!=entry.Symbol())
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Selected position symbol mismatch");

      if(position.Direction()!=entry.PositionDirection())
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Selected position direction mismatch");

      ENUM_BRE_TRADE_DIRECTION expectedClose=CManualProfitCloseCandidateEntry::CloseDirectionForPosition(entry.PositionDirection());
      if(entry.CloseDirection()!=expectedClose)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Close direction must oppose selected position");

      if(entry.ProposedCloseVolume()>position.Volume()+quote.Constraints().VolumeStep()*0.0001)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Insufficient position volume for close");

      CVoidResult volumeResult=ValidateVolume(entry.ProposedCloseVolume(),quote);
      if(volumeResult.IsFail())
         return volumeResult;

      CProfitLevelEvaluationContext planContext=BuildPlanContext(basket,entry,quote,nowUtc);
      CProfitLevelCloseCandidatePlanner planner;
      CProfitLevelCloseCandidate replanned=planner.Plan(planContext,false);
      if(!replanned.IsDue())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit close candidate is no longer DUE");

      if(replanned.Audit().ReductionCount()!=1)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned profit close is not single-instruction");

      CPositionReductionInstruction replannedInstruction;
      if(!replanned.Audit().ReductionAt(0,replannedInstruction))
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned reduction instruction missing");

      if(replannedInstruction.Ticket()!=entry.PositionTicket())
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned ticket mismatch");

      if(MathAbs(replannedInstruction.ProposedCloseVolume()-entry.ProposedCloseVolume())>quote.Constraints().VolumeStep()*0.5)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned close volume changed");

      if(replanned.Audit().ProfitLevelId()!=entry.ProfitLevelId())
         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit level changed since candidate generation");

      return CVoidResult::Ok();
     }
  };

#endif
