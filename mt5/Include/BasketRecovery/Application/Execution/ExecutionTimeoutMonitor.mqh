#ifndef BRE_APP_EXECUTION_TIMEOUT_MONITOR_MQH
#define BRE_APP_EXECUTION_TIMEOUT_MONITOR_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>

class CExecutionTimeoutMonitor
  {
private:
   CPendingExecutionRegistry           *m_registry;
   CExecutionReconciliationScheduler   *m_reconciliationScheduler;
   CPendingExecutionDiagnostics        *m_diagnostics;
   IClock                              *m_clock;

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
                                              CPendingExecutionDiagnostics *diagnostics,
                                              IClock *clock)
     {
      m_registry=registry;
      m_reconciliationScheduler=reconciliationScheduler;
      m_diagnostics=diagnostics;
      m_clock=clock;
     }

   int               ScanDueTimeouts(void)
     {
      if(m_registry==NULL || m_clock==NULL)
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
         if(entry.Status()==BRE_TRADE_EXEC_STATUS_TIMED_OUT ||
            entry.Status()==BRE_TRADE_EXEC_STATUS_RECONCILING)
            continue;

         CPendingExecutionEntry updated;
         if(!m_registry.TryTransition(dueIndices[i],BRE_TRADE_EXEC_STATUS_TIMED_OUT,updated))
            continue;
         entry=updated;
         if(m_diagnostics!=NULL)
            m_diagnostics.OnTimeoutDetected(entry.ExecutionRequestId());

         if(!m_registry.TryTransition(dueIndices[i],BRE_TRADE_EXEC_STATUS_RECONCILING,updated))
            continue;
         entry=updated;
         entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
         m_registry.TryUpdateEntry(dueIndices[i],entry);
         EnqueueReconciliation(entry,"execution_timeout");
         handled++;
        }

      return handled;
     }
  };

#endif
