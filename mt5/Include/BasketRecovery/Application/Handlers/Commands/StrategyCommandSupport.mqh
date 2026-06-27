#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_COMMAND_SUPPORT_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_COMMAND_SUPPORT_MQH

#include <BasketRecovery/Application/Commands/StrategyCommandBase.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>
#include <BasketRecovery/Domain/Events/StrategyDomainEvent.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CStrategyCommandSupport
  {
public:
   static CResult<CBasketAggregate> LoadAndValidate(const CStrategyCommandBase *command,
                                                    IBasketRepository *repository)
     {
      if(command==NULL || repository==NULL)
         return CResult<CBasketAggregate>::Fail(BRE_ERR_COMMAND_INVALID,"Strategy command or repository is missing");

      CResult<CBasketAggregate> loaded=repository.Load(command.BasketId());
      if(loaded.IsFail())
         return loaded;

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");

      CVoidResult guard=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                            command.ExpectedBasketVersion(),
                                                                            command.StrategyProfileHash());
      if(guard.IsFail())
         return CResult<CBasketAggregate>::Fail(guard.ErrorCode(),guard.ErrorMessage());

      return CResult<CBasketAggregate>::Ok(basket);
     }

   static CStrategyDomainEvent* CreateExecutionPendingEvent(const CBasketAggregate &basket,
                                                          const CStrategyCommandBase *command,
                                                          const ENUM_BRE_COMMAND_TYPE commandType)
     {
      CStrategyDomainEvent *event=new CStrategyDomainEvent();
      event.SetEventType(BRE_EVENT_EXECUTION_PENDING);
      event.SetBasketId(basket.Id());
      event.SetCorrelationId(command.CorrelationKey());
      event.SetSourceCommandType(commandType);
      return event;
     }
  };

#endif
