#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_RUNTIME_CONTEXT_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_RISK_RUNTIME_CONTEXT_MQH

class CRiskRuntimeContext
  {
private:
   double m_currentRiskPct;
   double m_targetRiskPct;
   double m_maxRiskPct;
   double m_realizedProfitUsd;
   bool   m_canOpenRecovery;
   bool   m_targetRiskReached;

public:
                     CRiskRuntimeContext(void) {}

                     CRiskRuntimeContext(const CRiskRuntimeContext &other)
     {
      m_currentRiskPct=other.m_currentRiskPct;
      m_targetRiskPct=other.m_targetRiskPct;
      m_maxRiskPct=other.m_maxRiskPct;
      m_realizedProfitUsd=other.m_realizedProfitUsd;
      m_canOpenRecovery=other.m_canOpenRecovery;
      m_targetRiskReached=other.m_targetRiskReached;
     }

   double            CurrentRiskPct(void) const { return m_currentRiskPct; }
   double            TargetRiskPct(void) const { return m_targetRiskPct; }
   double            MaxRiskPct(void) const { return m_maxRiskPct; }
   double            RealizedProfitUsd(void) const { return m_realizedProfitUsd; }
   bool              CanOpenRecovery(void) const { return m_canOpenRecovery; }
   bool              TargetRiskReached(void) const { return m_targetRiskReached; }

   static CRiskRuntimeContext Create(const double currentRiskPct,
                                     const double targetRiskPct,
                                     const double maxRiskPct,
                                     const double realizedProfitUsd,
                                     const bool canOpenRecovery,
                                     const bool targetRiskReached)
     {
      CRiskRuntimeContext context;
      context.m_currentRiskPct=currentRiskPct;
      context.m_targetRiskPct=targetRiskPct;
      context.m_maxRiskPct=maxRiskPct;
      context.m_realizedProfitUsd=realizedProfitUsd;
      context.m_canOpenRecovery=canOpenRecovery;
      context.m_targetRiskReached=targetRiskReached;
      return context;
     }
  };

#endif
