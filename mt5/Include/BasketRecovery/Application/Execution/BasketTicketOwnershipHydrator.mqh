#ifndef BRE_APP_BASKET_TICKET_OWNERSHIP_HYDRATOR_MQH
#define BRE_APP_BASKET_TICKET_OWNERSHIP_HYDRATOR_MQH

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5BasketPositionLookup.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5LivePositionTicketAuthority.mqh>

struct SBasketTicketOwnershipDiagnostics
  {
   string                          basket_id;
   ulong                           candidate_ticket;
   ulong                           live_ticket;
   int                             basket_position_count;
   string                          basket_position_ticket_list;
   string                          basket_position_state_list;
   string                          ownership_result;
   string                          ownership_failure_reason;
   bool                            restore_registry_basket_found;
   bool                            restore_registry_candidate_found;
   string                          reconcile_basket_id;
   string                          reconcile_position_ticket_list;

   void              Reset(void)
     {
      basket_id="";
      candidate_ticket=0;
      live_ticket=0;
      basket_position_count=0;
      basket_position_ticket_list="";
      basket_position_state_list="";
      ownership_result="";
      ownership_failure_reason="";
      restore_registry_basket_found=false;
      restore_registry_candidate_found=false;
      reconcile_basket_id="";
      reconcile_position_ticket_list="";
     }
  };

