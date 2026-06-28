#ifndef BRE_DOMAIN_SL_RISK_MATH_MQH
#define BRE_DOMAIN_SL_RISK_MATH_MQH

#include <BasketRecovery/Domain/Risk/Enums/RiskLimitMode.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

class CSlRiskMath
  {
public:
   static bool       TryWorstCaseLossAtSl(const double entryPrice,
                                          const double stopLoss,
                                          const double volume,
                                          const double tickSize,
                                          const double tickValue,
                                          const double commission,
                                          const double swap,
                                          const CRiskCalculationSettings &settings,
                                          const double spreadBufferPrice,
                                          double &outLossMoney)
     {
      outLossMoney=0.0;
      if(stopLoss<=0.0)
         return false;
      if(entryPrice<=0.0 || volume<=0.0)
         return false;
      if(tickSize<=0.0 || tickValue<=0.0)
         return false;
      if(settings.RequireCrossCurrencyConversion() && !settings.CrossCurrencyConversionAvailable())
         return false;

      double distance=MathAbs(entryPrice-stopLoss);
      if(settings.IncludeSpreadBuffer())
         distance+=MathMax(0.0,spreadBufferPrice);

      double ticks=distance/tickSize;
      double loss=ticks*tickValue*volume;
      if(settings.IncludeCommission())
         loss+=MathAbs(commission);
      if(settings.IncludeSwap() && swap<0.0)
         loss+=MathAbs(swap);
      outLossMoney=loss;
      return true;
     }

   static double     ResolveLimitMoney(const ENUM_BRE_RISK_LIMIT_MODE mode,
                                         const double value,
                                         const double equity)
     {
      if(mode==BRE_RISK_LIMIT_PERCENT_EQUITY)
         return equity>0.0 ? equity*value/100.0 : 0.0;
      return value;
     }

   static double     NormalizeVolumeDown(const double volume,const CSymbolTradingConstraints &constraints)
     {
      double step=constraints.VolumeStep();
      double minVolume=constraints.VolumeMin();
      if(volume<=0.0)
         return 0.0;
      if(step<=0.0)
         return volume;
      double normalized=MathFloor(volume/step)*step;
      if(normalized<minVolume)
         return 0.0;
      return normalized;
     }

   static double     ComputeWeightedAverageEntry(const double &entries[],
                                                   const double &volumes[],
                                                   const int count)
     {
      double weightedSum=0.0;
      double volumeSum=0.0;
      for(int i=0;i<count;i++)
        {
         weightedSum+=entries[i]*volumes[i];
         volumeSum+=volumes[i];
        }
      return volumeSum>0.0 ? weightedSum/volumeSum : 0.0;
     }
  };

#endif
