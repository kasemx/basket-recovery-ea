#ifndef BRE_APP_PORTS_IACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH
#define BRE_APP_PORTS_IACCOUNT_EXECUTION_ELIGIBILITY_PROVIDER_MQH

#include <BasketRecovery/Domain/Execution/AccountExecutionEligibilitySnapshot.mqh>

class IAccountExecutionEligibilityProvider
  {
public:
   virtual          ~IAccountExecutionEligibilityProvider(void) {}
   virtual CAccountExecutionEligibilitySnapshot Capture(void) const=0;
  };

#endif
