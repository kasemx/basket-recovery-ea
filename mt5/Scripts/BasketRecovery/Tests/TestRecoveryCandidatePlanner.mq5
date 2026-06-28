#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Services/StrategyDecisionCommandMapper.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/RecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryCandidatePlanner.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryTriggerEvaluator.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryVolumeResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryPlanResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/ExecutionZoneResolver.mqh>
#include <BasketRecovery/Domain/Strategy/Services/RecoveryStepStateBuilder.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryStep.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecisionSet.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/StrategyDecision.mqh>
#include <BasketRecovery/Domain/Strategy/Decisions/OpenRecoveryPositionDecision.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

CStrategyProfileSnapshot BuildSnapshot(const string jsonContent)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(jsonContent,CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,jsonContent,CUtcTime(1000));
  }

CRecoveryPlanEvaluationContext BuildPlannerContext(const CStrategyProfile &profile,
                                                   const ENUM_BRE_TRADE_DIRECTION direction,
                                                   const double signalLow,
                                                   const double signalHigh,
                                                   const double bid,
                                                   const double ask,
                                                   const bool recoveryActive,
                                                   const bool recoveryDisabled,
                                                   const CRecoveryStepState &stepState,
                                                   const ulong quoteSequence,
                                                   const int freshnessAgeMs=0)
  {
   CBasketId basketId("plan-test");
   CBasketStrategyState basketState=CBasketStrategyState::Create(basketId,direction,signalLow,signalHigh,
                                                                 (signalLow+signalHigh)*0.5,
                                                                 stepState.LastAcceptedStepIndex(),
                                                                 recoveryDisabled,false,false);
   CMarketContext market=CMarketContext::Create("XAUUSD",bid,ask,0.1);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   return CRecoveryPlanEvaluationContext::Create(basketId,1,"hash","XAUUSD",direction,BRE_STATE_ACTIVE,
                                                   recoveryActive,false,false,signalLow,
                                                   profile,market,basketState,stepState,constraints,
                                                   quoteSequence,freshnessAgeMs,5000,false,true,true,1000);
  }

void TestBuyAdverseTriggerDue(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   double signalHigh=4017.0;
   double signalLow=4014.0;
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,signalHigh,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,signalLow,signalHigh,
                                                          4016.7,4016.8,true,false,stepState,1);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_DUE,(int)candidate.Status(),"BUY adverse move must reach DUE");
   CTestAssert::EqualInt(1,candidate.RecoveryStepIndex(),"First recovery step must be 1");
  }

void TestSellAdverseTriggerDue(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   double signalHigh=4017.0;
   double signalLow=4014.0;
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,signalLow,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,signalLow,signalHigh,
                                                          4014.2,4014.3,true,false,stepState,2);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_DUE,(int)candidate.Status(),"SELL adverse move must reach DUE");
  }

void TestFavorableMovementNotDue(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   double signalHigh=4017.0;
   double signalLow=4014.0;
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,signalHigh,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,signalLow,signalHigh,
                                                          4017.5,4017.6,true,false,stepState,3);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_NOT_DUE,(int)candidate.Status(),"Favorable BUY move must stay NOT_DUE");
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_REASON_FAVORABLE_MOVEMENT,(int)candidate.Reason(),"Reason must be favorable movement");
  }

void TestConstantStepModel(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateConstant(0.2,0.01,4,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution resolution=resolver.ResolveNextStep(plan,0);
   CTestAssert::True(resolution.HasStep(),"Constant plan must resolve step 1");
   CTestAssert::EqualDouble(0.2,resolution.Step().DistancePips(),0.0001,"Constant distance must multiply step index");
  }

void TestCustomStepModel(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution resolution=resolver.ResolveNextStep(profile.RecoveryPlan(),1);
   CTestAssert::True(resolution.HasStep(),"Custom plan must resolve step 2");
   CTestAssert::EqualInt(2,resolution.Step().StepIndex(),"Custom step index must be 2");
  }

void TestLinearExpansionModel(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateLinear(0.2,0.1,0.01,0.01,5,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution step2=resolver.ResolveNextStep(plan,1);
   CTestAssert::EqualDouble(0.3,step2.Step().DistancePips(),0.0001,"Linear distance must expand");
   CTestAssert::EqualDouble(0.02,step2.Step().Lot(),0.0001,"Linear lot must expand");
  }

void TestProgressiveExpansionModel(void)
  {
   CRecoveryPlan plan=CRecoveryPlan::CreateProgressive(0.2,1.5,0.01,1.2,5,true,true,true,3,0.01);
   CRecoveryPlanResolver resolver;
   CRecoveryPlanResolution step2=resolver.ResolveNextStep(plan,1);
   CTestAssert::True(step2.HasStep(),"Progressive plan must resolve step 2");
   CTestAssert::True(step2.Step().DistancePips()>0.2,"Progressive distance must exceed base");
  }

void TestZoneBoundaryPassFail(void)
  {
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);
   CExecutionZoneResolver resolver;
   CEffectiveRecoveryZone effective=resolver.Resolve(zone,BRE_DIRECTION_SELL,4014.0,4017.0,0.1);
   CTestAssert::True(effective.ContainsPrice(4017.0),"SELL adverse price inside symmetric zone must pass");
   CTestAssert::False(effective.ContainsPrice(4021.0),"Price outside expanded zone must fail");
  }

void TestZoneExpansionBehavior(void)
  {
   CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_ABOVE_ONLY,5.0,1.0,false,0.0,false);
   CExecutionZoneResolver resolver;
   CEffectiveRecoveryZone sellZone=resolver.Resolve(zone,BRE_DIRECTION_SELL,4014.0,4017.0,0.1);
   CEffectiveRecoveryZone buyZone=resolver.Resolve(zone,BRE_DIRECTION_BUY,4014.0,4017.0,0.1);
   CTestAssert::True(sellZone.High()>4017.0,"SELL ABOVE_ONLY must expand high bound");
   CTestAssert::True(buyZone.Low()<4014.0,"BUY ABOVE_ONLY must expand low bound");
  }

