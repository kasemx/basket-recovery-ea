#ifndef BASKET_RECOVERY_APPLICATION_TRANSITION_RULE_REGISTRY_MQH
#define BASKET_RECOVERY_APPLICATION_TRANSITION_RULE_REGISTRY_MQH

#include <BasketRecovery/Domain/StateMachine/ITransitionRuleRegistry.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

struct SRejectedTransitionEvent
  {
   ENUM_BRE_BASKET_LIFECYCLE_STATE state;
   ENUM_BRE_EVENT_TYPE             eventType;
  };

class CTransitionRuleRegistry : public ITransitionRuleRegistry
  {
private:
   CTransitionRule            m_rules[];
   int                        m_count;
   SRejectedTransitionEvent   m_rejected[];
   int                        m_rejectedCount;

   bool IsTerminalState(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      return state==BRE_STATE_FINISHED || state==BRE_STATE_ERROR;
     }

   bool HasDuplicateRule(const CTransitionRule &rule) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_rules[i].CurrentState()==rule.CurrentState() &&
            m_rules[i].AllowedEvent()==rule.AllowedEvent())
            return true;
        }
      return false;
     }

   bool HasOutboundRule(const ENUM_BRE_BASKET_LIFECYCLE_STATE state) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_rules[i].CurrentState()==state)
            return true;
        }
      return false;
     }

   bool IsStateInSet(const ENUM_BRE_BASKET_LIFECYCLE_STATE state,
                     const ENUM_BRE_BASKET_LIFECYCLE_STATE &states[],
                     const int stateCount) const
     {
      for(int i=0;i<stateCount;i++)
        {
         if(states[i]==state)
            return true;
        }
      return false;
     }

   void MarkReachable(const ENUM_BRE_BASKET_LIFECYCLE_STATE state,
                      ENUM_BRE_BASKET_LIFECYCLE_STATE &reachable[],
                      int &reachableCount) const
     {
      if(IsStateInSet(state,reachable,reachableCount))
         return;

      ArrayResize(reachable,reachableCount+1);
      reachable[reachableCount]=state;
      reachableCount++;

      for(int i=0;i<m_count;i++)
        {
         if(m_rules[i].CurrentState()==state)
            MarkReachable(m_rules[i].NextState(),reachable,reachableCount);
        }
     }

   CVoidResult ValidateDuplicates(void) const
     {
      for(int i=0;i<m_count;i++)
        {
         for(int j=i+1;j<m_count;j++)
           {
            if(m_rules[i].CurrentState()==m_rules[j].CurrentState() &&
               m_rules[i].AllowedEvent()==m_rules[j].AllowedEvent())
               return CVoidResult::Fail(BRE_ERR_TRANSITION_DUPLICATE,
                                        StringFormat("Duplicate rule for state=%d event=%d",
                                                     m_rules[i].CurrentState(),
                                                     m_rules[i].AllowedEvent()));
           }
        }
      return CVoidResult::Ok();
     }

   CVoidResult ValidateDeadEnds(void) const
     {
      ENUM_BRE_BASKET_LIFECYCLE_STATE allStates[]=
        {
         BRE_STATE_PENDING_OPEN,BRE_STATE_WAIT_DETAILS,BRE_STATE_ACTIVE,
         BRE_STATE_CLOSING,BRE_STATE_SUSPENDED
        };

      for(int i=0;i<ArraySize(allStates);i++)
        {
         if(!HasOutboundRule(allStates[i]))
            return CVoidResult::Fail(BRE_ERR_TRANSITION_DEAD_END,
                                     StringFormat("Dead-end state without outbound rules: %d",allStates[i]));
        }
      return CVoidResult::Ok();
     }

   CVoidResult ValidateReachability(void) const
     {
      ENUM_BRE_BASKET_LIFECYCLE_STATE reachable[];
      int reachableCount=0;
      MarkReachable(BRE_STATE_PENDING_OPEN,reachable,reachableCount);

      ENUM_BRE_BASKET_LIFECYCLE_STATE requiredStates[]=
        {
         BRE_STATE_PENDING_OPEN,BRE_STATE_WAIT_DETAILS,BRE_STATE_ACTIVE,
         BRE_STATE_CLOSING,BRE_STATE_SUSPENDED,BRE_STATE_FINISHED,BRE_STATE_ERROR
        };

      for(int i=0;i<ArraySize(requiredStates);i++)
        {
         if(!IsStateInSet(requiredStates[i],reachable,reachableCount))
            return CVoidResult::Fail(BRE_ERR_TRANSITION_UNREACHABLE,
                                     StringFormat("Unreachable lifecycle state: %d",requiredStates[i]));
        }
      return CVoidResult::Ok();
     }

   CVoidResult ValidateTerminalStates(void) const
     {
      if(HasOutboundRule(BRE_STATE_FINISHED))
         return CVoidResult::Fail(BRE_ERR_TRANSITION_INVALID,"FINISHED must not have outbound rules");
      if(HasOutboundRule(BRE_STATE_ERROR))
         return CVoidResult::Fail(BRE_ERR_TRANSITION_INVALID,"ERROR must not have outbound rules");
      return CVoidResult::Ok();
     }

