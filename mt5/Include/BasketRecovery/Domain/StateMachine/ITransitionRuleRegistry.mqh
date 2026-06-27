#ifndef BASKET_RECOVERY_DOMAIN_ITRANSITION_RULE_REGISTRY_MQH
#define BASKET_RECOVERY_DOMAIN_ITRANSITION_RULE_REGISTRY_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/StateMachine/TransitionRule.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class ITransitionRuleRegistry
  {
public:
   virtual          ~ITransitionRuleRegistry(void) {}
   virtual CVoidResult RegisterRule(const CTransitionRule &rule)=0;
   virtual CVoidResult RegisterRejectedEvent(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                             const ENUM_BRE_EVENT_TYPE eventType)=0;
   virtual bool      FindRule(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                              const ENUM_BRE_EVENT_TYPE allowedEvent,
                              CTransitionRule &outRule) const=0;
   virtual bool      IsRejectedEvent(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                     const ENUM_BRE_EVENT_TYPE eventType) const=0;
   virtual CVoidResult Validate(void) const=0;
   virtual string    ExportTable(void) const=0;
   virtual int       RuleCount(void) const=0;
   virtual bool      GetRuleAt(const int index,CTransitionRule &outRule) const=0;
  };

#endif
