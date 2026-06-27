#ifndef BRE_INF_BROKER_RECONCILIATION_SERVICE_MQH
#define BRE_INF_BROKER_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IBrokerReconciliationService.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>

class CBrokerReconciliationService : public IBrokerReconciliationService
  {
private:
   CBasketPositionReconciler *m_reconciler;

public:
                     CBrokerReconciliationService(CBasketPositionReconciler *reconciler)
     {
      m_reconciler=reconciler;
     }

   virtual          ~CBrokerReconciliationService(void) {}

   virtual CVoidResult ReconcileAtStartup(void)
     {
      if(m_reconciler==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Reconciler is not registered");
      return m_reconciler.ReconcileAtStartup();
     }
  };

#endif
