#ifndef BASKET_RECOVERY_APPLICATION_EVALUATE_BASKET_STRATEGY_USE_CASE_MQH
#define BASKET_RECOVERY_APPLICATION_EVALUATE_BASKET_STRATEGY_USE_CASE_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CEvaluateBasketStrategyUseCase
  {
private:
   IBasketRepository  *m_repository;
   IStrategyEngine    *m_strategyEngine;
   ICommandQueue      *m_queue;
   IClock             *m_clock;
   IUniqueIdGenerator *m_idGenerator;

public:
                     CEvaluateBasketStrategyUseCase(IBasketRepository *repository,
                                                    IStrategyEngine *strategyEngine,
                                                    ICommandQueue *queue,
                                                    IClock *clock,
                                                    IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_strategyEngine=strategyEngine;
      m_queue=queue;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   CResult<int>      Execute(const CEvaluateStrategyCommand &command,
                             const CMarketContext &market,
                             const CRiskRuntimeContext &riskContext,
                             const double adverseMovePips,
                             const double floatingProfitUsd)
     {
      if(m_repository==NULL)
         return CResult<int>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket repository is required");

      CResult<CBasketAggregate> loaded=m_repository.Load(command.BasketId());
      if(loaded.IsFail())
         return CResult<int>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return CResult<int>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");

      CVoidResult guardResult=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                                  command.ExpectedBasketVersion(),
                                                                                  command.StrategyProfileHash());
      if(guardResult.IsFail())
         return CResult<int>::Fail(guardResult.ErrorCode(),guardResult.ErrorMessage());

      CStrategyEvaluationContext context=CStrategyEvaluationContextFactory::FromBasket(basket,market,riskContext,
                                                                                       adverseMovePips,floatingProfitUsd);
      CStrategyDecisionSet decisions=m_strategyEngine.EvaluateAll(context);

      CStrategyDecisionCommandMapper mapper;
      ICommand *mappedCommands[];
      CResult<int> mapResult=mapper.MapDecisionSet(decisions,
                                                   basket.Id(),
                                                   basket.Version(),
                                                   basket.StrategyProfileHash(),
                                                   command.CorrelationKey(),
                                                   mappedCommands);
      if(mapResult.IsFail())
         return mapResult;

      int mappedCount=0;
      mapResult.TryGetValue(mappedCount);
      if(m_queue!=NULL)
        {
         for(int i=0;i<mappedCount;i++)
           {
            if(mappedCommands[i]==NULL)
               continue;
            mappedCommands[i].SetId(CCommandId(m_idGenerator.NewGuid()));
            mappedCommands[i].SetEnqueuedAt(m_clock!=NULL ? m_clock.Now() : 0);
            m_queue.Enqueue(mappedCommands[i]);
           }
        }

      CCommandId auditCommandId=command.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : command.Id();
      CEventId auditEventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      basket.AppendEvaluationAudit(auditCommandId,auditEventId,timestampUtc);

      CVoidResult saveResult=m_repository.Save(basket);
      if(saveResult.IsFail())
         return CResult<int>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      return CResult<int>::Ok(mappedCount);
     }
  };

#endif
