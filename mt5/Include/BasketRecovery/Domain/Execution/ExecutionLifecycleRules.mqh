#ifndef BRE_DOMAIN_EXECUTION_LIFECYCLE_RULES_MQH
#define BRE_DOMAIN_EXECUTION_LIFECYCLE_RULES_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CExecutionLifecycleRules
  {
public:
   static bool       IsTerminal(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return TradeExecutionStatusIsTerminal(status);
     }

   static bool       CanSubmit(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      if(IsTerminal(status))
         return false;
      return status==BRE_TRADE_EXEC_STATUS_QUEUED ||
             status==BRE_TRADE_EXEC_STATUS_CREATED;
     }

   static bool       CanRetry(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_FAILED;
     }

   static bool       BlocksBlindResend(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_UNKNOWN;
     }

   static bool       CanTransition(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                   const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      if(fromStatus==toStatus)
         return true;
      if(IsTerminal(fromStatus))
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
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED;
         case BRE_TRADE_EXEC_STATUS_SUBMITTED:
            return toStatus==BRE_TRADE_EXEC_STATUS_ACCEPTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN ||
                   toStatus==BRE_TRADE_EXEC_STATUS_CANCELLED;
         case BRE_TRADE_EXEC_STATUS_ACCEPTED:
            return toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN;
         case BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED:
            return toStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_REJECTED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_FAILED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
                   toStatus==BRE_TRADE_EXEC_STATUS_UNKNOWN;
         case BRE_TRADE_EXEC_STATUS_FAILED:
            return toStatus==BRE_TRADE_EXEC_STATUS_QUEUED ||
                   toStatus==BRE_TRADE_EXEC_STATUS_SUBMITTED;
         default:
            return false;
        }
     }
  };

#endif
