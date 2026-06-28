#ifndef BRE_DOMAIN_PENDING_EXECUTION_TRANSITION_RULES_MQH
#define BRE_DOMAIN_PENDING_EXECUTION_TRANSITION_RULES_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionTransitionRules
  {
public:
   static bool       IsTerminal(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      switch(status)
        {
         case BRE_TRADE_EXEC_STATUS_FILLED:
         case BRE_TRADE_EXEC_STATUS_REJECTED:
         case BRE_TRADE_EXEC_STATUS_RECONCILED:
         case BRE_TRADE_EXEC_STATUS_CANCELLED:
         case BRE_TRADE_EXEC_STATUS_FAILED:
         case BRE_TRADE_EXEC_STATUS_TIMED_OUT:
            return true;
         default:
            return false;
        }
     }

   static bool       BlocksBlindResend(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_RECONCILING;
     }

   static int        StatusRank(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      switch(status)
        {
         case BRE_TRADE_EXEC_STATUS_CREATED: return 10;
         case BRE_TRADE_EXEC_STATUS_QUEUED: return 20;
         case BRE_TRADE_EXEC_STATUS_SUBMITTED: return 30;
         case BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED: return 40;
         case BRE_TRADE_EXEC_STATUS_ACCEPTED: return 45;
         case BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED: return 50;
         case BRE_TRADE_EXEC_STATUS_RECONCILING: return 55;
         case BRE_TRADE_EXEC_STATUS_TIMED_OUT: return 60;
         case BRE_TRADE_EXEC_STATUS_UNKNOWN: return 70;
         case BRE_TRADE_EXEC_STATUS_FILLED: return 80;
         case BRE_TRADE_EXEC_STATUS_REJECTED: return 80;
         case BRE_TRADE_EXEC_STATUS_RECONCILED: return 90;
         case BRE_TRADE_EXEC_STATUS_CANCELLED: return 90;
         case BRE_TRADE_EXEC_STATUS_FAILED: return 90;
         default: return 0;
        }
     }

   static bool       CanTransition(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                   const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      if(fromStatus==toStatus)
         return true;
      if(IsTerminal(fromStatus))
         return false;
      if(StatusRank(toStatus)<StatusRank(fromStatus))
         return false;

      switch(fromStatus)
        {
         case BRE_TRADE_EXEC_STATUS_CREATED:
            return toStatus==BRE_TRADE_EXEC_STATUS_QUEUED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED;
         case BRE_TRADE_EXEC_STATUS_QUEUED:
            return toStatus==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED;
         case BRE_TRADE_EXEC_STATUS_SUBMITTED:
            return toStatus==BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_ACCEPTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILING ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED;
         case BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED:
         case BRE_TRADE_EXEC_STATUS_ACCEPTED:
            return toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILING ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED;
         case BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED:
            return toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILING ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED;
         case BRE_TRADE_EXEC_STATUS_RECONCILING:
            return toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_RECONCILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED;
         default:
            return false;
        }
     }

   static bool       AllowsLateTransaction(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_RECONCILING;
     }
  };

#endif
