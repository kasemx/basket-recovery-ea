#ifndef BRE_APP_MANUAL_DEMO_AUTHORIZATION_USE_CASE_MQH
#define BRE_APP_MANUAL_DEMO_AUTHORIZATION_USE_CASE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGate.mqh>
#include <BasketRecovery/Application/Execution/LiveSubmissionSafetyGateContext.mqh>
#include <BasketRecovery/Application/Execution/PreparedSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationResult.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>

class CManualDemoAuthorizationUseCase
  {
private:
   CDemoExecutionAuthorizationConfig     m_config;
   CExecutionAuthorizationRegistry      *m_registry;
   CPendingExecutionRegistry            *m_pendingRegistry;
   IPendingExecutionStore               *m_pendingStore;
   IAccountExecutionEligibilityProvider *m_eligibilityProvider;
   IClock                               *m_clock;
   CPreparedSubmissionValidator          m_preparedValidator;
   CMarketSafetyConfig                   m_marketSafety;

   CExecutionAuthorizationResult Reject(const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON reason,
                                          const string detail,
                                          const string tokenHash="")
     {
      if(tokenHash!="")
        {
         CManualDemoExecutionAuthorization record;
         record.SetTokenHash(tokenHash);
         record.SetStatus(BRE_AUTH_STATUS_REJECTED);
         record.SetRejectionReason(reason);
         record.SetRejectionDetail(detail);
         m_registry.Upsert(record);
        }
      return CExecutionAuthorizationResult::Rejected(reason,detail);
     }

public:
                     CManualDemoAuthorizationUseCase(const CDemoExecutionAuthorizationConfig &config,
                                                     CExecutionAuthorizationRegistry *registry,
                                                     CPendingExecutionRegistry *pendingRegistry,
                                                     IPendingExecutionStore *pendingStore,
                                                     IAccountExecutionEligibilityProvider *eligibilityProvider,
                                                     IClock *clock,
                                                     const CMarketSafetyConfig &marketSafety)
     : m_preparedValidator(pendingRegistry,pendingStore,clock)
     {
      m_config=config;
      m_registry=registry;
      m_pendingRegistry=pendingRegistry;
      m_pendingStore=pendingStore;
      m_eligibilityProvider=eligibilityProvider;
      m_clock=clock;
      m_marketSafety=marketSafety;
     }

   CExecutionAuthorizationResult Authorize(const string executionRequestId,
                                           const string plaintextToken,
                                           const CBasketAggregate &basket,
                                           const CMarketQuote &quote)
     {
      datetime nowUtc=m_clock!=NULL ? m_clock.Now() : TimeCurrent();

      if(m_config.GlobalExecutionKillSwitch())
         return Reject(BRE_LIVE_SAFETY_GLOBAL_KILL_SWITCH,"Global execution kill switch enabled");

      if(!CExecutionAuthorizationPolicy::AllowsFutureSubmissionAuthorization(m_config))
         return Reject(BRE_LIVE_SAFETY_LIVE_DISABLED,"Runtime live submission authorization disabled");

      if(m_config.ExecutionRuntimeMode()!=BRE_EXEC_RUNTIME_DEMO_AUTHORIZATION)
         return Reject(BRE_LIVE_SAFETY_EXECUTION_MODE_INVALID,"Execution mode must be DEMO_AUTHORIZATION");

      if(!m_config.EnableLiveDemoExecution())
         return Reject(BRE_LIVE_SAFETY_DEMO_EXECUTION_DISABLED,"Live demo execution input disabled");

      if(m_config.RequireManualDemoAuthorization() && plaintextToken=="")
         return Reject(BRE_LIVE_SAFETY_TOKEN_MISSING,"Manual demo authorization token required");

      if(!m_registry.HasSessionCapacity(m_config.MaxAuthorizedRequestsPerSession()))
         return Reject(BRE_LIVE_SAFETY_SESSION_CAP_EXCEEDED,"Session authorization cap exceeded");

      string bindingFingerprint="";
      datetime tokenExpiry=0;
      if(!CExecutionAuthorizationToken::TryParsePlaintextToken(plaintextToken,bindingFingerprint,tokenExpiry))
         return Reject(BRE_LIVE_SAFETY_TOKEN_INVALID,"Authorization token format invalid");

      if(tokenExpiry<=nowUtc)
         return Reject(BRE_LIVE_SAFETY_TOKEN_EXPIRED,"Authorization token expired");

      string tokenHash=CExecutionAuthorizationToken::ComputeTokenHash(plaintextToken);
      if(m_registry.IsTokenConsumed(tokenHash))
         return Reject(BRE_LIVE_SAFETY_TOKEN_CONSUMED,"Authorization token already consumed",tokenHash);

      CPendingExecutionEntry entry;
      CBrokerSubmissionEnvelope envelope;
      ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON prepReason=BRE_SUBMIT_FAIL_NONE;
      string prepMessage="";
      if(!m_preparedValidator.Validate(executionRequestId,entry,envelope,prepReason,prepMessage))
         return Reject(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,prepMessage);

      string expectedFingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                                         entry.BasketId(),
                                                                                         entry.Symbol(),
                                                                                         entry.IntentType(),
                                                                                         entry.RequestedVolume(),
                                                                                         entry.ExpectedBasketVersion(),
                                                                                         entry.StrategyProfileHash());
      if(bindingFingerprint!=expectedFingerprint)
         return Reject(BRE_LIVE_SAFETY_TOKEN_BINDING_MISMATCH,"Authorization token binding mismatch",tokenHash);

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
         return Reject(safetyReason,safetyDetail,tokenHash);

      ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE scope=CExecutionAuthorizationPolicy::ResolveScope(m_config);
      CManualDemoExecutionAuthorization record;
      record.SetTokenHash(tokenHash);
      record.SetExecutionRequestId(entry.ExecutionRequestId());
      record.SetBasketId(entry.BasketId());
      record.SetExpiryUtc(tokenExpiry);
      record.SetConsumed(true);
      record.SetStatus(BRE_AUTH_STATUS_AUTHORIZED_FOR_FUTURE_SUBMISSION);
      record.SetScope(scope);
      record.SetAuthorizedAtUtc(nowUtc);
      m_registry.Upsert(record);
      m_registry.IncrementSessionAuthorizedCount();

      return CExecutionAuthorizationResult::Authorized(scope,true);
     }
  };

#endif
