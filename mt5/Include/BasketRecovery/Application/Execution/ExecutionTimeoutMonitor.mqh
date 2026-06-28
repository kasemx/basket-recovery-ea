#ifndef BRE_APP_EXECUTION_TIMEOUT_MONITOR_MQH
#define BRE_APP_EXECUTION_TIMEOUT_MONITOR_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>

class CExecutionTimeoutMonitor
  {
private:
   CPendingExecutionRegistry           *m_registry;
   CExecutionReconciliationScheduler   *m_reconciliationScheduler;
   IBrokerPositionReader               *m_positionReader;
   CPendingExecutionDiagnostics        *m_diagnostics;
   IClock                              *m_clock;
   CPendingExecutionLifecycleService   *m_lifecycle;

   void              EnqueueReconciliation(const CPendingExecutionEntry &entry,const string reason)
     {
      if(m_reconciliationScheduler==NULL)
         return;
      CExecutionReconciliationRequest request;
      request.SetExecutionRequestId(entry.ExecutionRequestId());
      request.SetBasketId(entry.BasketId());
      request.SetSymbol(entry.Symbol());
      request.SetReason(reason);
      if(m_clock!=NULL)
         request.SetRequestedAtUtc(m_clock.Now());
      m_reconciliationScheduler.Enqueue(request);
      if(m_diagnostics!=NULL)
         m_diagnostics.OnReconciliationRequested(entry.ExecutionRequestId(),reason);
     }

public:
                     CExecutionTimeoutMonitor(CPendingExecutionRegistry *registry,
                                              CExecutionReconciliationScheduler *reconciliationScheduler,
                                              IBrokerPositionReader *positionReader,
                                              CPendingExecutionDiagnostics *diagnostics,
                                              IClock *clock,
                                              CPendingExecutionLifecycleService *lifecycle=NULL)
     {
      m_registry=registry;
      m_reconciliationScheduler=reconciliationScheduler;
      m_positionReader=positionReader;
      m_diagnostics=diagnostics;
      m_clock=clock;
      m_lifecycle=lifecycle;
     }

   int               ScanDueTimeouts(void)
     {
      if(m_registry==NULL || m_clock==NULL || m_lifecycle==NULL)
         return 0;

      datetime nowUtc=m_clock.Now();
      int dueIndices[];
      int dueCount=m_registry.CollectTimeoutDue(nowUtc,dueIndices);
      int handled=0;

      for(int i=0;i<dueCount;i++)
        {
         CPendingExecutionEntry entry;
         if(!m_registry.TryGetEntry(dueIndices[i],entry))
            continue;
         if(CPendingExecutionQuery::IsTerminalStatus(entry.Status()) ||
            CPendingExecutionQuery::IsUnknownReconcilingStatus(entry.Status()))
            continue;

         if(m_diagnostics!=NULL)
            m_diagnostics.OnTimeoutDetected(entry.ExecutionRequestId());

         double matchedVolume=0.0;
         ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
            CExecutionReconciliationResolver::Resolve(entry,m_positionReader,matchedVolume);

         if(resolved==BRE_TRADE_EXEC_STATUS_FILLED)
           {
            if(m_lifecycle.MarkFilled(entry.ExecutionRequestId(),matchedVolume))
               handled++;
            continue;
           }

         if(resolved==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
           {
            ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
            entry.SetFilledVolume(matchedVolume);
            entry.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
            m_registry.TryUpdateEntry(dueIndices[i],entry);
            m_lifecycle.OnRegistryEntryUpdated(entry,fromStatus);
            handled++;
            continue;
           }

         if(resolved==BRE_TRADE_EXEC_STATUS_REJECTED)
           {
            if(m_lifecycle.MarkTimedOut(entry.ExecutionRequestId()))
               handled++;
            continue;
           }

         if(m_lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId()))
           {
            if(m_diagnostics!=NULL)
               m_diagnostics.OnUnresolvedUnknown(entry.ExecutionRequestId());
            CPendingExecutionEntry updated;
            if(m_registry.TryGetByExecutionRequestId(entry.ExecutionRequestId(),updated))
               EnqueueReconciliation(updated,"execution_timeout_unknown");
            handled++;
           }
        }

      return handled;
     }
  };

#endif
