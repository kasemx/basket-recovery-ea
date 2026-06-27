#ifndef BASKET_RECOVERY_DOMAIN_ITRANSITION_GUARD_MQH
#define BASKET_RECOVERY_DOMAIN_ITRANSITION_GUARD_MQH

#include <BasketRecovery/Domain/Aggregates/IBasketReadModel.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class ITransitionGuard
  {
public:
   virtual          ~ITransitionGuard(void) {}
   virtual string    Name(void) const=0;
   virtual bool      Evaluate(const IBasketReadModel &basket,const CDomainEvent &domainEvent) const=0;
  };

#endif
