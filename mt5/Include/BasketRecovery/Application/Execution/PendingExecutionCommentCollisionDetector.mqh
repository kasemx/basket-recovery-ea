#ifndef BRE_APP_PENDING_EXECUTION_COMMENT_COLLISION_DETECTOR_MQH
#define BRE_APP_PENDING_EXECUTION_COMMENT_COLLISION_DETECTOR_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionCommentCollisionDetector
  {
public:
   static bool       HasActiveCommentCollision(const CPendingExecutionRegistry &registry,
                                               const string brokerComment,
                                               const string executionRequestId)
     {
      if(brokerComment=="")
         return false;

      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.ExecutionRequestId()==executionRequestId)
            continue;
         if(entry.BrokerComment()!=brokerComment)
            continue;
         if(IsActivePending(entry.Status()))
            return true;
        }
      return false;
     }

   static bool       HasActiveCorrelationCollision(const CPendingExecutionRegistry &registry,
                                                   const string correlationToken,
                                                   const string executionRequestId)
     {
      if(correlationToken=="")
         return false;

      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.ExecutionRequestId()==executionRequestId)
            continue;
         if(entry.CorrelationToken()!=correlationToken)
            continue;
         if(IsActivePending(entry.Status()))
            return true;
        }
      return false;
     }

private:
   static bool       IsActivePending(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      return status==BRE_TRADE_EXEC_STATUS_CREATED ||
             status==BRE_TRADE_EXEC_STATUS_QUEUED ||
             status==BRE_TRADE_EXEC_STATUS_SUBMITTED ||
             status==BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED ||
             status==BRE_TRADE_EXEC_STATUS_ACCEPTED ||
             status==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED ||
             status==BRE_TRADE_EXEC_STATUS_RECONCILING ||
             status==BRE_TRADE_EXEC_STATUS_TIMED_OUT;
     }
  };

#endif
