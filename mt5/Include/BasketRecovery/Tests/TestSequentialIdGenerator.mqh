#ifndef BASKET_RECOVERY_TESTS_TEST_SEQUENTIAL_ID_GENERATOR_MQH
#define BASKET_RECOVERY_TESTS_TEST_SEQUENTIAL_ID_GENERATOR_MQH

#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>

class CTestSequentialIdGenerator : public IUniqueIdGenerator
  {
private:
   long m_counter;

public:
                     CTestSequentialIdGenerator(void) { m_counter=0; }

   virtual          ~CTestSequentialIdGenerator(void) {}

   virtual string    NewGuid(void)
     {
      m_counter++;
      return StringFormat("test-id-%I64d",m_counter);
     }

   void              Reset(void) { m_counter=0; }
  };

#endif
