#ifndef BRE_DOMAIN_RISK_REDUCTION_POLICY_MQH
#define BRE_DOMAIN_RISK_REDUCTION_POLICY_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskReductionTrigger.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CRiskReductionPolicy
  {
private:
   bool                          m_enabled;
   ENUM_BRE_RISK_REDUCTION_TRIGGER m_trigger;
   ENUM_BRE_RISK_REDUCTION_MODE  m_closeOrder;
   bool                          m_targetAfterReductionIsTargetRisk;

public:
                     CRiskReductionPolicy(void)
     {
      m_enabled=true;
      m_trigger=BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK;
      m_closeOrder=BRE_RISK_REDUCTION_MODE_WORST_ENTRY;
      m_targetAfterReductionIsTargetRisk=true;
     }

   bool              Enabled(void) const { return m_enabled; }
   ENUM_BRE_RISK_REDUCTION_TRIGGER Trigger(void) const { return m_trigger; }
   ENUM_BRE_RISK_REDUCTION_MODE CloseOrder(void) const { return m_closeOrder; }
   bool              TargetAfterReductionIsTargetRisk(void) const { return m_targetAfterReductionIsTargetRisk; }

   static CRiskReductionPolicy Create(const bool enabled,
                                      const ENUM_BRE_RISK_REDUCTION_TRIGGER trigger,
                                      const ENUM_BRE_RISK_REDUCTION_MODE closeOrder,
                                      const bool targetAfterReductionIsTargetRisk)
     {
      CRiskReductionPolicy policy;
      policy.m_enabled=enabled;
      policy.m_trigger=trigger;
      policy.m_closeOrder=closeOrder;
      policy.m_targetAfterReductionIsTargetRisk=targetAfterReductionIsTargetRisk;
      return policy;
     }
  };

#endif
