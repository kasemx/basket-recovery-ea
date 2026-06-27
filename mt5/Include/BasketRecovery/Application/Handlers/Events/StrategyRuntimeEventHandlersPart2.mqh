#ifndef BRE_APP_STRATEGY_RUNTIME_EVT_HANDLERS2_MQH
#define BRE_APP_STRATEGY_RUNTIME_EVT_HANDLERS2_MQH

#include <BasketRecovery/Application/Handlers/Events/StrategyRuntimeEventHandlers.mqh>

class CStrategyProfileBoundEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CStrategyProfileBoundEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_STRATEGY_PROFILE_BOUND) {}

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      return CResult<CEventHandlingResult>::EmptyOk();
     }
  };

class CProfitLevelCloseRequestedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CProfitLevelCloseRequestedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_PROFIT_LEVEL_CLOSE_REQUESTED) {}

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CStrategyDomainEvent *event=(CStrategyDomainEvent*)domainEvent;
      CResult<CBasketAggregate> loaded=LoadBasket(event.BasketId());
      if(loaded.IsFail())
         return CResult<CEventHandlingResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      CCommandId commandId(m_idGenerator.NewGuid());
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      CVoidResult apply=basket.ApplyProfitLevelCloseRequested(event.LevelId(),commandId,eventId,timestampUtc);
      if(apply.IsFail())
         return CResult<CEventHandlingResult>::Fail(apply.ErrorCode(),apply.ErrorMessage());
      return SaveBasket(basket);
     }
  };

class CProfitLevelCloseCompletedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CProfitLevelCloseCompletedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_PROFIT_LEVEL_CLOSE_COMPLETED) {}

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CStrategyDomainEvent *event=(CStrategyDomainEvent*)domainEvent;
      CResult<CBasketAggregate> loaded=LoadBasket(event.BasketId());
      if(loaded.IsFail())
         return CResult<CEventHandlingResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      CCommandId commandId(m_idGenerator.NewGuid());
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      CVoidResult apply=basket.ApplyProfitLevelCloseCompleted(event.LevelId(),
                                                            CMoney(event.RealizedProfit()),
                                                            commandId,eventId,timestampUtc);
      if(apply.IsFail())
         return CResult<CEventHandlingResult>::Fail(apply.ErrorCode(),apply.ErrorMessage());
      return SaveBasket(basket);
     }
  };

class CRiskReductionRequestedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CRiskReductionRequestedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_RISK_REDUCTION_REQUESTED) {}

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CResult<CBasketAggregate> loaded=LoadBasket(domainEvent.BasketId());
      if(loaded.IsFail())
         return CResult<CEventHandlingResult>::Fail(loaded.ErrorCode(),loaded.ErrorMessage());
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      CCommandId commandId(m_idGenerator.NewGuid());
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);
      basket.ApplyRiskReductionRequested(commandId,eventId,timestampUtc);
      return SaveBasket(basket);
     }
  };

#endif
