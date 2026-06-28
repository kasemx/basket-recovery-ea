#ifndef BRE_APP_PENDING_EXECUTION_LIFECYCLE_SERVICE_MQH
#define BRE_APP_PENDING_EXECUTION_LIFECYCLE_SERVICE_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionReconciliationTransitionGate.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

class CPendingExecutionLifecycleService
  {
private:
   CPendingExecutionRegistry            *m_registry;
   IPendingExecutionStore               *m_store;
   CInMemoryPendingExecutionEventBuffer *m_eventBuffer;
   IClock                               *m_clock;

   void              EmitTerminalEvent(const string executionRequestId,
                                       const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      if(m_eventBuffer==NULL)
         return;
      CPendingExecutionEvent event;
      event.SetExecutionRequestId(executionRequestId);
      event.SetResultCode(BRE_TRADE_TX_RESULT_ACCEPTED);
      event.SetDetail("terminal:"+TradeExecutionStatusLabel(status));
      if(m_clock!=NULL)
         event.SetOccurredAtUtc(m_clock.Now());
      m_eventBuffer.Append(event);
     }

   void              MaybeEmitTerminalEvent(const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                            const CPendingExecutionEntry &entry)
     {
      if(CPendingExecutionQuery::IsTerminalStatus(fromStatus))
         return;
      if(!CPendingExecutionQuery::IsTerminalStatus(entry.Status()))
         return;
      EmitTerminalEvent(entry.ExecutionRequestId(),entry.Status());
     }

   CVoidResult       PersistEntry(const CPendingExecutionEntry &entry)
     {
      if(m_store==NULL)
         return CVoidResult::Ok();
      return m_store.SaveEntryState(entry);
     }

   bool              ApplyStatus(const string executionRequestId,
                                 const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                 const double filledVolume,
                                 const bool reconciliationPath,
                                 CPendingExecutionEntry &updatedEntry)
     {
      if(m_registry==NULL)
         return false;

      int index=-1;
      for(int i=0;i<m_registry.Count();i++)
        {
         CPendingExecutionEntry candidate;
         if(m_registry.TryGetEntry(i,candidate) && candidate.ExecutionRequestId()==executionRequestId)
           {
            index=i;
            break;
           }
        }
      if(index<0)
         return false;

      CPendingExecutionEntry entry;
      if(!m_registry.TryGetEntry(index,entry))
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
      if(fromStatus==toStatus)
        {
         updatedEntry=entry;
         return true;
        }
      if(CPendingExecutionQuery::IsTerminalStatus(fromStatus))
         return false;

      if(m_registry.TryTransition(index,toStatus,updatedEntry))
        {
         if(filledVolume>0.0)
           {
            updatedEntry.SetFilledVolume(filledVolume);
            m_registry.TryUpdateEntry(index,updatedEntry);
           }
         return true;
        }

      if(!reconciliationPath)
         return false;
      if(!CPendingExecutionReconciliationTransitionGate::CanResolveFromBrokerRead(fromStatus,toStatus))
         return false;

      entry.SetStatus(toStatus);
      if(filledVolume>0.0)
         entry.SetFilledVolume(filledVolume);
      m_registry.TryUpdateEntry(index,entry);
      updatedEntry=entry;
      return true;
     }

   bool              CommitTerminalTransition(const string executionRequestId,
                                              const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                              const double filledVolume,
                                              const bool reconciliationPath)
     {
      CPendingExecutionEntry entry;
      CPendingExecutionEntry before;
      if(m_registry!=NULL && m_registry.TryGetByExecutionRequestId(executionRequestId,before))
         entry=before;
      else
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
      if(!ApplyStatus(executionRequestId,toStatus,filledVolume,reconciliationPath,entry))
         return false;

      PersistEntry(entry);
      MaybeEmitTerminalEvent(fromStatus,entry);
      return true;
     }

public:
                     CPendingExecutionLifecycleService(CPendingExecutionRegistry *registry,
                                                       IPendingExecutionStore *store,
                                                       CInMemoryPendingExecutionEventBuffer *eventBuffer,
                                                       IClock *clock)
     {
      m_registry=registry;
      m_store=store;
      m_eventBuffer=eventBuffer;
      m_clock=clock;
     }

   static bool       HasUnresolvedPendingExecution(const CPendingExecutionRegistry &registry,
                                                   const CBasketId &basketId)
     {
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
            return true;
        }
      return false;
     }

   static int        GetTerminalExecutionHistory(const CPendingExecutionRegistry &registry,
                                                 const CBasketId &basketId,
                                                 CPendingExecutionEntry &entries[])
     {
      ArrayResize(entries,0);
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(!CPendingExecutionQuery::IsTerminalStatus(entry.Status()))
            continue;
         int size=ArraySize(entries);
         ArrayResize(entries,size+1);
         entries[size]=entry;
        }
      return ArraySize(entries);
     }

   bool              MarkFilled(const string executionRequestId,const double filledVolume=0.0)
     {
      return CommitTerminalTransition(executionRequestId,BRE_TRADE_EXEC_STATUS_FILLED,filledVolume,true);
     }

   bool              MarkRejected(const string executionRequestId)
     {
      return CommitTerminalTransition(executionRequestId,BRE_TRADE_EXEC_STATUS_REJECTED,0.0,false);
     }

   bool              MarkTimedOut(const string executionRequestId)
     {
      return CommitTerminalTransition(executionRequestId,BRE_TRADE_EXEC_STATUS_TIMED_OUT,0.0,false);
     }

   bool              MarkUnknownReconciling(const string executionRequestId)
     {
      CPendingExecutionEntry entry;
      if(m_registry==NULL || !m_registry.TryGetByExecutionRequestId(executionRequestId,entry))
         return false;
      if(CPendingExecutionQuery::IsUnknownReconcilingStatus(entry.Status()))
        {
         PersistEntry(entry);
         return true;
        }
      if(CPendingExecutionQuery::IsTerminalStatus(entry.Status()))
         return false;

      ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus=entry.Status();
      if(!ApplyStatus(executionRequestId,BRE_TRADE_EXEC_STATUS_RECONCILING,0.0,true,entry))
         return false;
      entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
      int index=-1;
      for(int i=0;i<m_registry.Count();i++)
        {
         CPendingExecutionEntry candidate;
         if(m_registry.TryGetEntry(i,candidate) && candidate.ExecutionRequestId()==executionRequestId)
           {
            index=i;
            break;
           }
        }
      if(index>=0)
         m_registry.TryUpdateEntry(index,entry);
      PersistEntry(entry);
      return fromStatus!=entry.Status() || CPendingExecutionQuery::IsUnknownReconcilingStatus(entry.Status());
     }

   void              OnTransactionTransitionAccepted(const CPendingExecutionEntry &entry,
                                                     const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus)
     {
      PersistEntry(entry);
      MaybeEmitTerminalEvent(fromStatus,entry);
     }

   void              OnRegistryEntryUpdated(const CPendingExecutionEntry &entry,
                                            const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus)
     {
      OnTransactionTransitionAccepted(entry,fromStatus);
     }
  };

#endif
