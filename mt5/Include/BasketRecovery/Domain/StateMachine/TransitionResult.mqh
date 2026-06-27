#ifndef BASKET_RECOVERY_DOMAIN_TRANSITION_RESULT_MQH
#define BASKET_RECOVERY_DOMAIN_TRANSITION_RESULT_MQH

#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CTransitionResult
  {
private:
   bool                            m_applied;
   ENUM_BRE_BASKET_LIFECYCLE_STATE m_previousState;
   ENUM_BRE_BASKET_LIFECYCLE_STATE m_newState;
   ENUM_BRE_EVENT_TYPE             m_triggerEvent;
   string                          m_ruleId;
   string                          m_rejectionReason;
   int                             m_errorCode;

public:
                     CTransitionResult(void)
     {
      m_applied=false;
      m_previousState=BRE_STATE_NONE;
      m_newState=BRE_STATE_NONE;
      m_triggerEvent=BRE_EVENT_NONE;
      m_ruleId="";
      m_rejectionReason="";
      m_errorCode=0;
     }

   bool                            Applied(void) const { return m_applied; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE PreviousState(void) const { return m_previousState; }
   ENUM_BRE_BASKET_LIFECYCLE_STATE NewState(void) const { return m_newState; }
   ENUM_BRE_EVENT_TYPE             TriggerEvent(void) const { return m_triggerEvent; }
   string                          RuleId(void) const { return m_ruleId; }
   string                          RejectionReason(void) const { return m_rejectionReason; }
   int                             ErrorCode(void) const { return m_errorCode; }

   void                            SetApplied(const bool value) { m_applied=value; }
   void                            SetPreviousState(const ENUM_BRE_BASKET_LIFECYCLE_STATE value) { m_previousState=value; }
   void                            SetNewState(const ENUM_BRE_BASKET_LIFECYCLE_STATE value) { m_newState=value; }
   void                            SetTriggerEvent(const ENUM_BRE_EVENT_TYPE value) { m_triggerEvent=value; }
   void                            SetRuleId(const string value) { m_ruleId=value; }
   void                            SetRejectionReason(const string value) { m_rejectionReason=value; }
   void                            SetErrorCode(const int value) { m_errorCode=value; }

   static CTransitionResult        Rejected(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                            const ENUM_BRE_EVENT_TYPE triggerEvent,
                                            const string reason,
                                            const int errorCode)
     {
      CTransitionResult result;
      result.m_applied=false;
      result.m_previousState=currentState;
      result.m_newState=currentState;
      result.m_triggerEvent=triggerEvent;
      result.m_rejectionReason=reason;
      result.m_errorCode=errorCode;
      return result;
     }

   static CTransitionResult        Applied(const ENUM_BRE_BASKET_LIFECYCLE_STATE previousState,
                                           const ENUM_BRE_BASKET_LIFECYCLE_STATE newState,
                                           const ENUM_BRE_EVENT_TYPE triggerEvent,
                                           const string ruleId)
     {
      CTransitionResult result;
      result.m_applied=true;
      result.m_previousState=previousState;
      result.m_newState=newState;
      result.m_triggerEvent=triggerEvent;
      result.m_ruleId=ruleId;
      result.m_errorCode=0;
      return result;
     }
  };

#endif
