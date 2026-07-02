#ifndef BRE_APP_PROFIT_CLOSE_CANDIDATE_SUBMISSION_VALIDATOR_MQH

#define BRE_APP_PROFIT_CLOSE_CANDIDATE_SUBMISSION_VALIDATOR_MQH



#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>

#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>

#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>

#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmitDiagnostics.mqh>

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>

#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>

#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>

#include <BasketRecovery/Domain/Execution/Enums/ManualProfitCloseCandidateRegistryStatus.mqh>

#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh>

#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelEvaluationContext.mqh>

#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>

#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>

#include <BasketRecovery/Domain/Strategy/Validation/StrategyProfileValidator.mqh>

#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseCandidateStatus.mqh>

#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseReason.mqh>

#include <BasketRecovery/Domain/Market/MarketQuote.mqh>

#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>

#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>

#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>

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



   static double     SumPositionFloatingProfit(const CPositionRuntimeView &positions[],const int positionCount)

     {

      double total=0.0;

      for(int i=0;i<positionCount;i++)

         total+=positions[i].FloatingProfit();

      return total;

     }



   static void       OverlayLivePositionPlanning(const ulong ticket,
                                                 CPositionRuntimeView &positions[],
                                                 int &positionCount)

     {

      string liveSymbol="";

      long livePositionType=0;

      ENUM_BRE_TRADE_DIRECTION liveDirection=BRE_DIRECTION_NONE;

      double liveVolume=0.0;

      double liveEntryPrice=0.0;

      double liveFloatingProfitUsd=0.0;

      datetime liveOpenTimeUtc=0;

      string liveLookupFailure="";

      if(!CMt5LivePositionTicketAuthority::TryResolvePlanningFieldsByTicket(ticket,

                                                                            liveSymbol,

                                                                            livePositionType,

                                                                            liveDirection,

                                                                            liveVolume,

                                                                            liveEntryPrice,

                                                                            liveFloatingProfitUsd,

                                                                            liveOpenTimeUtc,

                                                                            liveLookupFailure))

         return;



      for(int i=0;i<positionCount;i++)

        {

         if(positions[i].Ticket()!=ticket)

            continue;

         positions[i]=CPositionRuntimeView::Create(positions[i].Ticket(),

                                                   liveEntryPrice>0.0 ? liveEntryPrice : positions[i].EntryPrice(),

                                                   liveVolume>0.0 ? liveVolume : positions[i].Lot(),

                                                   liveFloatingProfitUsd,

                                                   positions[i].PositionRiskUsd(),

                                                   positions[i].OpenTime(),

                                                   positions[i].Direction(),

                                                   positions[i].TradeRole());

         return;

        }



      ArrayResize(positions,positionCount+1);

      positions[positionCount]=CPositionRuntimeView::Create(ticket,

                                                            liveEntryPrice,

                                                            liveVolume,

                                                            liveFloatingProfitUsd,

                                                            0.0,

                                                            liveOpenTimeUtc,

                                                            liveDirection,

                                                            BRE_TRADE_ROLE_INITIAL);

      positionCount++;

     }

   static void       FilterPositionsToTicket(const ulong ticket,
                                               CPositionRuntimeView &positions[],
                                               int &positionCount)
     {
      if(ticket==0 || positionCount<=0)
         return;
      int filteredCount=0;
      for(int i=0;i<positionCount;i++)
        {
         if(positions[i].Ticket()!=ticket)
            continue;
         if(filteredCount!=i)
            positions[filteredCount]=positions[i];
         filteredCount++;
        }
      positionCount=filteredCount;
      ArrayResize(positions,positionCount);
     }

   CProfitLevelEvaluationContext BuildPlanContext(const CBasketAggregate &basket,

                                                  const CManualProfitCloseCandidateEntry &entry,

                                                  const CMarketQuote &quote,

                                                  const CRecoveryRiskGateInput &gateInput,

                                                  const datetime nowUtc) const

     {

      CStrategyProfile profile;

      basket.StrategyProfile(profile);

      CStrategyProfileValidator profileValidator;

      bool profileValid=profileValidator.Validate(profile).IsOk();



      CPositionRuntimeView positions[];

      int positionCount=0;

      CStrategyEvaluationContextFactory::BuildOpenPositionViews(basket,m_snapshotStore,positions,positionCount);

      OverlayLivePositionPlanning(entry.PositionTicket(),positions,positionCount);
      FilterPositionsToTicket(entry.PositionTicket(),positions,positionCount);
      bool unresolved=false;
      if(m_pendingRegistry!=NULL)
        {
         ulong openTickets[];
         int openTicketCount=positionCount;
         ArrayResize(openTickets,openTicketCount);
         for(int ticketIndex=0;ticketIndex<openTicketCount;ticketIndex++)
           {
            if(ticketIndex>=ArraySize(positions))
              {
               CManualProfitCloseSubmitDiagnostics::PrintSubmitValidatorArrayBounds("positions",
                                                                                    ArraySize(positions),
                                                                                    ticketIndex,
                                                                                    false,
                                                                                    "Open position view index out of range during pending check");
               openTicketCount=ticketIndex;
               ArrayResize(openTickets,openTicketCount);
               break;
              }
            openTickets[ticketIndex]=positions[ticketIndex].Ticket();
           }
         unresolved=CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(*m_pendingRegistry,
                                                                                          basket.Id(),
                                                                                          openTickets,
                                                                                          openTicketCount);
        }



      double floatingProfitUsd=SumPositionFloatingProfit(positions,positionCount);

      if(floatingProfitUsd==0.0 && positionCount==0)

         floatingProfitUsd=CStrategyEvaluationContextFactory::SumFloatingProfit(m_snapshotStore,basket.Id());



      CBasketProfitLevelProgress progress[];

      int progressCount=basket.ProfitLevelProgressCount();

      ArrayResize(progress,progressCount);

      for(int i=0;i<progressCount;i++)

         basket.ProfitLevelProgressAt(i,progress[i]);



      CSymbolTradingConstraints constraints=quote.Constraints();

      bool marketSessionValid=quote.SessionStatus()==BRE_TRADING_SESSION_OPEN;

      int freshnessAgeMs=quote.FreshnessAgeMs();

      ulong quoteSequence=entry.QuoteSequence();

      double equity=0.0;

      int staleThresholdMs=m_quoteStaleThresholdMs;



      if(gateInput.HasQuote())

        {

         constraints=gateInput.Quote().Constraints();

         marketSessionValid=gateInput.Quote().SessionStatus()==BRE_TRADING_SESSION_OPEN;

         freshnessAgeMs=gateInput.Quote().FreshnessAgeMs();

         quoteSequence=gateInput.QuoteSequence();

         equity=gateInput.Account().Equity();

         staleThresholdMs=gateInput.QuoteStaleThresholdMs();

        }



      double targetRiskMoney=0.0;

      if(equity>0.0)

         targetRiskMoney=equity*profile.RiskPlan().TargetRiskPct()/100.0;



      CMarketContext market=CMarketContext::Create(basket.Symbol(),quote.Bid(),quote.Ask(),

                                                   quote.TickSize()>0.0 ? quote.TickSize() : quote.Point());



      return CProfitLevelEvaluationContext::Create(basket.Id(),

                                                   basket.Version(),

                                                   basket.StrategyProfileHash(),

                                                   basket.Symbol(),

                                                   basket.Direction(),

                                                   basket.LifecycleState(),

                                                   basket.ModeFlags().Locked(),

                                                   profile,

                                                   market,

                                                   positions,

                                                   positionCount,

                                                   progress,

                                                   progressCount,

                                                   floatingProfitUsd,

                                                   equity,

                                                   targetRiskMoney,

                                                   constraints,

                                                   quoteSequence,

                                                   freshnessAgeMs,

                                                   staleThresholdMs,

                                                   unresolved,

                                                   profileValid,

                                                   marketSessionValid,

                                                   nowUtc);

     }



   CVoidResult       BuildTicketScopedOpenTickets(const ulong ticket,
                                                  ulong &openTickets[],
                                                  int &openTicketCount,
                                                  const string methodName,
                                                  const CManualProfitCloseCandidateEntry &entry) const
     {
      openTicketCount=0;
      ArrayResize(openTickets,0);
      const int requestedIndex=ticket>0 ? 0 : -1;
      CManualProfitCloseSubmitDiagnostics::PrintSubmitValidatorContext(methodName,entry,requestedIndex);
      CManualProfitCloseSubmitDiagnostics::PrintSubmitValidatorArrayBounds("openTickets",
                                                                           ArraySize(openTickets),
                                                                           requestedIndex,
                                                                           false,
                                                                           ticket>0 ? "Array not sized before ticket assignment" :
                                                                                      "Candidate position ticket missing");
      if(ticket==0)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Candidate position ticket missing for ticket-scoped pending check");

      openTicketCount=1;
      ArrayResize(openTickets,openTicketCount);
      CManualProfitCloseSubmitDiagnostics::PrintSubmitValidatorArrayBounds("openTickets",
                                                                           ArraySize(openTickets),
                                                                           0,
                                                                           ArraySize(openTickets)>=1,
                                                                           ArraySize(openTickets)>=1 ? "" : "Failed to size openTickets for candidate ticket");
      if(ArraySize(openTickets)<1)
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Failed to build ticket-scoped open ticket collection");

      openTickets[0]=ticket;
      return CVoidResult::Ok();
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



      if(m_pendingRegistry!=NULL)
        {
         ulong openTickets[];
         int openTicketCount=0;
         CVoidResult ticketScopeResult=BuildTicketScopedOpenTickets(entry.PositionTicket(),
                                                                    openTickets,
                                                                    openTicketCount,
                                                                    "ValidateForSubmission",
                                                                    entry);
         if(ticketScopeResult.IsFail())
            return ticketScopeResult;
         if(CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(*m_pendingRegistry,
                                                                                  basket.Id(),
                                                                                  openTickets,
                                                                                  openTicketCount))
            return CVoidResult::Fail(BRE_ERR_EXEC_TERMINAL_STATE,"Unresolved pending execution blocks profit close submission");
        }



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

      bool hasSnapshot=TryFindOpenPosition(basket.Id(),entry.PositionTicket(),position);



      string liveSymbol="";

      long livePositionType=0;

      ENUM_BRE_TRADE_DIRECTION livePositionDirection=BRE_DIRECTION_NONE;

      double liveVolume=0.0;

      string liveLookupFailure="";

      bool hasLive=CMt5LivePositionTicketAuthority::TryResolveByTicket(entry.PositionTicket(),

                                                                      liveSymbol,

                                                                      livePositionType,

                                                                      livePositionDirection,

                                                                      liveVolume,

                                                                      liveLookupFailure);



      if(!hasLive && !hasSnapshot)

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,

                                  hasLive ? liveLookupFailure : "Selected position is missing");



      string authoritativeSymbol=hasLive ? liveSymbol : position.Symbol();

      ENUM_BRE_TRADE_DIRECTION authoritativeDirection=hasLive ? livePositionDirection : position.Direction();

      double authoritativeVolume=hasLive ? liveVolume : position.Volume();



      if(authoritativeSymbol!=entry.Symbol())

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Selected position symbol mismatch");



      if(authoritativeDirection==BRE_DIRECTION_NONE)

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Selected position direction is unresolved");



      if(entry.ProposedCloseVolume()>authoritativeVolume+quote.Constraints().VolumeStep()*0.0001)

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Insufficient position volume for close");



      CVoidResult volumeResult=ValidateVolume(entry.ProposedCloseVolume(),quote);

      if(volumeResult.IsFail())

         return volumeResult;



      CProfitLevelEvaluationContext planContext=BuildPlanContext(basket,entry,quote,gateInput,nowUtc);

      CProfitLevelCloseCandidatePlanner planner;

      CProfitLevelCloseCandidate replanned=planner.Plan(planContext,false);

      if(!replanned.IsDue())

        {

         CManualProfitCloseSubmitDiagnostics::PrintReplanDueRejection(entry,

                                                                      basket,

                                                                      planContext,

                                                                      replanned,

                                                                      hasSnapshot,

                                                                      position,

                                                                      hasLive,

                                                                      livePositionType,

                                                                      liveVolume);

         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit close candidate is no longer DUE");

        }



      if(replanned.Audit().ReductionCount()!=1)

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned profit close is not single-instruction");



      CPositionReductionInstruction replannedInstruction;

      const int requestedReductionIndex=0;

      const int reductionCount=replanned.Audit().ReductionCount();

      CManualProfitCloseSubmitDiagnostics::PrintSubmitValidatorArrayBounds("replanned_reductions",

                                                                           reductionCount,

                                                                           requestedReductionIndex,

                                                                           requestedReductionIndex>=0 && requestedReductionIndex<reductionCount,

                                                                           requestedReductionIndex>=0 && requestedReductionIndex<reductionCount ?

                                                                              "" :

                                                                              "Replanned reduction instruction index out of range");

      if(!replanned.Audit().ReductionAt(requestedReductionIndex,replannedInstruction))

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned reduction instruction missing");



      if(replannedInstruction.Ticket()!=entry.PositionTicket())

         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned ticket mismatch");



      if(MathAbs(replannedInstruction.ProposedCloseVolume()-entry.ProposedCloseVolume())>quote.Constraints().VolumeStep()*0.5)

        {
         CStrategyProfile profile;
         basket.StrategyProfile(profile);
         double closePercent=0.0;
         CProfitCloseCandidateCloseVolumeCalculator::TryResolveLevelClosePercent(profile,entry.ProfitLevelId(),closePercent);
         CSymbolTradingConstraints volumeConstraints=quote.Constraints();
         if(gateInput.HasQuote())
            volumeConstraints=gateInput.Quote().Constraints();
         double expectedCloseVolume=CProfitCloseCandidateCloseVolumeCalculator::ComputePartialCloseVolume(
            authoritativeVolume,closePercent,volumeConstraints);
         double normalizedReplannedCloseVolume=CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(
            replannedInstruction.ProposedCloseVolume(),volumeConstraints);
         string volumeMismatchReason=CProfitCloseCandidateCloseVolumeCalculator::DescribeVolumeMismatch(
            entry.ProposedCloseVolume(),
            entry.ProposedCloseVolume(),
            replannedInstruction.ProposedCloseVolume(),
            expectedCloseVolume,
            volumeConstraints);
         CManualProfitCloseSubmitDiagnostics::PrintVolumeMismatchRejection(entry,
                                                                           basket,
                                                                           profile,
                                                                           closePercent,
                                                                           entry.ProposedCloseVolume(),
                                                                           replannedInstruction.ProposedCloseVolume(),
                                                                           authoritativeVolume,
                                                                           expectedCloseVolume,
                                                                           normalizedReplannedCloseVolume,
                                                                           volumeConstraints,
                                                                           volumeMismatchReason);
         return CVoidResult::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Replanned close volume changed");
        }



      if(replanned.Audit().ProfitLevelId()!=entry.ProfitLevelId())

         return CVoidResult::Fail(BRE_ERR_EXEC_DISABLED,"Profit level changed since candidate generation");



      return CVoidResult::Ok();

     }

  };

#endif
