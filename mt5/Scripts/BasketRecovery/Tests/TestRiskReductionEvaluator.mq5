#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RiskReductionEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>

void TestRiskReductionDecision(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CPositionRuntimeView positions[2];
   positions[0]=CPositionRuntimeView::Create(201,4018.0,0.01,2.0,20.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[1]=CPositionRuntimeView::Create(202,4017.0,0.02,3.0,15.0,200,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);

   CProfitLevelRuntimeState states[];
   ArrayResize(states,0);

   CStrategyEvaluationContext context=CStrategyEngineTestFixture::BuildContext(profile,
                                                                               BRE_DIRECTION_SELL,
                                                                               4014.0,
                                                                               4017.0,
                                                                               4010.0,
                                                                               4010.1,
                                                                               0.0,
                                                                               5.0,
                                                                               1.5,
                                                                               0.0,
                                                                               true,
                                                                               0,
                                                                               false,
                                                                               states,
                                                                               0,
                                                                               positions,
                                                                               2);

   CRiskReductionEvaluator evaluator;
   CStrategyDecisionSet decisions=evaluator.Evaluate(context);
   CTestAssert::EqualInt(1,decisions.Count(),"Risk above target must produce one reduction decision");
   CTestAssert::EqualInt(BRE_STRATEGY_DECISION_REDUCE_RISK,decisions.DecisionAt(0).Type(),"Decision type must be reduce risk");
   CTestAssert::EqualInt(BRE_RISK_REDUCTION_MODE_WORST_ENTRY,decisions.DecisionAt(0).ReduceRisk().ReductionMode(),"Golden profile must use worst entry reduction");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestRiskReductionDecision();
   CTestAssert::Summary("TestRiskReductionEvaluator");
  }
