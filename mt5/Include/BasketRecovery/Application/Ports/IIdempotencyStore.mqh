#ifndef BASKET_RECOVERY_APPLICATION_IIDEMPOTENCY_STORE_MQH
#define BASKET_RECOVERY_APPLICATION_IIDEMPOTENCY_STORE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>

class IIdempotencyStore
  {
public:
   virtual          ~IIdempotencyStore(void) {}
   virtual bool      IsProcessed(const string &idempotencyKey) const=0;
   virtual CVoidResult MarkProcessed(const string &idempotencyKey)=0;
   virtual CVoidResult Clear(void)=0;
   virtual int       Count(void) const=0;
  };

#endif