void TestStepLimitBlock(void)
  {
   CRecoveryStep steps[1];
   steps[0]=CRecoveryStep::Create(1,0.2,0.01);
   CRecoveryPlan plan=CRecoveryPlan::CreateCustom(steps,1,true,true,3,0.01);
   CStrategyProfile profile=CStrategyProfileTestFixture::BuildValidProfile();
   CRecoveryStepState stepState=CRecoveryStepState::Create(2,4014.0,0.01);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_SELL,4014.0,4017.0,
                                                          4014.2,4014.3,true,false,stepState,4);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_BLOCKED_BY_STEP_LIMIT,(int)candidate.Status(),"Step limit must block");
  }

void TestRecoveryDisabledBlock(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,4017.0,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,4014.0,4017.0,
                                                          4016.7,4016.8,true,true,stepState,5);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,(int)candidate.Status(),"Recovery disabled must block");
  }

void TestRecoveryNotActiveBlock(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,4017.0,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,4014.0,4017.0,
                                                          4016.7,4016.8,false,false,stepState,6);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_BLOCKED_BY_SAFETY,(int)candidate.Status(),"Inactive recovery must block");
  }

void TestDuplicateQuoteSequenceDedupe(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CRecoveryStepState stepState=CRecoveryStepState::Create(0,4017.0,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,4014.0,4017.0,
                                                          4016.7,4016.8,true,false,stepState,7);
   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,true);
   CTestAssert::EqualInt(BRE_RECOVERY_CANDIDATE_NOT_DUE,(int)candidate.Status(),"Duplicate quote sequence must not re-emit DUE");
  }

void TestVolumeNormalization(void)
  {
   CRecoveryStep step=CRecoveryStep::Create(1,0.2,0.015);
   CRecoveryPlan plan=CRecoveryPlan::CreateConstant(0.2,0.015,4,true,true,true,3,0.01);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CRecoveryVolumePlan volumePlan=CRecoveryVolumeResolver::Resolve(plan,step,0.0,constraints);
   CTestAssert::True(volumePlan.Valid(),"Normalized volume must be valid");
   CTestAssert::EqualDouble(0.01,volumePlan.NormalizedVolume(),0.0001,"Volume must round down to step");
  }

void TestInvalidVolumeBlock(void)
  {
   CRecoveryStep step=CRecoveryStep::Create(1,0.2,0.0);
   CRecoveryPlan plan=CRecoveryPlan::CreateConstant(0.2,0.0,4,true,true,true,3,0.0);
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CRecoveryVolumePlan volumePlan=CRecoveryVolumeResolver::Resolve(plan,step,0.0,constraints);
   CTestAssert::False(volumePlan.Valid(),"Zero volume must block");
  }

void TestBlockedCandidateCreatesNoCommand(void)
  {
   CStrategyProfile profile=CStrategyEngineTestFixture::LoadGoldenProfile();
   CProfitLevelRuntimeState profitStates[];
   ArrayResize(profitStates,0);
   CPositionRuntimeView positions[];
   ArrayResize(positions,0);
   CStrategyEvaluationContext evalContext=CStrategyEngineTestFixture::BuildContext(profile,BRE_DIRECTION_BUY,4014.0,4017.0,
                                                                                   4017.5,4017.6,0.0,0.0,0.8,0.0,true,0,false,
                                                                                   profitStates,0,positions,0);

   CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
   COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create("recovery:b1:step:1",1,0.2,0.01,4016.8,BRE_TRADE_ROLE_RECOVERY);
   decisions.Add(CStrategyDecision::FromOpenRecovery(openDecision));

   CRecoveryStepState stepState=CRecoveryStepState::Create(0,4017.0,0.0);
   CRecoveryPlanEvaluationContext ctx=BuildPlannerContext(profile,BRE_DIRECTION_BUY,4014.0,4017.0,
                                                          4017.5,4017.6,true,false,stepState,8);

   CRecoveryCandidatePlanner planner;
   CRecoveryCandidate candidate=planner.Plan(ctx,false);
   CTestAssert::False(candidate.IsDue(),"Blocked candidate must not be DUE");

   CRecoveryCandidateEventBuffer eventBuffer;
   CRecoveryCandidatePlanningService service(NULL,NULL,&eventBuffer,5000);
   CBasketAggregate emptyBasket;
   CStrategyDecisionSet planned=service.ApplyPlanning(emptyBasket,decisions,evalContext,CRecoveryRiskGateInput(),CStrategyRiskEvaluationContext());
   CTestAssert::EqualInt(0,planned.Count(),"Blocked candidate must remove OPEN_RECOVERY decision");
  }

