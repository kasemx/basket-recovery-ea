#ifndef BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH
#define BRE_APP_PENDING_EXECUTION_STARTUP_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationResolver.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
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
   static bool       ReconcileEntry(CPendingExecutionLifecycleService *lifecycle,
                                    IBrokerPositionReader *positionReader,
                                    IPendingExecutionFillNotifier *fillNotifier,
                                    CPendingExecutionEntry &entry)
     {
      if(lifecycle==NULL)
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS status=entry.Status();
      if(CPendingExecutionQuery::IsTerminalStatus(status))
         return false;

      if(status==BRE_TRADE_EXEC_STATUS_QUEUED || status==BRE_TRADE_EXEC_STATUS_CREATED)
         return false;

      if(CPendingExecutionQuery::IsUnknownReconcilingStatus(status))
        {
         double matchedVolume=0.0;
         ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
            CExecutionReconciliationResolver::Resolve(entry,positionReader,matchedVolume);
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
         if(resolved==BRE_TRADE_EXEC_STATUS_UNKNOWN)
            return lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId());
         if(resolved==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
           {
            entry.SetFilledVolume(matchedVolume);
            entry.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
            lifecycle.OnRegistryEntryUpdated(entry,status);
            return true;
           }
         return false;
        }

      double matchedVolume=0.0;
      ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
         CExecutionReconciliationResolver::Resolve(entry,positionReader,matchedVolume);

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

      if(resolved==BRE_TRADE_EXEC_STATUS_UNKNOWN)
         return lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId());

      if(resolved==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
        {
         entry.SetFilledVolume(matchedVolume);
         entry.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
         lifecycle.OnRegistryEntryUpdated(entry,status);
         return true;
        }

      if(CPendingExecutionTransitionRules::BlocksBlindResend(status))
         return lifecycle.MarkUnknownReconciling(entry.ExecutionRequestId());

      return false;
     }

public:
   static int        ReconcilePersistedEntries(IPendingExecutionStore *store,
                                               CPendingExecutionRegistry *registry,
                                               CPendingExecutionLifecycleService *lifecycle,
                                               IBrokerPositionReader *positionReader,
                                               IPendingExecutionFillNotifier *fillNotifier=NULL)
     {
      if(store==NULL || registry==NULL || lifecycle==NULL)
         return 0;

      CPendingExecutionEntry entries[];
      int count=store.RestoreEntries(entries);
      int reconciled=0;

      for(int i=0;i<count;i++)
        {
         registry.Upsert(entries[i]);
         if(ReconcileEntry(lifecycle,positionReader,fillNotifier,entries[i]))
            reconciled++;
        }

      return reconciled;
     }
  };

#endif
