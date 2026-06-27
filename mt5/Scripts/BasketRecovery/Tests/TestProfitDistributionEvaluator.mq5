#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitDistributionEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

CStrategyProfile BuildCustomProfitProfile(void)
  {
   CProfitLevel levels[3];
   levels[0]=CProfitLevel::Create("P20",1,BRE_PROFIT_LEVEL_SOURCE_FIXED_PRICE,4010.0,true,20.0,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
   levels[1]=CProfitLevel::Create("P30",2,BRE_PROFIT_LEVEL_SOURCE_FIXED_PRICE,4011.0,true,30.0,BRE_CLOSE_MODE_FIFO,true,false,true);
   levels[2]=CProfitLevel::Create("P50",3,BRE_PROFIT_LEVEL_SOURCE_FIXED_PRICE,4012.0,true,50.0,BRE_CLOSE_MODE_LARGEST_LOT_FIRST,true,false,true);
   CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,3);

   CRecoveryStep steps[1];
   steps[0]=CRecoveryStep::Create(1,0.2,0.01);
   CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,1,true,true,3,0.01);
   CBreakEvenRule beRules[];
   ArrayResize(beRules,0);
   CBreakEvenPlan breakEven=CBreakEvenPlan::Create(beRules,0);
   CRiskPlan risk=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);
   CExecutionProfileConfig executionPolicy;

   return CStrategyProfile::Create("profit-test",
                                   BRE_STRATEGY_SCHEMA_VERSION,
                                   CStrategyMetadata::Create("Profit Test","",""),
                                   zone,
                                   recovery,
                                   profitPlan,
                                   breakEven,
                                   risk,
                                   executionPolicy,
                                   CUtcTime(0));
  }

void TestUnlimitedProfitLevels(void)
  {
   CStrategyProfile profile=BuildCustomProfitProfile();
   CProfitLevelRuntimeState states[3];
   states[0]=CProfitLevelRuntimeState::Create("P20",true,false,4010.0,true);
   states[1]=CProfitLevelRuntimeState::Create("P30",true,false,4011.0,true);
   states[2]=CProfitLevelRuntimeState::Create("P50",false,false,4012.0,true);

   CPositionRuntimeView positions[3];
   positions[0]=CPositionRuntimeView::Create(101,4018.0,0.01,5.0,10.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[1]=CPositionRuntimeView::Create(102,4017.0,0.02,4.0,8.0,200,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[2]=CPositionRuntimeView::Create(103,4016.0,0.03,3.0,6.0,300,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_RECOVERY);

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
                                                                               3,
                                                                               positions,
                                                                               3);

   CProfitDistributionEvaluator evaluator;
   CStrategyDecisionSet decisions=evaluator.Evaluate(context);
   CTestAssert::EqualInt(2,decisions.Count(),"Two reached profit levels must produce two close decisions");
   CTestAssert::EqualDouble(20.0,decisions.DecisionAt(0).ClosePositions().ClosePercent(),0.0001,"First close percent must be 20");
   CTestAssert::EqualDouble(30.0,decisions.DecisionAt(1).ClosePositions().ClosePercent(),0.0001,"Second close percent must be 30");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestUnlimitedProfitLevels();
   CTestAssert::Summary("TestProfitDistributionEvaluator");
  }
