#ifndef BASKET_RECOVERY_APPLICATION_TRANSITION_ENGINE_MQH
#define BASKET_RECOVERY_APPLICATION_TRANSITION_ENGINE_MQH

#include <BasketRecovery/Domain/StateMachine/ITransitionRuleRegistry.mqh>
#include <BasketRecovery/Domain/StateMachine/TransitionResult.mqh>
#include <BasketRecovery/Domain/Aggregates/IBasketReadModel.mqh>
#include <BasketRecovery/Domain/Events/DomainEvent.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CTransitionEngine
  {
private:
   ITransitionRuleRegistry *m_registry;

   CResult<CTransitionResult> EvaluateTransition(const IBasketReadModel &basket,
                                                 const CDomainEvent &domainEvent) const
     {
      ENUM_BRE_BASKET_LIFECYCLE_STATE currentState=basket.LifecycleState();
      ENUM_BRE_EVENT_TYPE eventType=domainEvent.EventType();

      if(m_registry==NULL)
         return CResult<CTransitionResult>::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Transition rule registry is not registered");

      if(m_registry.IsRejectedEvent(currentState,eventType))
        {
         return CResult<CTransitionResult>::Ok(
            CTransitionResult::Rejected(currentState,eventType,"Event rejected for current lifecycle state",
                                        BRE_ERR_TRANSITION_REJECTED));
        }

      CTransitionRule rule;
      if(!m_registry.FindRule(currentState,eventType,rule))
        {
         return CResult<CTransitionResult>::Ok(
            CTransitionResult::Rejected(currentState,eventType,"No matching transition rule",
                                        BRE_ERR_TRANSITION_INVALID));
        }

      if(!rule.EvaluateGuard(basket,domainEvent))
        {
         return CResult<CTransitionResult>::Ok(
            CTransitionResult::Rejected(currentState,eventType,"Transition guard evaluation failed",
                                        rule.ErrorCode()==0 ? BRE_ERR_TRANSITION_GUARD_FAILED : rule.ErrorCode()));
        }

      return CResult<CTransitionResult>::Ok(
         CTransitionResult::Applied(currentState,rule.NextState(),eventType,rule.RuleId()));
     }

public:
                     CTransitionEngine(ITransitionRuleRegistry *registry)
     {
      m_registry=registry;
     }

   CResult<CTransitionResult> ValidateTransition(const IBasketReadModel &basket,
                                                 const CDomainEvent &domainEvent) const
     {
      return EvaluateTransition(basket,domainEvent);
     }

   CResult<CTransitionResult> ApplyTransition(const IBasketReadModel &basket,
                                                const CDomainEvent &domainEvent) const
     {
      return EvaluateTransition(basket,domainEvent);
     }
  };

#endif
