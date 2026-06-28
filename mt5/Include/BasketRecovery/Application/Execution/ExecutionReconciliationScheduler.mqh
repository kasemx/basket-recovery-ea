#ifndef BRE_APP_EXECUTION_RECONCILIATION_SCHEDULER_MQH
#define BRE_APP_EXECUTION_RECONCILIATION_SCHEDULER_MQH

#include <BasketRecovery/Domain/Execution/ExecutionReconciliationRequest.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>

class CExecutionReconciliationScheduler
  {
private:
   CExecutionReconciliationRequest m_queue[];
   CPendingExecutionRegistry       *m_registry;
   IBrokerPositionReader           *m_positionReader;
   CPendingExecutionDiagnostics    *m_diagnostics;
   CPendingExecutionLifecycleService *m_lifecycle;
   int                              m_maxBatchSize;

   int               FindEntryIndex(const string executionRequestId) const
     {
      if(m_registry==NULL)
         return -1;
      CPendingExecutionEntry entry;
      if(!m_registry.TryGetByExecutionRequestId(executionRequestId,entry))
         return -1;
      for(int i=0;i<m_registry.Count();i++)
        {
         CPendingExecutionEntry candidate;
         if(m_registry.TryGetEntry(i,candidate) && candidate.ExecutionRequestId()==executionRequestId)
            return i;
        }
      return -1;
     }

public:
                     CExecutionReconciliationScheduler(CPendingExecutionRegistry *registry,
                                                       IBrokerPositionReader *positionReader,
                                                       CPendingExecutionDiagnostics *diagnostics,
                                                       const int maxBatchSize=8,
                                                       CPendingExecutionLifecycleService *lifecycle=NULL)
     {
      m_registry=registry;
      m_positionReader=positionReader;
      m_diagnostics=diagnostics;
      m_lifecycle=lifecycle;
      m_maxBatchSize=(maxBatchSize<=0 ? 8 : maxBatchSize);
     }

   void              Enqueue(const CExecutionReconciliationRequest &request)
     {
      if(request.ExecutionRequestId()=="")
         return;
      for(int i=0;i<ArraySize(m_queue);i++)
        {
         if(m_queue[i].ExecutionRequestId()==request.ExecutionRequestId())
            return;
        }
      int size=ArraySize(m_queue);
      ArrayResize(m_queue,size+1);
      m_queue[size]=request;
     }

   int               PendingCount(void) const { return ArraySize(m_queue); }

   int               ProcessBatch(void)
     {
      int processed=0;
      int batch=MathMin(ArraySize(m_queue),m_maxBatchSize);
      for(int i=0;i<batch;i++)
        {
         CExecutionReconciliationRequest request=m_queue[i];
         int index=FindEntryIndex(request.ExecutionRequestId());
         if(index<0)
            continue;

         CPendingExecutionEntry entry;
         if(!m_registry.TryGetEntry(index,entry))
            continue;
         if(entry.Status()!=BRE_TRADE_EXEC_STATUS_RECONCILING)
            continue;

         ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
         double matchedVolume=0.0;
         ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
            CExecutionReconciliationResolver::Resolve(entry,m_positionReader,matchedVolume);

         if(resolved==BRE_TRADE_EXEC_STATUS_UNKNOWN)
           {
            if(m_diagnostics!=NULL)
               m_diagnostics.OnUnresolvedUnknown(entry.ExecutionRequestId());
            processed++;
            continue;
           }

         CPendingExecutionEntry updated;
         if(!m_registry.TryTransition(index,resolved,updated))
            continue;

         if(matchedVolume>0.0)
            updated.SetFilledVolume(matchedVolume);
         m_registry.TryUpdateEntry(index,updated);
         if(m_lifecycle!=NULL)
            m_lifecycle.OnRegistryEntryUpdated(updated,fromStatus);

         processed++;
        }

      if(batch>0)
         ArrayRemove(m_queue,0,batch);

      return processed;
     }

   void              Clear(void)
     {
      ArrayResize(m_queue,0);
     }
  };

#endif
