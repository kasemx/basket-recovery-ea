#ifndef BRE_DOMAIN_DEMO_MANUAL_SUBMISSION_RESULT_MQH
#define BRE_DOMAIN_DEMO_MANUAL_SUBMISSION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>

class CDemoManualSubmissionResult
  {
private:
   bool                                              m_success;
   ENUM_BRE_TRADE_EXECUTION_STATUS                   m_resultingStatus;
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON  m_rejectionReason;
   string                                            m_detail;
   bool                                              m_brokerInvoked;
   bool                                              m_authTokenConsumed;
   bool                                              m_triggerTokenConsumed;
   bool                                              m_orderSendAsyncAccepted;

public:
                     CDemoManualSubmissionResult(void)
     {
      m_success=false;
      m_resultingStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_rejectionReason=BRE_LIVE_SAFETY_NONE;
      m_brokerInvoked=false;
      m_authTokenConsumed=false;
      m_triggerTokenConsumed=false;
      m_orderSendAsyncAccepted=false;
     }

   bool              IsSuccess(void) const { return m_success; }
   ENUM_BRE_TRADE_EXECUTION_STATUS ResultingStatus(void) const { return m_resultingStatus; }
   ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON RejectionReason(void) const { return m_rejectionReason; }
   string            Detail(void) const { return m_detail; }
   bool              BrokerInvoked(void) const { return m_brokerInvoked; }
   bool              AuthTokenConsumed(void) const { return m_authTokenConsumed; }
   bool              TriggerTokenConsumed(void) const { return m_triggerTokenConsumed; }
   bool              OrderSendAsyncAccepted(void) const { return m_orderSendAsyncAccepted; }

   static CDemoManualSubmissionResult Submitted(const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                                                const bool orderSendAsyncAccepted,
                                                const bool authTokenConsumed,
                                                const bool triggerTokenConsumed)
     {
      CDemoManualSubmissionResult result;
      result.m_success=(status==BRE_TRADE_EXEC_STATUS_SUBMITTED);
      result.m_resultingStatus=status;
      result.m_brokerInvoked=orderSendAsyncAccepted;
      result.m_orderSendAsyncAccepted=orderSendAsyncAccepted;
      result.m_authTokenConsumed=authTokenConsumed;
      result.m_triggerTokenConsumed=triggerTokenConsumed;
      return result;
     }

   static CDemoManualSubmissionResult Rejected(const ENUM_BRE_LIVE_SUBMISSION_SAFETY_REJECTION_REASON reason,
                                               const string detail,
                                               const ENUM_BRE_TRADE_EXECUTION_STATUS status=BRE_TRADE_EXEC_STATUS_NONE,
                                               const bool triggerTokenConsumed=false,
                                               const bool brokerInvoked=false)
     {
      CDemoManualSubmissionResult result;
      result.m_success=false;
      result.m_resultingStatus=status;
      result.m_rejectionReason=reason;
      result.m_detail=detail;
      result.m_triggerTokenConsumed=triggerTokenConsumed;
      result.m_brokerInvoked=brokerInvoked;
      result.m_orderSendAsyncAccepted=brokerInvoked;
      return result;
     }
  };

#endif
