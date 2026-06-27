#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_TIMER_PIPELINE_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_TIMER_PIPELINE_MQH

#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceManager.mqh>
#include <BasketRecovery/Application/Services/ReconciliationSchedulerService.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Application/Services/SystemHealthCheckService.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CApplicationTimerPipeline
  {
private:
   CCommandIngestionService          *m_ingestionService;
   CCommandProcessor                 *m_commandProcessor;
   CPersistenceManager               *m_persistenceManager;
   CReconciliationSchedulerService   *m_reconciliationScheduler;
   CTimerFallbackEvaluationService   *m_fallbackEvaluation;
   CSystemHealthCheckService         *m_healthCheck;
   CFastCommandStagingBuffer         *m_stagingQueue;
   int                                m_restPollIntervalMs;
   ulong                              m_lastRestPollTickMs;

   bool              IsRestPollDue(void) const
     {
      if(m_restPollIntervalMs<=0 || m_ingestionService==NULL)
         return false;
      return ((ulong)GetTickCount()-m_lastRestPollTickMs)>=(ulong)m_restPollIntervalMs;
     }

   void              SuspendBasketIfPossible(const CBasketId &basketId)
     {
      if(m_persistenceManager==NULL || basketId.IsEmpty())
         return;
      CResult<CBasketAggregate> loaded=m_persistenceManager.BasketRepository().Load(basketId);
      if(loaded.IsFail())
         return;
      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return;
      if(basket.LifecycleState()==BRE_STATE_ACTIVE)
        {
         basket.SetLifecycleState(BRE_STATE_SUSPENDED);
         m_persistenceManager.QueueSaveBasket(basket);
        }
     }

   int               FlushStagingQueue(void)
     {
      if(m_stagingQueue==NULL || m_persistenceManager==NULL)
         return 0;
      return m_stagingQueue.FlushTo(m_persistenceManager.CommandQueue());
     }

public:
                     CApplicationTimerPipeline(CCommandIngestionService *ingestionService,
                                               CCommandProcessor *commandProcessor,
                                               CPersistenceManager *persistenceManager,
                                               CReconciliationSchedulerService *reconciliationScheduler,
                                               CTimerFallbackEvaluationService *fallbackEvaluation,
                                               CSystemHealthCheckService *healthCheck,
                                               CFastCommandStagingBuffer *stagingQueue,
                                               const int restPollIntervalMs=3000)
     {
      m_ingestionService=ingestionService;
      m_commandProcessor=commandProcessor;
      m_persistenceManager=persistenceManager;
      m_reconciliationScheduler=reconciliationScheduler;
      m_fallbackEvaluation=fallbackEvaluation;
      m_healthCheck=healthCheck;
      m_stagingQueue=stagingQueue;
      m_restPollIntervalMs=restPollIntervalMs;
      m_lastRestPollTickMs=0;
     }

   CVoidResult       OnTimer(int &commandsProcessed,int &eventsProcessed,int &evaluationsScheduled)
     {
      commandsProcessed=0;
      eventsProcessed=0;
      evaluationsScheduled=0;

      if(IsRestPollDue() && m_ingestionService!=NULL)
        {
         m_ingestionService.PollAndEnqueue();
         m_lastRestPollTickMs=(ulong)GetTickCount();
        }

      FlushStagingQueue();

      if(m_commandProcessor!=NULL)
        {
         CVoidResult cycleResult=m_commandProcessor.RunCycle(commandsProcessed,eventsProcessed);
         if(cycleResult.IsFail())
           {
            if(cycleResult.ErrorCode()==BRE_ERR_PROCESSOR_LOOP_LIMIT)
               SuspendBasketIfPossible(m_commandProcessor.LastProcessedBasketId());
            return cycleResult;
           }
        }

      if(m_persistenceManager!=NULL)
        {
         CVoidResult flushResult=m_persistenceManager.FlushIfDue();
         if(flushResult.IsFail())
            return flushResult;
        }

      if(m_reconciliationScheduler!=NULL)
         m_reconciliationScheduler.RunIfDue();

      if(m_healthCheck!=NULL)
         m_healthCheck.RunIfDue();

      if(m_fallbackEvaluation!=NULL)
         evaluationsScheduled=m_fallbackEvaluation.RunIfDue();

      if(evaluationsScheduled>0)
         FlushStagingQueue();

      return CVoidResult::Ok();
     }
  };

#endif
