#ifndef BRE_APP_COMPOSITE_PENDING_EXECUTION_FILL_NOTIFIER_MQH
#define BRE_APP_COMPOSITE_PENDING_EXECUTION_FILL_NOTIFIER_MQH

#include <BasketRecovery/Application/Execution/PendingExecutionStartupReconciliationService.mqh>

class CCompositePendingExecutionFillNotifier : public IPendingExecutionFillNotifier
  {
private:
   IPendingExecutionFillNotifier *m_notifiers[];
   int                            m_count;

public:
                     CCompositePendingExecutionFillNotifier(void)
     {
      m_count=0;
     }

   void              AddNotifier(IPendingExecutionFillNotifier *notifier)
     {
      if(notifier==NULL)
         return;
      int size=ArraySize(m_notifiers);
      ArrayResize(m_notifiers,size+1);
      m_notifiers[size]=notifier;
      m_count=size+1;
     }

   virtual void      OnBrokerFillConfirmed(const string executionRequestId)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_notifiers[i]!=NULL)
            m_notifiers[i].OnBrokerFillConfirmed(executionRequestId);
        }
     }
  };

#endif
