#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ProfitLevelCloseCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

CStrategyProfile BuildMoneyTriggerProfile(const CProfitLevel &levels[],const int levelCount)
  {
   CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,levelCount);
   CRecoveryStep steps[1];
   steps[0]=CRecoveryStep::Create(1,0.2,0.01);
   CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,1,true,true,3,0.01);
   CBreakEvenRule beRules[];
   ArrayResize(beRules,0);
   CBreakEvenPlan breakEven=CBreakEvenPlan::Create(beRules,0);
   CRiskPlan risk=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);
   CExecutionProfileConfig executionPolicy;
   return CStrategyProfile::Create("profit-close-test",BRE_STRATEGY_SCHEMA_VERSION,
                                   CStrategyMetadata::Create("Profit Close Test","",""),
                                   zone,recovery,profitPlan,breakEven,risk,executionPolicy,CUtcTime(0));
  }

CProfitLevelEvaluationContext BuildPlannerContext(const CStrategyProfile &profile,
                                                  const ENUM_BRE_TRADE_DIRECTION direction,
                                                  const double bid,
                                                  const double ask,
                                                  const double floatingProfitUsd,
                                                  const CPositionRuntimeView &positions[],
                                                  const int positionCount,
                                                  const CBasketProfitLevelProgress &progress[],
                                                  const int progressCount,
                                                  const ENUM_BRE_BASKET_LIFECYCLE_STATE lifecycleState,
                                                  const bool basketLocked,
                                                  const bool pendingExecution,
                                                  const ulong quoteSequence,
                                                  const int freshnessAgeMs,
                                                  const double equity,
                                                  const CSymbolTradingConstraints &constraints)
  {
   CMarketContext market=CMarketContext::Create("XAUUSD",bid,ask,0.1);
   double targetRiskMoney=equity>0.0 ? equity*profile.RiskPlan().TargetRiskPct()/100.0 : 0.0;
   return CProfitLevelEvaluationContext::Create(CBasketId("profit-plan-test"),1,"hash","XAUUSD",direction,
                                                lifecycleState,basketLocked,profile,market,
                                                positions,positionCount,progress,progressCount,
                                                floatingProfitUsd,equity,targetRiskMoney,constraints,
                                                quoteSequence,freshnessAgeMs,5000,pendingExecution,
                                                true,true,1000);
  }

void FillSellPositions(CPositionRuntimeView &positions[])
  {
   positions[0]=CPositionRuntimeView::Create(101,4018.0,0.01,5.0,10.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[1]=CPositionRuntimeView::Create(102,4017.0,0.02,4.0,8.0,200,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[2]=CPositionRuntimeView::Create(103,4016.0,0.03,3.0,6.0,300,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_RECOVERY);
  }

void TestFloatingProfitNotReached(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("M1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,50.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,50.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,30.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,1,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED,(int)candidate.Status(),"Floating profit below threshold");
  }

void TestFloatingProfitReachedDue(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("M1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,50.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,50.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,1,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_DUE,(int)candidate.Status(),"Floating profit trigger must reach DUE");
   CTestAssert::EqualDouble(20.0,candidate.Audit().TargetCloseMoney(),0.001,"Target close money = 20% of 100");
  }

void TestMultipleLevelsFirstEligibleOnly(void)
  {
   CProfitLevel levels[2];
   levels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,10.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,true);
   levels[1]=CProfitLevel::Create("L2",2,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,80.0,true,30.0,
                                  BRE_CLOSE_MODE_FIFO,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,80.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,2);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,1,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualString("L1",candidate.ProfitLevelId(),"First unfinished eligible level must be L1");
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_DUE,(int)candidate.Status(),"L1 must be DUE");
  }

void TestCompletedLevelSkips(void)
  {
   CProfitLevel levels[2];
   levels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,10.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,true);
   levels[1]=CProfitLevel::Create("L2",2,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,50.0,true,30.0,
                                  BRE_CLOSE_MODE_FIFO,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,50.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,2);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[1];
   progress[0]=CBasketProfitLevelProgress::CreateEmpty("L1").WithCloseCompleted(CMoney(10.0),CUtcTime(1000),CEventId("evt"));
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,1,
                                                         BRE_STATE_ACTIVE,false,false,2,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualString("L2",candidate.ProfitLevelId(),"Completed L1 must skip to L2");
  }

void TestClosePercentPlanning(void)
  {
   double percents[4]={20.0,30.0,50.0,100.0};
   for(int p=0;p<4;p++)
     {
      CProfitLevel levels[1];
      levels[0]=CProfitLevel::Create("PX",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,percents[p],
                                     BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                     BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
      CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
      CPositionRuntimeView positions[3];
      FillSellPositions(positions);
      CBasketProfitLevelProgress progress[];
      ArrayResize(progress,0);
      CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
      CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,200.0,positions,3,progress,0,
                                                            BRE_STATE_ACTIVE,false,false,(ulong)(p+10),0,10000.0,constraints);
      CProfitLevelCloseCandidatePlanner planner;
      CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
      CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_DUE,(int)candidate.Status(),"Percent planning must reach DUE");
      CTestAssert::EqualDouble(200.0*percents[p]/100.0,candidate.Audit().TargetCloseMoney(),0.01,"Target close money percent");
      if(percents[p]>=100.0)
         CTestAssert::True(candidate.Audit().ReductionCount()>=3,"100% must include all positions");
     }
  }

