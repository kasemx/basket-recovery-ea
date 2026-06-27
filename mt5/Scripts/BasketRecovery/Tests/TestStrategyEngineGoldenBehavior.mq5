#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/StrategyDecisionType.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>

void TestGoldenRecoveryDecision(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState states[];
   ArrayResize(states,0);
   CPositionRuntimeView positions[];
   ArrayResize(positions,0);

   CStrategyEvaluationContext context=CStrategyEngineTestFixture::BuildContext(profile,
                                                                               BRE_DIRECTION_SELL,
                                                                               4014.0,
                                                                               4017.0,
                                                                               4017.0,
                                                                               4017.1,
                                                                               0.2,
                                                                               0.0,
                                                                               0.8,
                                                                               0.0,
                                                                               true,
                                                                               0,
                                                                               false,
                                                                               states,
                                                                               0,
                                                                               positions,
                                                                               0);

   CStrategyEngineAdapter engine;
   CStrategyDecisionSet recovery=engine.EvaluateRecovery(context);
   CTestAssert::EqualInt(1,recovery.Count(),"Golden profile must open first custom recovery step");
   CTestAssert::EqualInt(BRE_STRATEGY_DECISION_OPEN_RECOVERY,recovery.DecisionAt(0).Type(),"Recovery decision type must match");
   CTestAssert::EqualInt(1,recovery.DecisionAt(0).OpenRecovery().StepIndex(),"First recovery step index must be 1");
   CTestAssert::EqualDouble(0.01,recovery.DecisionAt(0).OpenRecovery().Lot(),0.0001,"First recovery lot must be 0.01");
  }

void TestDuplicateDecisionsRemoved(void)
  {
   CStrategyDecisionSet set=CStrategyDecisionSet::Create();
   COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create("dup-key",1,0.2,0.01,4019.0,BRE_TRADE_ROLE_RECOVERY);
   CTestAssert::True(set.Add(CStrategyDecision::FromOpenRecovery(openDecision)),"First decision must be added");
   CTestAssert::False(set.Add(CStrategyDecision::FromOpenRecovery(openDecision)),"Duplicate idempotency key must be rejected");
   CTestAssert::EqualInt(1,set.Count(),"Decision set must contain one decision after dedupe");
  }

void TestDisableRecoveryAfterBreakEven(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState states[1];
   states[0]=CProfitLevelRuntimeState::Create("L1",true,false,0.0,false);
   CPositionRuntimeView positions[];
   ArrayResize(positions,0);

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
                                                                               positions,
                                                                               0);

   CStrategyEngineAdapter engine;
   CStrategyDecisionSet all=engine.EvaluateAll(context);

   bool disableFound=false;
   for(int i=0;i<all.Count();i++)
     {
      if(all.DecisionAt(i).Type()==BRE_STRATEGY_DECISION_DISABLE_RECOVERY)
         disableFound=true;
     }
   CTestAssert::True(disableFound,"Golden evaluate-all must include disable recovery after BE rule");
  }

void TestGoldenProfitLevelDecision(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState states[1];
   states[0]=CProfitLevelRuntimeState::Create("L1",true,false,0.0,false);

   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(301,4018.0,0.01,5.0,10.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);

   CStrategyEvaluationContext context=CStrategyEngineTestFixture::BuildContext(profile,
                                                                               BRE_DIRECTION_SELL,
                                                                               4014.0,
                                                                               4017.0,
                                                                               4010.0,
                                                                               4010.1,
                                                                               0.0,
                                                                               12.0,
                                                                               0.8,
                                                                               0.0,
                                                                               true,
                                                                               0,
                                                                               false,
                                                                               states,
                                                                               1,
                                                                               positions,
                                                                               1);

   CStrategyEngineAdapter engine;
   CStrategyDecisionSet profit=engine.EvaluateProfitDistribution(context);
   CTestAssert::EqualInt(1,profit.Count(),"Reached L1 must produce close decision");
   CTestAssert::EqualString("L1",profit.DecisionAt(0).ClosePositions().LevelId(),"Close decision must reference L1");
   CTestAssert::EqualDouble(33.0,profit.DecisionAt(0).ClosePositions().ClosePercent(),0.0001,"Golden L1 close percent must be 33");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestGoldenRecoveryDecision();
   TestDuplicateDecisionsRemoved();
   TestDisableRecoveryAfterBreakEven();
   TestGoldenProfitLevelDecision();
   CTestAssert::Summary("TestStrategyEngineGoldenBehavior");
  }
