#ifndef BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_CLOSE_VOLUME_CALCULATOR_MQH
#define BRE_DOMAIN_PROFIT_CLOSE_CANDIDATE_CLOSE_VOLUME_CALCULATOR_MQH

#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>

#define BRE_PROFIT_CLOSE_VOLUME_CALC_BUILD_MARKER "S8C_PROFIT_CLOSE_VOLUME_CALC_V1"

enum ENUM_BRE_PROFIT_CLOSE_VOLUME_RESULT
  {
   BRE_PROFIT_CLOSE_VOLUME_RESULT_OK=0,
   BRE_PROFIT_CLOSE_VOLUME_RESULT_NO_VALID_CLOSE_VOLUME
  };

struct SProfitCloseVolumeCalculation
  {
   ENUM_BRE_PROFIT_CLOSE_VOLUME_RESULT result;
   double            closeVolume;
   double            sourceRemainingVolume;
   double            remainderVolume;
  };

class CProfitCloseCandidateCloseVolumeCalculator
  {
public:
   static string     BuildMarker(void) { return BRE_PROFIT_CLOSE_VOLUME_CALC_BUILD_MARKER; }
   static string     VolumeRoundingModeLabel(void) { return "NORMALIZE_VOLUME_DOWN_STEP"; }
   static string     DustRemainderPolicyLabel(void) { return "PROMOTE_TO_FULL_CLOSE_WHEN_REMAINDER_BELOW_MIN"; }

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

   static double     VolumeComparisonEpsilon(const double lotStep)
     {
      if(lotStep>0.0)
         return lotStep*0.0001;
      return 0.0000001;
     }

   static bool       VolumeEquals(const double left,const double right,const double epsilon)
     {
      return MathAbs(left-right)<=epsilon;
     }

   static bool       VolumeIsZero(const double volume,const double epsilon)
     {
      return volume<=epsilon;
     }

   static bool       VolumeIsPositiveBelowMin(const double volume,const double minLot,const double epsilon)
     {
      return volume>epsilon && volume+epsilon<minLot;
     }

   static SProfitCloseVolumeCalculation CalculateNextCloseVolume(const double remainingVolume,
                                                                 const double closePercent,
                                                                 const double minLot,
                                                                 const double lotStep)
     {
      SProfitCloseVolumeCalculation out;
      out.result=BRE_PROFIT_CLOSE_VOLUME_RESULT_NO_VALID_CLOSE_VOLUME;
      out.closeVolume=0.0;
      out.sourceRemainingVolume=remainingVolume;
      out.remainderVolume=remainingVolume;

      if(remainingVolume<=0.0 || closePercent<=0.0 || minLot<=0.0 || lotStep<=0.0)
         return out;

      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,minLot,remainingVolume,lotStep);
      double epsilon=VolumeComparisonEpsilon(lotStep);

      // 1. Normalize remaining volume safely to broker step.
      double remaining=CSlRiskMath::NormalizeVolumeDown(remainingVolume,constraints);
      if(remaining<minLot-epsilon)
         return out;

      out.sourceRemainingVolume=remaining;

      // 2-3. rawClose then partialClose normalized DOWN to broker step.
      double rawClose=remaining*closePercent/100.0;
      if(closePercent>=100.0)
         rawClose=remaining;
      double partialClose=CSlRiskMath::NormalizeVolumeDown(rawClose,constraints);

      // 4. partialClose below min lot is the only NO_VALID_CLOSE_VOLUME path.
      if(partialClose<minLot-epsilon)
         return out;

      // 5. remainder from normalized remaining minus partial close (no upward rounding).
      double remainder=remaining-partialClose;
      if(remainder<0.0 && remainder>-epsilon)
         remainder=0.0;
      if(remainder>remaining+epsilon)
         return out;

      // 6. exact full close from partial request.
      if(VolumeIsZero(remainder,epsilon))
        {
         out.result=BRE_PROFIT_CLOSE_VOLUME_RESULT_OK;
         out.closeVolume=partialClose;
         out.remainderVolume=0.0;
         return out;
        }

      // 7. dust remainder promotes to full close.
      if(VolumeIsPositiveBelowMin(remainder,minLot,epsilon))
        {
         out.result=BRE_PROFIT_CLOSE_VOLUME_RESULT_OK;
         out.closeVolume=remaining;
         out.remainderVolume=0.0;
         return out;
        }

      // 8. valid partial close.
      out.result=BRE_PROFIT_CLOSE_VOLUME_RESULT_OK;
      out.closeVolume=partialClose;
      out.remainderVolume=remainder;
      return out;
     }

   static SProfitCloseVolumeCalculation CalculateNextCloseVolume(const double remainingVolume,
                                                                 const double closePercent,
                                                                 const CSymbolTradingConstraints &constraints)
     {
      double minLot=constraints.VolumeMin();
      double lotStep=constraints.VolumeStep();
      return CalculateNextCloseVolume(remainingVolume,closePercent,minLot,lotStep);
     }
  };

#endif
