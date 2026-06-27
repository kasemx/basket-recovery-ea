#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_RULE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_RULE_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenTrigger.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenAction.mqh>

class CBreakEvenRule
  {
private:
   string            m_ruleId;
   bool              m_enabled;
   int               m_priority;
   bool              m_runOnce;
   CBreakEvenTrigger m_trigger;
   CBreakEvenAction  m_actions[];

public:
                     CBreakEvenRule(void) {}

                     CBreakEvenRule(const CBreakEvenRule &other)
     {
      m_ruleId=other.m_ruleId;
      m_enabled=other.m_enabled;
      m_priority=other.m_priority;
      m_runOnce=other.m_runOnce;
      m_trigger=other.m_trigger;
      int actionCount=ArraySize(other.m_actions);
      ArrayResize(m_actions,actionCount);
      for(int i=0;i<actionCount;i++)
         m_actions[i]=other.m_actions[i];
     }

   string            RuleId(void) const { return m_ruleId; }
   bool              Enabled(void) const { return m_enabled; }
   int               Priority(void) const { return m_priority; }
   bool              RunOnce(void) const { return m_runOnce; }
   CBreakEvenTrigger Trigger(void) const { return m_trigger; }
   int               ActionCount(void) const { return ArraySize(m_actions); }

   CBreakEvenAction  ActionAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_actions))
         return CBreakEvenAction::Create(BRE_BE_ACTION_NONE,0.0,0.0,false,false);
      return m_actions[index];
     }

   static CBreakEvenRule Create(const string ruleId,
                                const bool enabled,
                                const int priority,
                                const bool runOnce,
                                const CBreakEvenTrigger &trigger,
                                const CBreakEvenAction &actions[],
                                const int actionCount)
     {
      CBreakEvenRule rule;
      rule.m_ruleId=ruleId;
      rule.m_enabled=enabled;
      rule.m_priority=priority;
      rule.m_runOnce=runOnce;
      rule.m_trigger=trigger;
      ArrayResize(rule.m_actions,actionCount);
      for(int i=0;i<actionCount;i++)
         rule.m_actions[i]=actions[i];
      return rule;
     }
  };

#endif
