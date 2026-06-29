#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/BreakEvenCandidateEventBuffer.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/StrategyMetadata.mqh>
#include <BasketRecovery/Domain/Configuration/ExecutionProfileConfig.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenRule.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenTrigger.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenAction.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

CStrategyProfile BuildBreakEvenProfile(const CBreakEvenRule &rules[],const int ruleCount)
  {
   CProfitLevel levels[];
   ArrayResize(levels,0);
   CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,0);
   CRecoveryStep steps[1];
   steps[0]=CRecoveryStep::Create(1,0.2,0.01);
   CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,1,true,true,3,0.01);
   CBreakEvenPlan breakEven=CBreakEvenPlan::Create(rules,ruleCount);
   CRiskPlan risk=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);
   CExecutionProfileConfig executionPolicy;
   return CStrategyProfile::Create("be-candidate-test",BRE_STRATEGY_SCHEMA_VERSION,
                                   CStrategyMetadata::Create("BE Candidate Test","",""),
                                   zone,recovery,profitPlan,breakEven,risk,executionPolicy,CUtcTime(0));
  }

CBreakEvenRule BuildFloatingMoneyRule(const string ruleId,const double thresholdUsd)
  {
   CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_FLOATING_PROFIT,0.0,false,
                                                       thresholdUsd,true,0.0,false,"","","","");
   CBreakEvenAction actions[2];
   actions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_MOVE_SL_TO_AVERAGE,0.0,0.5,true,false);
   actions[1]=CBreakEvenAction::Create(BRE_BE_ACTION_DISABLE_RECOVERY,0.0,0.0,false,false);
   return CBreakEvenRule::Create(ruleId,true,1,true,trigger,actions,2);
  }

CBreakEvenEvaluationContext BuildContext(const CStrategyProfile &profile,
                                         const ENUM_BRE_TRADE_DIRECTION direction,
                                         const double bid,
                                         const double ask,
                                         const double pipSize,
                                         const double point,
                                         const double tickSize,
                                         const double floatingProfitUsd,
                                         const CPositionRuntimeView &positions[],
                                         const int positionCount,
                                         const CSymbolTradingConstraints &constraints,
                                         const bool breakEvenActive=false,
                                         const bool pendingExecution=false,
                                         const ulong quoteSequence=1,
                                         const int freshnessAgeMs=0,
                                         const double basketStopLoss=0.0)
  {
   CMarketContext market=CMarketContext::Create("XAUUSD",bid,ask,pipSize);
   string executed[];
   ArrayResize(executed,0);
   CProfitLevelRuntimeState profitStates[];
   ArrayResize(profitStates,0);
   CBasketProfitLevelProgress progress[];
   ArrayResize(progress,0);
   return CBreakEvenEvaluationContext::Create(CBasketId("be-plan-test"),1,"hash","XAUUSD",direction,
                                            BRE_STATE_ACTIVE,false,breakEvenActive,false,false,
                                            executed,0,profile,market,positions,positionCount,
                                            profitStates,0,progress,0,floatingProfitUsd,0.0,10000.0,100.0,false,
                                            basketStopLoss,point,tickSize,constraints,quoteSequence,
                                            freshnessAgeMs,5000,pendingExecution,true,true,1000);
  }

void TestBuyWeightedAverageDue(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_BUY",10.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[2];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,5.0,10.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   positions[1]=CPositionRuntimeView::Create(2,102.0,0.10,5.0,10.0,200,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,2,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_DUE,(int)candidate.Status(),"BUY floating trigger must reach DUE");
   CTestAssert::EqualDouble(101.0,candidate.Audit().WeightedAverageEntry(),0.001,"BUY weighted average entry");
   CTestAssert::EqualDouble(101.25,candidate.Audit().ProposedStopLoss(),0.001,"BUY SL = avg + spread + buffer");
   CTestAssert::True(candidate.Audit().RecoveryDisableRecommended(),"Disable recovery recommendation captured");
  }

