#ifndef BRE_DOMAIN_RECOVERY_VOLUME_RESOLVER_MQH
#define BRE_DOMAIN_RECOVERY_VOLUME_RESOLVER_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryVolumePlan.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/RecoveryAlgorithm.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CRecoveryVolumeResolver
  {
private:
   static bool       VolumeWithinMax(const double normalizedVolume,const CSymbolTradingConstraints &constraints)
     {
      double maxVolume=constraints.VolumeMax();
      if(maxVolume<=0.0)
         return normalizedVolume>0.0;
      return normalizedVolume>0.0 && normalizedVolume<=maxVolume+0.0000001;
     }

public:
   static CRecoveryVolumePlan Resolve(const CRecoveryPlan &plan,
                                      const CRecoveryStep &step,
                                      const double priorRecoveryVolume,
                                      const CSymbolTradingConstraints &constraints)
     {
      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_ATR || plan.Algorithm()==BRE_RECOVERY_ALGORITHM_VOLATILITY)
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_UNSUPPORTED_ALGORITHM);

      double rawVolume=step.Lot();
      if(rawVolume<=0.0 && plan.InitialLotSize()>0.0)
         rawVolume=plan.InitialLotSize();

      if(rawVolume<=0.0)
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_INVALID_VOLUME);

      if(plan.Algorithm()==BRE_RECOVERY_ALGORITHM_CONSTANT && priorRecoveryVolume>0.0 && step.LotMultiplierEnabled())
        {
         rawVolume=priorRecoveryVolume*step.LotMultiplier();
         if(rawVolume<=0.0)
            return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_INVALID_VOLUME);
        }

      if(step.UsesRiskBudgetVolume())
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_RISK_BUDGET_NOT_IMPLEMENTED);

      double normalized=CSlRiskMath::NormalizeVolumeDown(rawVolume,constraints);
      if(normalized<=0.0)
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_INVALID_VOLUME);

      if(!VolumeWithinMax(normalized,constraints))
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_INVALID_VOLUME);

      if(MathAbs(normalized-rawVolume)>0.0000001 && normalized>rawVolume)
         return CRecoveryVolumePlan::Invalid(BRE_RECOVERY_CANDIDATE_REASON_INVALID_VOLUME);

      return CRecoveryVolumePlan::ValidPlan(rawVolume,normalized);
     }
  };

#endif
