#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_DECISION_SET_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_DECISION_SET_MQH

#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecision.mqh>

class CStrategyDecisionSet
  {
private:
   CStrategyDecision m_decisions[];

   bool              ContainsKey(const string idempotencyKey) const
     {
      if(idempotencyKey=="")
         return false;
      for(int i=0;i<ArraySize(m_decisions);i++)
        {
         if(m_decisions[i].IdempotencyKey()==idempotencyKey)
            return true;
        }
      return false;
     }

public:
   int               Count(void) const { return ArraySize(m_decisions); }

   CStrategyDecision DecisionAt(const int index) const
     {
      if(index<0 || index>=ArraySize(m_decisions))
        {
         CNoActionDecision empty=CNoActionDecision::Create("","");
         return CStrategyDecision::FromNoAction(empty);
        }
      return m_decisions[index];
     }

   bool              Add(const CStrategyDecision &decision)
     {
      string key=decision.IdempotencyKey();
      if(key!="" && ContainsKey(key))
         return false;
      int nextIndex=ArraySize(m_decisions);
      ArrayResize(m_decisions,nextIndex+1);
      m_decisions[nextIndex]=decision;
      return true;
     }

   void              Merge(const CStrategyDecisionSet &other)
     {
      for(int i=0;i<other.Count();i++)
         Add(other.DecisionAt(i));
     }

   static CStrategyDecisionSet Create(void)
     {
      CStrategyDecisionSet set;
      ArrayResize(set.m_decisions,0);
      return set;
     }
  };

#endif
