#ifndef BRE_APP_PENDING_EXECUTION_RESTART_SERVICE_MQH
#define BRE_APP_PENDING_EXECUTION_RESTART_SERVICE_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCommentCollisionDetector.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CPendingExecutionRestartService
  {
public:
   static int        RestorePreparedEntries(IPendingExecutionStore *store,
                                            CPendingExecutionRegistry *registry,
                                            string &duplicateWarnings[])
     {
      ArrayResize(duplicateWarnings,0);
      if(store==NULL || registry==NULL)
         return 0;

      CPendingExecutionEntry entries[];
      int count=store.RestoreEntries(entries);
      int restored=0;

      for(int i=0;i<count;i++)
        {
         if(entries[i].Status()!=BRE_TRADE_EXEC_STATUS_QUEUED &&
            entries[i].Status()!=BRE_TRADE_EXEC_STATUS_CREATED)
            continue;
         if(!entries[i].HasPreparationMetadata())
            continue;

         if(CPendingExecutionCommentCollisionDetector::HasActiveCommentCollision(*registry,
                                                                                 entries[i].BrokerComment(),
                                                                                 entries[i].ExecutionRequestId()))
           {
            int size=ArraySize(duplicateWarnings);
            ArrayResize(duplicateWarnings,size+1);
            duplicateWarnings[size]="duplicate_comment:"+entries[i].ExecutionRequestId();
            continue;
           }

         registry.Upsert(entries[i]);
         restored++;
        }

      return restored;
     }
  };

#endif
