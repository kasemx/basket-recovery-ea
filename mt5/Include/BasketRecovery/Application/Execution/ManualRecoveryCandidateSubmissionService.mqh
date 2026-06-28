#ifndef BRE_APP_MANUAL_RECOVERY_CANDIDATE_SUBMISSION_SERVICE_MQH
#define BRE_APP_MANUAL_RECOVERY_CANDIDATE_SUBMISSION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/RecoveryCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/RecoveryCandidateExecutionRequestFactory.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualRecoveryCandidateSelection.mqh>
#include <BasketRecovery/Domain/Events/ManualRecoveryCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

class CManualRecoveryCandidateSubmissionService
  {
private:
   CDemoExecutionAuthorizationConfig       m_config;
   CManualRecoveryCandidateRegistry       *m_candidateRegistry;
   CManualRecoveryCandidateTriggerRegistry *m_triggerRegistry;
   CManualRecoveryCandidateEventBuffer    *m_eventBuffer;
   CRecoveryCandidateSubmissionValidator  *m_validator;
   CRecoveryStepExecutionTracker          *m_stepTracker;
   CExecutionAuthorizationRegistry        *m_authRegistry;
   CExecutionSubmissionPreparer           *m_preparer;
   CDemoManualSubmissionService           *m_demoSubmissionService;
   IClock                                 *m_clock;
   string                                 m_lastProcessedTriggerToken;

   void              EmitRejected(const CManualRecoveryCandidateEntry &entry,
                                  const string detail,
                                  const datetime nowUtc)
     {
      if(m_eventBuffer==NULL)
         return;
      CManualRecoveryCandidateDomainEvent event=CManualRecoveryCandidateDomainEvent::Create(
         BRE_EVENT_RECOVERY_SUBMISSION_REJECTED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         detail);
      m_eventBuffer.TryEmit(event);
     }

   void              EmitSubmitted(const CManualRecoveryCandidateEntry &entry,const datetime nowUtc)
     {
      if(m_eventBuffer==NULL)
         return;
      CManualRecoveryCandidateDomainEvent event=CManualRecoveryCandidateDomainEvent::Create(
         BRE_EVENT_RECOVERY_SUBMISSION_SUBMITTED,
         entry.BasketId(),
         entry.CandidateId(),
         nowUtc,
         entry.CandidateId(),
         entry.ExecutionRequestId(),
         "broker-submission-attempted");
      m_eventBuffer.TryEmit(event);
     }

public:
                     CManualRecoveryCandidateSubmissionService(const CDemoExecutionAuthorizationConfig &config,
                                                               CManualRecoveryCandidateRegistry *candidateRegistry,
                                                               CManualRecoveryCandidateTriggerRegistry *triggerRegistry,
                                                               CManualRecoveryCandidateEventBuffer *eventBuffer,
                                                               CRecoveryCandidateSubmissionValidator *validator,
                                                               CRecoveryStepExecutionTracker *stepTracker,
                                                               CExecutionAuthorizationRegistry *authRegistry,
                                                               CExecutionSubmissionPreparer *preparer,
                                                               CDemoManualSubmissionService *demoSubmissionService,
                                                               IClock *clock)
     {
      m_config=config;
      m_candidateRegistry=candidateRegistry;
      m_triggerRegistry=triggerRegistry;
      m_eventBuffer=eventBuffer;
      m_validator=validator;
      m_stepTracker=stepTracker;
      m_authRegistry=authRegistry;
      m_preparer=preparer;
      m_demoSubmissionService=demoSubmissionService;
      m_clock=clock;
      m_lastProcessedTriggerToken="";
     }

   bool              IsWiredToStrategyEngine(void) const { return false; }
   bool              IsWiredToRestIntake(void) const { return false; }
   bool              IsWiredToOnTick(void) const { return false; }
   bool              IsWiredToOnTradeTransaction(void) const { return false; }
   bool              IsWiredToAutomaticTimer(void) const { return false; }

   CDemoManualSubmissionResult TrySubmitRecoveryCandidate(const string candidateId,
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
                                                      "Manual recovery submission route disabled");

      if(m_candidateRegistry==NULL || m_demoSubmissionService==NULL || m_preparer==NULL)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Manual recovery submission route is not configured");

      if(candidateId=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Manual recovery candidate id is required");

      if(triggerToken=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_MISSING,
                                                      "Manual recovery submission trigger token is required");

      if(triggerToken==m_lastProcessedTriggerToken)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,
                                                      "Manual recovery trigger already processed in this session");

      if(m_triggerRegistry!=NULL && m_triggerRegistry.IsConsumed(triggerToken))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,
                                                      "Manual recovery trigger token already consumed");

      if(m_authRegistry!=NULL &&
         !m_authRegistry.HasRecoverySubmissionSessionCapacity(m_config.MaxRecoverySubmissionsPerSession()))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_SUBMISSION_SESSION_CAP,
                                                      "Recovery submission session cap exceeded");

      CManualRecoveryCandidateEntry entry;
      if(!m_candidateRegistry.TryGetByCandidateId(candidateId,entry))
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Manual recovery candidate not found");

      if(entry.BasketId().Value()!=basket.Id().Value())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_BASKET_NOT_ACTIVE,
                                                      "Candidate basket mismatch");

      m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_SELECTED);
      Print("BRE manual_recovery_candidate_manually_selected | candidate_id=",candidateId,
            " | basket_id=",basket.Id().Value(),
            " | step=",entry.RecoveryStepIndex());
      if(m_eventBuffer!=NULL)
        {
         CManualRecoveryCandidateDomainEvent selected=CManualRecoveryCandidateDomainEvent::Create(
            BRE_EVENT_RECOVERY_CANDIDATE_MANUALLY_SELECTED,
            basket.Id(),
            candidateId,
            nowUtc,
            candidateId,
            entry.ExecutionRequestId(),
            "operator-selected");
         m_eventBuffer.TryEmit(selected);
        }

      if(m_validator!=NULL)
        {
         CVoidResult validation=m_validator.ValidateForSubmission(entry,basket,quote,gateInput,nowUtc);
         if(validation.IsFail())
           {
            m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_REJECTED);
            EmitRejected(entry,validation.ErrorMessage(),nowUtc);
            return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                         validation.ErrorMessage(),
                                                         BRE_TRADE_EXEC_STATUS_NONE,
                                                         false);
           }
         Print("BRE manual_recovery_candidate_revalidation=passed | candidate_id=",candidateId,
               " | projected_sl_risk=",DoubleToString(entry.ProjectedSlRisk(),4),
               " | max_risk=",DoubleToString(entry.MaxRisk(),4));
        }

      CTradeExecutionRequest request=CRecoveryCandidateExecutionRequestFactory::CreateOpenRecoveryRequest(entry,nowUtc);
      Print("BRE manual_recovery_sealed_request_created | candidate_id=",candidateId,
            " | execution_request_id=",entry.ExecutionRequestId(),
            " | sealed=",request.IsSealed()?"true":"false");
      CSubmissionPreparationResult prep=m_preparer.Prepare(request,basket,magicNumber);
      if(!prep.IsSuccess())
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_REJECTED);
         EmitRejected(entry,prep.FailureMessage(),nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,prep.FailureMessage(),
                                                      BRE_TRADE_EXEC_STATUS_NONE,false);
        }

      if(entry.ProposedVolume()>m_config.MaxManualDemoOpenVolume())
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_REJECTED);
         EmitRejected(entry,"Requested volume exceeds demo maximum",nowUtc);
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_VOLUME_EXCEEDS_DEMO_MAX,
                                                      "Candidate volume exceeds demo maximum",
                                                      BRE_TRADE_EXEC_STATUS_NONE,
                                                      false);
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
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_SUBMITTED);
         if(m_stepTracker!=NULL)
            m_stepTracker.MarkSubmitted(basket.Id().Value(),entry.RecoveryStepIndex(),entry.ExecutionRequestId());
         if(m_authRegistry!=NULL)
            m_authRegistry.IncrementRecoverySubmissionCount();
         EmitSubmitted(entry,nowUtc);
        }
      else
        {
         m_candidateRegistry.TryUpdateStatus(candidateId,BRE_MANUAL_RECOVERY_CANDIDATE_REJECTED);
         EmitRejected(entry,result.Detail(),nowUtc);
        }

      return result;
     }

   void              OnBrokerFillConfirmed(const string executionRequestId)
     {
      if(m_candidateRegistry==NULL || m_stepTracker==NULL)
         return;

      CManualRecoveryCandidateEntry entry;
      if(!m_candidateRegistry.TryGetByExecutionRequestId(executionRequestId,entry))
         return;

      if(m_stepTracker.TryMarkFilled(executionRequestId))
        {
         m_candidateRegistry.TryUpdateStatus(entry.CandidateId(),BRE_MANUAL_RECOVERY_CANDIDATE_EXECUTED);
         Print("BRE recovery_step_execution_tracker | filled=true | basket_id=",entry.BasketId().Value(),
               " | step=",entry.RecoveryStepIndex(),
               " | execution_request_id=",executionRequestId);
        }
     }
  };

#endif
