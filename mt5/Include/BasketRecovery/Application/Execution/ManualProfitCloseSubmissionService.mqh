#ifndef BRE_APP_MANUAL_PROFIT_CLOSE_SUBMISSION_SERVICE_MQH
#define BRE_APP_MANUAL_PROFIT_CLOSE_SUBMISSION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Execution/BasketTicketOwnershipHydrator.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmitDiagnostics.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionStartupReconciliationService.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseFilledPendingCompletionService.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateExecutionRequestFactory.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Events/ManualProfitCloseCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

class CManualProfitCloseSubmissionService : public IPendingExecutionFillNotifier
  {
private:
   CDemoExecutionAuthorizationConfig            m_config;
   CManualProfitCloseCandidateRegistry         *m_candidateRegistry;
   CManualProfitCloseCandidateTriggerRegistry  *m_triggerRegistry;
   CManualProfitCloseCandidateEventBuffer      *m_eventBuffer;
   CProfitCloseCandidateSubmissionValidator    *m_validator;
   CProfitLevelCloseExecutionTracker           *m_levelTracker;
   CExecutionAuthorizationRegistry             *m_authRegistry;
   CExecutionSubmissionPreparer                *m_preparer;
   CDemoManualSubmissionService                *m_demoSubmissionService;
   IBasketRepository                           *m_basketRepository;
   IClock                                      *m_clock;
   IUniqueIdGenerator                          *m_idGenerator;
   IPositionSnapshotStore                      *m_snapshotStore;
   CPendingExecutionRegistry                   *m_pendingRegistry;
   CMt5AsyncSubmissionGateway                  *m_asyncGateway;
   string                                       m_lastProcessedTriggerToken;

   CManualProfitCloseCandidateEntry BuildSubmitEntryWithLiveAuthority(const CManualProfitCloseCandidateEntry &entry,
                                                                      const ENUM_BRE_TRADE_DIRECTION livePositionDirection) const
     {
      return CManualProfitCloseCandidateEntry::Create(entry.CandidateId(),
                                                      entry.ExecutionRequestId(),
                                                      entry.IdempotencyKey(),
                                                      entry.BasketId(),
                                                      entry.ProfitLevelId(),
                                                      entry.ProfitLevelIndex(),
                                                      entry.StrategyProfileHash(),
                                                      entry.BasketVersion(),
                                                      entry.Symbol(),
                                                      entry.BasketDirection(),
                                                      livePositionDirection,
                                                      entry.PositionTicket(),
                                                      entry.OriginalPositionVolume(),
                                                      entry.ProposedCloseVolume(),
                                                      entry.EstimatedCloseMoney(),
                                                      entry.TriggerType(),
                                                      entry.TriggerValue(),
                                                      entry.QuoteSequence(),
                                                      entry.CreatedAtUtc(),
                                                      entry.ExpiresAtUtc(),
                                                      entry.AccountPositionModel());
     }

   void              FinalizePreSubmitRejection(const string candidateId,
                                                const string triggerToken,
                                                const CManualProfitCloseCandidateEntry &entry,
                                                const string validationMessage,
                                                const datetime nowUtc)
     {
      m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REJECTED);
      EmitRejected(entry,validationMessage,nowUtc);
      m_lastProcessedTriggerToken=triggerToken;
      if(m_triggerRegistry!=NULL)
         m_triggerRegistry.Consume(triggerToken);
      CManualProfitCloseSubmitDiagnostics::PrintDirectionValidation(entry.PositionTicket(),"FAIL","pre_submit_validation");
      CManualProfitCloseSubmitDiagnostics::PrintBoundsValidationRejection(m_asyncGateway,m_pendingRegistry,entry.ExecutionRequestId());
     }

   void              EmitRejected(const CManualProfitCloseCandidateEntry &entry,
                                  const string detail,
                                  const datetime nowUtc)
     {
      if(m_eventBuffer==NULL)
         return;
      CManualProfitCloseCandidateDomainEvent event=CManualProfitCloseCandidateDomainEvent::Create(
         BRE_EVENT_PROFIT_LEVEL_CLOSE_SUBMISSION_REJECTED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         entry.ProfitLevelId(),
         detail);
      m_eventBuffer.TryEmit(event);
     }

   void              EmitSubmitted(const CManualProfitCloseCandidateEntry &entry,const datetime nowUtc)
     {
      if(m_eventBuffer==NULL)
         return;
      CManualProfitCloseCandidateDomainEvent event=CManualProfitCloseCandidateDomainEvent::Create(
         BRE_EVENT_PROFIT_LEVEL_CLOSE_SUBMISSION_SUBMITTED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         entry.ProfitLevelId(),
         "broker-submission-attempted");
      m_eventBuffer.TryEmit(event);
     }

   void              EmitCloseConfirmed(const CManualProfitCloseCandidateEntry &entry,const datetime nowUtc)
     {
      if(m_eventBuffer==NULL)
         return;
      CManualProfitCloseCandidateDomainEvent confirmed=CManualProfitCloseCandidateDomainEvent::Create(
         BRE_EVENT_PROFIT_LEVEL_CLOSE_CONFIRMED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         entry.ProfitLevelId(),
         "broker-close-fill-confirmed");
      m_eventBuffer.TryEmit(confirmed);
      CManualProfitCloseCandidateDomainEvent completed=CManualProfitCloseCandidateDomainEvent::Create(
         BRE_EVENT_PROFIT_LEVEL_MARKED_COMPLETED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         entry.ProfitLevelId(),
         "profit-level-progress-completed");
      m_eventBuffer.TryEmit(completed);
     }

   void              TryCompleteProfitLevel(const CManualProfitCloseCandidateEntry &entry,const datetime nowUtc)
     {
      if(m_basketRepository==NULL)
         return;

      CResult<CBasketAggregate> loaded=m_basketRepository.Load(entry.BasketId());
      if(loaded.IsFail())
         return;

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return;

      CEventId eventId;
      if(m_idGenerator!=NULL)
         eventId=CEventId(m_idGenerator.NewGuid());
      else
         eventId=CEventId("profit-close-fill");

      CBasketProfitLevelProgress progress;
      bool hasProgress=basket.FindProfitLevelProgress(entry.ProfitLevelId(),progress);
      if(!hasProgress || !progress.Reached())
         basket.ApplyProfitLevelReached(entry.ProfitLevelId(),CUtcTime(nowUtc),CCommandId(""),eventId);

      basket.ApplyProfitLevelCloseCompleted(entry.ProfitLevelId(),
                                            CMoney(entry.EstimatedCloseMoney()),
                                            CCommandId(""),
                                            eventId,
                                            CUtcTime(nowUtc));

      m_basketRepository.Save(basket);
     }

