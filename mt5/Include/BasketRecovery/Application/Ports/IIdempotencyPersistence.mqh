#ifndef BASKET_RECOVERY_APPLICATION_IIDEMPOTENCY_PERSISTENCE_MQH
#define BASKET_RECOVERY_APPLICATION_IIDEMPOTENCY_PERSISTENCE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>

class IIdempotencyPersistence
  {
public:
   virtual          ~IIdempotencyPersistence(void) {}
   virtual CVoidResult SaveProcessedKey(const string &idempotencyKey)=0;
   virtual CVoidResult LoadProcessedKeys(string &keys[]) const=0;
   virtual CVoidResult ClearAll(void)=0;
  };

#endif
