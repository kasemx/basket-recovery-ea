#ifndef BRE_DOMAIN_RISK_LIMIT_PROFILE_MQH
#define BRE_DOMAIN_RISK_LIMIT_PROFILE_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitValue.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPolicy.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>

class CRiskLimitProfile
  {
private:
   string               m_profileBindingId;
   CRiskLimitValue      m_targetRisk;
   CRiskLimitValue      m_maxRisk;
   CRiskReductionPolicy m_reductionPolicy;

public:
                     CRiskLimitProfile(void) {}

   string            ProfileBindingId(void) const { return m_profileBindingId; }
   CRiskLimitValue   TargetRisk(void) const { return m_targetRisk; }
   CRiskLimitValue   MaxRisk(void) const { return m_maxRisk; }
   CRiskReductionPolicy ReductionPolicy(void) const { return m_reductionPolicy; }

   static CRiskLimitProfile Create(const string profileBindingId,
                                   const CRiskLimitValue &targetRisk,
                                   const CRiskLimitValue &maxRisk,
                                   const CRiskReductionPolicy &reductionPolicy)
     {
      CRiskLimitProfile profile;
      profile.m_profileBindingId=profileBindingId;
      profile.m_targetRisk=targetRisk;
      profile.m_maxRisk=maxRisk;
      profile.m_reductionPolicy=reductionPolicy;
      return profile;
     }

   static CRiskLimitProfile FromRiskPlan(const string profileBindingId,const CRiskPlan &plan)
     {
      CRiskReductionPolicy reduction=CRiskReductionPolicy::Create(true,
                                                                  BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK,
                                                                  plan.RiskReductionMode(),
                                                                  true);
      return Create(profileBindingId,
                    CRiskLimitValue::PercentEquity(plan.TargetRiskPct()),
                    CRiskLimitValue::PercentEquity(plan.MaxRiskPct()),
                    reduction);
     }
  };

#endif
