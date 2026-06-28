#ifndef BRE_DOMAIN_BASKET_RISK_CALCULATOR_MQH
#define BRE_DOMAIN_BASKET_RISK_CALCULATOR_MQH

#include <BasketRecovery/Domain/Risk/Services/PositionSlRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/SlRiskMath.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>

class CBasketRiskCalculator
  {
public:
   static CBasketRiskSnapshot Calculate(const CBasketId &basketId,
                                        const CPositionSnapshotEntry &entries[],
                                        const int entryCount,
                                        const CRiskCalculationContext &context)
     {
      const CAccountContextSnapshot account=context.Account();
      const CMarketQuote quote=context.Quote();
      const CRiskLimitProfile profile=context.RiskProfile();

      if(quote.Bid()<=0.0 || quote.Ask()<=0.0 || quote.TickSize()<=0.0 || quote.TickValue()<=0.0)
         return CBasketRiskSnapshot::Unsafe(basketId,quote.Symbol());

      if(context.Settings().RequireCrossCurrencyConversion() &&
         !context.Settings().CrossCurrencyConversionAvailable())
         return CBasketRiskSnapshot::Unknown(basketId,quote.Symbol());

      double targetMoney=CSlRiskMath::ResolveLimitMoney(profile.TargetRisk().Mode(),
                                                        profile.TargetRisk().Value(),
                                                        account.Equity());
      double maxMoney=CSlRiskMath::ResolveLimitMoney(profile.MaxRisk().Mode(),
                                                     profile.MaxRisk().Value(),
                                                     account.Equity());

      CPositionRiskSnapshot positionRisks[];
      int safeCount=0;
      double totalSlRisk=0.0;
      double floatingProfit=0.0;
      double entryPrices[];
      double volumes[];
      ArrayResize(entryPrices,entryCount);
      ArrayResize(volumes,entryCount);
      int openCount=0;

      for(int i=0;i<entryCount;i++)
        {
         if(entries[i].Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;

         CPositionRiskSnapshot positionRisk=CPositionSlRiskCalculator::Calculate(entries[i],context);
         ArrayResize(positionRisks,safeCount+1);
         positionRisks[safeCount]=positionRisk;
         safeCount++;

         if(!positionRisk.IsSafe())
           {
            CBasketRiskSnapshot unsafeSnapshot=CBasketRiskSnapshot::Unsafe(basketId,quote.Symbol());
            unsafeSnapshot.SetPositions(positionRisks,safeCount);
            return unsafeSnapshot;
           }

         totalSlRisk+=positionRisk.WorstCaseLossAtSl();
         floatingProfit+=positionRisk.FloatingProfit();
         entryPrices[openCount]=positionRisk.EntryPrice();
         volumes[openCount]=positionRisk.Volume();
         openCount++;
        }

      CBasketRiskSnapshot snapshot;
      snapshot.SetCore(basketId,
                       quote.Symbol(),
                       context.AccountCurrency(),
                       account.Equity(),
                       account.Balance(),
                       context.BasketStopLoss(),
                       CSlRiskMath::ComputeWeightedAverageEntry(entryPrices,volumes,openCount),
                       floatingProfit,
                       totalSlRisk,
                       targetMoney,
                       maxMoney,
                       BRE_RISK_SAFETY_SAFE);
      snapshot.SetPositions(positionRisks,safeCount);
      return snapshot;
     }
  };

#endif