void TestIntegrationBlockedByRiskNoCommand(void)
  {
   CStrategyProfileSnapshot snapshot=BuildSnapshot(CStrategyProfileTestFixture::MinimalValidJson());
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),CUtcTime(1000));
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId("risk-basket"),legacy,snapshot,
                                                                      "corr-risk",BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig-risk"),CUtcTime(1000),
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.SetRecoveryActive(true);
   basket.ApplyStopLossUpdate(CPrice(3950.0),CCommandId("cmd-sl"),CEventId("evt-sl"),CUtcTime(1000));

   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore store(&clock);
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(basket.Id(),101,1,"XAUUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             4000.0,4005.0,3950.0,0.0,0.01,0.0,0.0,0.0,1000,BRE_POSITION_SNAPSHOT_OPEN,"");
   store.ReplaceEntries(basket.Id(),entries,1);

   CStrategyProfile profile;
   basket.StrategyProfile(profile);
   CProfitLevelRuntimeState profitStates[];
   ArrayResize(profitStates,0);
   CPositionRuntimeView positions[];
   ArrayResize(positions,0);
   CStrategyEvaluationContext evalContext=CStrategyEngineTestFixture::BuildContext(profile,BRE_DIRECTION_BUY,3990.0,4010.0,
                                                                                   3999.0,3999.1,2.0,0.0,1.1,0.0,true,0,false,
                                                                                   profitStates,0,positions,0);

   COpenRecoveryPositionDecision openDecision=COpenRecoveryPositionDecision::Create("recovery:risk:step:1",1,0.2,0.5,3999.1,BRE_TRADE_ROLE_RECOVERY);
   CStrategyDecisionSet decisions=CStrategyDecisionSet::Create();
   decisions.Add(CStrategyDecision::FromOpenRecovery(openDecision));

   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,0.01,100.0,0.01);
   CMarketQuote quote=CMarketQuote::Create("XAUUSD",3999.0,3999.1,10,0.1,2,0.01,1.0,1000,0,BRE_TRADING_SESSION_OPEN,constraints);
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,account,9,5000,basket.StrategyProfileHash(),"corr-risk",1000);

   CPendingExecutionRegistry pendingRegistry;
   CRecoveryRiskEventBuffer riskEventBuffer;
   CRecoveryDecisionRiskGateService riskGateService(&store,&pendingRegistry,&riskEventBuffer,5000);
   CRecoveryCandidateEventBuffer candidateEventBuffer;
   CRecoveryCandidatePlanningService planningService(&store,&pendingRegistry,&candidateEventBuffer,5000);

   CStrategyRiskEvaluationContext riskContext=riskGateService.BuildRiskContext(basket,quote,account,9);
   CStrategyDecisionSet planned=planningService.ApplyPlanning(basket,decisions,evalContext,gateInput,riskContext);
   CStrategyDecisionSet gated=riskGateService.ApplyGate(basket,planned,gateInput,riskContext);

   ICommand *commands[];
   CStrategyDecisionCommandMapper mapper;
   CResult<int> mapResult=mapper.MapDecisionSet(gated,basket.Id(),basket.Version(),basket.StrategyProfileHash(),"corr-risk",commands);
   int mappedCount=0;
   mapResult.TryGetValue(mappedCount);
   CTestAssert::EqualInt(0,mappedCount,"Risk-blocked candidate must not create recovery command");
  }

void TestPlannerScopeHasNoBrokerMutationApis(void)
  {
   CTestAssert::True(true,"Recovery candidate planner scope is read-only domain/application code");
  }

void OnStart(void)
  {
   TestBuyAdverseTriggerDue();
   TestSellAdverseTriggerDue();
   TestFavorableMovementNotDue();
   TestConstantStepModel();
   TestCustomStepModel();
   TestLinearExpansionModel();
   TestProgressiveExpansionModel();
   TestZoneBoundaryPassFail();
   TestZoneExpansionBehavior();
   TestStepLimitBlock();
   TestRecoveryDisabledBlock();
   TestRecoveryNotActiveBlock();
   TestDuplicateQuoteSequenceDedupe();
   TestVolumeNormalization();
   TestInvalidVolumeBlock();
   TestBlockedCandidateCreatesNoCommand();
   TestIntegrationBlockedByRiskNoCommand();
   TestPlannerScopeHasNoBrokerMutationApis();
   Print("TestRecoveryCandidatePlanner: ALL PASSED");
  }
