#ifndef BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH
#define BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>

class IPendingExecutionFillNotifier
  {
public:
   virtual          ~IPendingExecutionFillNotifier(void) {}
   virtual void      OnBrokerFillConfirmed(const string executionRequestId)=0;
  };

class CPendingExecutionStartupReconciliationService
  {
private:
   static bool       ApplyResolvedStatus(CPendingExecutionLifecycleService *lifecycle,
                                         IPendingExecutionFillNotifier *fillNotifier,
                                         CPendingExecutionEntry &entry,
                                         const ENUM_BRE_TRADE_EXECUTION_STATUS resolved,
                                         const double matchedVolume)
     {
      if(resolved==BRE_TRADE_EXEC_STATUS_FILLED)
        {
         if(!lifecycle.MarkFilled(entry.ExecutionRequestId(),matchedVolume))
            return false;
         if(fillNotifier!=NULL)
            fillNotifier.OnBrokerFillConfirmed(entry.ExecutionRequestId());
         return true;
        }

      if(resolved==BRE_TRADE_EXEC_STATUS_REJECTED)
         return lifecycle.MarkRejected(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_TIMED_OUT)
         return lifecycle.MarkTimedOut(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_CANCELLED)
         return lifecycle.MarkCancelled(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_FAILED)
         return lifecycle.MarkFailed(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_RECONCILED)
         return lifecycle.MarkReconciled(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_UNKNOWN || resolved==BRE_TRADE_EXEC_STATUS_RECONCILING)
         return lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
        {
         ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
         entry.SetFilledVolume(matchedVolume);
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
         lifecycle.OnRegistryEntryUpdated(entry,fromStatus);
         return true;
        }

      return false;
     }

   static bool       ReconcileEntry(CPendingExecutionLifecycleService *lifecycle,
                                    IBrokerPositionReader *positionReader,
                                    IBrokerExecutionHistoryReader *historyReader,
                                    IPendingExecutionFillNotifier *fillNotifier,
                                    CPendingExecutionEntry &entry,
                                    const datetime nowUtc)
     {
      if(lifecycle==NULL)
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS status=entry.Status();
      if(CPendingExecutionQuery::IsTerminalStatus(status))
         return false;

      if(status==BRE_TRADE_EXEC_STATUS_QUEUED || status==BRE_TRADE_EXEC_STATUS_CREATED)
         return false;

      double matchedVolume=0.0;
      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
         CExecutionReconciliationResolver::Resolve(entry,positionReader,matchedVolume,historyReader,nowUtc);

      return ApplyResolvedStatus(lifecycle,fillNotifier,entry,resolved,matchedVolume);
     }

public:
   static int        ReconcilePersistedEntries(IPendingExecutionStore *store,
                                               CPendingExecutionRegistry *registry,
                                               CPendingExecutionLifecycleService *lifecycle,
                                               IBrokerPositionReader *positionReader,
                                               IPendingExecutionFillNotifier *fillNotifier=NULL,
                                               IBrokerExecutionHistoryReader *historyReader=NULL,
                                               const datetime nowUtc=0)
     {
      if(store==NULL || registry==NULL || lifecycle==NULL)
         return 0;

      CPendingExecutionEntry entries[];
      int count=store.RestoreEntries(entries);
      int reconciled=0;
      datetime effectiveNow=(nowUtc>0 ? nowUtc : TimeCurrent());

      for(int i=0;i<count;i++)
        {
         CPendingExecutionReconciliationHydrator::TryHydrate(entries[i],store);
         registry.Upsert(entries[i]);
         if(ReconcileEntry(lifecycle,positionReader,historyReader,fillNotifier,entries[i],effectiveNow))
            reconciled++;
        }

      return reconciled;
     }
  };

#endif
