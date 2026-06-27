#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Domain/Strategy/Services/BreakEvenEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>

void TestBreakEvenAfterSpecificLevel(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState states[1];
   states[0]=CProfitLevelRuntimeState::Create("L1",true,false,0.0,false);

   CPositionRuntimeView emptyPositions[];
   ArrayResize(emptyPositions,0);

   CStrategyEvaluationContext context=CStrategyEngineTestFixture::BuildContext(profile,
                                                                               BRE_DIRECTION_SELL,
                                                                               4014.0,
                                                                               4017.0,
                                                                               4010.0,
                                                                               4010.1,
                                                                               0.0,
                                                                               10.0,
                                                                               0.8,
                                                                               0.0,
                                                                               true,
                                                                               0,
                                                                               false,
                                                                               states,
                                                                               1,
                                                                               emptyPositions,
                                                                               0);

   CBreakEvenEvaluator evaluator;
   CStrategyDecisionSet decisions=evaluator.Evaluate(context);
   CTestAssert::True(decisions.Count()>=2,"Golden BE after L1 must produce move and disable decisions");

   bool foundDisable=false;
   for(int i=0;i<decisions.Count();i++)
     {
      if(decisions.DecisionAt(i).Type()==BRE_STRATEGY_DECISION_DISABLE_RECOVERY)
         foundDisable=true;
     }
   CTestAssert::True(foundDisable,"Break-even must include disable recovery decision");
  }

void TestBreakEvenAfterRealizedProfit(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState states[];
   ArrayResize(states,0);

   CPositionRuntimeView emptyPositions[];
   ArrayResize(emptyPositions,0);

   CStrategyEvaluationContext context=CStrategyEngineTestFixture::BuildContext(profile,
                                                                               BRE_DIRECTION_SELL,
                                                                               4014.0,
                                                                               4017.0,
                                                                               4010.0,
                                                                               4010.1,
                                                                               0.0,
                                                                               10.0,
                                                                               0.8,
                                                                               15.0,
                                                                               true,
                                                                               0,
                                                                               false,
                                                                               states,
                                                                               0,
                                                                               emptyPositions,
                                                                               0);

   CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_REALIZED_PROFIT,10.0,true,0.0,false,0.0,false,"","","","");
   CBreakEvenAction actions[1];
   actions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_MOVE_SL_TO_AVERAGE,0.0,0.5,true,false);
   CBreakEvenRule rules[1];
   rules[0]=CBreakEvenRule::Create("BE_REALIZED",true,1,true,trigger,actions,1);
   CBreakEvenPlan breakEvenPlan=CBreakEvenPlan::Create(rules,1);

   CStrategyProfile customProfile=CStrategyProfile::Create(profile.StrategyId(),
                                                           profile.SchemaVersion(),
                                                           profile.Metadata(),
                                                           profile.ExecutionZone(),
                                                           profile.RecoveryPlan(),
                                                           profile.ProfitDistributionPlan(),
                                                           breakEvenPlan,
                                                           profile.RiskPlan(),
                                                           profile.ExecutionPolicy(),
                                                           profile.BoundAt());

   context=CStrategyEngineTestFixture::BuildContext(customProfile,
                                                    BRE_DIRECTION_SELL,
                                                    4014.0,
                                                    4017.0,
                                                    4010.0,
                                                    4010.1,
                                                    0.0,
                                                    10.0,
                                                    0.8,
                                                    15.0,
                                                    true,
                                                    0,
                                                    false,
                                                    states,
                                                    0,
                                                    emptyPositions,
                                                    0);

   CBreakEvenEvaluator evaluator;
   CStrategyDecisionSet decisions=evaluator.Evaluate(context);
   CTestAssert::EqualInt(1,decisions.Count(),"Realized profit threshold must produce one BE decision");
   CTestAssert::EqualInt(BRE_STRATEGY_DECISION_MOVE_BREAK_EVEN,decisions.DecisionAt(0).Type(),"Realized profit BE must move SL");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestBreakEvenAfterSpecificLevel();
   TestBreakEvenAfterRealizedProfit();
   CTestAssert::Summary("TestBreakEvenEvaluator");
  }
