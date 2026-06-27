#ifndef BASKET_RECOVERY_APPLICATION_BASKET_CLOSED_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_BASKET_CLOSED_HANDLER_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CBasketClosedHandler : public IEventHandler
  {
public:
   virtual          ~CBasketClosedHandler(void) {}

   virtual bool      CanHandle(const CDomainEvent *domainEvent) const
     {
      if(domainEvent==NULL)
         return false;
      return domainEvent.EventType()==BRE_EVENT_BASKET_CLOSING ||
             domainEvent.EventType()==BRE_EVENT_BASKET_FINISHED;
     }

   virtual int       Priority(void) const { return 30; }

   virtual CResult<CEventHandlingResult> Handle(CDomainEvent *domainEvent)
     {
      CEventHandlingResult result;
      return CResult<CEventHandlingResult>::Ok(result);
     }
  };

#endif
