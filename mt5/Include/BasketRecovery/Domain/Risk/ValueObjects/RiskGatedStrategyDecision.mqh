#ifndef BRE_DOMAIN_RISK_GATED_STRATEGY_DECISION_MQH
#define BRE_DOMAIN_RISK_GATED_STRATEGY_DECISION_MQH

#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecision.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RecoveryDecisionRiskGateResult.mqh>

class CRiskGatedStrategyDecision
  {
private:
   CStrategyDecision                 m_decision;
   CRecoveryDecisionRiskGateResult   m_gateResult;
   bool                              m_hasGateResult;

public:
                     CRiskGatedStrategyDecision(void)
     {
      m_hasGateResult=false;
     }

   CStrategyDecision                 Decision(void) const { return m_decision; }
   bool                              HasGateResult(void) const { return m_hasGateResult; }
   CRecoveryDecisionRiskGateResult   GateResult(void) const { return m_gateResult; }
   bool                              Allowed(void) const { return !m_hasGateResult || m_gateResult.Allowed(); }

   static CRiskGatedStrategyDecision PassThrough(const CStrategyDecision &decision)
     {
      CRiskGatedStrategyDecision gated;
      gated.m_decision=decision;
      gated.m_hasGateResult=false;
      return gated;
     }

   static CRiskGatedStrategyDecision FromRecoveryGate(const CStrategyDecision &decision,
                                                      const CRecoveryDecisionRiskGateResult &gateResult)
     {
      CRiskGatedStrategyDecision gated;
      gated.m_decision=decision;
      gated.m_gateResult=gateResult;
      gated.m_hasGateResult=true;
      return gated;
     }
  };

#endif
