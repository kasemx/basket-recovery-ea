#ifndef BRE_APP_BASKET_RISK_READ_MODEL_SERVICE_MQH
#define BRE_APP_BASKET_RISK_READ_MODEL_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Risk/Services/BasketRiskCalculator.mqh>
#include <BasketRecovery/Domain/Risk/Services/ProposedPositionRiskValidator.mqh>
#include <BasketRecovery/Domain/Risk/Services/RiskRuntimeContextMapper.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationContext.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskLimitProfile.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>

class CBasketRiskReadModelService
  {
private:
   static int        CopyOpenEntries(IPositionSnapshotStore *snapshotStore,
                                     const CBasketId &basketId,
                                     CPositionSnapshotEntry &outEntries[])
     {
      if(snapshotStore==NULL)
         return 0;

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return 0;

      int count=0;
      int total=snapshot.EntryCount();
      ArrayResize(outEntries,total);
      for(int i=0;i<total;i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         outEntries[count]=entry;
         count++;
        }
      if(count!=total)
         ArrayResize(outEntries,count);
      return count;
     }

   static CRiskCalculationContext BuildContext(const CBasketAggregate &basket,
                                               const CMarketQuote &quote,
                                               const CAccountContextSnapshot &account,
                                               const CRiskCalculationSettings &settings,
                                               const string accountCurrency="")
     {
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CRiskLimitProfile riskProfile=CRiskLimitProfile::FromRiskPlan(profile.StrategyId(),profile.RiskPlan());
      CSignalDetails details=basket.SignalDetails();
      return CRiskCalculationContext::Create(account,
                                               quote,
                                               riskProfile,
                                               details.StopLoss().Value(),
                                               basket.Direction(),
                                               settings,
                                               accountCurrency,
                                               0.0);
     }

public:
   static CBasketRiskSnapshot TryCalculateBasketRisk(const CBasketAggregate &basket,
                                                     const CMarketQuote &quote,
                                                     const CAccountContextSnapshot &account,
                                                     IPositionSnapshotStore *snapshotStore,
                                                     const CRiskCalculationSettings &settings,
                                                     const string accountCurrency="")
     {
      CPositionSnapshotEntry entries[];
      int count=CopyOpenEntries(snapshotStore,basket.Id(),entries);
      CRiskCalculationContext context=BuildContext(basket,quote,account,settings,accountCurrency);
      return CBasketRiskCalculator::Calculate(basket.Id(),entries,count,context);
     }

   static CRiskRuntimeContext TryBuildRiskRuntimeContext(const CBasketAggregate &basket,
                                                         const CMarketQuote &quote,
                                                         const CAccountContextSnapshot &account,
                                                         IPositionSnapshotStore *snapshotStore,
                                                         const CRiskCalculationSettings &settings,
                                                         const string accountCurrency="")
     {
      CBasketRiskSnapshot snapshot=TryCalculateBasketRisk(basket,quote,account,snapshotStore,settings,accountCurrency);
      return CRiskRuntimeContextMapper::FromBasketRiskSnapshot(snapshot,
                                                               basket.Metadata().RealizedProfit().Amount(),
                                                               basket.RecoveryPermanentlyDisabled());
     }

   static CRiskValidationResult TryValidateProposedPositionReadOnly(const CBasketAggregate &basket,
                                                                    const CTradeExecutionRequest &request,
                                                                    const CMarketQuote &quote,
                                                                    const CAccountContextSnapshot &account,
                                                                    IPositionSnapshotStore *snapshotStore,
                                                                    const CRiskCalculationSettings &settings,
                                                                    const string accountCurrency="")
     {
      CPositionSnapshotEntry entries[];
      int count=CopyOpenEntries(snapshotStore,basket.Id(),entries);
      CRiskCalculationContext context=BuildContext(basket,quote,account,settings,accountCurrency);
      return CProposedPositionRiskValidator::Validate(basket,entries,count,request,context);
     }
  };

#endif
