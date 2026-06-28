#ifndef BRE_DOMAIN_MANUAL_DEMO_EXECUTION_AUTHORIZATION_MQH
#define BRE_DOMAIN_MANUAL_DEMO_EXECUTION_AUTHORIZATION_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationScope.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationStatus.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>

class CManualDemoExecutionAuthorization
  {
private:
   string                                      m_tokenHash;
   string                                      m_executionRequestId;
   CBasketId                                   m_basketId;
   datetime                                    m_expiryUtc;
   bool                                        m_consumed;
   ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS     m_status;
   ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE      m_scope;
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON m_rejectionReason;
   string                                      m_rejectionDetail;
   datetime                                    m_authorizedAtUtc;

public:
                     CManualDemoExecutionAuthorization(void)
     {
      m_expiryUtc=0;
      m_consumed=false;
      m_status=BRE_AUTH_STATUS_NONE;
      m_scope=BRE_AUTH_SCOPE_LIVE_DISABLED;
      m_rejectionReason=BRE_LIVE_SAFETY_NONE;
      m_authorizedAtUtc=0;
     }

   string            TokenHash(void) const { return m_tokenHash; }
   string            ExecutionRequestId(void) const { return m_executionRequestId; }
   CBasketId         BasketId(void) const { return m_basketId; }
   datetime          ExpiryUtc(void) const { return m_expiryUtc; }
   bool              Consumed(void) const { return m_consumed; }
   ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS Status(void) const { return m_status; }
   ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE Scope(void) const { return m_scope; }
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON RejectionReason(void) const { return m_rejectionReason; }
   string            RejectionDetail(void) const { return m_rejectionDetail; }
   datetime          AuthorizedAtUtc(void) const { return m_authorizedAtUtc; }

   void              SetTokenHash(const string value) { m_tokenHash=value; }
   void              SetExecutionRequestId(const string value) { m_executionRequestId=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetExpiryUtc(const datetime value) { m_expiryUtc=value; }
   void              SetConsumed(const bool value) { m_consumed=value; }
   void              SetStatus(const ENUM_BRE_EXECUTION_AUTHORIZATION_STATUS value) { m_status=value; }
   void              SetScope(const ENUM_BRE_EXECUTION_AUTHORIZATION_SCOPE value) { m_scope=value; }
   void              SetRejectionReason(const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON value) { m_rejectionReason=value; }
   void              SetRejectionDetail(const string value) { m_rejectionDetail=value; }
   void              SetAuthorizedAtUtc(const datetime value) { m_authorizedAtUtc=value; }

   bool              IsExpired(const datetime nowUtc) const
     {
      return m_expiryUtc>0 && nowUtc>=m_expiryUtc;
     }
  };

#endif
