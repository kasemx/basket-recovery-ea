#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_PLAN_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_BREAK_EVEN_PLAN_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenRule.mqh>

class CBreakEvenPlan
  {
private:
   CBreakEvenRule m_rules[];

                     CBreakEvenPlan(void) {}

public:
   int            RuleCount(void) const { return ArraySize(m_rules); }

   CBreakEvenRule RuleAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_rules))
        {
         CBreakEvenTrigger emptyTrigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_NONE,0.0,false,0.0,false,0.0,false,"","","","");
         CBreakEvenAction emptyActions[];
         ArrayResize(emptyActions,0);
         return CBreakEvenRule::Create("",false,0,true,emptyTrigger,emptyActions,0);
        }
      return m_rules[index];
     }

   static CBreakEvenPlan Create(const CBreakEvenRule &rules[],const int ruleCount)
     {
      CBreakEvenPlan plan;
      ArrayResize(plan.m_rules,ruleCount);
      for(int i=0;i<ruleCount;i++)
         plan.m_rules[i]=rules[i];
      return plan;
     }
  };

#endif
