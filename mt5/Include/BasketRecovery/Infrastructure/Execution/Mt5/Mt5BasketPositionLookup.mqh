#ifndef BRE_INF_MT5_BASKET_POSITION_LOOKUP_MQH
#define BRE_INF_MT5_BASKET_POSITION_LOOKUP_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CMt5BasketPositionLookup
  {
public:
   static bool       TryFindEntry(const CBasketAggregate &basket,
                                  const ulong ticket,
                                  CPositionSnapshotEntry &outEntry)
     {
      if(ticket==0)
         return false;

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
            if(entry.Ticket()==ticket)
              {
               outEntry=entry;
               return true;
              }
           }
        }
      return false;
     }

   static bool       TicketBelongsToBasket(const CBasketAggregate &basket,const ulong ticket)
     {
      CPositionSnapshotEntry entry;
      return TryFindEntry(basket,ticket,entry);
     }
  };

#endif
