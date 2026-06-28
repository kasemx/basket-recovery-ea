#ifndef BRE_DOMAIN_PROFIT_LEVEL_CLOSE_VOLUME_PLANNER_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_CLOSE_VOLUME_PLANNER_MQH

#include <BasketRecovery/Domain/Strategy/Context/PositionRuntimeView.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/PositionReductionInstruction.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelPositionSelector.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/CloseMode.mqh>

class CProfitLevelCloseVolumePlan
  {
private:
   bool                              m_valid;
   bool                              m_minimumVolumeOverrun;
   CPositionReductionInstruction     m_reductions[];

public:
                     CProfitLevelCloseVolumePlan(void)
     {
      m_valid=false;
      m_minimumVolumeOverrun=false;
     }

   bool                              Valid(void) const { return m_valid; }
   bool                              MinimumVolumeOverrun(void) const { return m_minimumVolumeOverrun; }
   int                               ReductionCount(void) const { return ArraySize(m_reductions); }

   bool                              ReductionAt(const int index,CPositionReductionInstruction &outInstruction) const
     {
      if(index<0 || index>=ArraySize(m_reductions))
         return false;
      outInstruction=m_reductions[index];
      return true;
     }

   static CProfitLevelCloseVolumePlan CreateInvalid(void)
     {
      CProfitLevelCloseVolumePlan plan;
      return plan;
     }

   static CProfitLevelCloseVolumePlan Create(const CPositionReductionInstruction &reductions[],
                                               const int reductionCount,
                                               const bool minimumVolumeOverrun)
     {
      CProfitLevelCloseVolumePlan plan;
      plan.m_valid=reductionCount>0;
      plan.m_minimumVolumeOverrun=minimumVolumeOverrun;
      ArrayResize(plan.m_reductions,reductionCount);
      for(int i=0;i<reductionCount;i++)
         plan.m_reductions[i]=reductions[i];
      return plan;
     }
  };

class CProfitLevelCloseVolumePlanner
  {
private:
   static double     EstimateCloseMoney(const CPositionRuntimeView &position,const double closeVolume)
     {
      if(position.Lot()<=0.0 || closeVolume<=0.0)
         return 0.0;
      return position.FloatingProfit()*(closeVolume/position.Lot());
     }

   static CProfitLevelCloseVolumePlan PlanFullClose(const CPositionRuntimeView &ordered[],
                                                    const int count,
                                                    const CSymbolTradingConstraints &constraints)
     {
      CPositionReductionInstruction reductions[];
      int reductionCount=0;
      bool overrun=false;
      double totalEstimated=0.0;

      for(int i=0;i<count;i++)
        {
         double normalized=CSlRiskMath::NormalizeVolumeDown(ordered[i].Lot(),constraints);
         if(normalized<=0.0)
            continue;
         double estimated=EstimateCloseMoney(ordered[i],normalized);
         ArrayResize(reductions,reductionCount+1);
         reductions[reductionCount]=CPositionReductionInstruction::Create(ordered[i].Ticket(),normalized,estimated);
         reductionCount++;
         totalEstimated+=estimated;
        }

      if(reductionCount<=0)
         return CProfitLevelCloseVolumePlan::CreateInvalid();

      return CProfitLevelCloseVolumePlan::Create(reductions,reductionCount,overrun);
     }

public:
   static CProfitLevelCloseVolumePlan Plan(const ENUM_BRE_CLOSE_MODE closeMode,
                                           const ENUM_BRE_TRADE_DIRECTION direction,
                                           const CPositionRuntimeView &positions[],
                                           const int positionCount,
                                           const double targetCloseMoney,
                                           const double closePercent,
                                           const CSymbolTradingConstraints &constraints)
     {
      if(positionCount<=0 || targetCloseMoney<=0.0)
         return CProfitLevelCloseVolumePlan::CreateInvalid();

      CPositionRuntimeView ordered[];
      int orderedCount=CProfitLevelPositionSelector::SelectOrdered(closeMode,direction,positions,positionCount,ordered);
      if(orderedCount<=0)
         return CProfitLevelCloseVolumePlan::CreateInvalid();

      if(closePercent>=100.0)
         return PlanFullClose(ordered,orderedCount,constraints);

      double remaining=targetCloseMoney;
      bool overrun=false;
      CPositionReductionInstruction reductions[];
      int reductionCount=0;
      const double tolerance=0.01;

      for(int i=0;i<orderedCount && remaining>tolerance;i++)
        {
         CPositionRuntimeView position=ordered[i];
         if(position.Lot()<=0.0 || position.FloatingProfit()<=0.0)
            continue;

         double profitPerLot=position.FloatingProfit()/position.Lot();
         double rawVolume=MathMin(position.Lot(),remaining/profitPerLot);
         double normalized=CSlRiskMath::NormalizeVolumeDown(rawVolume,constraints);
         if(normalized<=0.0)
           {
            normalized=CSlRiskMath::NormalizeVolumeDown(position.Lot(),constraints);
            if(normalized<=0.0)
               continue;
            overrun=true;
           }

         if(normalized>position.Lot())
            normalized=CSlRiskMath::NormalizeVolumeDown(position.Lot(),constraints);

         double estimated=EstimateCloseMoney(position,normalized);
         if(estimated<=0.0)
            continue;

         if(estimated>remaining+tolerance && !overrun)
            overrun=true;

         ArrayResize(reductions,reductionCount+1);
         reductions[reductionCount]=CPositionReductionInstruction::Create(position.Ticket(),normalized,estimated);
         reductionCount++;
         remaining-=estimated;
        }

      if(reductionCount<=0)
         return CProfitLevelCloseVolumePlan::CreateInvalid();

      if(remaining>tolerance)
        {
         double planned=0.0;
         for(int i=0;i<reductionCount;i++)
            planned+=reductions[i].EstimatedCloseMoney();
         if(planned+constraints.VolumeMin()*0.01<targetCloseMoney-tolerance)
            return CProfitLevelCloseVolumePlan::CreateInvalid();
         overrun=true;
        }

      return CProfitLevelCloseVolumePlan::Create(reductions,reductionCount,overrun);
     }
  };

#endif
