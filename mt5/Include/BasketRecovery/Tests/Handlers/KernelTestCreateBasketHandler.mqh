#ifndef BASKET_RECOVERY_TESTS_KERNEL_TEST_CREATE_BASKET_HANDLER_MQH
#define BASKET_RECOVERY_TESTS_KERNEL_TEST_CREATE_BASKET_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CKernelTestCreateBasketCommandHandler : public ICommandHandler
  {
public:
   virtual          ~CKernelTestCreateBasketCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_CREATE_BASKET;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CCommandExecutionResult executionResult;
      CDomainEvent *event=new CDomainEvent();
      event.SetEventType(BRE_EVENT_BASKET_CREATED);
      event.SetBasketId(command.BasketId());
      event.SetCorrelationId(command.CorrelationKey());
      executionResult.AddEvent(event);
      return CResult<CCommandExecutionResult>::Ok(executionResult);
     }
  };

#endif
