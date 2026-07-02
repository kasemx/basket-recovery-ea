#ifndef BRE_APP_RECOVERY_PENDING_EXECUTION_CHECKER_MQH
#define BRE_APP_RECOVERY_PENDING_EXECUTION_CHECKER_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

#define BRE_PLANNER_PENDING_CHECKER_BUILD_MARKER "S8C_TICKET_SCOPED_PENDING_CHECKER_V2"

class CRecoveryPendingExecutionChecker
  {
public:
   static string     BuildMarker(void) { return BRE_PLANNER_PENDING_CHECKER_BUILD_MARKER; }

   static bool       HasUnresolvedForBasket(const CPendingExecutionRegistry &registry,const CBasketId &basketId)
     {
      return CPendingExecutionLifecycleService::HasUnresolvedPendingExecution(registry,basketId);
     }

   static int        CountUnresolvedForBasket(const CPendingExecutionRegistry &registry,const CBasketId &basketId)
     {
      int count=0;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
            count++;
        }
      return count;
     }

   static bool       HasOtherUnresolvedForBasket(const CPendingExecutionRegistry &registry,
                                                 const CBasketId &basketId,
                                                 const string excludeExecutionRequestId)
     {
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(excludeExecutionRequestId!="" && entry.ExecutionRequestId()==excludeExecutionRequestId)
            continue;
         if(CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
            return true;
        }
      return false;
     }

   static ulong      ResolveEntryPositionTicket(const CPendingExecutionEntry &entry,
                                                IPendingExecutionStore *store=NULL)
     {
      if(entry.BrokerCorrelation().HasPositionTicket())
         return entry.BrokerCorrelation().PositionTicket();
      if(store==NULL || entry.IdempotencyKey()=="")
         return 0;
      CPendingExecutionEntry hydrated=entry;
      if(CPendingExecutionReconciliationHydrator::TryHydrate(hydrated,store) &&
         hydrated.BrokerCorrelation().HasPositionTicket())
         return hydrated.BrokerCorrelation().PositionTicket();
      CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(entry.IdempotencyKey());
      if(envelopeResult.IsFail())
         return 0;
      CBrokerSubmissionEnvelope envelope;
      if(!envelopeResult.TryGetValue(envelope))
         return 0;
      return envelope.Ticket();
     }

   static int        CollectOpenTicketsForBasket(const CBasketId &basketId,
                                                 const CPositionSnapshotEntry &brokerEntries[],
                                                 const int brokerCount,
                                                 ulong &openTickets[])
     {
      ArrayResize(openTickets,0);
      int count=0;
      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].BasketId().Value()!=basketId.Value())
            continue;
         ArrayResize(openTickets,count+1);
         openTickets[count]=brokerEntries[i].Ticket();
         count++;
        }
      return count;
     }

   static bool       TicketMatchesOpenPositions(const ulong ticket,
                                                const ulong &openTickets[],
                                                const int openTicketCount)
     {
      if(ticket==0 || openTicketCount<=0)
         return false;
      for(int i=0;i<openTicketCount;i++)
        {
         if(openTickets[i]==ticket)
            return true;
        }
      return false;
     }

   static bool       EntryBlocksOpenTickets(const CPendingExecutionEntry &entry,
                                            const ulong ticket,
                                            const ulong &openTickets[],
                                            const int openTicketCount)
     {
      if(!CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
         return false;
      if(entry.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
        {
         if(ticket==0)
            return true;
         return TicketMatchesOpenPositions(ticket,openTickets,openTicketCount);
        }
      if(ticket==0)
         return false;
      return TicketMatchesOpenPositions(ticket,openTickets,openTicketCount);
     }

   static bool       EntryBlocksOpenTickets(const CPendingExecutionEntry &entry,
                                            const ulong &openTickets[],
                                            const int openTicketCount,
                                            IPendingExecutionStore *store=NULL)
     {
      ulong ticket=ResolveEntryPositionTicket(entry,store);
      return EntryBlocksOpenTickets(entry,ticket,openTickets,openTicketCount);
     }

   static bool       HasBlockingUnresolvedForOpenTickets(const CPendingExecutionRegistry &registry,
                                                         const CBasketId &basketId,
                                                         const ulong &openTickets[],
                                                         const int openTicketCount,
                                                         IPendingExecutionStore *store=NULL)
     {
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(EntryBlocksOpenTickets(entry,openTickets,openTicketCount,store))
            return true;
        }
      return false;
     }

   static int        CountBlockingUnresolvedForOpenTickets(const CPendingExecutionRegistry &registry,
                                                            const CBasketId &basketId,
                                                            const ulong &openTickets[],
                                                            const int openTicketCount,
                                                            IPendingExecutionStore *store=NULL)
     {
      int count=0;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(EntryBlocksOpenTickets(entry,openTickets,openTicketCount,store))
            count++;
        }
      return count;
     }

   static void       CountTicketScopedUnresolved(const CPendingExecutionRegistry &registry,
                                                  const CBasketId &basketId,
                                                  const ulong &openTickets[],
                                                  const int openTicketCount,
                                                  IPendingExecutionStore *store,
                                                  int &rawUnresolvedOut,
                                                  int &currentTicketUnresolvedOut,
                                                  int &foreignTicketUnresolvedOut)
     {
      rawUnresolvedOut=0;
      currentTicketUnresolvedOut=0;
      foreignTicketUnresolvedOut=0;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(!CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
            continue;
         rawUnresolvedOut++;
         if(EntryBlocksOpenTickets(entry,openTickets,openTicketCount,store))
            currentTicketUnresolvedOut++;
         else
            foreignTicketUnresolvedOut++;
        }
     }
   static bool       HasOtherBlockingUnresolvedForOpenTickets(const CPendingExecutionRegistry &registry,
                                                               const CBasketId &basketId,
                                                               const string excludeExecutionRequestId,
                                                               const ulong &openTickets[],
                                                               const int openTicketCount,
                                                               IPendingExecutionStore *store=NULL)
     {
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(excludeExecutionRequestId!="" && entry.ExecutionRequestId()==excludeExecutionRequestId)
            continue;
         if(EntryBlocksOpenTickets(entry,openTickets,openTicketCount,store))
            return true;
        }
      return false;
     }

   static int        CountForeignBlockingUnresolved(const CPendingExecutionRegistry &registry,
                                                     const CBasketId &basketId,
                                                     const string excludeExecutionRequestId,
                                                     const ulong &openTickets[],
                                                     const int openTicketCount,
                                                     IPendingExecutionStore *store=NULL)
     {
      int count=0;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         if(excludeExecutionRequestId!="" && entry.ExecutionRequestId()==excludeExecutionRequestId)
            continue;
         if(!CPendingExecutionQuery::IsUnresolvedStatus(entry.Status()))
            continue;
         if(EntryBlocksOpenTickets(entry,openTickets,openTicketCount,store))
            continue;
         count++;
        }
      return count;
     }
  };

#endif
