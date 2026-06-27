#ifndef BASKET_RECOVERY_APPLICATION_IBROKER_RECONCILIATION_SERVICE_MQH
#define BASKET_RECOVERY_APPLICATION_IBROKER_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>

class IBrokerReconciliationService
  {
public:
   virtual          ~IBrokerReconciliationService(void) {}
   virtual CVoidResult ReconcileAtStartup(void)=0;
  };

#endif
