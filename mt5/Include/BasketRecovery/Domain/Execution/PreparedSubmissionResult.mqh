#ifndef BRE_DOMAIN_PREPARED_SUBMISSION_RESULT_MQH
#define BRE_DOMAIN_PREPARED_SUBMISSION_RESULT_MQH

#include <BasketRecovery/Domain/Execution/PreparedSubmissionFailureReason.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionGatewayResult.mqh>

class CPreparedSubmissionResult
  {
private:
   bool                                      m_success;
   ENUM_BRE_TRADE_EXECUTION_STATUS           m_resultingStatus;
   ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON m_failureReason;
   string                                    m_failureMessage;
   ulong                                     m_brokerRequestId;
   bool                                      m_duplicateReplay;
   bool                                      m_gatewayInvoked;

public:
                     CPreparedSubmissionResult(void)
     {
      m_success=false;
      m_resultingStatus=BRE_TRADE_EXEC_STATUS_NONE;
      m_failureReason=BRE_SUBMIT_FAIL_NONE;
      m_failureMessage="";
      m_brokerRequestId=0;
      m_duplicateReplay=false;
      m_gatewayInvoked=false;
     }

   bool              IsSuccess(void) const { return m_success; }
   ENUM_BRE_TRADE_EXECUTION_STATUS ResultingStatus(void) const { return m_resultingStatus; }
   ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON FailureReason(void) const { return m_failureReason; }
   string            FailureMessage(void) const { return m_failureMessage; }
   ulong             BrokerRequestId(void) const { return m_brokerRequestId; }
   bool              IsDuplicateReplay(void) const { return m_duplicateReplay; }
   bool              GatewayInvoked(void) const { return m_gatewayInvoked; }

   static CPreparedSubmissionResult Ok(const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                                       const ulong brokerRequestId,
                                       const bool duplicateReplay=false,
                                       const bool gatewayInvoked=true)
     {
      CPreparedSubmissionResult result;
      result.m_success=true;
      result.m_resultingStatus=status;
      result.m_brokerRequestId=brokerRequestId;
      result.m_duplicateReplay=duplicateReplay;
      result.m_gatewayInvoked=gatewayInvoked;
      return result;
     }

   static CPreparedSubmissionResult Fail(const ENUM_BRE_PREPARED_SUBMISSION_FAILURE_REASON reason,
                                         const string message,
                                         const ENUM_BRE_TRADE_EXECUTION_STATUS status=BRE_TRADE_EXEC_STATUS_NONE,
                                         const bool duplicateReplay=false,
                                         const bool gatewayInvoked=true)
     {
      CPreparedSubmissionResult result;
      result.m_success=false;
      result.m_failureReason=reason;
      result.m_failureMessage=message;
      result.m_resultingStatus=status;
      result.m_duplicateReplay=duplicateReplay;
      result.m_gatewayInvoked=gatewayInvoked;
      return result;
     }
  };

#endif
