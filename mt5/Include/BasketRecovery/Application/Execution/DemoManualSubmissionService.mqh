#ifndef BRE_APP_DEMO_MANUAL_SUBMISSION_SERVICE_MQH
#define BRE_APP_DEMO_MANUAL_SUBMISSION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGate.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGateContext.mqh>
#include <BasketRecovery/Application/Execution/PreparedSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ManualDemoExecutionAuthorization.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationStatus.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationScope.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionFailureReason.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>

class CDemoManualSubmissionService
  {
private:
   CDemoExecutionAuthorizationConfig       m_config;
   CExecutionAuthorizationRegistry        *m_authRegistry;
   CDemoManualSubmissionTriggerRegistry   *m_triggerRegistry;
   CPendingExecutionRegistry              *m_pendingRegistry;
   IPendingExecutionStore                 *m_pendingStore;
   IAccountExecutionEligibilityProvider   *m_eligibilityProvider;
   IClock                                 *m_clock;
   CPreparedSubmissionValidator            m_preparedValidator;
   CSubmitPreparedExecutionUseCase        *m_submitUseCase;
   CMt5AsyncSubmissionGateway             *m_asyncGateway;
   CMarketSafetyConfig                     m_marketSafety;

   CDemoManualSubmissionResult Reject(const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON reason,
                                      const string detail,
                                      const bool consumeTrigger=false)
     {
      if(consumeTrigger)
         return CDemoManualSubmissionResult::Rejected(reason,detail,BRE_TRADE_EXEC_STATUS_NONE,true);
      return CDemoManualSubmissionResult::Rejected(reason,detail);
     }

   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON MapPreparedSubmissionFailureReason(
      const ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON reason) const
     {
      switch(reason)
        {
         case BRE_SUBMIT_FAIL_NOT_FOUND:
            return BRE_LIVE_SAFETY_REQUEST_NOT_FOUND;
         case BRE_SUBMIT_FAIL_NOT_QUEUED:
         case BRE_SUBMIT_FAIL_NOT_PREPARED:
            return BRE_LIVE_SAFETY_NOT_QUEUED_PREPARED;
         case BRE_SUBMIT_FAIL_ENVELOPE_EXPIRED:
            return BRE_LIVE_SAFETY_ENVELOPE_EXPIRED;
         case BRE_SUBMIT_FAIL_ENVELOPE_MISMATCH:
         case BRE_SUBMIT_FAIL_ALREADY_SUBMITTED:
         case BRE_SUBMIT_FAIL_BLOCKED_STATE:
         case BRE_SUBMIT_FAIL_GATEWAY_REJECTED:
         case BRE_SUBMIT_FAIL_GATEWAY_UNKNOWN:
            return BRE_LIVE_SAFETY_REQUEST_NOT_FOUND;
         case BRE_SUBMIT_FAIL_VALIDATION:
            return BRE_LIVE_SAFETY_REQUEST_NOT_FOUND;
         default:
            return BRE_LIVE_SAFETY_REQUEST_NOT_FOUND;
        }
     }

   string            FormatSubmitFailureDetail(const CPreparedSubmissionResult &submitResult) const
     {
      string detail=submitResult.FailureMessage();
      if(detail!="")
         return detail;
      ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON reason=submitResult.FailureReason();
      if(reason!=BRE_SUBMIT_FAIL_NONE)
         return PreparedSubmissionFailureReasonLabel(reason);
      return "Prepared submission failed";
     }

   bool              ValidateAuthorizationToken(const string plaintextToken,
                                              const CPendingExecutionEntry &entry,
                                              datetime nowUtc,
                                              string &tokenHashOut,
                                              ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON &reason,
                                              string &detail)
     {
      tokenHashOut="";
      reason=BRE_LIVE_SAFETY_NONE;
      detail="";
      if(m_config.RequireManualDemoAuthorization() && plaintextToken=="")
        {
         reason=BRE_LIVE_SAFETY_TOKEN_MISSING;
         detail="Manual demo authorization token required";
         return false;
        }
      string bindingFingerprint="";
      datetime tokenExpiry=0;
      if(!CExecutionAuthorizationToken::TryParsePlaintextToken(plaintextToken,bindingFingerprint,tokenExpiry))
        {
         reason=BRE_LIVE_SAFETY_TOKEN_INVALID;
         detail="Authorization token format invalid";
         return false;
        }
      if(tokenExpiry<=nowUtc)
        {
         reason=BRE_LIVE_SAFETY_TOKEN_EXPIRED;
         detail="Authorization token expired";
         return false;
        }
      tokenHashOut=CExecutionAuthorizationToken::ComputeTokenHash(plaintextToken);
      if(m_authRegistry.IsTokenConsumed(tokenHashOut))
        {
         reason=BRE_LIVE_SAFETY_TOKEN_CONSUMED;
         detail="Authorization token already consumed";
         return false;
        }
      string expectedFingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                                         entry.BasketId(),
                                                                                         entry.Symbol(),
                                                                                         entry.IntentType(),
                                                                                         entry.RequestedVolume(),
                                                                                         entry.ExpectedBasketVersion(),
                                                                                         entry.StrategyProfileHash());
      if(bindingFingerprint!=expectedFingerprint)
        {
         reason=BRE_LIVE_SAFETY_TOKEN_BINDING_MISMATCH;
         detail="Authorization token binding mismatch";
         return false;
        }
      return true;
     }

