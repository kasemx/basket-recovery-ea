#ifndef BRE_APP_BIND_MIGRATED_BASKET_STRATEGY_UC_MQH
#define BRE_APP_BIND_MIGRATED_BASKET_STRATEGY_UC_MQH

#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/DomainEventResult.mqh>

class CBindMigratedBasketStrategyUseCase
  {
private:
   IBasketRepository  *m_repository;
   IClock             *m_clock;
   IUniqueIdGenerator *m_idGenerator;

public:
                     CBindMigratedBasketStrategyUseCase(IBasketRepository *repository,
                                                        IClock *clock,
                                                        IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   CDomainEventResult Execute(const CBasketId &basketId,
                              const string explicitCanonicalJson,
                              const CStrategyProfile &explicitProfile)
     {
      if(m_repository==NULL)
         return CDomainEventResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Repository is required");
      if(explicitCanonicalJson=="")
         return CDomainEventResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Explicit strategy JSON is required");
      if(explicitProfile.StrategyId()=="")
         return CDomainEventResult::Fail(BRE_ERR_STRATEGY_VALIDATION_FAILED,"Explicit strategy profile is required");

      CResult<CBasketAggregate> loaded=m_repository.Load(basketId);
      if(loaded.IsFail())
         return CDomainEventResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return CDomainEventResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");

      if(!basket.StrategyMigrationRequired())
         return CDomainEventResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Basket does not require strategy migration");
      if(basket.HasStrategyProfile())
         return CDomainEventResult::Fail(BRE_ERR_STRATEGY_ALREADY_BOUND,"Basket already has a bound strategy profile");

      CUtcTime boundAt(m_clock!=NULL ? m_clock.Now() : 0);
      CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(explicitProfile,
                                                                                              explicitCanonicalJson,
                                                                                              boundAt);

      CCommandId commandId(m_idGenerator.NewGuid());
      CEventId eventId(m_idGenerator.NewGuid());
      CVoidResult bindResult=basket.CompleteStrategyMigration(snapshot,commandId,eventId,boundAt);
      if(bindResult.IsFail())
         return CDomainEventResult::Fail(bindResult.ErrorCode(),bindResult.ErrorMessage());

      if(m_repository.Save(basket).IsFail())
         return CDomainEventResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to save migrated basket");

      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_STRATEGY_PROFILE_BOUND);
      event.SetBasketId(basket.Id());
      event.SetCorrelationId("migration:"+basket.Id().Value());
      event.SetOccurredAt(boundAt.Value());
      return CDomainEventResult::Ok(event);
     }
  };

#endif
