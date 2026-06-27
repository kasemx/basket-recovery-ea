#ifndef BRE_INF_BROKER_RECONCILIATION_SERVICE_MQH
#define BRE_INF_BROKER_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IBrokerReconciliationService.mqh>
#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>

class CBrokerReconciliationService : public IBrokerReconciliationService
  {
private:
   IBrokerPositionReader      *m_reader;
   CBasketPositionReconciler  *m_reconciler;
   bool                        m_ownsGraph;

public:
                     CBrokerReconciliationService(IBrokerPositionReader *reader,
                                                  CBasketPositionReconciler *reconciler,
                                                  const bool takeOwnership=true)
     {
      m_reader=reader;
      m_reconciler=reconciler;
      m_ownsGraph=takeOwnership;
     }

   virtual          ~CBrokerReconciliationService(void)
     {
      if(!m_ownsGraph)
         return;
      if(m_reconciler!=NULL)
        {
         delete m_reconciler;
         m_reconciler=NULL;
        }
      if(m_reader!=NULL)
        {
         delete m_reader;
         m_reader=NULL;
        }
     }

   CBasketPositionReconciler* Reconciler(void) const { return m_reconciler; }

   virtual CVoidResult ReconcileAtStartup(void)
     {
      if(m_reconciler==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Reconciler is not registered");
      return m_reconciler.ReconcileAtStartup();
     }
  };

#endif
