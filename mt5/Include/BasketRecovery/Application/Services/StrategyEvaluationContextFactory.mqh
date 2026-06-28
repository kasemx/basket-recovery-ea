#ifndef BRE_APP_STRATEGY_EVAL_CONTEXT_FACTORY_MQH
#define BRE_APP_STRATEGY_EVAL_CONTEXT_FACTORY_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelRuntimeState.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Application/Risk/BasketRiskReadModelService.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/BasketRiskSnapshot.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>

class CStrategyEvaluationContextFactory
  {
private:
   static void       BuildProfitStates(const CBasketAggregate &basket,
                                       CProfitLevelRuntimeState &outStates[],
                                       int &outCount)
     {
      outCount=basket.ProfitLevelProgressCount();
      ArrayResize(outStates,outCount);
      CBasketProfitLevelProgress progress;
      for(int i=0;i<outCount;i++)
        {
         if(basket.ProfitLevelProgressAt(i,progress))
            outStates[i]=CProfitLevelRuntimeState::Create(progress.LevelId(),
                                                          progress.Reached(),
                                                          progress.CloseCompleted(),
                                                          0.0,
                                                          false);
        }
     }

   static void       BuildPositionViews(const CBasketAggregate &basket,
                                        IPositionSnapshotStore *snapshotStore,
                                        CPositionRuntimeView &outViews[],
                                        int &outCount)
     {
      outCount=0;
      ArrayResize(outViews,0);
      if(snapshotStore==NULL)
         return;

      CPositionSnapshot *snapshot=snapshotStore.Get(basket.Id());
      if(snapshot==NULL)
         return;

      int entryCount=snapshot.EntryCount();
      if(entryCount<=0)
         return;

      ArrayResize(outViews,entryCount);
      for(int i=0;i<entryCount;i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;

         outViews[outCount]=CPositionRuntimeView::Create(entry.Ticket(),
                                                         entry.EntryPrice(),
                                                         entry.Volume(),
                                                         entry.FloatingProfit(),
                                                         0.0,
                                                         entry.OpenTimeUtc(),
                                                         entry.Direction(),
                                                         entry.Role());
         outCount++;
        }

      if(outCount!=entryCount)
         ArrayResize(outViews,outCount);
     }

   static double     SumFloatingProfit(IPositionSnapshotStore *snapshotStore,const CBasketId &basketId)
     {
      if(snapshotStore==NULL)
         return 0.0;

      CPositionSnapshot *snapshot=snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return 0.0;

      double total=0.0;
      for(int i=0;i<snapshot.EntryCount();i++)
        {
         CPositionSnapshotEntry entry;
         if(!snapshot.EntryAt(i,entry))
            continue;
         if(entry.Status()==BRE_POSITION_SNAPSHOT_OPEN)
            total+=entry.FloatingProfit();
        }
      return total;
     }

public:
   static CResult<CStrategyEvaluationContext> TryBuild(const CBasketAggregate &basket,
                                                       const CMarketContext &market,
                                                       const CRiskRuntimeContext &riskContext,
                                                       IPositionSnapshotStore *snapshotStore)
     {
      if(market.Symbol()=="" || market.Bid()<=0.0 || market.Ask()<=0.0)
         return CResult<CStrategyEvaluationContext>::Fail(BRE_ERR_COMMAND_INVALID,"Market context is incomplete");

      CStrategyProfile profile;
      if(!basket.StrategyProfile(profile))
         return CResult<CStrategyEvaluationContext>::Fail(BRE_ERR_STRATEGY_NOT_BOUND,"Basket has no strategy profile");

      CSignalDetails details=basket.SignalDetails();
      string executedRules[];
      int executedRuleCount=0;
      basket.CopyExecutedBreakEvenRuleIds(executedRules,executedRuleCount);

      CBasketStrategyState basketState=CBasketStrategyState::Create(basket.Id(),
                                                                    basket.Direction(),
                                                                    details.RangeLow().Value(),
                                                                    details.RangeHigh().Value(),
                                                                    details.StopLoss().Value(),
                                                                    0,
                                                                    basket.RecoveryPermanentlyDisabled(),
                                                                    basket.ModeFlags().BreakEvenActive(),
                                                                    false,
                                                                    executedRules,
                                                                    executedRuleCount);

      CProfitLevelRuntimeState profitStates[];
      int profitStateCount=0;
      BuildProfitStates(basket,profitStates,profitStateCount);

      CPositionRuntimeView positions[];
      int positionCount=0;
      BuildPositionViews(basket,snapshotStore,positions,positionCount);

      double mid=(market.Bid()+market.Ask())*0.5;
      double adverseMovePips=MathAbs(mid-details.StopLoss().Value())/MathMax(market.PipSize(),0.0000001);
      double floatingProfitUsd=SumFloatingProfit(snapshotStore,basket.Id());

      return CResult<CStrategyEvaluationContext>::Ok(
         CStrategyEvaluationContext::Create(profile,market,basketState,riskContext,profitStates,profitStateCount,
                                          positions,positionCount,adverseMovePips,floatingProfitUsd));
     }

   static CBasketRiskSnapshot TryCalculateBasketRisk(const CBasketAggregate &basket,
                                                     const CMarketQuote &quote,
                                                     const CAccountContextSnapshot &account,
                                                     IPositionSnapshotStore *snapshotStore)
     {
      return CBasketRiskReadModelService::TryCalculateBasketRisk(basket,
                                                                 quote,
                                                                 account,
                                                                 snapshotStore,
                                                                 CRiskCalculationSettings::CreateDefault());
     }

   static CStrategyEvaluationContext FromBasket(const CBasketAggregate &basket,
                                                const CMarketContext &market,
                                                const CRiskRuntimeContext &riskContext,
                                                const double adverseMovePips,
                                                const double floatingProfitUsd)
     {
      CStrategyProfile profile;
      basket.StrategyProfile(profile);
      CSignalDetails details=basket.SignalDetails();
      string executedRules[];
      int executedRuleCount=0;
      basket.CopyExecutedBreakEvenRuleIds(executedRules,executedRuleCount);
      CBasketStrategyState basketState=CBasketStrategyState::Create(basket.Id(),basket.Direction(),
                                                                    details.RangeLow().Value(),details.RangeHigh().Value(),
                                                                    details.StopLoss().Value(),0,
                                                                    basket.RecoveryPermanentlyDisabled(),
                                                                    basket.ModeFlags().BreakEvenActive(),false,
                                                                    executedRules,executedRuleCount);
      CProfitLevelRuntimeState profitStates[];
      int profitStateCount=0;
      BuildProfitStates(basket,profitStates,profitStateCount);
      CPositionRuntimeView positions[];
      ArrayResize(positions,0);
      return CStrategyEvaluationContext::Create(profile,market,basketState,riskContext,profitStates,profitStateCount,
                                                positions,0,adverseMovePips,floatingProfitUsd);
     }
  };

#endif
