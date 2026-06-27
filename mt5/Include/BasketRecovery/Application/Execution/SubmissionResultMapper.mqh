#ifndef BRE_APP_SUBMISSION_RESULT_MAPPER_MQH
#define BRE_APP_SUBMISSION_RESULT_MAPPER_MQH

#include <BasketRecovery/Domain/Execution/SubmissionGatewayResult.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionFailureReason.mqh>
#include <BasketRecovery/Domain/Execution/PreparedSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CSubmissionResultMapper
  {
public:
   static ENUM_BRE_TRADE_EXECUTION_STATUS MapGatewayRejectionStatus(void)
     {
      return BRE_TRADE_EXEC_STATUS_REJECTED;
     }

   static ENUM_BRE_TRADE_EXECUTION_STATUS MapGatewayUnknownStatus(void)
     {
      return BRE_TRADE_EXEC_STATUS_UNKNOWN;
     }

   static CPreparedSubmissionResult MapGatewayAccepted(const ulong brokerRequestId,
                                                       const bool duplicateReplay=false,
                                                       const bool gatewayInvoked=true)
     {
      return CPreparedSubmissionResult::Ok(BRE_TRADE_EXEC_STATUS_SUBMITTED,
                                           brokerRequestId,
                                           duplicateReplay,
                                           gatewayInvoked);
     }

   static CPreparedSubmissionResult MapGatewayRejected(const string detail)
     {
      return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_GATEWAY_REJECTED,
                                             detail,
                                             BRE_TRADE_EXEC_STATUS_REJECTED);
     }

   static CPreparedSubmissionResult MapGatewayUnknown(const string detail)
     {
      return CPreparedSubmissionResult::Fail(BRE_SUBMIT_FAIL_GATEWAY_UNKNOWN,
                                             detail,
                                             BRE_TRADE_EXEC_STATUS_UNKNOWN);
     }

   static CPreparedSubmissionResult MapDuplicateFromEntry(const CPendingExecutionEntry &entry,
                                                          const ulong brokerRequestId)
     {
      return CPreparedSubmissionResult::Ok(entry.Status(),
                                           brokerRequestId,
                                           true,
                                           false);
     }

   static bool       CanApplyGatewayOutcome(const ENUM_BRE_TRADE_EXECUTION_STATUS currentStatus,
                                            const ENUM_BRE_TRADE_EXECUTION_STATUS proposedStatus)
     {
      return CPendingExecutionTransitionRules::CanTransition(currentStatus,proposedStatus);
     }
  };

#endif
