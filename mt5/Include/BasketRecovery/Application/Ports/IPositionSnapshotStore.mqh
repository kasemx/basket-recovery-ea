#ifndef BASKET_RECOVERY_APPLICATION_IPOSITION_SNAPSHOT_STORE_MQH
#define BASKET_RECOVERY_APPLICATION_IPOSITION_SNAPSHOT_STORE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>

class IPositionSnapshotStore
  {
public:
   virtual          ~IPositionSnapshotStore(void) {}
   virtual CPositionSnapshot* Get(const CBasketId &basketId)=0;
   virtual CVoidResult        CreateEmpty(const CBasketId &basketId)=0;
   virtual CVoidResult        ApplyNormalizedTransaction(const CNormalizedTradeTransaction &transaction)=0;
   virtual CVoidResult        Remove(const CBasketId &basketId)=0;
   virtual int                Count(void) const=0;
   virtual int                TotalTransactionCount(void) const=0;
  };

#endif
