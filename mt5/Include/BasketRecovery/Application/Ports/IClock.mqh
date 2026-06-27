#ifndef BASKET_RECOVERY_APPLICATION_ICLOCK_MQH
#define BASKET_RECOVERY_APPLICATION_ICLOCK_MQH

class IClock
  {
public:
   virtual          ~IClock(void) {}
   virtual datetime  Now(void) const=0;
   virtual ulong     TickCount(void) const=0;
  };

#endif
