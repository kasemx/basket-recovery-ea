#ifndef BRE_DOMAIN_RISK_REDUCTION_PLANNER_MQH
#define BRE_DOMAIN_RISK_REDUCTION_PLANNER_MQH

#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskReductionPlan.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>

class CRiskReductionPlanner
  {
private:
   static void       SortWorstEntryFirst(CPositionRiskSnapshot &positions[],
                                         const int count,
                                         const ENUM_BRE_TRADE_DIRECTION direction)
     {
      for(int i=0;i<count-1;i++)
        {
         for(int j=i+1;j<count;j++)
           {
            bool swap=false;
            if(direction==BRE_DIRECTION_SELL)
               swap=positions[j].EntryPrice()>positions[i].EntryPrice();
            else if(direction==BRE_DIRECTION_BUY)
               swap=positions[j].EntryPrice()<positions[i].EntryPrice();
            if(swap)
              {
               CPositionRiskSnapshot temp=positions[i];
               positions[i]=positions[j];
               positions[j]=temp;
              }
           }
        }
     }

public:
   static CRiskReductionPlan Plan(const CBasketRiskSnapshot &snapshot,
                                  const CRiskCalculationContext &context)
     {
      const CRiskReductionPolicy policy=context.RiskProfile().ReductionPolicy();
      if(!policy.Enabled())
         return CRiskReductionPlan::CreateEmpty();
      if(policy.Trigger()!=BRE_RISK_REDUCTION_TRIGGER_ABOVE_TARGET_RISK)
         return CRiskReductionPlan::CreateEmpty();
      if(!snapshot.IsSafe())
         return CRiskReductionPlan::CreateEmpty();
      if(snapshot.CurrentSlRiskMoney()<=snapshot.TargetRiskMoney())
         return CRiskReductionPlan::CreateEmpty();

      int count=snapshot.PositionCount();
      if(count<=0)
         return CRiskReductionPlan::CreateEmpty();

      CPositionRiskSnapshot positions[];
      ArrayResize(positions,count);
      for(int i=0;i<count;i++)
         positions[i]=snapshot.PositionAt(i);

      SortWorstEntryFirst(positions,count,context.BasketDirection());

      const CSymbolTradingConstraints constraints=context.Quote().Constraints();
      double remaining=snapshot.CurrentSlRiskMoney()-snapshot.TargetRiskMoney();
      CRiskReductionPlanEntry entries[];
      int entryCount=0;

      for(int i=0;i<count && remaining>0.0;i++)
        {
         double positionRisk=positions[i].WorstCaseLossAtSl();
         if(positionRisk<=0.0)
            continue;

         double closeVolume=positions[i].Volume();
         double estimatedReduction=positionRisk;
         if(estimatedReduction>remaining && positions[i].Volume()>0.0)
           {
            double ratio=remaining/positionRisk;
            closeVolume=CSlRiskMath::NormalizeVolumeDown(positions[i].Volume()*ratio,constraints);
            if(closeVolume<=0.0)
               break;
            estimatedReduction=positionRisk*(closeVolume/positions[i].Volume());
           }

         ArrayResize(entries,entryCount+1);
         entries[entryCount]=CRiskReductionPlanEntry::Create(positions[i].Ticket(),
                                                             closeVolume,
                                                             estimatedReduction);
         entryCount++;
         remaining-=estimatedReduction;
        }

      return CRiskReductionPlan::Create(snapshot.CurrentSlRiskMoney(),
                                      snapshot.TargetRiskMoney(),
                                      policy.CloseOrder(),
                                      entries,
                                      entryCount);
     }
  };

#endif
