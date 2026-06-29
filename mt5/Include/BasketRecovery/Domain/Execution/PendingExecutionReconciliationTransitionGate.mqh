#ifndef BRE_DOMAIN_PENDING_EXECUTION_RECONCILIATION_TRANSITION_GATE_MQH
#define BRE_DOMAIN_PENDING_EXECUTION_RECONCILIATION_TRANSITION_GATE_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionPersistedFillEvidence.mqh>

class CPendingExecutionReconciliationTransitionGate
  {
public:
   static bool       CanResolveFromBrokerRead(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                              const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      if(CPendingExecutionQuery::IsTerminalStatus(fromStatus))
         return false;
      if(!CPendingExecutionPersistedFillEvidence::IsTerminalFillMonotonic(fromStatus,toStatus))
         return false;
      if(fromStatus==toStatus)
         return true;
      if(CPendingExecutionTransitionRules::CanTransition(fromStatus,toStatus))
         return true;

      switch(fromStatus)
        {
         case BRE_TRADE_EXEC_STATUS_SUBMITTED:
         case BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED:
         case BRE_TRADE_EXEC_STATUS_ACCEPTED:
         case BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED:
         case BRE_TRADE_EXEC_STATUS_RECONCILING:
         case BRE_TRADE_EXEC_STATUS_UNKNOWN:
            return toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILING;
         default:
            return false;
        }
     }
  };

#endif
