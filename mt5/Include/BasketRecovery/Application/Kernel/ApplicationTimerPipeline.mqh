#ifndef BASKET_RECOVERY_APPLICATION_APPLICATION_TIMER_PIPELINE_MQH
#define BASKET_RECOVERY_APPLICATION_APPLICATION_TIMER_PIPELINE_MQH

#include <BasketRecovery/Application/Services/CommandIngestionService.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceManager.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationScheduler.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CApplicationTimerPipeline
  {
private:
   CCommandIngestionService     *m_ingestionService;
   CCommandProcessor            *m_commandProcessor;
   CPersistenceManager          *m_persistenceManager;
   CStrategyEvaluationScheduler *m_strategyScheduler;
   int                           m_restPollIntervalMs;
   ulong                         m_lastRestPollTickMs;

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

public:
                     CApplicationTimerPipeline(CCommandIngestionService *ingestionService,
                                               CCommandProcessor *commandProcessor,
                                               CPersistenceManager *persistenceManager,
                                               CStrategyEvaluationScheduler *strategyScheduler,
                                               const int restPollIntervalMs=3000)
     {
      m_ingestionService=ingestionService;
      m_commandProcessor=commandProcessor;
      m_persistenceManager=persistenceManager;
      m_strategyScheduler=strategyScheduler;
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

      if(m_strategyScheduler!=NULL)
         evaluationsScheduled=m_strategyScheduler.RunIfDue();

      return CVoidResult::Ok();
     }
  };

#endif
