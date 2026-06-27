#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_EVALUATION_SCHEDULER_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_EVALUATION_SCHEDULER_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>

class CStrategyEvaluationScheduler
  {
private:
   IBasketRepository  *m_repository;
   ICommandQueue      *m_queue;
   IClock             *m_clock;
   IUniqueIdGenerator *m_idGenerator;
   int                 m_intervalMs;
   int                 m_maxBasketsPerCycle;
   ulong               m_lastRunTickMs;
   int                 m_nextBasketIndex;

   bool              IsDue(void) const
     {
      if(m_intervalMs<=0)
         return true;
      return ((ulong)GetTickCount()-m_lastRunTickMs)>=(ulong)m_intervalMs;
     }

public:
                     CStrategyEvaluationScheduler(IBasketRepository *repository,
                                                  ICommandQueue *queue,
                                                  IClock *clock,
                                                  IUniqueIdGenerator *idGenerator,
                                                  const int intervalMs=5000,
                                                  const int maxBasketsPerCycle=5)
     {
      m_repository=repository;
      m_queue=queue;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_intervalMs=intervalMs;
      m_maxBasketsPerCycle=maxBasketsPerCycle;
      m_lastRunTickMs=0;
      m_nextBasketIndex=0;
     }

   void              SetIntervalMs(const int value) { m_intervalMs=value; }
   void              SetMaxBasketsPerCycle(const int value) { m_maxBasketsPerCycle=value; }

   int               RunIfDue(void)
     {
      if(!IsDue() || m_repository==NULL || m_queue==NULL)
         return 0;

      CBasketAggregate baskets[];
      int basketCount=m_repository.LoadAll(baskets);
      if(basketCount<=0)
        {
         m_lastRunTickMs=(ulong)GetTickCount();
         return 0;
        }

      int scheduled=0;
      int scanned=0;
      while(scheduled<m_maxBasketsPerCycle && scanned<basketCount)
        {
         if(m_nextBasketIndex>=basketCount)
            m_nextBasketIndex=0;

         CBasketAggregate basket=baskets[m_nextBasketIndex];
         m_nextBasketIndex++;
         scanned++;

         if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
            continue;
         if(!basket.HasStrategyProfile() || basket.StrategyMigrationRequired())
            continue;

         CEvaluateStrategyCommand *command=new CEvaluateStrategyCommand();
         command.SetId(CCommandId(m_idGenerator.NewGuid()));
         command.SetBasketId(basket.Id());
         command.SetCorrelationKey(basket.CorrelationKey());
         command.SetExpectedBasketVersion(basket.Version());
         command.SetStrategyProfileHash(basket.StrategyProfileHash());
         command.SetIdempotencyKey("eval:"+basket.Id().Value()+":"+IntegerToString((long)basket.Version()));
         command.SetEnqueuedAt(m_clock!=NULL ? m_clock.Now() : 0);
         if(m_queue.Enqueue(command).IsOk())
            scheduled++;
         else
            delete command;
        }

      m_lastRunTickMs=(ulong)GetTickCount();
      return scheduled;
     }
  };

#endif
