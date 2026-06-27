#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_RUNTIME_EVENT_HANDLERS_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_RUNTIME_EVENT_HANDLERS_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Domain/Events/StrategyDomainEvent.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CStrategyRuntimeEventHandlerBase : public IEventHandler
  {
protected:
   IBasketRepository  *m_repository;
   IClock             *m_clock;
   IUniqueIdGenerator *m_idGenerator;
   ENUM_BRE_EVENT_TYPE m_eventType;

                     CStrategyRuntimeEventHandlerBase(IBasketRepository *repository,
                                                      IClock *clock,
                                                      IUniqueIdGenerator *idGenerator,
                                                      const ENUM_BRE_EVENT_TYPE eventType)
     {
      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;
      m_eventType=eventType;
     }

   CResult<CBasketAggregate> LoadBasket(const CBasketId &basketId) const
     {
      if(m_repository==NULL)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Repository is missing");
      return m_repository.Load(basketId);
     }

   CResult<CEventHandlingResult> SaveBasket(CBasketAggregate &basket) const
     {
      if(m_repository.Save(basket).IsFail())
         return CResult<CEventHandlingResult>::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to save basket");
      return CResult<CEventHandlingResult>::EmptyOk();
     }

public:
   virtual bool      CanHandle(const CDomainEvent *domainEvent) const
     {
      return domainEvent!=NULL && domainEvent.EventType()==m_eventType;
     }

   virtual int       Priority(void) const { return 30; }
  };

class CProfitLevelReachedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CProfitLevelReachedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_PROFIT_LEVEL_REACHED) {}

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
      CVoidResult apply=basket.ApplyProfitLevelReached(event.LevelId(),timestampUtc,commandId,eventId);
      if(apply.IsFail())
         return CResult<CEventHandlingResult>::Fail(apply.ErrorCode(),apply.ErrorMessage());
      return SaveBasket(basket);
     }
  };

class CBreakEvenActivatedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CBreakEvenActivatedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_BREAK_EVEN_ACTIVATED) {}

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
      CVoidResult apply=basket.ApplyBreakEvenActivated(event.RuleId(),commandId,eventId,timestampUtc);
      if(apply.IsFail())
         return CResult<CEventHandlingResult>::Fail(apply.ErrorCode(),apply.ErrorMessage());
      CStrategyProfile profile;
      if(basket.StrategyProfile(profile) && profile.RecoveryPlan().DisableAfterBreakEven())
         basket.ApplyRecoveryDisabled(commandId,eventId,timestampUtc);
      return SaveBasket(basket);
     }
  };

class CRecoveryDisabledEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CRecoveryDisabledEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_RECOVERY_DISABLED) {}

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
      basket.ApplyRecoveryDisabled(commandId,eventId,timestampUtc);
      return SaveBasket(basket);
     }
  };

class CBasketLockedEventHandler : public CStrategyRuntimeEventHandlerBase
  {
public:
                     CBasketLockedEventHandler(IBasketRepository *repository,IClock *clock,IUniqueIdGenerator *idGenerator)
        : CStrategyRuntimeEventHandlerBase(repository,clock,idGenerator,BRE_EVENT_BASKET_LOCKED) {}

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
      basket.ApplyBasketLocked(commandId,eventId,timestampUtc);
      return SaveBasket(basket);
     }
  };

#endif
