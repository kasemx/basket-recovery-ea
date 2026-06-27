#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_CONTEXT_MQH

#include <BasketRecovery/Application/Kernel/ServiceContainer.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationKernel.mqh>
#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Shared/DTOs/NormalizedTradeTransaction.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CApplicationContext
  {
private:
   CServiceContainer  *m_container;
   CApplicationKernel *m_kernel;
   bool                m_initialized;

public:
                     CApplicationContext(void)
     {
      m_container=NULL;
      m_kernel=NULL;
      m_initialized=false;
     }

                    ~CApplicationContext(void)
     {
      Shutdown();
     }

   bool              Initialize(CServiceContainer *container,CApplicationKernel *kernel)
     {
      if(container==NULL || kernel==NULL)
         return false;
      m_container=container;
      m_kernel=kernel;
      m_initialized=true;
      return true;
     }

   void              Shutdown(void)
     {
      if(m_kernel!=NULL)
        {
         delete m_kernel;
         m_kernel=NULL;
        }
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
      if(!m_initialized || m_kernel==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Application context is not initialized");

      CTradeTransactionFastPathService *fastPath=m_kernel.TradeTransactionFastPath();
      if(fastPath==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"Trade transaction fast path is unavailable");

      return fastPath.Handle(transaction);
     }

   int               OnTick(const string symbol)
     {
      if(!m_initialized || m_kernel==NULL)
         return 0;

      CTimerFallbackEvaluationService *fallback=m_kernel.FallbackEvaluation();
      if(fallback!=NULL)
         fallback.NotifyTick();

      CFastMarketEvaluationCoordinator *coordinator=m_kernel.FastCoordinator();
      if(coordinator==NULL)
         return 0;

      return coordinator.OnTick(symbol);
     }

   CVoidResult       OnApplicationTimer(int &commandsProcessed,int &eventsProcessed,int &evaluationsScheduled)
     {
      if(!m_initialized || m_kernel==NULL)
         return CVoidResult::Ok();
      return m_kernel.TimerPipeline().OnTimer(commandsProcessed,eventsProcessed,evaluationsScheduled);
     }

   CVoidResult       OnRestPollTimer(void)
     {
      int commandsProcessed=0;
      int eventsProcessed=0;
      int evaluationsScheduled=0;
      return OnApplicationTimer(commandsProcessed,eventsProcessed,evaluationsScheduled);
     }

   int               ApplicationTimerIntervalMs(void) const
     {
      if(m_container==NULL)
         return 250;
      return m_container.EAConfiguration().ApplicationTimerIntervalMs();
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

   CApplicationKernel* Kernel(void) const { return m_kernel; }

   int               CommandQueuePendingCount(void) const
     {
      if(m_kernel==NULL)
         return 0;
      return m_kernel.PersistenceManager().CommandQueue().PendingCount();
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
