#ifndef BRE_DOMAIN_BREAK_EVEN_PRICE_CALCULATION_SERVICE_MQH
#define BRE_DOMAIN_BREAK_EVEN_PRICE_CALCULATION_SERVICE_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Strategy/Context/BreakEvenEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenRule.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenAction.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPriceCalculation.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/BreakEvenActionType.mqh>

class CBreakEvenPriceCalculationService
  {
private:
   static double     NormalizeToTickSize(const double price,const double tickSize)
     {
      if(tickSize<=0.0)
         return price;
      return MathRound(price/tickSize)*tickSize;
     }

   static bool       TryFindMoveAction(const CBreakEvenRule &rule,CBreakEvenAction &outAction)
     {
      for(int i=0;i<rule.ActionCount();i++)
        {
         CBreakEvenAction action=rule.ActionAt(i);
         if(action.Type()==BRE_BE_ACTION_MOVE_SL_TO_AVERAGE || action.Type()==BRE_BE_ACTION_MOVE_SL_WITH_OFFSET)
           {
            outAction=action;
            return true;
           }
        }
      return false;
     }

public:
   static bool       TryComputeWeightedAverage(const CBreakEvenEvaluationContext &ctx,
                                               double &outWeightedAverage,
                                               double &outTotalVolume)
     {
      int count=ctx.PositionCount();
      if(count<=0)
         return false;

      double entries[];
      double volumes[];
      ArrayResize(entries,count);
      ArrayResize(volumes,count);
      outTotalVolume=0.0;
      for(int i=0;i<count;i++)
        {
         CPositionRuntimeView position;
         if(!ctx.PositionAt(i,position) || position.Lot()<=0.0 || position.EntryPrice()<=0.0)
            return false;
         entries[i]=position.EntryPrice();
         volumes[i]=position.Lot();
         outTotalVolume+=position.Lot();
        }

      outWeightedAverage=CSlRiskMath::ComputeWeightedAverageEntry(entries,volumes,count);
      return outWeightedAverage>0.0 && outTotalVolume>0.0;
     }

   static CBreakEvenPriceCalculation Compute(const CBreakEvenEvaluationContext &ctx,
                                             const CBreakEvenRule &rule)
     {
      double weightedAverage=0.0;
      double totalVolume=0.0;
      if(!TryComputeWeightedAverage(ctx,weightedAverage,totalVolume))
         return CBreakEvenPriceCalculation::Invalid();

      CBreakEvenAction moveAction;
      if(!TryFindMoveAction(rule,moveAction))
         return CBreakEvenPriceCalculation::Invalid();

      double pipSize=ctx.Market().PipSize();
      if(pipSize<=0.0)
         pipSize=ctx.Point();
      if(pipSize<=0.0)
         return CBreakEvenPriceCalculation::Invalid();

      double spreadComponent=0.0;
      if(moveAction.IncludeSpread())
         spreadComponent=MathMax(0.0,ctx.Market().Ask()-ctx.Market().Bid());

      double safetyBuffer=0.0;
      if(moveAction.Type()==BRE_BE_ACTION_MOVE_SL_WITH_OFFSET)
         safetyBuffer=MathMax(0.0,moveAction.SlOffsetPips()*pipSize);
      else
         safetyBuffer=MathMax(0.0,moveAction.BufferPips()*pipSize);

      double rawStop=0.0;
      if(ctx.Direction()==BRE_DIRECTION_BUY)
         rawStop=weightedAverage+spreadComponent+safetyBuffer;
      else if(ctx.Direction()==BRE_DIRECTION_SELL)
         rawStop=weightedAverage-spreadComponent-safetyBuffer;
      else
         return CBreakEvenPriceCalculation::Invalid();

      double normalized=NormalizeToTickSize(rawStop,ctx.TickSize());
      return CBreakEvenPriceCalculation::Create(weightedAverage,totalVolume,spreadComponent,safetyBuffer,
                                                rawStop,normalized,normalized>0.0);
     }

   static bool       ExtractPolicyRecommendations(const CBreakEvenRule &rule,
                                                  bool &outDisableRecovery,
                                                  bool &outLockBasket,
                                                  bool &outTrailingHandoff)
     {
      outDisableRecovery=false;
      outLockBasket=false;
      outTrailingHandoff=false;
      for(int i=0;i<rule.ActionCount();i++)
        {
         CBreakEvenAction action=rule.ActionAt(i);
         if(action.Type()==BRE_BE_ACTION_DISABLE_RECOVERY)
            outDisableRecovery=true;
         if(action.Type()==BRE_BE_ACTION_LOCK_BASKET)
            outLockBasket=true;
         if(action.Type()==BRE_BE_ACTION_ENABLE_TRAILING)
            outTrailingHandoff=true;
        }
      return true;
     }
  };

#endif
