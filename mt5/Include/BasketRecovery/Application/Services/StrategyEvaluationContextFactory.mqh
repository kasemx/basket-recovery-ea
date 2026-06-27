#ifndef BASKET_RECOVERY_APPLICATION_STRATEGY_EVALUATION_CONTEXT_FACTORY_MQH
#define BASKET_RECOVERY_APPLICATION_STRATEGY_EVALUATION_CONTEXT_FACTORY_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/ProfitLevelRuntimeState.mqh>

class CStrategyEvaluationContextFactory
  {
public:
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
      int profitStateCount=basket.ProfitLevelProgressCount();
      ArrayResize(profitStates,profitStateCount);
      CBasketProfitLevelProgress progress;
      for(int i=0;i<profitStateCount;i++)
        {
         if(basket.ProfitLevelProgressAt(i,progress))
            profitStates[i]=CProfitLevelRuntimeState::Create(progress.LevelId(),
                                                               progress.Reached(),
                                                               progress.CloseCompleted(),
                                                               0.0,
                                                               false);
        }

      CPositionRuntimeView positions[];
      ArrayResize(positions,0);
      return CStrategyEvaluationContext::Create(profile,market,basketState,riskContext,profitStates,profitStateCount,
                                                positions,0,adverseMovePips,floatingProfitUsd);
     }
  };

#endif
