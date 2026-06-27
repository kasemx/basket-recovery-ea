#ifndef BASKET_RECOVERY_DOMAIN_TRANSITION_RULE_MQH
#define BASKET_RECOVERY_DOMAIN_TRANSITION_RULE_MQH

#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>
#include <BasketRecovery/Domain/StateMachine/ITransitionGuard.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CTransitionRule
  {
private:
   string                          m_ruleId;
   ENUM_BRE_BASKET_LIFECYCLE_STATE m_currentState;
   ENUM_BRE_EVENT_TYPE             m_allowedEvent;
   ENUM_BRE_BASKET_LIFECYCLE_STATE m_nextState;
   ITransitionGuard               *m_guard;
   int                             m_priority;
   int                             m_errorCode;
   string                          m_description;

public:
                     CTransitionRule(void)
     {
      m_ruleId="";
      m_currentState=BRE_STATE_NONE;
      m_allowedEvent=BRE_EVENT_NONE;
      m_nextState=BRE_STATE_NONE;
      m_guard=NULL;
      m_priority=0;
      m_errorCode=BRE_ERR_TRANSITION_INVALID;
      m_description="";
     }

   string                          RuleId(void) const { return m_ruleId; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE CurrentState(void) const { return m_currentState; }
   ENUM_BRE_EVENT_TYPE             AllowedEvent(void) const { return m_allowedEvent; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE NextState(void) const { return m_nextState; }
   ITransitionGuard*               Guard(void) const { return m_guard; }
   int                             Priority(void) const { return m_priority; }
   int                             ErrorCode(void) const { return m_errorCode; }
   string                          Description(void) const { return m_description; }

   void                            SetRuleId(const string value) { m_ruleId=value; }
   void                            SetCurrentState(const ENUM_BRE_BASKET_LIFECYCLE_STATE value) { m_currentState=value; }
   void                            SetAllowedEvent(const ENUM_BRE_EVENT_TYPE value) { m_allowedEvent=value; }
   void                            SetNextState(const ENUM_BRE_BASKET_LIFECYCLE_STATE value) { m_nextState=value; }
   void                            SetGuard(ITransitionGuard *guard) { m_guard=guard; }
   void                            SetPriority(const int value) { m_priority=value; }
   void                            SetErrorCode(const int value) { m_errorCode=value; }
   void                            SetDescription(const string value) { m_description=value; }

   bool                            EvaluateGuard(const IBasketReadModel &basket,const CDomainEvent &domainEvent) const
     {
      if(m_guard==NULL)
         return true;
      return m_guard.Evaluate(basket,domainEvent);
     }
  };

#endif