public:
                     CTransitionRuleRegistry(void)
     {
      m_count=0;
      m_rejectedCount=0;
      ArrayResize(m_rules,0);
      ArrayResize(m_rejected,0);
     }

   virtual          ~CTransitionRuleRegistry(void) {}

   virtual CVoidResult RegisterRule(const CTransitionRule &rule)
     {
      if(HasDuplicateRule(rule))
         return CVoidResult::Fail(BRE_ERR_TRANSITION_DUPLICATE,"Rule already registered for state/event pair");

      ArrayResize(m_rules,m_count+1);
      m_rules[m_count]=rule;
      m_count++;
      return CVoidResult::Ok();
     }

   virtual CVoidResult RegisterRejectedEvent(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                             const ENUM_BRE_EVENT_TYPE eventType)
     {
      for(int i=0;i<m_rejectedCount;i++)
        {
         if(m_rejected[i].state==currentState && m_rejected[i].eventType==eventType)
            return CVoidResult::Ok();
        }

      ArrayResize(m_rejected,m_rejectedCount+1);
      m_rejected[m_rejectedCount].state=currentState;
      m_rejected[m_rejectedCount].eventType=eventType;
      m_rejectedCount++;
      return CVoidResult::Ok();
     }

   virtual bool      FindRule(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                              const ENUM_BRE_EVENT_TYPE allowedEvent,
                              CTransitionRule &outRule) const
     {
      bool found=false;
      int bestPriority=-1;

      for(int i=0;i<m_count;i++)
        {
         if(m_rules[i].CurrentState()==currentState && m_rules[i].AllowedEvent()==allowedEvent)
           {
            if(!found || m_rules[i].Priority()>bestPriority)
              {
               outRule=m_rules[i];
               bestPriority=m_rules[i].Priority();
               found=true;
              }
           }
        }
      return found;
     }

   virtual bool      IsRejectedEvent(const ENUM_BRE_BASKET_LIFECYCLE_STATE currentState,
                                     const ENUM_BRE_EVENT_TYPE eventType) const
     {
      if(IsTerminalState(currentState) && eventType!=BRE_EVENT_NONE)
         return true;

      for(int i=0;i<m_rejectedCount;i++)
        {
         if(m_rejected[i].state==currentState && m_rejected[i].eventType==eventType)
            return true;
        }
      return false;
     }

   virtual CVoidResult Validate(void) const
     {
      if(m_count==0)
         return CVoidResult::Fail(BRE_ERR_TRANSITION_INVALID,"Transition rule table is empty");

      CVoidResult duplicateCheck=ValidateDuplicates();
      if(duplicateCheck.IsFail())
         return duplicateCheck;

      CVoidResult terminalCheck=ValidateTerminalStates();
      if(terminalCheck.IsFail())
         return terminalCheck;

      CVoidResult deadEndCheck=ValidateDeadEnds();
      if(deadEndCheck.IsFail())
         return deadEndCheck;

      CVoidResult reachabilityCheck=ValidateReachability();
      if(reachabilityCheck.IsFail())
         return reachabilityCheck;

      return CVoidResult::Ok();
     }

   virtual string    ExportTable(void) const
     {
      string table="TransitionRuleTable\n";
      for(int i=0;i<m_count;i++)
        {
         table+=StringFormat("%s|%s+%s->%s|priority=%d|error=%d|%s\n",
                             m_rules[i].RuleId(),
                             CBasketLifecycleStateHelper::ToString(m_rules[i].CurrentState()),
                             CEventTypeHelper::ToString(m_rules[i].AllowedEvent()),
                             CBasketLifecycleStateHelper::ToString(m_rules[i].NextState()),
                             m_rules[i].Priority(),
                             m_rules[i].ErrorCode(),
                             m_rules[i].Description());
        }
      return table;
     }

   virtual int       RuleCount(void) const { return m_count; }

   virtual bool      GetRuleAt(const int index,CTransitionRule &outRule) const
     {
      if(index<0 || index>=m_count)
         return false;
      outRule=m_rules[index];
      return true;
     }
  };

#endif
