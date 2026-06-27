#ifndef BASKET_RECOVERY_APPLICATION_IBASKET_REPOSITORY_MQH
#define BASKET_RECOVERY_APPLICATION_IBASKET_REPOSITORY_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>

class IBasketRepository
  {
public:
   virtual          ~IBasketRepository(void) {}
   virtual CResult<CBasketAggregate> Load(const CBasketId &basketId) const=0;
   virtual CVoidResult Save(const CBasketAggregate &aggregate)=0;
   virtual bool      Exists(const CBasketId &basketId) const=0;
   virtual CVoidResult Delete(const CBasketId &basketId)=0;
   virtual int       Count(void) const=0;
  };

#endif