public:
                     CDemoManualSubmissionService(const CDemoExecutionAuthorizationConfig &config,
                                                  CExecutionAuthorizationRegistry *authRegistry,
                                                  CDemoManualSubmissionTriggerRegistry *triggerRegistry,
                                                  CPendingExecutionRegistry *pendingRegistry,
                                                  IPendingExecutionStore *pendingStore,
                                                  IAccountExecutionEligibilityProvider *eligibilityProvider,
                                                  IClock *clock,
                                                  CSubmitPreparedExecutionUseCase *submitUseCase,
                                                  CMt5AsyncSubmissionGateway *asyncGateway,
                                                  const CMarketSafetyConfig &marketSafety)
     : m_preparedValidator(pendingRegistry,pendingStore,clock)
     {
      m_config=config;
      m_authRegistry=authRegistry;
      m_triggerRegistry=triggerRegistry;
      m_pendingRegistry=pendingRegistry;
      m_pendingStore=pendingStore;
      m_eligibilityProvider=eligibilityProvider;
      m_clock=clock;
      m_submitUseCase=submitUseCase;
      m_asyncGateway=asyncGateway;
      m_marketSafety=marketSafety;
     }

   CDemoManualSubmissionResult TrySubmit(const string executionRequestId,
                                         const string authorizationToken,
                                         const string triggerToken,
                                         const CBasketAggregate &basket,
                                         const CMarketQuote &quote)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      if(!CExecutionAuthorizationPolicy::AllowsDemoManualSubmission(m_config))
         return Reject(BRE_LIVE_SAFETY_LIVE_DISABLED,"Demo manual submission route disabled");

      if(executionRequestId=="")
         return Reject(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,"Execution request id is required");

      if(triggerToken=="")
         return Reject(BRE_LIVE_SAFETY_TRIGGER_TOKEN_MISSING,"Manual submission trigger token is required");

      if(m_triggerRegistry.IsConsumed(triggerToken))
         return Reject(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,"Manual submission trigger token already consumed");

      if(!m_authRegistry.HasSubmissionSessionCapacity(m_config.MaxAuthorizedRequestsPerSession()))
         return Reject(BRE_LIVE_SAFETY_SUBMISSION_SESSION_CAP,"Submission session cap exceeded");

      CPendingExecutionEntry entry;
      CBrokerSubmissionEnvelope envelope;
      ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON prepReason=BRE_SUBMIT_FAIL_NONE;
      string prepMessage="";
      if(!m_preparedValidator.Validate(executionRequestId,entry,envelope,prepReason,prepMessage))
         return Reject(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,prepMessage);

      if(entry.IntentType()!=BRE_EXEC_INTENT_OPEN_POSITION)
         return Reject(BRE_LIVE_SAFETY_INTENT_NOT_ALLOWED,"Only OPEN_POSITION is allowed for demo manual submission");

      if(entry.RequestedVolume()>m_config.MaxManualDemoOpenVolume())
         return Reject(BRE_LIVE_SAFETY_VOLUME_EXCEEDS_DEMO_MAX,"Requested volume exceeds demo maximum");

      if(!m_authRegistry.IsSessionSymbolAllowed(entry.Symbol()))
         return Reject(BRE_LIVE_SAFETY_SYMBOL_SESSION_LOCKED,"Only one symbol per session is allowed");

      string tokenHash="";
      ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON authReason=BRE_LIVE_SAFETY_NONE;
      string authDetail="";
      if(!ValidateAuthorizationToken(authorizationToken,entry,nowUtc,tokenHash,authReason,authDetail))
         return Reject(authReason,authDetail);

      CLiveSubmissionSafetyGateContext context;
      context.SetConfig(m_config);
      context.SetEntry(entry);
      context.SetEnvelope(envelope);
      context.SetBasket(basket);
      context.SetQuote(quote);
      context.SetEligibility(m_eligibilityProvider!=NULL ? m_eligibilityProvider.Capture() : CAccountExecutionEligibilitySnapshot());
      context.SetMarketSafety(m_marketSafety);
      context.SetNowUtc(nowUtc);

      ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON safetyReason=BRE_LIVE_SAFETY_NONE;
      string safetyDetail="";
      if(!CLiveSubmissionSafetyGate::Evaluate(context,m_pendingRegistry,safetyReason,safetyDetail))
         return Reject(safetyReason,safetyDetail);

      CManualDemoExecutionAuthorization authRecord;
      authRecord.SetTokenHash(tokenHash);
      authRecord.SetExecutionRequestId(entry.ExecutionRequestId());
      authRecord.SetBasketId(entry.BasketId());
      authRecord.SetExpiryUtc(nowUtc+m_config.AuthorizationTokenExpirySeconds());
      authRecord.SetConsumed(false);
      authRecord.SetStatus(BRE_AUTH_STATUS_AUTHORIZED_FOR_FUTURE_SUBMISSION);
      authRecord.SetScope(BRE_AUTH_SCOPE_DEMO_SINGLE_REQUEST);
      authRecord.SetAuthorizedAtUtc(nowUtc);
      m_authRegistry.Upsert(authRecord);
      m_authRegistry.LockSessionSymbol(entry.Symbol());

      if(m_asyncGateway!=NULL)
         m_asyncGateway.BeginSubmissionAttempt(context,m_pendingRegistry);

      CPreparedSubmissionResult submitResult;
      if(m_submitUseCase!=NULL)
         submitResult=m_submitUseCase.Execute(executionRequestId);
      else
         submitResult=CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_VALIDATION,"Submit use case is not configured");

      if(m_asyncGateway!=NULL)
         m_asyncGateway.EndSubmissionAttempt();

      bool brokerInvoked=(m_asyncGateway!=NULL && m_asyncGateway.WasBrokerInvoked());
      bool authConsumed=false;
      bool triggerConsumed=false;
      if(brokerInvoked)
        {
         m_triggerRegistry.Consume(triggerToken);
         triggerConsumed=true;
         authConsumed=m_authRegistry.ConsumeToken(tokenHash);
         if(submitResult.IsSuccess() && submitResult.ResultingStatus()==BRE_TRADE_EXEC_STATUS_SUBMITTED)
            m_authRegistry.IncrementSessionSubmissionCount();
        }

      if(submitResult.IsSuccess())
         return CDemoManualSubmissionResult::Submitted(submitResult.ResultingStatus(),
                                                       brokerInvoked,
                                                       authConsumed,
                                                       triggerConsumed);

      ENUM_BRE_TRADE_EXECUTION_STATUS status=submitResult.ResultingStatus();
      if(status==BRE_TRADE_EXEC_STATUS_NONE)
         status=BRE_TRADE_EXEC_STATUS_REJECTED;

      ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON rejectReason=
         MapPreparedSubmissionFailureReason(submitResult.FailureReason());
      string detail=FormatSubmitFailureDetail(submitResult);
      return CDemoManualSubmissionResult::Rejected(rejectReason,detail,status,triggerConsumed,brokerInvoked);
     }
  };

#endif
