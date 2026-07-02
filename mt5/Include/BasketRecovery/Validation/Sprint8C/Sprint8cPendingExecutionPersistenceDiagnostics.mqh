#ifndef BRE_S8C_PENDING_EXEC_PERSIST_DIAG_MQH
#define BRE_S8C_PENDING_EXEC_PERSIST_DIAG_MQH

#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>

class CSprint8cPendingExecutionPersistenceDiagnostics
  {
public:
   static string     DefaultStoreRelativePath(void) { return "BasketRecovery/pending_executions.dat"; }

   static ulong      ResolveRecordTicket(const CPendingExecutionEntry &entry,IPendingExecutionStore *store)
     {
      return CRecoveryPendingExecutionChecker::ResolveEntryPositionTicket(entry,store);
     }

   static void       PrintRecordRow(const CPendingExecutionEntry &entry,
                                    IPendingExecutionStore *store,
                                    const ulong currentTicket,
                                    const ulong &openTickets[],
                                    const int openTicketCount,
                                    const string source,
                                    const string persistencePath)
     {
      ulong ticket=ResolveRecordTicket(entry,store);
      bool isTerminal=CPendingExecutionQuery::IsTerminalStatus(entry.Status());
      bool isUnresolved=CPendingExecutionQuery::IsUnresolvedStatus(entry.Status());
      bool blocksCurrentTicket=isUnresolved &&
                               CRecoveryPendingExecutionChecker::EntryBlocksOpenTickets(entry,
                                                                                      openTickets,
                                                                                      openTicketCount,
                                                                                      store);
      bool blocksResume=blocksCurrentTicket;
      bool blocksPlanner=blocksCurrentTicket;
      datetime updatedAt=entry.PreparedAtUtc();
      if(entry.SubmittedAtUtc()>updatedAt)
         updatedAt=entry.SubmittedAtUtc();
      if(updatedAt<=0)
         updatedAt=entry.CreatedAtUtc();
      Print("pending_record_id=",entry.ExecutionRequestId());
      Print("pending_record_execution_request_id=",entry.ExecutionRequestId());
      Print("pending_record_basket_id=",entry.BasketId().Value());
      Print("pending_record_ticket=",ticket>0 ? IntegerToString((long)ticket) : "NONE");
      Print("pending_record_status=",TradeExecutionStatusLabel(entry.Status()));
      Print("pending_record_is_current_ticket=",(currentTicket>0 && ticket==currentTicket)?"true":"false");
      Print("pending_record_blocks_current_ticket=",blocksCurrentTicket?"true":"false");
      Print("pending_record_blocks_basket_resume=",blocksResume?"true":"false");
      Print("pending_record_blocks_planner=",blocksPlanner?"true":"false");
      Print("pending_record_source_path=",persistencePath);
      Print("pending_record_source=",source);
      Print("pending_record_requested_volume=",DoubleToString(entry.RequestedVolume(),8));
      Print("pending_record_created_at=",IntegerToString((long)entry.CreatedAtUtc()));
      Print("pending_record_updated_at=",IntegerToString((long)updatedAt));
      Print("pending_record_is_terminal=",isTerminal?"true":"false");
      Print("pending_record_is_unresolved=",isUnresolved?"true":"false");
     }

   static int        PrintRegistryRecordsForBasket(const CPendingExecutionRegistry &registry,
                                                    const CBasketId &basketId,
                                                    const ulong currentTicket,
                                                    const ulong &openTickets[],
                                                    const int openTicketCount,
                                                    IPendingExecutionStore *store,
                                                    const string source,
                                                    const string persistencePath)
     {
      int printed=0;
      for(int i=0;i<registry.Count();i++)
        {
         CPendingExecutionEntry entry;
         if(!registry.TryGetEntry(i,entry))
            continue;
         if(entry.BasketId().Value()!=basketId.Value())
            continue;
         CPendingExecutionEntry hydrated=entry;
         if(store!=NULL)
            CPendingExecutionReconciliationHydrator::TryHydrate(hydrated,store);
         PrintRecordRow(hydrated,store,currentTicket,openTickets,openTicketCount,source,persistencePath);
         printed++;
        }
      return printed;
     }

   static void       PrintRegisterRuntimeSummary(const CPendingExecutionRegistry &registry,
                                                   const CBasketId &basketId,
                                                   const ulong currentTicket,
                                                   const ulong &openTickets[],
                                                   const int openTicketCount,
                                                   IPendingExecutionStore *store,
                                                   const string registerBuildMarker,
                                                   const string pendingStoreBuildMarker,
                                                   const string plannerCheckerBuildMarker)
     {
      int rawUnresolved=0;
      int currentTicketUnresolved=0;
      int foreignTicketUnresolved=0;
      CRecoveryPendingExecutionChecker::CountTicketScopedUnresolved(registry,
                                                                    basketId,
                                                                    openTickets,
                                                                    openTicketCount,
                                                                    store,
                                                                    rawUnresolved,
                                                                    currentTicketUnresolved,
                                                                    foreignTicketUnresolved);
      Print("register_runtime_build_marker=",registerBuildMarker);
      Print("register_pending_store_build_marker=",pendingStoreBuildMarker);
      Print("planner_pending_checker_build_marker=",plannerCheckerBuildMarker);
      Print("current_ticket=",IntegerToString((long)currentTicket));
      Print("ticket_scoped_pending_filter_applied=true");
      Print("raw_unresolved_count=",IntegerToString(rawUnresolved));
      Print("current_ticket_unresolved_count=",IntegerToString(currentTicketUnresolved));
      Print("foreign_ticket_unresolved_count=",IntegerToString(foreignTicketUnresolved));
     }

   static int        CountUnresolvedForBasketOnDisk(const CBasketId &basketId,
                                                    CFilePendingExecutionStore &store)
     {
      CPendingExecutionEntry entries[];
      int count=store.RestoreEntries(entries);
      int unresolved=0;
      for(int i=0;i<count;i++)
        {
         if(entries[i].BasketId().Value()!=basketId.Value())
            continue;
         if(CPendingExecutionQuery::IsUnresolvedStatus(entries[i].Status()))
            unresolved++;
        }
      return unresolved;
     }
  };

#endif