class CBasketTicketOwnershipHydrator
  {
private:
   static string     PositionStateLabel(const ENUM_BRE_POSITION_SNAPSHOT_STATUS status)
     {
      if(status==BRE_POSITION_SNAPSHOT_OPEN)
         return "OPEN";
      if(status==BRE_POSITION_SNAPSHOT_CLOSED)
         return "CLOSED";
      return "UNKNOWN";
     }

   static void       FillBasketPositionDiagnostics(const CBasketAggregate &basket,
                                                 SBasketTicketOwnershipDiagnostics &diagnostics)
     {
      diagnostics.basket_position_count=0;
      diagnostics.basket_position_ticket_list="";
      diagnostics.basket_position_state_list="";

      for(int i=0;i<basket.PositionSnapshotCount();i++)
        {
         CPositionSnapshot *snapshot=basket.PositionSnapshotAt(i);
         if(snapshot==NULL)
            continue;
         for(int j=0;j<snapshot.EntryCount();j++)
           {
            CPositionSnapshotEntry entry;
            if(!snapshot.EntryAt(j,entry))
               continue;
            diagnostics.basket_position_count++;
            if(diagnostics.basket_position_ticket_list!="")
               diagnostics.basket_position_ticket_list+=",";
            diagnostics.basket_position_ticket_list+=IntegerToString((long)entry.Ticket());
            if(diagnostics.basket_position_state_list!="")
               diagnostics.basket_position_state_list+=",";
            diagnostics.basket_position_state_list+=PositionStateLabel(entry.Status());
           }
        }
     }

   static bool       TryCopyOpenEntriesFromSnapshotStore(const CBasketId &basketId,
                                                       IPositionSnapshotStore *snapshotStore,
                                                       CPositionSnapshotEntry &outEntries[],
                                                       int &outCount)
     {
      outCount=0;
      ArrayResize(outEntries,0);
      if(snapshotStore==NULL)
         return false;

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return false;

      for(int i=0;i<snapshot.EntryCount();i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         ArrayResize(outEntries,outCount+1);
         outEntries[outCount]=entry;
         outCount++;
        }
      return outCount>0;
     }

   static bool       TryFindOpenEntryInSnapshotStore(const CBasketId &basketId,
                                                     const ulong ticket,
                                                     IPositionSnapshotStore *snapshotStore,
                                                     CPositionSnapshotEntry &outEntry)
     {
      if(snapshotStore==NULL || ticket==0)
         return false;

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return false;

      for(int i=0;i<snapshot.EntryCount();i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(entry.Ticket()!=ticket)
            continue;
         outEntry=entry;
         return true;
        }
      return false;
     }

   static bool       TryBuildAuthoritativeEntryFromLive(const CBasketId &basketId,
                                                        const ulong ticket,
                                                        const string expectedSymbol,
                                                        CPositionSnapshotEntry &outEntry,
                                                        string &failureReason)
     {
      failureReason="";
      string liveSymbol="";
      long livePositionType=0;
      ENUM_BRE_TRADE_DIRECTION liveDirection=BRE_DIRECTION_NONE;
      double liveVolume=0.0;
      double liveEntryPrice=0.0;
      double liveFloatingProfitUsd=0.0;
      datetime liveOpenTimeUtc=0;
      string liveLookupFailure="";
      if(!CMt5LivePositionTicketAuthority::TryResolvePlanningFieldsByTicket(ticket,
                                                                            liveSymbol,
                                                                            livePositionType,
                                                                            liveDirection,
                                                                            liveVolume,
                                                                            liveEntryPrice,
                                                                            liveFloatingProfitUsd,
                                                                            liveOpenTimeUtc,
                                                                            liveLookupFailure))
        {
         failureReason=liveLookupFailure;
         return false;
        }

      if(liveSymbol!=expectedSymbol)
        {
         failureReason="Live position symbol mismatch";
         return false;
        }

      if(!PositionSelectByTicket(ticket))
        {
         failureReason="Live position not found for ticket";
         return false;
        }

      outEntry=CPositionSnapshotEntry::Create(basketId,
                                              ticket,
                                              (long)PositionGetInteger(POSITION_MAGIC),
                                              liveSymbol,
                                              liveDirection,
                                              BRE_TRADE_ROLE_INITIAL,
                                              0,
                                              liveEntryPrice,
                                              PositionGetDouble(POSITION_PRICE_CURRENT),
                                              PositionGetDouble(POSITION_SL),
                                              PositionGetDouble(POSITION_TP),
                                              liveVolume,
                                              liveFloatingProfitUsd,
                                              PositionGetDouble(POSITION_COMMISSION),
                                              PositionGetDouble(POSITION_SWAP),
                                              liveOpenTimeUtc,
                                              BRE_POSITION_SNAPSHOT_OPEN,
                                              "");
      return true;
     }

   static void       UpsertOpenEntry(CPositionSnapshotEntry &entries[],
                                     int &entryCount,
                                     const CPositionSnapshotEntry &entry)
     {
      for(int i=0;i<entryCount;i++)
        {
         if(entries[i].Ticket()==entry.Ticket())
           {
            entries[i]=entry;
            return;
           }
        }
      ArrayResize(entries,entryCount+1);
      entries[entryCount]=entry;
      entryCount++;
     }

   static void       FillReconcileDiagnostics(const CBasketId &basketId,
                                              IPositionSnapshotStore *snapshotStore,
                                              SBasketTicketOwnershipDiagnostics &diagnostics)
     {
      diagnostics.reconcile_basket_id=basketId.Value();
      diagnostics.reconcile_position_ticket_list="";
      if(snapshotStore==NULL)
         return;

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return;

      for(int i=0;i<snapshot.EntryCount();i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         if(diagnostics.reconcile_position_ticket_list!="")
            diagnostics.reconcile_position_ticket_list+=",";
         diagnostics.reconcile_position_ticket_list+=IntegerToString((long)entry.Ticket());
        }
     }

public:
   static bool       SyncMembershipFromSnapshotStore(CBasketAggregate &basket,
                                                     IPositionSnapshotStore *snapshotStore)
     {
      CPositionSnapshotEntry entries[];
      int entryCount=0;
      if(!TryCopyOpenEntriesFromSnapshotStore(basket.Id(),snapshotStore,entries,entryCount))
         return false;
      basket.ReplaceOpenPositionMembership(entries,entryCount);
      return true;
     }

   static bool       TryEnsureTicketMembership(CBasketAggregate &basket,
                                               const ulong ticket,
                                               IPositionSnapshotStore *snapshotStore,
                                               const string expectedSymbol,
                                               SBasketTicketOwnershipDiagnostics &diagnostics)
     {
      diagnostics.Reset();
      diagnostics.basket_id=basket.Id().Value();
      diagnostics.candidate_ticket=ticket;

      string liveLookupFailure="";
      string liveSymbol="";
      long livePositionType=0;
      ENUM_BRE_TRADE_DIRECTION liveDirection=BRE_DIRECTION_NONE;
      double liveVolume=0.0;
      ulong liveTicket=0;
      if(CMt5LivePositionTicketAuthority::TryResolveByTicket(ticket,
                                                                      liveSymbol,
                                                                      livePositionType,
                                                                      liveDirection,
                                                                      liveVolume,
                                                                      liveLookupFailure))
         liveTicket=ticket;
      else if(PositionSelectByTicket(ticket))
         liveTicket=ticket;
      diagnostics.live_ticket=liveTicket;

      FillReconcileDiagnostics(basket.Id(),snapshotStore,diagnostics);
      FillBasketPositionDiagnostics(basket,diagnostics);

      if(CMt5BasketPositionLookup::TicketBelongsToBasket(basket,ticket))
        {
         diagnostics.ownership_result="OK";
         return true;
        }

      CPositionSnapshotEntry openEntries[];
      int openEntryCount=0;
      if(TryCopyOpenEntriesFromSnapshotStore(basket.Id(),snapshotStore,openEntries,openEntryCount))
        {
         basket.ReplaceOpenPositionMembership(openEntries,openEntryCount);
         FillBasketPositionDiagnostics(basket,diagnostics);
         if(CMt5BasketPositionLookup::TicketBelongsToBasket(basket,ticket))
           {
            diagnostics.ownership_result="OK";
            return true;
           }
        }

      diagnostics.ownership_result="FAIL";
      diagnostics.ownership_failure_reason="Ticket not present in basket aggregate membership";
      return false;
     }

   static bool       TryEnsureCandidateTicketMembership(CBasketAggregate &basket,
                                                        const CManualProfitCloseCandidateEntry &entry,
                                                        IPositionSnapshotStore *snapshotStore,
                                                        const bool restoreRegistryBasketFound,
                                                        const bool restoreRegistryCandidateFound,
                                                        SBasketTicketOwnershipDiagnostics &diagnostics)
     {
      diagnostics.Reset();
      diagnostics.basket_id=basket.Id().Value();
      diagnostics.candidate_ticket=entry.PositionTicket();
      diagnostics.restore_registry_basket_found=restoreRegistryBasketFound;
      diagnostics.restore_registry_candidate_found=restoreRegistryCandidateFound;

      string liveLookupFailure="";
      string liveSymbol="";
      long livePositionType=0;
      ENUM_BRE_TRADE_DIRECTION liveDirection=BRE_DIRECTION_NONE;
      double liveVolume=0.0;
      bool hasLive=CMt5LivePositionTicketAuthority::TryResolveByTicket(entry.PositionTicket(),
                                                                      liveSymbol,
                                                                      livePositionType,
                                                                      liveDirection,
                                                                      liveVolume,
                                                                      liveLookupFailure);
      diagnostics.live_ticket=hasLive ? entry.PositionTicket() : 0;

      FillReconcileDiagnostics(basket.Id(),snapshotStore,diagnostics);
      FillBasketPositionDiagnostics(basket,diagnostics);

      if(entry.BasketId().Value()!=basket.Id().Value())
        {
         diagnostics.ownership_result="FAIL";
         diagnostics.ownership_failure_reason="Candidate basket mismatch";
         return false;
        }

      if(CMt5BasketPositionLookup::TicketBelongsToBasket(basket,entry.PositionTicket()))
        {
         diagnostics.ownership_result="OK";
         return true;
        }

      CPositionSnapshotEntry openEntries[];
      int openEntryCount=0;
      TryCopyOpenEntriesFromSnapshotStore(basket.Id(),snapshotStore,openEntries,openEntryCount);

      CPositionSnapshotEntry snapshotEntry;
      if(TryFindOpenEntryInSnapshotStore(basket.Id(),entry.PositionTicket(),snapshotStore,snapshotEntry))
         UpsertOpenEntry(openEntries,openEntryCount,snapshotEntry);
      else if(hasLive && entry.PositionTicket()>0 && liveSymbol==entry.Symbol())
        {
         CPositionSnapshotEntry liveEntry;
         string liveBuildFailure="";
         if(TryBuildAuthoritativeEntryFromLive(basket.Id(),entry.PositionTicket(),entry.Symbol(),liveEntry,liveBuildFailure))
           {
            UpsertOpenEntry(openEntries,openEntryCount,liveEntry);
            if(snapshotStore!=NULL)
              {
               if(snapshotStore.Get(basket.Id())==NULL)
                  snapshotStore.CreateEmpty(basket.Id());
               snapshotStore.ReplaceEntries(basket.Id(),openEntries,openEntryCount);
               FillReconcileDiagnostics(basket.Id(),snapshotStore,diagnostics);
              }
           }
         else
           {
            diagnostics.ownership_result="FAIL";
            diagnostics.ownership_failure_reason=liveBuildFailure;
            return false;
           }
        }

      if(openEntryCount>0)
        {
         basket.ReplaceOpenPositionMembership(openEntries,openEntryCount);
         FillBasketPositionDiagnostics(basket,diagnostics);
        }

      if(CMt5BasketPositionLookup::TicketBelongsToBasket(basket,entry.PositionTicket()))
        {
         diagnostics.ownership_result="OK";
         return true;
        }

      diagnostics.ownership_result="FAIL";
      if(diagnostics.ownership_failure_reason=="")
         diagnostics.ownership_failure_reason="Ticket does not belong to basket";
      return false;
     }
  };

#endif
