#ifndef BRE_INF_BASKET_SNAPSHOT_LIVE_REFRESH_MQH
#define BRE_INF_BASKET_SNAPSHOT_LIVE_REFRESH_MQH

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketSnapshotLiveRefresh
  {
public:
   static CVoidResult RefreshBasket(IPositionSnapshotStore *snapshotStore,const CBasketId &basketId)
     {
      if(snapshotStore==NULL || basketId.IsEmpty())
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Snapshot store is required");

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return CVoidResult::Ok();

      int entryCount=snapshot.EntryCount();
      if(entryCount<=0)
         return CVoidResult::Ok();

      CPositionSnapshotEntry entries[];
      ArrayResize(entries,entryCount);
      bool anyMissing=false;
      for(int i=0;i<entryCount;i++)
        {
         if(!snapshot.EntryAt(i,entries[i]))
            continue;

         ulong ticket=entries[i].Ticket();
         if(ticket==0)
            continue;

         if(!PositionSelectByTicket(ticket))
           {
            if(entries[i].Status()==BRE_POSITION_SNAPSHOT_OPEN)
               anyMissing=true;
            continue;
           }

         entries[i]=CPositionSnapshotEntry::Create(entries[i].BasketId(),
                                                 ticket,
                                                 PositionGetInteger(POSITION_MAGIC),
                                                 PositionGetString(POSITION_SYMBOL),
                                                 entries[i].Direction(),
                                                 entries[i].Role(),
                                                 entries[i].RecoveryStepIndex(),
                                                 PositionGetDouble(POSITION_PRICE_OPEN),
                                                 PositionGetDouble(POSITION_PRICE_CURRENT),
                                                 PositionGetDouble(POSITION_SL),
                                                 PositionGetDouble(POSITION_TP),
                                                 PositionGetDouble(POSITION_VOLUME),
                                                 PositionGetDouble(POSITION_PROFIT),
                                                 PositionGetDouble(POSITION_COMMISSION),
                                                 PositionGetDouble(POSITION_SWAP),
                                                 (datetime)PositionGetInteger(POSITION_TIME),
                                                 entries[i].Status(),
                                                 entries[i].CorrelationId());
        }

      if(anyMissing)
         return CVoidResult::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Live basket position read failed");

      return snapshotStore.ReplaceEntries(basketId,entries,entryCount);
     }
  };

#endif
