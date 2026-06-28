#ifndef BRE_DOMAIN_STRATEGY_RISK_EVALUATION_CONTEXT_MQH
#define BRE_DOMAIN_STRATEGY_RISK_EVALUATION_CONTEXT_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlan.mqh>
#include <BasketRecovery/Domain/Risk/Enums/RiskSafetyStatus.mqh>

class CStrategyRiskEvaluationContext
  {
private:
   CRiskLimitProfile               m_riskProfile;
   CBasketRiskSnapshot             m_basketRiskSnapshot;
   ENUM_BRE_RISK_SAFETY_STATUS     m_dataQualityState;
   double                          m_basketStopLoss;
   ulong                           m_quoteSequence;
   bool                            m_unresolvedPendingExecution;
   CRiskReductionPlan              m_reductionPlan;
   bool                            m_hasReductionPlan;
   bool                            m_populated;

public:
                     CStrategyRiskEvaluationContext(void)
     {
      m_dataQualityState=BRE_RISK_SAFETY_UNKNOWN;
      m_basketStopLoss=0.0;
      m_quoteSequence=0;
      m_unresolvedPendingExecution=false;
      m_hasReductionPlan=false;
      m_populated=false;
     }

   bool              IsPopulated(void) const { return m_populated; }
   CRiskLimitProfile RiskProfile(void) const { return m_riskProfile; }
   CBasketRiskSnapshot BasketRiskSnapshot(void) const { return m_basketRiskSnapshot; }
   ENUM_BRE_RISK_SAFETY_STATUS DataQualityState(void) const { return m_dataQualityState; }
   double            BasketStopLoss(void) const { return m_basketStopLoss; }
   ulong             QuoteSequence(void) const { return m_quoteSequence; }
   bool              UnresolvedPendingExecution(void) const { return m_unresolvedPendingExecution; }
   bool              HasReductionPlan(void) const { return m_hasReductionPlan; }
   CRiskReductionPlan ReductionPlan(void) const { return m_reductionPlan; }

   static CStrategyRiskEvaluationContext Create(const CRiskLimitProfile &riskProfile,
                                                const CBasketRiskSnapshot &snapshot,
                                                const double basketStopLoss,
                                                const ulong quoteSequence,
                                                const bool unresolvedPendingExecution,
                                                const CRiskReductionPlan &reductionPlan,
                                                const bool hasReductionPlan)
     {
      CStrategyRiskEvaluationContext context;
      context.m_riskProfile=riskProfile;
      context.m_basketRiskSnapshot=snapshot;
      context.m_dataQualityState=snapshot.SafetyStatus();
      context.m_basketStopLoss=basketStopLoss;
      context.m_quoteSequence=quoteSequence;
      context.m_unresolvedPendingExecution=unresolvedPendingExecution;
      context.m_reductionPlan=reductionPlan;
      context.m_hasReductionPlan=hasReductionPlan;
      context.m_populated=true;
      return context;
     }

   static CStrategyRiskEvaluationContext Empty(void)
     {
      CStrategyRiskEvaluationContext context;
      context.m_populated=false;
      return context;
     }
  };

#endif
