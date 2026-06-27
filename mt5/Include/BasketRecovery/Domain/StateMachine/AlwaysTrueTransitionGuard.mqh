#ifndef BASKET_RECOVERY_DOMAIN_ALWAYS_TRUE_TRANSITION_GUARD_MQH
#define BASKET_RECOVERY_DOMAIN_ALWAYS_TRUE_TRANSITION_GUARD_MQH

#include <BasketRecovery/Domain/StateMachine/ITransitionGuard.mqh>

class CAlwaysTrueTransitionGuard : public ITransitionGuard
  {
public:
   virtual          ~CAlwaysTrueTransitionGuard(void) {}

   virtual string    Name(void) const { return "AlwaysTrue"; }

   virtual bool      Evaluate(const IBasketReadModel &basket,const CDomainEvent &domainEvent) const
     {
      return true;
     }
  };

#endif
