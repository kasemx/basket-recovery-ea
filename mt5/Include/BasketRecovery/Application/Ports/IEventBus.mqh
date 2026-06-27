#ifndef BASKET_RECOVERY_APPLICATION_IEVENT_BUS_MQH
#define BASKET_RECOVERY_APPLICATION_IEVENT_BUS_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Application/Ports/IEventHandler.mqh>

class IEventBus
  {
public:
   virtual          ~IEventBus(void) {}
   virtual void     Publish(CDomainEvent *domainEvent)=0;
   virtual void     Subscribe(const ENUM_BRE_EVENT_TYPE eventType,IEventHandler *handler)=0;
   virtual void     DrainQueue(void)=0;
   virtual int      QueueSize(void) const=0;
  };

#endif
