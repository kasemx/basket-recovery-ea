#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_CLOCK_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_CLOCK_MQH

#include <BasketRecovery/Application/Ports/IClock.mqh>

class CMt5Clock : public IClock
  {
public:
   virtual          ~CMt5Clock(void) {}

   virtual datetime  Now(void) const
     {
      return TimeCurrent();
     }

   virtual ulong     TickCount(void) const
     {
      return GetTickCount64();
     }
  };

#endif