void TestSellWeightedAverageDue(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_SELL",10.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[2];
   positions[0]=CPositionRuntimeView::Create(1,4020.0,0.10,5.0,10.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   positions[1]=CPositionRuntimeView::Create(2,4018.0,0.10,5.0,10.0,200,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_SELL,4010.0,4010.2,0.1,0.01,0.01,50.0,positions,2,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_DUE,(int)candidate.Status(),"SELL floating trigger must reach DUE");
   CTestAssert::EqualDouble(4019.0,candidate.Audit().WeightedAverageEntry(),0.001,"SELL weighted average entry");
   CTestAssert::EqualDouble(4018.75,candidate.Audit().ProposedStopLoss(),0.001,"SELL SL = avg - spread - buffer");
  }

void TestSpreadAndSafetyBufferComponents(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_SPREAD",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,2000.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,2001.0,2001.4,0.1,0.01,0.01,5.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualDouble(0.4,candidate.Audit().PriceCalculation().SpreadComponent(),0.001,"Spread component");
   CTestAssert::EqualDouble(0.05,candidate.Audit().PriceCalculation().SafetyBufferComponent(),0.001,"Safety buffer component");
  }

void TestTickSizeNormalization(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_TICK",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,1.234,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,1.30,1.31,0.01,0.01,0.05,5.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   double normalized=candidate.Audit().ProposedStopLoss();
   CTestAssert::True(MathMod(normalized,0.05)<0.00001,"Proposed SL must align to tick size");
  }

void TestInvalidStopLevel(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_STOP",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(500,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,100.5,100.7,0.1,0.01,0.01,5.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_INVALID_STOP_PRICE,(int)candidate.Status(),"Stop-level violation must block");
  }

void TestInvalidFreezeLevel(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_FREEZE",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_SELL,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,500,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_SELL,99.0,99.2,0.1,0.01,0.01,5.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_INVALID_STOP_PRICE,(int)candidate.Status(),"Freeze-level violation must block");
  }

void TestTriggerNotReached(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_NR",100.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,10.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED,(int)candidate.Status(),"Trigger below threshold");
  }

void TestAlreadyActivatedSkip(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_ACTIVE",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints,true);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_ALREADY_ACTIVATED,(int)candidate.Status(),"Active BE must skip");
  }

void TestStaleQuote(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_STALE",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints,false,false,1,6000);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_INVALID_MARKET_CONTEXT,(int)candidate.Status(),"Stale quote blocks");
  }

void TestPendingExecutionBlock(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_PEND",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints,false,true);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_PENDING_EXECUTION,(int)candidate.Status(),"Pending execution blocks");
  }

void TestNoOpenPositions(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_NOPOS",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[];
   ArrayResize(positions,0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,0,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_BLOCKED_BY_SAFETY,(int)candidate.Status(),"Missing positions block");
  }

void TestInvalidProfile(void)
  {
   CBreakEvenRule rules[];
   ArrayResize(rules,0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,0);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_INVALID_PROFILE,(int)candidate.Status(),"Empty BE plan invalid");
  }

void TestDuplicateQuoteDedupe(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_DUP",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,true);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_NOT_REACHED,(int)candidate.Status(),"Duplicate quote deduped");
  }

void TestEventBufferDedupe(void)
  {
   CBreakEvenCandidateEventBuffer buffer;
   CBreakEvenCandidateAudit audit=CBreakEvenCandidateAudit::Create(CBasketId("be"),"hash",1,"BE1",
      BRE_BE_CANDIDATE_TRIGGER_FLOATING_PROFIT_MONEY,10.0,100.0,0.1,100.0,100.2,
      CBreakEvenPriceCalculation::Invalid(),0.0,BRE_DIRECTION_BUY,7,false,false,false,"key",1000,
      BRE_BREAK_EVEN_CANDIDATE_DUE,BRE_BREAK_EVEN_REASON_NONE,BRE_BREAK_EVEN_PROGRESS_CANDIDATE_GENERATED);
   CBreakEvenCandidateDomainEvent event=CBreakEvenCandidateDomainEvent::Create(BRE_EVENT_BREAK_EVEN_CANDIDATE_AVAILABLE,
      CBasketId("be"),"corr",1000,audit,7);
   CTestAssert::True(buffer.TryEmit(event),"First event emits");
   CTestAssert::False(buffer.TryEmit(event),"Duplicate event blocked");
  }

void TestDueDoesNotMutateProgressFlags(void)
  {
   CBreakEvenRule rules[1];
   rules[0]=BuildFloatingMoneyRule("BE_PROGRESS",1.0);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_DUE,(int)candidate.Status(),"Candidate due");
   CTestAssert::EqualInt(BRE_BREAK_EVEN_PROGRESS_CANDIDATE_GENERATED,(int)candidate.Audit().ProgressState(),"Progress is candidate-only");
   CTestAssert::False(ctx.BreakEvenActive(),"Context break-even flag unchanged");
  }

void TestUnsupportedTriggerNotImplemented(void)
  {
   CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_SPECIFIC_EVENT,0.0,false,0.0,false,0.0,false,"","","evt","");
   CBreakEvenAction actions[1];
   actions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_MOVE_SL_TO_AVERAGE,0.0,0.5,true,false);
   CBreakEvenRule rules[1];
   rules[0]=CBreakEvenRule::Create("BE_FUTURE",true,1,true,trigger,actions,1);
   CStrategyProfile profile=BuildBreakEvenProfile(rules,1);
   CPositionRuntimeView positions[1];
   positions[0]=CPositionRuntimeView::Create(1,100.0,0.10,1.0,1.0,100,BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CBreakEvenEvaluationContext ctx=BuildContext(profile,BRE_DIRECTION_BUY,101.0,101.2,0.1,0.01,0.01,50.0,positions,1,constraints);
   CBreakEvenCandidatePlanner planner;
   CBreakEvenCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_BREAK_EVEN_CANDIDATE_NOT_IMPLEMENTED,(int)candidate.Status(),"Future trigger returns NOT_IMPLEMENTED");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestBuyWeightedAverageDue();
   TestSellWeightedAverageDue();
   TestSpreadAndSafetyBufferComponents();
   TestTickSizeNormalization();
   TestInvalidStopLevel();
   TestInvalidFreezeLevel();
   TestTriggerNotReached();
   TestAlreadyActivatedSkip();
   TestStaleQuote();
   TestPendingExecutionBlock();
   TestNoOpenPositions();
   TestInvalidProfile();
   TestDuplicateQuoteDedupe();
   TestEventBufferDedupe();
   TestDueDoesNotMutateProgressFlags();
   TestUnsupportedTriggerNotImplemented();
   CTestAssert::Summary("TestBreakEvenCandidatePlanner");
  }
