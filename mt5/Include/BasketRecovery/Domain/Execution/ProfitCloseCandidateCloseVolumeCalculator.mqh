#ifndef BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_CLOSE_VOLUME_CALCULATOR_MQH
#define BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_CLOSE_VOLUME_CALCULATOR_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>

#define BRE_PROFIT_CLOSE_VOLUME_CALC_BUILD_MARKER "S8C_PROFIT_CLOSE_VOLUME_CALC_V1"

class CProfitCloseCandidateCloseVolumeCalculator
  {
public:
   static string     BuildMarker(void) { return BRE_PROFIT_CLOSE_VOLUME_CALC_BUILD_MARKER; }
   static string     VolumeRoundingModeLabel(void) { return "NORMALIZE_VOLUME_DOWN_STEP"; }

   static bool       TryResolveLevelClosePercent(const CStrategyProfile &profile,
                                                 const string profitLevelId,
                                                 double &outClosePercent)
     {
      outClosePercent=0.0;
      CProfitDistributionPlan plan=profile.ProfitDistributionPlan();
      for(int i=0;i<plan.LevelCount();i++)
        {
         CProfitLevel level=plan.LevelAt(i);
         if(level.LevelId()==profitLevelId)
           {
            outClosePercent=level.ClosePercent();
            return true;
           }
        }
      return false;
     }

   static double     ComputePartialCloseVolume(const double positionLot,
                                               const double closePercent,
                                               const CSymbolTradingConstraints &constraints)
     {
      if(positionLot<=0.0 || closePercent<=0.0)
         return 0.0;
      if(closePercent>=100.0)
         return CSlRiskMath::NormalizeVolumeDown(positionLot,constraints);
      return CSlRiskMath::NormalizeVolumeDown(positionLot*closePercent/100.0,constraints);
     }

   static double     NormalizeVolume(const double volume,const CSymbolTradingConstraints &constraints)
     {
      return CSlRiskMath::NormalizeVolumeDown(volume,constraints);
     }

   static bool       VolumesMatch(const double expectedVolume,
                                  const double actualVolume,
                                  const CSymbolTradingConstraints &constraints)
     {
      double step=constraints.VolumeStep();
      if(step<=0.0)
         return MathAbs(expectedVolume-actualVolume)<=0.00000001;
      return MathAbs(expectedVolume-actualVolume)<=step*0.5;
     }

   static string     DescribeVolumeMismatch(const double artifactCloseVolume,
                                            const double candidateCloseVolume,
                                            const double replannedCloseVolume,
                                            const double expectedCloseVolume,
                                            const CSymbolTradingConstraints &constraints)
     {
      if(!VolumesMatch(expectedCloseVolume,artifactCloseVolume,constraints))
         return "artifact_close_volume_drift";
      if(!VolumesMatch(expectedCloseVolume,candidateCloseVolume,constraints))
         return "candidate_close_volume_drift";
      if(!VolumesMatch(expectedCloseVolume,replannedCloseVolume,constraints))
         return "replanned_close_volume_drift";
      return "none";
     }
  };

#endif
