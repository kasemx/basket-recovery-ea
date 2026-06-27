#ifndef BRE_APP_RECONCILIATION_SCHEDULER_SERVICE_MQH
#define BRE_APP_RECONCILIATION_SCHEDULER_SERVICE_MQH

#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>

class CReconciliationSchedulerService
  {
private:
   CBasketPositionReconciler *m_reconciler;
   int                        m_intervalMs;
   int                        m_maxBasketsPerCycle;
   ulong                      m_lastRunTickMs;

   bool              IsDue(void) const
     {
      if(m_intervalMs<=0)
         return false;
      return ((ulong)GetTickCount()-m_lastRunTickMs)>=(ulong)m_intervalMs;
     }

public:
                     CReconciliationSchedulerService(CBasketPositionReconciler *reconciler,
                                                     const int intervalMs=30000,
                                                     const int maxBasketsPerCycle=3)
     {
      m_reconciler=reconciler;
      m_intervalMs=intervalMs;
      m_maxBasketsPerCycle=maxBasketsPerCycle;
      m_lastRunTickMs=0;
     }

   int               RunIfDue(void)
     {
      if(!IsDue() || m_reconciler==NULL)
         return 0;

      int processed=m_reconciler.RunPeriodicCycle(m_maxBasketsPerCycle);
      m_lastRunTickMs=(ulong)GetTickCount();
      return processed;
     }
  };

#endif
