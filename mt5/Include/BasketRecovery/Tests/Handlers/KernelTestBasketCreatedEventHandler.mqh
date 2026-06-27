#ifndef BRE_TEST_KERNEL_BASKET_CREATED_EVT_H_MQH
#define BRE_TEST_KERNEL_BASKET_CREATED_EVT_H_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>

class CKernelTestBasketCreatedEventHandler : public IEventHandler
  {
public:
   virtual          ~CKernelTestBasketCreatedEventHandler(void) {}

   virtual bool      CanHandle(const CDomainEvent *domainEvent) const
     {
      return domainEvent!=NULL && domainEvent.EventType()==BRE_EVENT_BASKET_CREATED;
     }

   virtual int       Priority(void) const { return 10; }

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CEventHandlingResult handlingResult;
      CActivateBasketCommand *command=new CActivateBasketCommand();
      command.SetId(CCommandId("cmd-activate-kernel-test"));
      command.SetIdempotencyKey("activate:kernel:test:001");
      command.SetBasketId(domainEvent.BasketId());
      command.SetCorrelationKey(domainEvent.CorrelationId());
      command.SetPriority(50);
      handlingResult.AddCommand(command);
      return BreResultOkAdopting(handlingResult);
     }
  };

#endif
