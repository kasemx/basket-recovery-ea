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
#include <BasketRecovery/Application/Execution/PendingExecutionStartupReconciliationService.mqh>
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
   string                                       m_lastProcessedTriggerToken;

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
      if(basket.FindProfitLevelProgress(entry.ProfitLevelId(),progress) && !progress.Reached())
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
                                                         IUniqueIdGenerator *idGenerator)
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
         CVoidResult validation=m_validator.ValidateForSubmission(entry,basket,quote,gateInput,nowUtc);
         if(validation.IsFail())
           {
            m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REJECTED);
            EmitRejected(entry,validation.ErrorMessage(),nowUtc);
            return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                         validation.ErrorMessage(),
                                                         BRE_TRADE_EXEC_STATUS_NONE,
                                                         false);
           }
        }

      CTradeExecutionRequest request=CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest(entry,nowUtc);
      CSubmissionPreparationResult prep=m_preparer.Prepare(request,basket,magicNumber);
      if(!prep.IsSuccess())
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_REJECTED);
         EmitRejected(entry,prep.FailureMessage(),nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,prep.FailureMessage(),
                                                      BRE_TRADE_EXEC_STATUS_NONE,false);
        }

      CDemoManualSubmissionResult result=m_demoSubmissionService.TrySubmit(entry.ExecutionRequestId(),
                                                                           authorizationToken,
                                                                           triggerToken,
                                                                           basket,
                                                                           quote);

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

      return result;
     }

   void              OnBrokerFillConfirmed(const string executionRequestId) override
     {
      if(m_candidateRegistry==NULL || m_levelTracker==NULL)
         return;

      CManualProfitCloseCandidateEntry entry;
      if(!m_candidateRegistry.TryGetByExecutionRequestId(executionRequestId,entry))
         return;

      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();
      if(!m_levelTracker.TryMarkFilled(executionRequestId))
         return;

      m_candidateRegistry.TryUpdateStatus(entry.CandidateId(),BRE_MANUAL_PROFIT_CLOSE_CANDIDATE_EXECUTED);
      TryCompleteProfitLevel(entry,nowUtc);
      EmitCloseConfirmed(entry,nowUtc);
      Print("BRE profit_level_close_execution_tracker | filled=true | basket_id=",entry.BasketId().Value(),
            " | profit_level_id=",entry.ProfitLevelId(),
            " | execution_request_id=",executionRequestId);
     }
  };

#endif
