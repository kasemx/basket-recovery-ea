#ifndef BRE_DOMAIN_PENDING_EXECUTION_QUERY_MQH
#define BRE_DOMAIN_PENDING_EXECUTION_QUERY_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionQuery
  {
public:
   static bool       IsTerminalStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      switch(status)
        {
         case BRE_TRADE_EXEC_STATUS_FILLED:
         case BRE_TRADE_EXEC_STATUS_REJECTED:
         case BRE_TRADE_EXEC_STATUS_CANCELLED:
         case BRE_TRADE_EXEC_STATUS_FAILED:
         case BRE_TRADE_EXEC_STATUS_TIMED_OUT:
         case BRE_TRADE_EXEC_STATUS_RECONCILED:
            return true;
         default:
            return false;
        }
     }

   static bool       IsUnknownReconcilingStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_RECONCILING;
     }

   static bool       IsUnresolvedStatus(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      if(status==BRE_TRADE_EXEC_STATUS_NONE)
         return false;
      return !IsTerminalStatus(status);
     }
  };

#endif
