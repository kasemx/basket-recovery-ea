#ifndef BRE_DOMAIN_RECOVERY_DECISION_RISK_GATE_RESULT_MQH
#define BRE_DOMAIN_RECOVERY_DECISION_RISK_GATE_RESULT_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RecoveryRiskDecisionAudit.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlan.mqh>

class CRecoveryDecisionRiskGateResult
  {
private:
   CRecoveryRiskDecisionAudit    m_audit;
   CRiskReductionPlan            m_reductionPlan;
   bool                          m_hasReductionSuggestion;

public:
                     CRecoveryDecisionRiskGateResult(void)
     {
      m_hasReductionSuggestion=false;
     }

   CRecoveryRiskDecisionAudit    Audit(void) const { return m_audit; }
   CRiskReductionPlan            ReductionPlan(void) const { return m_reductionPlan; }
   bool                          HasReductionSuggestion(void) const { return m_hasReductionSuggestion; }
   bool                          Allowed(void) const { return m_audit.Allowed(); }

   static CRecoveryDecisionRiskGateResult Allowed(const CRecoveryRiskDecisionAudit &audit,
                                                  const CRiskReductionPlan &reductionPlan,
                                                  const bool suggestReduction)
     {
      CRecoveryDecisionRiskGateResult result;
      result.m_audit=audit;
      result.m_reductionPlan=reductionPlan;
      result.m_hasReductionSuggestion=suggestReduction && reductionPlan.HasPlan();
      return result;
     }

   static CRecoveryDecisionRiskGateResult Blocked(const CRecoveryRiskDecisionAudit &audit,
                                                  const CRiskReductionPlan &reductionPlan)
     {
      CRecoveryDecisionRiskGateResult result;
      result.m_audit=audit;
      result.m_reductionPlan=reductionPlan;
      result.m_hasReductionSuggestion=false;
      return result;
     }
  };

#endif
