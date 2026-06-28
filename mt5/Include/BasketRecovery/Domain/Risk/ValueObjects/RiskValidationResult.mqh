#ifndef BRE_DOMAIN_RISK_VALIDATION_RESULT_MQH
#define BRE_DOMAIN_RISK_VALIDATION_RESULT_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskViolationReason.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/ProjectedBasketRisk.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlan.mqh>

class CRiskValidationResult
  {
private:
   bool                          m_allowed;
   ENUM_BRE_RISK_VIOLATION_REASON m_reason;
   string                        m_detail;
   CBasketRiskSnapshot           m_currentRisk;
   CProjectedBasketRisk          m_projectedRisk;
   CRiskReductionPlan            m_reductionPlan;

public:
                     CRiskValidationResult(void)
     {
      m_allowed=false;
      m_reason=BRE_RISK_VIOLATION_NONE;
     }

   bool              Allowed(void) const { return m_allowed; }
   ENUM_BRE_RISK_VIOLATION_REASON Reason(void) const { return m_reason; }
   string            Detail(void) const { return m_detail; }
   CBasketRiskSnapshot CurrentRisk(void) const { return m_currentRisk; }
   CProjectedBasketRisk ProjectedRisk(void) const { return m_projectedRisk; }
   CRiskReductionPlan ReductionPlan(void) const { return m_reductionPlan; }

   static CRiskValidationResult AllowedResult(const CBasketRiskSnapshot &current,
                                              const CProjectedBasketRisk &projected,
                                              const CRiskReductionPlan &reductionPlan)
     {
      CRiskValidationResult result;
      result.m_allowed=true;
      result.m_reason=BRE_RISK_VIOLATION_NONE;
      result.m_currentRisk=current;
      result.m_projectedRisk=projected;
      result.m_reductionPlan=reductionPlan;
      return result;
     }

   static CRiskValidationResult Rejected(const ENUM_BRE_RISK_VIOLATION_REASON reason,
                                         const string detail,
                                         const CBasketRiskSnapshot &current,
                                         const CProjectedBasketRisk &projected,
                                         const CRiskReductionPlan &reductionPlan)
     {
      CRiskValidationResult result;
      result.m_allowed=false;
      result.m_reason=reason;
      result.m_detail=detail;
      result.m_currentRisk=current;
      result.m_projectedRisk=projected;
      result.m_reductionPlan=reductionPlan;
      return result;
     }
  };

#endif
