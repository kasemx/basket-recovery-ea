#ifndef BASKET_RECOVERY_APPLICATION_IEVENT_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_IEVENT_HANDLER_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Application/DTOs/EventHandlingResult.mqh>
#include <BasketRecovery/Shared/Types/ResultValueTransfer.mqh>

class IEventHandler
  {
public:
   virtual          ~IEventHandler(void) {}
   virtual bool      CanHandle(const CDomainEvent *domainEvent) const=0;
   virtual int       Priority(void) const=0;
   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)=0;
  };

#endif
