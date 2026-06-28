#ifndef BRE_DOMAIN_EXECUTION_AUTHORIZATION_RESULT_MQH
#define BRE_DOMAIN_EXECUTION_AUTHORIZATION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationStatus.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationScope.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>

class CExecutionAuthorizationResult
  {
private:
   bool                                      m_success;
   ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS   m_status;
   ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE    m_scope;
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON m_rejectionReason;
   string                                    m_detail;
   bool                                      m_tokenConsumed;
   bool                                      m_brokerInvoked;

public:
                     CExecutionAuthorizationResult(void)
     {
      m_success=false;
      m_status=BRE_AUTH_STATUS_NONE;
      m_scope=BRE_AUTH_SCOPE_LIVE_DISABLED;
      m_rejectionReason=BRE_LIVE_SAFETY_NONE;
      m_tokenConsumed=false;
      m_brokerInvoked=false;
     }

   bool              IsSuccess(void) const { return m_success; }
   ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS Status(void) const { return m_status; }
   ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE Scope(void) const { return m_scope; }
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON RejectionReason(void) const { return m_rejectionReason; }
   string            Detail(void) const { return m_detail; }
   bool              TokenConsumed(void) const { return m_tokenConsumed; }
   bool              BrokerInvoked(void) const { return m_brokerInvoked; }

   static CExecutionAuthorizationResult Authorized(const ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE scope,
                                                   const bool tokenConsumed)
     {
      CExecutionAuthorizationResult result;
      result.m_success=true;
      result.m_status=BRE_AUTH_STATUS_AUTHORIZED_FOR_FUTURE_SUBMISSION;
      result.m_scope=scope;
      result.m_tokenConsumed=tokenConsumed;
      result.m_brokerInvoked=false;
      return result;
     }

   static CExecutionAuthorizationResult Rejected(const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON reason,
                                                 const string detail)
     {
      CExecutionAuthorizationResult result;
      result.m_success=false;
      result.m_status=BRE_AUTH_STATUS_REJECTED;
      result.m_rejectionReason=reason;
      result.m_detail=detail;
      result.m_brokerInvoked=false;
      return result;
     }
  };

#endif
