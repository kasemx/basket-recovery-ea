#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH

#include <BasketRecovery/Application/Kernel/ServiceContainer.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CApplicationContext
  {
private:
   CServiceContainer *m_container;
   bool               m_initialized;

public:
                     CApplicationContext(void)
     {
      m_container=NULL;
      m_initialized=false;
     }

                    ~CApplicationContext(void)
     {
      Shutdown();
     }

   bool              Initialize(CServiceContainer *container)
     {
      if(container==NULL)
         return false;

      m_container=container;
      m_initialized=true;
      return true;
     }

   void              Shutdown(void)
     {
      if(m_container!=NULL)
        {
         m_container.Shutdown();
         delete m_container;
         m_container=NULL;
        }
      m_initialized=false;
     }

   bool              IsInitialized(void) const { return m_initialized; }

   CVoidResult       ApplyNormalizedTransaction(const CNormalizedTradeTransaction &transaction)
     {
      if(!m_initialized || m_container==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Application context is not initialized");

      IPositionSnapshotStore *snapshotStore=m_container.SnapshotStore();
      if(snapshotStore==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Snapshot store is not registered");

      return snapshotStore.ApplyNormalizedTransaction(transaction);
     }

   CVoidResult       OnRestPollTimer(void)
     {
      if(!m_initialized || m_container==NULL)
         return CVoidResult::Ok();

      CCommandIngestionService *ingestionService=m_container.CommandIngestionService();
      if(ingestionService==NULL)
         return CVoidResult::Ok();

      return ingestionService.PollAndEnqueue();
     }

   int               RestPollIntervalMs(void) const
     {
      if(m_container==NULL)
         return 3000;
      int configured=m_container.EAConfiguration().RestPollIntervalMs();
      if(configured<=0)
         return 3000;
      return configured;
     }

   bool              IsRestIngestionConfigured(void) const
     {
      if(m_container==NULL)
         return false;
      return m_container.EAConfiguration().ApiBaseUrl()!="";
     }

   int               CommandQueuePendingCount(void) const
     {
      if(m_container==NULL || m_container.CommandQueue()==NULL)
         return 0;
      return m_container.CommandQueue().PendingCount();
     }

   void              LogShutdown(const int reason)
     {
      if(m_container==NULL)
         return;

      ILogger *logger=m_container.Logger();
      if(logger==NULL)
         return;

      logger.Info("SYSTEM","Shutdown","",StringFormat("BasketRecoveryEA stopped | reason=%d",reason));
     }

   int               SnapshotCount(void) const
     {
      if(m_container==NULL)
         return 0;

      IPositionSnapshotStore *snapshotStore=m_container.SnapshotStore();
      if(snapshotStore==NULL)
         return 0;

      return snapshotStore.Count();
     }
  };

#endif
