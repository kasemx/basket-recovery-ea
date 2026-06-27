#ifndef BASKET_RECOVERY_DOMAIN_POSITION_SNAPSHOT_MQH
#define BASKET_RECOVERY_DOMAIN_POSITION_SNAPSHOT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>

class CPositionSnapshot
  {
private:
   int                      m_version;
   CBasketId                m_basketId;
   datetime                 m_updatedAt;
   int                      m_openCount;
   int                      m_transactionCount;
   CPositionSnapshotEntry   m_entries[];

public:
                     CPositionSnapshot(void)
     {
      m_version=0;
      m_updatedAt=0;
      m_openCount=0;
      m_transactionCount=0;
     }

   int               Version(void) const { return m_version; }
   CBasketId         BasketId(void) const { return m_basketId; }
   datetime          UpdatedAt(void) const { return m_updatedAt; }
   int               OpenCount(void) const { return m_openCount; }
   int               TransactionCount(void) const { return m_transactionCount; }
   int               EntryCount(void) const { return ArraySize(m_entries); }

   bool              EntryAt(const int index,CPositionSnapshotEntry &outEntry) const
     {
      if(index<0 || index>=EntryCount())
         return false;
      outEntry=m_entries[index];
      return true;
     }

   void              SetVersion(const int value) { m_version=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetUpdatedAt(const datetime value) { m_updatedAt=value; }
   void              SetOpenCount(const int value) { m_openCount=value; }
   void              SetTransactionCount(const int value) { m_transactionCount=value; }

   void              IncrementVersion(void) { m_version++; }
   void              IncrementTransactionCount(void) { m_transactionCount++; }

   void              ReplaceEntries(const CPositionSnapshotEntry &entries[],const int count)
     {
      ArrayResize(m_entries,count);
      int openCount=0;
      for(int i=0;i<count;i++)
        {
         m_entries[i]=entries[i];
         if(entries[i].Status()==BRE_POSITION_SNAPSHOT_OPEN)
            openCount++;
        }
      m_openCount=openCount;
     }
  };

#endif
