#ifndef BRE_DOMAIN_BROKER_SUBMISSION_TRANSITION_GATE_MQH
#define BRE_DOMAIN_BROKER_SUBMISSION_TRANSITION_GATE_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CBrokerSubmissionTransitionGate
  {
public:
   static bool       CanTransitionToSubmitted(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                              const bool brokerSubmitAccepted)
     {
      if(!brokerSubmitAccepted)
         return false;
      return fromStatus==BRE_TRADE_EXEC_STATUS_QUEUED;
     }

   static bool       PreparationMaySetStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_CREATED ||
             status==BRE_TRADE_EXEC_STATUS_QUEUED;
     }
  };

#endif
