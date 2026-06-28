#ifndef BRE_DOMAIN_RISK_REDUCTION_PLAN_MQH
#define BRE_DOMAIN_RISK_REDUCTION_PLAN_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlanEntry.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CRiskReductionPlan
  {
private:
   bool                          m_hasPlan;
   double                        m_currentRiskMoney;
   double                        m_targetRiskMoney;
   double                        m_requiredReductionMoney;
   ENUM_BRE_RISK_REDUCTION_MODE  m_closeOrder;
   CRiskReductionPlanEntry       m_entries[];
   int                           m_entryCount;

public:
                     CRiskReductionPlan(void)
     {
      m_hasPlan=false;
      m_currentRiskMoney=0.0;
      m_targetRiskMoney=0.0;
      m_requiredReductionMoney=0.0;
      m_closeOrder=BRE_RISK_REDUCTION_MODE_WORST_ENTRY;
      m_entryCount=0;
     }

   bool              HasPlan(void) const { return m_hasPlan; }
   double            CurrentRiskMoney(void) const { return m_currentRiskMoney; }
   double            TargetRiskMoney(void) const { return m_targetRiskMoney; }
   double            RequiredReductionMoney(void) const { return m_requiredReductionMoney; }
   ENUM_BRE_RISK_REDUCTION_MODE CloseOrder(void) const { return m_closeOrder; }
   int               EntryCount(void) const { return m_entryCount; }

   CRiskReductionPlanEntry EntryAt(const int index) const
     {
      if(index<0 || index>=m_entryCount)
         return CRiskReductionPlanEntry::Create(0,0.0,0.0);
      return m_entries[index];
     }

   static CRiskReductionPlan CreateEmpty(void)
     {
      CRiskReductionPlan plan;
      return plan;
     }

   static CRiskReductionPlan Create(const double currentRiskMoney,
                                    const double targetRiskMoney,
                                    const ENUM_BRE_RISK_REDUCTION_MODE closeOrder,
                                    const CRiskReductionPlanEntry &entries[],
                                    const int entryCount)
     {
      CRiskReductionPlan plan;
      plan.m_hasPlan=entryCount>0;
      plan.m_currentRiskMoney=currentRiskMoney;
      plan.m_targetRiskMoney=targetRiskMoney;
      plan.m_requiredReductionMoney=MathMax(0.0,currentRiskMoney-targetRiskMoney);
      plan.m_closeOrder=closeOrder;
      plan.m_entryCount=entryCount;
      ArrayResize(plan.m_entries,entryCount);
      for(int i=0;i<entryCount;i++)
         plan.m_entries[i]=entries[i];
      return plan;
     }
  };

#endif
