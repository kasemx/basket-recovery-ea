#ifndef BASKET_RECOVERY_DOMAIN_POSITION_SNAPSHOT_MQH
#define BASKET_RECOVERY_DOMAIN_POSITION_SNAPSHOT_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionEntry.mqh>

class CPositionSnapshot
  {
private:
   int        m_version;
   CBasketId  m_basketId;
   datetime   m_updatedAt;
   int        m_openCount;
   int        m_transactionCount;

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

   void              SetVersion(const int value) { m_version=value; }
   void              SetBasketId(const CBasketId &value) { m_basketId=value; }
   void              SetUpdatedAt(const datetime value) { m_updatedAt=value; }
   void              SetOpenCount(const int value) { m_openCount=value; }
   void              SetTransactionCount(const int value) { m_transactionCount=value; }

   void              IncrementVersion(void) { m_version++; }
   void              IncrementTransactionCount(void) { m_transactionCount++; }
  };

#endif
