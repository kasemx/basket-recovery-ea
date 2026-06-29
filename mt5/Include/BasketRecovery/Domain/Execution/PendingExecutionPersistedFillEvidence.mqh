#ifndef BRE_DOMAIN_PENDING_EXECUTION_PERSISTED_FILL_EVIDENCE_MQH
#define BRE_DOMAIN_PENDING_EXECUTION_PERSISTED_FILL_EVIDENCE_MQH

#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionPersistedFillEvidence
  {
public:
   static bool       HasKnownFill(const CPendingExecutionEntry &entry)
     {
      if(entry.Status()==BRE_TRADE_EXEC_STATUS_FILLED)
         return true;
      if(entry.FilledVolume()>0.0000001)
         return true;
      return false;
     }

   static bool       BlocksDowngradeToNonFill(const CPendingExecutionEntry &entry,
                                              const ENUM_BRE_TRADE_EXECUTION_STATUS proposedStatus)
     {
      if(!HasKnownFill(entry))
         return false;
      if(proposedStatus==BRE_TRADE_EXEC_STATUS_FILLED ||
         proposedStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
         return false;
      return true;
     }

   static bool       IsTerminalFillMonotonic(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                             const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus)
     {
      if(fromStatus!=BRE_TRADE_EXEC_STATUS_FILLED)
         return true;
      return toStatus==BRE_TRADE_EXEC_STATUS_FILLED;
     }
  };

#endif
