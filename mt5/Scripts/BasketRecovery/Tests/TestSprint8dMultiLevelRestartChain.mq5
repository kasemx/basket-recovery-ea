#property script_show_inputs

#include "../../../Include/BasketRecovery/Tests/TestAssert.mqh"
#include "../../../Include/BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh"
#include "../../../Include/BasketRecovery/Domain/Aggregates/BasketAggregate.mqh"
#include "../../../Include/BasketRecovery/Domain/Factories/BasketFactory.mqh"
#include "../../../Include/BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh"
#include "../../../Include/BasketRecovery/Domain/Enums/BasketLifecycleState.mqh"
#include "../../../Include/BasketRecovery/Shared/Constants/StrategySchema.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Money.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Identifiers.mqh"

const string TEST_BASKET_ID="basket-8d3-restart-chain";
const ulong TEST_QUOTE_SEQUENCE=888;

CStrategyProfile BuildThreeLevelProfile(void)
  {
   CProfitLevel levels[3];
   levels[0]=CProfitLevel::Create("M1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,10.0,true,33.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,true);
   levels[1]=CProfitLevel::Create("M2",2,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,20.0,true,33.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,20.0,true);
   levels[2]=CProfitLevel::Create("M3",3,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,30.0,true,34.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,30.0,true);
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
   return CStrategyProfile::Create("sprint-8d3-profile",BRE_STRATEGY_SCHEMA_VERSION,
                                   CStrategyMetadata::Create("Sprint 8D3","",""),
                                   zone,recovery,profitPlan,breakEven,risk,executionPolicy,CUtcTime(1000));
  }

CBasketAggregate BuildBasketWithReachedLevels(const CStrategyProfile &profile)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,"",boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(TEST_BASKET_ID),legacy,snapshot,
                                                                      "corr-"+TEST_BASKET_ID,BRE_DIRECTION_BUY,"EURUSD",
                                                                      CSignalId("sig-"+TEST_BASKET_ID),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.ApplyProfitLevelReached("M1",CUtcTime(1001),CCommandId("reach-m1"),CEventId("reach-evt-m1"));
   basket.ApplyProfitLevelReached("M2",CUtcTime(1002),CCommandId("reach-m2"),CEventId("reach-evt-m2"));
   basket.ApplyProfitLevelReached("M3",CUtcTime(1003),CCommandId("reach-m3"),CEventId("reach-evt-m3"));
   return basket;
  }

void MarkLevelCompleted(CBasketAggregate &basket,const string levelId,const datetime completedAt)
  {
   basket.ApplyProfitLevelCloseCompleted(levelId,CMoney(1.0),CCommandId("close-"+levelId),CEventId("close-evt-"+levelId),
                                         CUtcTime(completedAt));
  }

bool LevelIsCompleted(const CBasketAggregate &basket,const string levelId)
  {
   CBasketProfitLevelProgress progress;
   if(!basket.FindProfitLevelProgress(levelId,progress))
      return false;
   return progress.CloseCompleted();
  }

void TestMultiLevelRestartChain(void)
  {
   CStrategyProfile profile=BuildThreeLevelProfile();
   CBasketAggregate basket=BuildBasketWithReachedLevels(profile);

   MarkLevelCompleted(basket,"M1",1101);
   string afterM1="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(basket,profile,afterM1),
                     "M1 completed must still leave an eligible level");
   CTestAssert::EqualString("M2",afterM1,"M1 completed must select M2");
   CTestAssert::True(afterM1!="M1","completed M1 must not be selected again");

   MarkLevelCompleted(basket,"M2",1102);
   string afterM2="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(basket,profile,afterM2),
                     "M2 completed must still leave an eligible level");
   CTestAssert::EqualString("M3",afterM2,"M2 completed must select M3");
   CTestAssert::True(afterM2!="M1" && afterM2!="M2","completed M1 and M2 must not be selected again");

   CBasketAggregate restored(basket);
   CTestAssert::True(LevelIsCompleted(restored,"M1"),"restart must preserve M1 completed");
   CTestAssert::True(LevelIsCompleted(restored,"M2"),"restart must preserve M2 completed");
   CTestAssert::False(LevelIsCompleted(restored,"M3"),"restart must keep M3 open");

   string afterRestart="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restored,profile,afterRestart),
                     "post-restart basket must still have eligible level");
   CTestAssert::EqualString("M3",afterRestart,"post-restart planner must still select M3");

   string seenIds[];
   int seenCount=0;
   string firstLevel="";
   string firstCandidateId="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::TryPlanNextLevelCandidate(TEST_BASKET_ID,
                                                                                        restored,
                                                                                        profile,
                                                                                        TEST_QUOTE_SEQUENCE,
                                                                                        seenIds,
                                                                                        seenCount,
                                                                                        firstLevel,
                                                                                        firstCandidateId),
                     "first M3 planning pass must produce one candidate");
   CTestAssert::EqualString("M3",firstLevel,"first candidate level must be M3");
   CTestAssert::True(StringFind(firstCandidateId,":level:M3:")>=0,"candidate id must contain :level:M3:");

   string duplicateLevel="";
   string duplicateCandidateId="";
   CTestAssert::False(CProfitLevelCloseCandidatePlanningService::TryPlanNextLevelCandidate(TEST_BASKET_ID,
                                                                                           restored,
                                                                                           profile,
                                                                                           TEST_QUOTE_SEQUENCE,
                                                                                           seenIds,
                                                                                           seenCount,
                                                                                           duplicateLevel,
                                                                                           duplicateCandidateId),
                      "same quote sequence must not create duplicate M3 candidate");
   CTestAssert::EqualInt(1,seenCount,"duplicate planning must keep candidate count unchanged");

   MarkLevelCompleted(restored,"M3",1103);
   string afterM3="";
   CTestAssert::False(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restored,profile,afterM3),
                      "all levels completed must return no eligible profit-close level");
   CTestAssert::EqualString("",afterM3,"no level should be selected after M3 completion");

   string afterAllCompletedLevel="";
   string afterAllCompletedCandidateId="";
   CTestAssert::False(CProfitLevelCloseCandidatePlanningService::TryPlanNextLevelCandidate(TEST_BASKET_ID,
                                                                                         restored,
                                                                                         profile,
                                                                                         TEST_QUOTE_SEQUENCE,
                                                                                         seenIds,
                                                                                         seenCount,
                                                                                         afterAllCompletedLevel,
                                                                                         afterAllCompletedCandidateId),
                      "post-completion planning must not create another M3 candidate");
   CTestAssert::EqualInt(1,seenCount,"post-completion planning must keep prior M3 candidate count");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestMultiLevelRestartChain();
   CTestAssert::Summary("TestSprint8dMultiLevelRestartChain");
  }