public:
                     CManualProfitCloseSubmissionService(const CDemoExecutionAuthorizationConfig &config,
                                                         CManualProfitCloseCandidateRegistry *candidateRegistry,
                                                         CManualProfitCloseCandidateTriggerRegistry *triggerRegistry,
                                                         CManualProfitCloseCandidateEventBuffer *eventBuffer,
                                                         CProfitCloseCandidateSubmissionValidator *validator,
                                                         CProfitLevelCloseExecutionTracker *levelTracker,
                                                         CExecutionAuthorizationRegistry *authRegistry,
                                                         CExecutionSubmissionPreparer *preparer,
                                                         CDemoManualSubmissionService *demoSubmissionService,
                                                         IBasketRepository *basketRepository,
                                                         IClock *clock,
                                                         IUniqueIdGenerator *idGenerator,
                                                         IPositionSnapshotStore *snapshotStore=NULL,
                                                         CPendingExecutionRegistry *pendingRegistry=NULL,
                                                         CMt5AsyncSubmissionGateway *asyncGateway=NULL)
     {
      m_config=config;
      m_candidateRegistry=candidateRegistry;
      m_triggerRegistry=triggerRegistry;
      m_eventBuffer=eventBuffer;
      m_validator=validator;
      m_levelTracker=levelTracker;
      m_authRegistry=authRegistry;
      m_preparer=preparer;
      m_demoSubmissionService=demoSubmissionService;
      m_basketRepository=basketRepository;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_snapshotStore=snapshotStore;
      m_pendingRegistry=pendingRegistry;
      m_asyncGateway=asyncGateway;
      m_lastProcessedTriggerToken="";
     }

   bool              IsWiredToStrategyEngine(void) const { return false; }
   bool              IsWiredToRestIntake(void) const { return false; }
   bool              IsWiredToOnTick(void) const { return false; }
   bool              IsWiredToOnTradeTransaction(void) const { return false; }
   bool              IsWiredToAutomaticTimer(void) const { return false; }

   CDemoManualSubmissionResult TrySubmitProfitCloseCandidate(const string candidateId,
                                                             const string authorizationToken,
                                                             const string triggerToken,
                                                             const CBasketAggregate &basket,
                                                             const CMarketQuote &quote,
                                                             const CRecoveryRiskGateInput &gateInput,
                                                             const long magicNumber)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      if(!CExecutionAuthorizationPolicy::AllowsDemoManualSubmission(m_config))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Manual profit close submission route disabled");

      if(m_candidateRegistry==NULL || m_demoSubmissionService==NULL || m_preparer==NULL)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Manual profit close submission route is not configured");

      if(candidateId=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Manual profit close candidate id is required");

      if(triggerToken=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_MISSING,
                                                      "Manual profit close submission trigger token is required");

      if(triggerToken==m_lastProcessedTriggerToken)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,
                                                      "Manual profit close trigger already processed in this session");

      if(m_triggerRegistry!=NULL && m_triggerRegistry.IsConsumed(triggerToken))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,
                                                      "Manual profit close trigger token already consumed");

      if(m_authRegistry!=NULL &&
         !m_authRegistry.HasProfitCloseSubmissionSessionCapacity(m_config.MaxProfitCloseSubmissionsPerSession()))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_SUBMISSION_SESSION_CAP,
                                                      "Profit close submission session cap exceeded");

      CManualProfitCloseCandidateEntry entry;
      if(!m_candidateRegistry.TryGetByCandidateId(candidateId,entry))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Manual profit close candidate not found");

      if(entry.BasketId().Value()!=basket.Id().Value())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_BASKET_NOT_ACTIVE,
                                                      "Candidate basket mismatch");

      m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_SELECTED);
      if(m_eventBuffer!=NULL)
        {
         CManualProfitCloseCandidateDomainEvent selected=CManualProfitCloseCandidateDomainEvent::Create(
            BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_MANUALLY_SELECTED,
            basket.Id(),
            candidateId,
            nowUtc,
            candidateId,
            entry.ExecutionRequestId(),
            entry.ProfitLevelId(),
            "operator-selected");
         m_eventBuffer.TryEmit(selected);
        }

      if(m_validator!=NULL)
        {
         CManualProfitCloseSubmitDiagnostics::PrintDirectionValidation(entry.PositionTicket(),"PENDING");
         CVoidResult validation=m_validator.ValidateForSubmission(entry,basket,quote,gateInput,nowUtc);
         if(validation.IsFail())
           {
            FinalizePreSubmitRejection(candidateId,triggerToken,entry,validation.ErrorMessage(),nowUtc);
            return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                         validation.ErrorMessage(),
                                                         BRE_TRADE_EXEC_STATUS_NONE,
                                                         false);
           }
         CManualProfitCloseSubmitDiagnostics::PrintDirectionValidation(entry.PositionTicket(),"OK");
        }

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

      ENUM_BRE_TRADE_DIRECTION submitPositionDirection=hasLive ? livePositionDirection : entry.PositionDirection();
      if(submitPositionDirection==BRE_DIRECTION_NONE)
        {
         FinalizePreSubmitRejection(candidateId,triggerToken,entry,"Selected position direction is unresolved",nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Selected position direction is unresolved",
                                                      BRE_TRADE_EXEC_STATUS_NONE,
                                                      false);
        }

      CManualProfitCloseCandidateEntry submitEntry=BuildSubmitEntryWithLiveAuthority(entry,submitPositionDirection);
      ENUM_BRE_TRADE_DIRECTION liveCloseDirection=
         CManualProfitCloseCandidateEntry::CloseDirectionForPosition(submitPositionDirection);
      CTradeExecutionRequest request=CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest(submitEntry,
                                                                                                      liveCloseDirection,
                                                                                                      nowUtc);

      CBasketAggregate submitBasket=basket;
      SBasketTicketOwnershipDiagnostics ownershipDiagnostics;
      bool restoreRegistryBasketFound=entry.BasketId().Value()==basket.Id().Value();
      bool restoreRegistryCandidateFound=m_candidateRegistry!=NULL &&
                                         m_candidateRegistry.TryGetByCandidateId(candidateId,entry);
      bool ownershipOk=CBasketTicketOwnershipHydrator::TryEnsureCandidateTicketMembership(submitBasket,
                                                                                          entry,
                                                                                          m_snapshotStore,
                                                                                          restoreRegistryBasketFound,
                                                                                          restoreRegistryCandidateFound,
                                                                                          ownershipDiagnostics);
      CManualProfitCloseSubmitDiagnostics::PrintTicketOwnershipValidation(ownershipDiagnostics,request);
      if(!ownershipOk)
        {
         FinalizePreSubmitRejection(candidateId,triggerToken,entry,ownershipDiagnostics.ownership_failure_reason,nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      ownershipDiagnostics.ownership_failure_reason,
                                                      BRE_TRADE_EXEC_STATUS_NONE,
                                                      false);
        }

      double currentPositionVolume=hasLive ? liveVolume : entry.OriginalPositionVolume();
      string pendingDetail="";
      bool pendingPrecheckOk=CManualProfitCloseSubmitDiagnostics::PendingExecutionPrecheck(m_pendingRegistry,
                                                                                           basket.Id(),
                                                                                           submitEntry.ExecutionRequestId(),
                                                                                           submitEntry.PositionTicket(),
                                                                                           pendingDetail);
      string authFailureReason="";
      string authValidation="SKIPPED";
      if(authorizationToken!="")
        {
         authValidation=CManualProfitCloseSubmitDiagnostics::PreviewAuthorizationToken(authorizationToken,
                                                                                       submitEntry,
                                                                                       nowUtc,
                                                                                       authFailureReason) ? "OK" : "FAIL";
        }
      else
         authValidation="MISSING";

      bool singleSubmitGuard=(triggerToken!="" &&
                              triggerToken!=m_lastProcessedTriggerToken &&
                              (m_triggerRegistry==NULL || !m_triggerRegistry.IsConsumed(triggerToken)));
      string typeFillingLabel=CManualProfitCloseSubmitDiagnostics::ResolveCloseTypeFillingLabel(submitEntry.Symbol());

      if(!pendingPrecheckOk || authValidation=="FAIL" || authValidation=="MISSING")
        {
         CManualProfitCloseSubmitDiagnostics::PrintPreSubmit(submitEntry,
                                                             currentPositionVolume,
                                                             singleSubmitGuard,
                                                             pendingPrecheckOk,
                                                             pendingDetail,
                                                             authValidation,
                                                             authFailureReason,
                                                             typeFillingLabel);
         string rejectionDetail=!pendingPrecheckOk ? pendingDetail :
                                (authFailureReason!="" ? authFailureReason : "Authorization token missing");
         ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON rejectionReason=BRE_LIVE_SAFETY_TOKEN_BINDING_MISMATCH;
         if(!pendingPrecheckOk)
            rejectionReason=BRE_LIVE_SAFETY_CONFLICTING_PENDING;
         else if(authValidation=="MISSING")
            rejectionReason=BRE_LIVE_SAFETY_TOKEN_MISSING;
         FinalizePreSubmitRejection(candidateId,triggerToken,submitEntry,rejectionDetail,nowUtc);
         CManualProfitCloseSubmitDiagnostics::PrintPostSubmit(m_asyncGateway,m_pendingRegistry,submitEntry.ExecutionRequestId(),false);
         return CDemoManualSubmissionResult::Rejected(rejectionReason,
                                                      rejectionDetail,
                                                      BRE_TRADE_EXEC_STATUS_NONE,
                                                      false);
        }

      CSubmissionPreparationResult prep=m_preparer.Prepare(request,submitBasket,magicNumber);
      CManualProfitCloseSubmitDiagnostics::PrintBrokerCommentSubmitDiagnostics(m_preparer.LastCommentSubmitDiagnostics());
      if(!prep.IsSuccess())
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REJECTED);
         EmitRejected(entry,prep.FailureMessage(),nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,prep.FailureMessage(),
                                                      BRE_TRADE_EXEC_STATUS_NONE,false);
        }

      CManualProfitCloseSubmitDiagnostics::PrintPreSubmit(submitEntry,
                                                          currentPositionVolume,
                                                          singleSubmitGuard,
                                                          pendingPrecheckOk,
                                                          pendingDetail,
                                                          authValidation,
                                                          authFailureReason,
                                                          typeFillingLabel);

      CDemoManualSubmissionResult result=m_demoSubmissionService.TrySubmit(submitEntry.ExecutionRequestId(),
                                                                           authorizationToken,
                                                                           triggerToken,
                                                                           basket,
                                                                           quote,
                                                                           submitEntry.CandidateId(),
                                                                           submitEntry.PositionTicket(),
                                                                           submitEntry.ProposedCloseVolume());

      if(result.TriggerTokenConsumed())
        {
         m_lastProcessedTriggerToken=triggerToken;
         if(m_triggerRegistry!=NULL)
            m_triggerRegistry.Consume(triggerToken);
        }

      if(result.IsSuccess())
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_SUBMITTED);
         if(m_levelTracker!=NULL)
            m_levelTracker.MarkSubmitted(basket.Id().Value(),entry.ProfitLevelId(),entry.ExecutionRequestId());
         if(m_authRegistry!=NULL)
            m_authRegistry.IncrementProfitCloseSubmissionCount();
         EmitSubmitted(entry,nowUtc);
        }
      else
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REJECTED);
         EmitRejected(entry,result.Detail(),nowUtc);
        }

      CManualProfitCloseSubmitDiagnostics::PrintPostSubmit(m_asyncGateway,
                                                           m_pendingRegistry,
                                                           entry.ExecutionRequestId(),
                                                           result.BrokerInvoked());

      return result;
     }

   void              OnBrokerFillConfirmed(const string executionRequestId,const string completionPath="") override
     {
      if(m_candidateRegistry==NULL || m_levelTracker==NULL)
         return;

      CManualProfitCloseCandidateEntry entry;
      if(!m_candidateRegistry.TryGetByExecutionRequestId(executionRequestId,entry))
         return;

      if(!m_levelTracker.TryMarkFilled(executionRequestId))
         return;

      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      m_candidateRegistry.TryUpdateStatus(entry.CandidateId(),BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_EXECUTED);
      TryCompleteProfitLevel(entry,nowUtc);
      EmitCloseConfirmed(entry,nowUtc);

      string brokerComment="";
      if(m_pendingRegistry!=NULL)
        {
         CPendingExecutionEntry pending;
         if(m_pendingRegistry.TryGetByExecutionRequestId(executionRequestId,pending))
            brokerComment=pending.BrokerComment();
        }

      bool profitLevelCompleted=false;
      if(m_basketRepository!=NULL)
        {
         CResult<CBasketAggregate> loaded=m_basketRepository.Load(entry.BasketId());
         CBasketAggregate basket;
         if(loaded.TryGetValue(basket))
           {
            CBasketProfitLevelProgress progress;
            if(basket.FindProfitLevelProgress(entry.ProfitLevelId(),progress))
               profitLevelCompleted=progress.CloseCompleted();
           }
        }

      CManualProfitCloseSubmitDiagnostics::PrintBrokerFillCompletion(brokerComment,
                                                                     executionRequestId,
                                                                     entry.ProfitLevelId(),
                                                                     profitLevelCompleted,
                                                                     completionPath);
     }

   static bool       TryCompleteFilledProfitCloseFromPending(const CPendingExecutionEntry &entry,
                                                             IBasketRepository *basketRepository,
                                                             SProfitClosePersistedCompletionOutcome &outcomeOut,
                                                             IClock *clock=NULL,
                                                             IUniqueIdGenerator *idGenerator=NULL,
                                                             const string completionPath="startup_persisted_pending")
     {
      return CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(entry,
                                                                                                 basketRepository,
                                                                                                 outcomeOut,
                                                                                                 clock,
                                                                                                 idGenerator,
                                                                                                 completionPath);
     }
  };

#endif
