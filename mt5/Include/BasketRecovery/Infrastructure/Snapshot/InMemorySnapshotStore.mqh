#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_SNAPSHOT_STORE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_SNAPSHOT_STORE_MQH

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemorySnapshotStore : public IPositionSnapshotStore
  {
private:
   CPositionSnapshot *m_snapshots[];
   string             m_basketKeys[];
   int                m_count;
   int                m_totalTransactionCount;
   IClock            *m_clock;

   int FindIndex(const CBasketId &basketId) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_basketKeys[i]==basketId.Value())
            return i;
        }
      return -1;
     }

   datetime CurrentTimestamp(void) const
     {
      if(m_clock!=NULL)
         return m_clock.Now();
      return 0;
     }

   CVoidResult EnsureSnapshot(const CBasketId &basketId)
     {
      if(basketId.IsEmpty())
         return CVoidResult::Ok();

      if(FindIndex(basketId)>=0)
         return CVoidResult::Ok();

      CPositionSnapshot *snapshot=new CPositionSnapshot();
      snapshot.SetBasketId(basketId);
      snapshot.SetUpdatedAt(CurrentTimestamp());

      ArrayResize(m_snapshots,m_count+1);
      ArrayResize(m_basketKeys,m_count+1);
      m_snapshots[m_count]=snapshot;
      m_basketKeys[m_count]=basketId.Value();
      m_count++;
      return CVoidResult::Ok();
     }

public:
                     CInMemorySnapshotStore(IClock *clock)
     {
      m_count=0;
      m_totalTransactionCount=0;
      m_clock=clock;
      ArrayResize(m_snapshots,0);
      ArrayResize(m_basketKeys,0);
     }

   virtual          ~CInMemorySnapshotStore(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_snapshots[i]!=NULL)
           {
            delete m_snapshots[i];
            m_snapshots[i]=NULL;
           }
        }
     }

   virtual CPositionSnapshot* Get(const CBasketId &basketId)
     {
      int index=FindIndex(basketId);
      if(index<0)
         return NULL;
      return m_snapshots[index];
     }

   virtual CVoidResult CreateEmpty(const CBasketId &basketId)
     {
      if(basketId.IsEmpty())
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Basket id is empty");

      if(FindIndex(basketId)>=0)
         return CVoidResult::Ok();

      return EnsureSnapshot(basketId);
     }

   virtual CVoidResult ApplyNormalizedTransaction(const CNormalizedTradeTransaction &transaction)
     {
      m_totalTransactionCount++;

      CBasketId basketId=transaction.BasketId();
      if(basketId.IsEmpty())
         basketId=CBasketId("__unassigned__");

      EnsureSnapshot(basketId);

      int index=FindIndex(basketId);
      if(index<0)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Snapshot index not found");

      m_snapshots[index].IncrementVersion();
      m_snapshots[index].IncrementTransactionCount();
      m_snapshots[index].SetUpdatedAt(transaction.OccurredAtUtc());
      return CVoidResult::Ok();
     }

   virtual CVoidResult Remove(const CBasketId &basketId)
     {
      int index=FindIndex(basketId);
      if(index<0)
         return CVoidResult::Ok();

      if(m_snapshots[index]!=NULL)
        {
         delete m_snapshots[index];
         m_snapshots[index]=NULL;
        }

      for(int i=index;i<m_count-1;i++)
        {
         m_snapshots[i]=m_snapshots[i+1];
         m_basketKeys[i]=m_basketKeys[i+1];
        }

      m_count--;
      ArrayResize(m_snapshots,m_count);
      ArrayResize(m_basketKeys,m_count);
      return CVoidResult::Ok();
     }

   virtual int Count(void) const
     {
      return m_count;
     }

   virtual int TotalTransactionCount(void) const
     {
      return m_totalTransactionCount;
     }
  };

#endif