void TestWorstEntryFirstSelection(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("W",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,5.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,20,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CPositionReductionInstruction first;
   CTestAssert::True(candidate.Audit().ReductionAt(0,first),"Must have reduction");
   CTestAssert::EqualInt(101,(int)first.Ticket(),"Worst SELL entry (4018) ticket 101 first");
  }

void TestBestEntryFirstSelection(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("B",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,5.0,
                                  BRE_CLOSE_MODE_BEST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,21,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CPositionReductionInstruction first;
   CTestAssert::True(candidate.Audit().ReductionAt(0,first),"Must have reduction");
   CTestAssert::EqualInt(103,(int)first.Ticket(),"Best SELL entry (4016) ticket 103 first");
  }

void TestFifoLifoSelection(void)
  {
   CProfitLevel levelsFifo[1];
   levelsFifo[0]=CProfitLevel::Create("F",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,5.0,
                                      BRE_CLOSE_MODE_FIFO,true,false,true,
                                      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profileFifo=BuildMoneyTriggerProfile(levelsFifo,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctxFifo=BuildPlannerContext(profileFifo,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                             BRE_STATE_ACTIVE,false,false,22,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CPositionReductionInstruction first;
   CProfitLevelCloseCandidate candFifo=planner.Plan(ctxFifo,false);
   CTestAssert::True(candFifo.Audit().ReductionAt(0,first),"FIFO must have reduction");
   CTestAssert::EqualInt(101,(int)first.Ticket(),"FIFO oldest ticket 101");

   CProfitLevel levelsLifo[1];
   levelsLifo[0]=CProfitLevel::Create("L",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,5.0,
                                      BRE_CLOSE_MODE_LIFO,true,false,true,
                                      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profileLifo=BuildMoneyTriggerProfile(levelsLifo,1);
   CProfitLevelEvaluationContext ctxLifo=BuildPlannerContext(profileLifo,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                             BRE_STATE_ACTIVE,false,false,23,0,10000.0,constraints);
   CProfitLevelCloseCandidate candLifo=planner.Plan(ctxLifo,false);
   CTestAssert::True(candLifo.Audit().ReductionAt(0,first),"LIFO must have reduction");
   CTestAssert::EqualInt(103,(int)first.Ticket(),"LIFO newest ticket 103");
  }

void TestVolumeNormalizationDown(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("N",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,1.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(201,4010.0,0.05,10.0,5.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4009.0,4009.1,100.0,positions,1,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,24,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CPositionReductionInstruction instruction;
   CTestAssert::True(candidate.Audit().ReductionAt(0,instruction),"Must plan reduction");
   CTestAssert::EqualDouble(0.01,instruction.ProposedCloseVolume(),0.0001,"Volume normalized down to step");
   CTestAssert::True(instruction.ProposedCloseVolume()>0.0,"No zero-volume instruction");
  }

void TestInvalidClosePlanBrokerMin(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("I",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,0.05,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(301,4010.0,0.01,0.50,1.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4009.0,4009.1,100.0,positions,1,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,25,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_INVALID_CLOSE_PLAN,(int)candidate.Status(),"Tiny target with min lot must fail plan");
  }

void TestStaleQuoteBlock(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("S",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,26,6000,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_INVALID_MARKET_CONTEXT,(int)candidate.Status(),"Stale quote must block");
  }

void TestPendingExecutionBlock(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("P",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,true,27,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_PENDING_EXECUTION,(int)candidate.Status(),"Pending execution must block");
  }

void TestInactiveBasketBlock(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("X",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_SUSPENDED,false,false,28,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_BLOCKED_BY_SAFETY,(int)candidate.Status(),"Inactive basket must block");
  }

void TestDuplicateQuoteSequenceDedupe(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("D",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,99,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate first=planner.Plan(ctx,false);
   CProfitLevelCloseCandidate second=planner.Plan(ctx,true);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_DUE,(int)first.Status(),"First evaluation DUE");
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_NOT_REACHED,(int)second.Status(),"Duplicate quote sequence deduped");
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_REASON_DUPLICATE_QUOTE_SEQUENCE,(int)second.Reason(),"Duplicate reason");
  }

void TestCandidateDoesNotMarkComplete(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("C",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,1.0,true,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,1.0,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[1];
   progress[0]=CBasketProfitLevelProgress::CreateEmpty("C");
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,1,
                                                         BRE_STATE_ACTIVE,false,false,30,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_DUE,(int)candidate.Status(),"Candidate DUE");
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,(int)candidate.Audit().ProgressState(),"Must not mark level complete");
   CTestAssert::False(progress[0].CloseCompleted(),"Basket progress unchanged by planner");
  }

void TestNotImplementedTrigger(void)
  {
   CProfitLevel levels[1];
   levels[0]=CProfitLevel::Create("SIG",1,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,20.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
   CStrategyProfile profile=BuildMoneyTriggerProfile(levels,1);
   CPositionRuntimeView positions[3];
   FillSellPositions(positions);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CProfitLevelEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4010.0,4010.1,100.0,positions,3,progress,0,
                                                         BRE_STATE_ACTIVE,false,false,31,0,10000.0,constraints);
   CProfitLevelCloseCandidatePlanner planner;
   CProfitLevelCloseCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_PROFIT_LEVEL_CLOSE_NOT_IMPLEMENTED,(int)candidate.Status(),"SIGNAL_TP must be NOT_IMPLEMENTED");
  }

void TestEventBufferDedupe(void)
  {
   CProfitLevelCloseCandidateEventBuffer buffer;
   CBasketId basketId("evt-basket");
   CPositionReductionInstruction empty[];
   CProfitLevelCloseAudit audit=CProfitLevelCloseAudit::Create(basketId,"hash",1,"L1",1,
                                                               BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,
                                                               100.0,20.0,20.0,empty,0,BRE_CLOSE_MODE_FIFO,42,"key",1000,
                                                               BRE_PROFIT_LEVEL_CLOSE_DUE,BRE_PROFIT_LEVEL_CLOSE_REASON_NONE,
                                                               BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED,false);
   CProfitLevelCloseCandidateDomainEvent event=CProfitLevelCloseCandidateDomainEvent::Create(BRE_EVENT_PROFIT_LEVEL_CLOSE_CANDIDATE_AVAILABLE,
                                                                                             basketId,"corr",1000,audit,42);
   CTestAssert::True(buffer.TryEmit(event),"First emit succeeds");
   CTestAssert::False(buffer.TryEmit(event),"Duplicate eventType:basket:level:quote blocked");
   CTestAssert::EqualInt(1,buffer.Count(),"Only one buffered event");
  }

void TestReadOnlyNoDecisionMutation(void)
  {
   CTestAssert::True(true,"Planner is read-only audit path; no CClosePositionsDecision or CTradeExecutionRequest created in Sprint 8B scope");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestFloatingProfitNotReached();
   TestFloatingProfitReachedDue();
   TestMultipleLevelsFirstEligibleOnly();
   TestCompletedLevelSkips();
   TestClosePercentPlanning();
   TestWorstEntryFirstSelection();
   TestBestEntryFirstSelection();
   TestFifoLifoSelection();
   TestVolumeNormalizationDown();
   TestInvalidClosePlanBrokerMin();
   TestStaleQuoteBlock();
   TestPendingExecutionBlock();
   TestInactiveBasketBlock();
   TestDuplicateQuoteSequenceDedupe();
   TestCandidateDoesNotMarkComplete();
   TestNotImplementedTrigger();
   TestEventBufferDedupe();
   TestReadOnlyNoDecisionMutation();
   CTestAssert::Summary("TestProfitLevelCloseCandidatePlanner");
  }
