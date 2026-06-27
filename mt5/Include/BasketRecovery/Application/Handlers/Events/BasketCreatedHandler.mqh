#ifndef BASKET_RECOVERY_APPLICATION_BASKET_CREATED_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_BASKET_CREATED_HANDLER_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CBasketCreatedHandler : public IEventHandler
  {
public:
   virtual          ~CBasketCreatedHandler(void) {}

   virtual bool      CanHandle(const CDomainEvent *domainEvent) const
     {
      return domainEvent!=NULL && domainEvent.EventType()==BRE_EVENT_BASKET_CREATED;
     }

   virtual int       Priority(void) const { return 10; }

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CEventHandlingResult result;
      return CResult<CEventHandlingResult>::Ok(result);
     }
  };

#endif
