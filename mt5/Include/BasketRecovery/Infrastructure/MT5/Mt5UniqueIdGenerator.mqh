#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_UNIQUE_ID_GENERATOR_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_UNIQUE_ID_GENERATOR_MQH

#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>

class CMt5UniqueIdGenerator : public IUniqueIdGenerator
  {
public:
   virtual          ~CMt5UniqueIdGenerator(void) {}

   virtual string    NewGuid(void)
     {
      return StringFormat("%I64u-%04X-%04X",
                          GetTickCount64(),
                          MathRand() & 0xFFFF,
                          MathRand() & 0xFFFF);
     }
  };

#endif
