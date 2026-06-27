#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_PLAN_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_PLAN_MQH

#include <BasketRecovery/Domain/Strategy/Enums/ExecutionZoneExpansionMode.mqh>

class CRiskPlan
  {
private:
   double                      m_targetRiskPct;
   double                      m_maxRiskPct;
   double                      m_riskReductionThresholdPct;
   bool                        m_hasRiskReductionThreshold;
   ENUM_BRE_RISK_REDUCTION_MODE m_riskReductionMode;
   double                      m_accountRiskCapPct;
   bool                        m_hasAccountRiskCap;
   int                         m_waitDetailsTimeoutMinutes;
   int                         m_riskEvalDebounceMs;

                     CRiskPlan(void) {}

public:
   double                      TargetRiskPct(void) const { return m_targetRiskPct; }
   double                      MaxRiskPct(void) const { return m_maxRiskPct; }
   bool                        HasRiskReductionThreshold(void) const { return m_hasRiskReductionThreshold; }
   double                      RiskReductionThresholdPct(void) const { return m_riskReductionThresholdPct; }
   ENUM_BRE_RISK_REDUCTION_MODE RiskReductionMode(void) const { return m_riskReductionMode; }
   bool                        HasAccountRiskCap(void) const { return m_hasAccountRiskCap; }
   double                      AccountRiskCapPct(void) const { return m_accountRiskCapPct; }
   int                         WaitDetailsTimeoutMinutes(void) const { return m_waitDetailsTimeoutMinutes; }
   int                         RiskEvalDebounceMs(void) const { return m_riskEvalDebounceMs; }

   static CRiskPlan            Create(const double targetRiskPct,
                                      const double maxRiskPct,
                                      const double riskReductionThresholdPct,
                                      const bool hasRiskReductionThreshold,
                                      const ENUM_BRE_RISK_REDUCTION_MODE riskReductionMode,
                                      const double accountRiskCapPct,
                                      const bool hasAccountRiskCap,
                                      const int waitDetailsTimeoutMinutes,
                                      const int riskEvalDebounceMs)
     {
      CRiskPlan plan;
      plan.m_targetRiskPct=targetRiskPct;
      plan.m_maxRiskPct=maxRiskPct;
      plan.m_riskReductionThresholdPct=riskReductionThresholdPct;
      plan.m_hasRiskReductionThreshold=hasRiskReductionThreshold;
      plan.m_riskReductionMode=riskReductionMode;
      plan.m_accountRiskCapPct=accountRiskCapPct;
      plan.m_hasAccountRiskCap=hasAccountRiskCap;
      plan.m_waitDetailsTimeoutMinutes=waitDetailsTimeoutMinutes;
      plan.m_riskEvalDebounceMs=riskEvalDebounceMs;
      return plan;
     }
  };

#endif
