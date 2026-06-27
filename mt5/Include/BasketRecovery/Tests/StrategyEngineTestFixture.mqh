#ifndef BASKET_RECOVERY_TESTS_STRATEGY_ENGINE_TEST_FIXTURE_MQH
#define BASKET_RECOVERY_TESTS_STRATEGY_ENGINE_TEST_FIXTURE_MQH

#include <BasketRecovery/Domain/Strategy/Context/StrategyEvaluationContext.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonLoader.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

class CStrategyEngineTestFixture
  {
public:
   static CStrategyProfile LoadGoldenProfile(void)
     {
      CStrategyProfileJsonLoader loader;
      CResult<CStrategyProfile> result=loader.LoadFromStrategyId(BRE_STRATEGY_DEFAULT_ID);
      CStrategyProfile profile;
      result.TryGetValue(profile);
      return profile;
     }

   static CStrategyEvaluationContext BuildContext(const CStrategyProfile &profile,
                                                  const ENUM_BRE_TRADE_DIRECTION direction,
                                                  const double signalLow,
                                                  const double signalHigh,
                                                  const double bid,
                                                  const double ask,
                                                  const double adverseMovePips,
                                                  const double floatingProfitUsd,
                                                  const double currentRiskPct,
                                                  const double realizedProfitUsd,
                                                  const bool canOpenRecovery,
                                                  const int currentRecoveryStep,
                                                  const bool recoveryDisabled,
                                                  const CProfitLevelRuntimeState &profitStates[],
                                                  const int profitStateCount,
                                                  const CPositionRuntimeView &positions[],
                                                  const int positionCount)
     {
      CBasketId basketId("basket-engine-test");
      CBasketStrategyState basketState=CBasketStrategyState::Create(basketId,
                                                                    direction,
                                                                    signalLow,
                                                                    signalHigh,
                                                                    (signalLow+signalHigh)/2.0,
                                                                    currentRecoveryStep,
                                                                    recoveryDisabled,
                                                                    false,
                                                                    false);
      CMarketContext market=CMarketContext::Create("XAUUSD",bid,ask,0.1);
      CRiskRuntimeContext riskContext=CRiskRuntimeContext::Create(currentRiskPct,
                                                                   profile.RiskPlan().TargetRiskPct(),
                                                                   profile.RiskPlan().MaxRiskPct(),
                                                                   realizedProfitUsd,
                                                                   canOpenRecovery,
                                                                   currentRiskPct>=profile.RiskPlan().TargetRiskPct());
      return CStrategyEvaluationContext::Create(profile,
                                                market,
                                                basketState,
                                                riskContext,
                                                profitStates,
                                                profitStateCount,
                                                positions,
                                                positionCount,
                                                adverseMovePips,
                                                floatingProfitUsd);
     }
  };

#endif
