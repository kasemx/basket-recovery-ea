#ifndef BRE_INF_IN_MEMORY_ACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH
#define BRE_INF_IN_MEMORY_ACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH

#include <BasketRecovery/Application/Execution/Ports/IAccountExecutionEligibilityProvider.mqh>

class CInMemoryAccountExecutionEligibilityProvider : public IAccountExecutionEligibilityProvider
  {
private:
   CAccountExecutionEligibilitySnapshot m_snapshot;

public:
   void              SetSnapshot(const CAccountExecutionEligibilitySnapshot &snapshot) { m_snapshot=snapshot; }

   virtual CAccountExecutionEligibilitySnapshot Capture(void) const
     {
      return m_snapshot;
     }
  };

#endif
