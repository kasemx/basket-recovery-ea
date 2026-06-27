#ifndef BASKET_RECOVERY_TESTS_TEST_CLOCK_MQH
#define BASKET_RECOVERY_TESTS_TEST_CLOCK_MQH

#include <BasketRecovery/Application/Ports/IClock.mqh>

class CTestClock : public IClock
  {
private:
   datetime m_now;
   ulong    m_tickCount;

public:
                     CTestClock(void)
     {
      m_now=946684800;
      m_tickCount=0;
     }

   virtual          ~CTestClock(void) {}

   virtual datetime  Now(void) const { return m_now; }
   virtual ulong     TickCount(void) const { return m_tickCount; }

   void              SetNow(const datetime value) { m_now=value; }
   void              AdvanceSeconds(const int seconds) { m_now+=seconds; }
  };

#endif
