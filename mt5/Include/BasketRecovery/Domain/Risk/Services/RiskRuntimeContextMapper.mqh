#ifndef BRE_DOMAIN_RISK_RUNTIME_CONTEXT_MAPPER_MQH
#define BRE_DOMAIN_RISK_RUNTIME_CONTEXT_MAPPER_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>

class CRiskRuntimeContextMapper
  {
public:
   static CRiskRuntimeContext FromBasketRiskSnapshot(const CBasketRiskSnapshot &snapshot,
                                                     const double realizedProfitUsd,
                                                     const bool recoveryPermanentlyDisabled)
     {
      double currentRiskPct=0.0;
      if(snapshot.IsSafe() && snapshot.AccountEquity()>0.0)
         currentRiskPct=(snapshot.CurrentSlRiskMoney()/snapshot.AccountEquity())*100.0;

      double targetPct=0.0;
      double maxPct=0.0;
      if(snapshot.AccountEquity()>0.0)
        {
         targetPct=(snapshot.TargetRiskMoney()/snapshot.AccountEquity())*100.0;
         maxPct=(snapshot.MaxRiskMoney()/snapshot.AccountEquity())*100.0;
        }

      bool canOpenRecovery=snapshot.IsSafe() &&
                           !recoveryPermanentlyDisabled &&
                           !snapshot.AtOrAboveMaxRisk();
      bool targetReached=snapshot.IsSafe() && snapshot.AboveTargetRisk();

      return CRiskRuntimeContext::Create(currentRiskPct,
                                         targetPct,
                                         maxPct,
                                         realizedProfitUsd,
                                         canOpenRecovery,
                                         targetReached);
     }
  };

#endif
