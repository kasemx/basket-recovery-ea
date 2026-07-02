#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseFilledPendingCompletionService.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh>
#include <BasketRecovery/Application/Strategy/ProfitLevelCloseCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitLevel.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ProfitDistributionPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/ExecutionZone.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RecoveryPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/BreakEvenPlan.mqh>
#include <BasketRecovery/Domain/Strategy/ValueObjects/RiskPlan.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>
#include <BasketRecovery/Domain/Strategy/Enums/ProfitLevelCloseCandidateStatus.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateExecutionRequestFactory.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotStatus.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Types/Money.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>

const string TEST_BASKET_ID="basket-8d6-pending-chain";
const ulong TEST_TICKET=1517000001;
const ulong TEST_QUOTE_SEQUENCE_M2=901;
const ulong TEST_QUOTE_SEQUENCE_M3=902;
const double TEST_REMAINING_VOLUME=0.10;
const double TEST_CLOSE_PERCENT_M2=50.0;
const double TEST_EXPECTED_CLOSE_VOLUME=0.05;
const double TEST_FLOATING_PROFIT_USD=25.0;
const double TEST_M3_TRIGGER_USD=30.0;
const double TEST_FLOATING_PROFIT_M3_DUE_USD=35.0;

CStrategyProfile BuildThreeLevelProfile(void)
  {
   CProfitLevel levels[3];
   levels[0]=CProfitLevel::Create("M1",1,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,10.0,true,33.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,10.0,true);
   levels[1]=CProfitLevel::Create("M2",2,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,20.0,true,TEST_CLOSE_PERCENT_M2,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,20.0,true);
   levels[2]=CProfitLevel::Create("M3",3,BRE_PROFIT_LEVEL_SOURCE_FLOATING_PROFIT_MONEY,30.0,true,34.0,
                                  BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true,
                                  BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,TEST_M3_TRIGGER_USD,true);
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
   return CStrategyProfile::Create("sprint-8d6-profile",BRE_STRATEGY_SCHEMA_VERSION,
                                   CStrategyMetadata::Create("Sprint 8D6","",""),
                                   zone,recovery,profitPlan,breakEven,risk,executionPolicy,CUtcTime(1000));
  }

CBasketAggregate BuildBasketWithM1Completed(const CStrategyProfile &profile)
  {
   string canonicalJson="{\"schemaVersion\":\""+IntegerToString(BRE_STRATEGY_SCHEMA_VERSION)+"\"}";
   CUtcTime boundAt(1000);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,canonicalJson,boundAt);
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
   basket.ApplyProfitLevelCloseCompleted("M1",CMoney(1.0),CCommandId("close-m1"),CEventId("close-evt-m1"),
                                         CUtcTime(1101));
   return basket;
  }

void SeedOpenPosition(CInMemorySnapshotStore &snapshotStore,
                      const CBasketId &basketId,
                      const ulong ticket,
                      const double volume,
                      const double floatingProfitUsd)
  {
   CPositionSnapshotEntry entries[1];
   entries[0]=CPositionSnapshotEntry::Create(basketId,ticket,202607001,"EURUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_INITIAL,0,
                                             1.1000,1.1001,1.0900,1.1100,volume,floatingProfitUsd,0.0,0.0,1000,
                                             BRE_POSITION_SNAPSHOT_OPEN,"");
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,entries,1);
  }

CMarketQuote BuildQuote(void)
  {
   return CMarketQuote::Create("EURUSD",1.1000,1.1001,10,0.0001,2,0.01,100.0,1000,10,
                               BRE_TRADING_SESSION_OPEN,
                               CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
  }

bool LevelIsCloseCompleted(const CBasketAggregate &basket,const string levelId)
  {
   CBasketProfitLevelProgress progress;
   if(!basket.FindProfitLevelProgress(levelId,progress))
      return false;
   return progress.CloseCompleted();
  }

CManualProfitCloseCandidateEntry BuildEntryFromCandidate(const CProfitLevelCloseCandidate &candidate,
                                                        const CBasketAggregate &basket,
                                                        const ulong ticket,
                                                        const double originalPositionVolume,
                                                        const double closeVolume,
                                                        const ulong quoteSequence)
  {
   CPositionReductionInstruction instruction;
   candidate.Audit().ReductionAt(0,instruction);
   datetime now=1000;
   return CManualProfitCloseCandidateEntry::Create(candidate.IdempotencyKey(),
                                                   "profit-close-manual:8d6-chain",
                                                   candidate.IdempotencyKey(),
                                                   basket.Id(),
                                                   candidate.ProfitLevelId(),
                                                   candidate.Audit().ProfitLevelIndex(),
                                                   basket.StrategyProfileHash(),
                                                   basket.Version(),
                                                   basket.Symbol(),
                                                   basket.Direction(),
                                                   BRE_DIRECTION_BUY,
                                                   ticket,
                                                   originalPositionVolume,
                                                   closeVolume,
                                                   instruction.EstimatedCloseMoney(),
                                                   candidate.Audit().TriggerType(),
                                                   candidate.Audit().TriggerValue(),
                                                   quoteSequence,
                                                   now,
                                                   now+360,
                                                   BRE_ACCOUNT_POSITION_MODEL_HEDGING);
  }

void TestMultiLevelPendingRegistrationChain(void)
  {
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBasketRepository repository;
   CPendingExecutionRegistry pendingRegistry;
   CInMemoryPendingExecutionStore pendingStore;
   CProfitLevelCloseCandidateEventBuffer eventBuffer;
   CProfitLevelCloseCandidatePlanningService planningService(&pendingRegistry,&eventBuffer,5000,&pendingStore);

   CStrategyProfile profile=BuildThreeLevelProfile();
   CBasketAggregate basket=BuildBasketWithM1Completed(profile);
   repository.Save(basket);
   SeedOpenPosition(snapshotStore,basket.Id(),TEST_TICKET,TEST_REMAINING_VOLUME,TEST_FLOATING_PROFIT_USD);

   CMarketQuote quote=BuildQuote();
   CAccountContextSnapshot account=CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true);
   CRecoveryRiskGateInput gateInputM2=CRecoveryRiskGateInput::Create(quote,account,TEST_QUOTE_SEQUENCE_M2,5000,
                                                                     basket.StrategyProfileHash(),
                                                                     basket.CorrelationKey(),
                                                                     clock.Now());

   CRiskRuntimeContext riskContext=CRiskRuntimeContext::Create(0.0,1.0,1.2,0.0,true,false);
   CStrategyEvaluationContext evalContext;
   CStrategyEvaluationContextFactory::TryBuild(basket,
                                               CMarketContext::Create(basket.Symbol(),quote.Bid(),quote.Ask(),quote.Point()),
                                               riskContext,
                                               &snapshotStore).TryGetValue(evalContext);

   CProfitLevelCloseCandidate candidate=planningService.EvaluateAndEmit(basket,evalContext,gateInputM2);
   CTestAssert::True(candidate.IsDue(),"EvaluateAndEmit must emit DUE candidate for M2");
   CTestAssert::EqualString("M2",candidate.ProfitLevelId(),"emitted level must be M2");

   CSymbolTradingConstraints constraints=quote.Constraints();
   double emittedCloseVolume=CProfitLevelCloseCandidatePlanningService::ReadEmittedCloseVolume(candidate);
   SProfitCloseVolumeCalculation expectedVolumePlan=
      CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(TEST_REMAINING_VOLUME,
                                                                           TEST_CLOSE_PERCENT_M2,
                                                                           constraints);
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_VOLUME_RESULT_OK,(int)expectedVolumePlan.result,
                         "fixture remaining volume must produce valid close plan");
   CTestAssert::True(CProfitCloseCandidateCloseVolumeCalculator::VolumesMatch(TEST_EXPECTED_CLOSE_VOLUME,
                                                                              emittedCloseVolume,
                                                                              constraints),
                     "emitted closeVolume must be 0.05");
   CTestAssert::True(CProfitCloseCandidateCloseVolumeCalculator::VolumesMatch(expectedVolumePlan.closeVolume,
                                                                              emittedCloseVolume,
                                                                              constraints),
                     "emitted closeVolume must match calculator output for remaining=0.10 at 50%");
   string idemMsg="idempotency must contain :level:M2:";
   CTestAssert::True(StringFind(candidate.IdempotencyKey(),":level:M2:")>=0,idemMsg);

   CManualProfitCloseCandidateEntry entry=BuildEntryFromCandidate(candidate,basket,TEST_TICKET,
                                                                TEST_REMAINING_VOLUME,
                                                                emittedCloseVolume,
                                                                TEST_QUOTE_SEQUENCE_M2);
   CTradeExecutionRequest request=CProfitCloseCandidateExecutionRequestFactory::CreateCloseRequest(entry,
                                                                                                   entry.CloseDirection(),
                                                                                                   clock.Now());
   CTestAssert::EqualString("profit-close-manual:8d6-chain",request.ExecutionRequestId(),"execution request id must match fixture");
   CTestAssert::True(StringFind(request.IdempotencyKey(),":level:M2:")>=0,"request idempotency must contain :level:M2:");
   CTestAssert::True(request.BasketId().Value()!="","request basket id must be non-empty");
   CTestAssert::True(request.StrategyProfileHash()!="","request strategy profile hash must be non-empty");
   CTestAssert::True(request.ExpectedBasketVersion()>0,"request basket version must be valid");
   CTestAssert::EqualString("EURUSD",request.Symbol(),"request symbol must match fixture");
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)request.IntentType(),"request intent must be CLOSE_POSITION");
   CTestAssert::EqualInt((int)entry.CloseDirection(),(int)request.Direction(),"request direction must match close direction");
   CTestAssert::EqualInt((int)TEST_TICKET,(int)request.Ticket(),"execution request must bind fixture ticket");
   CTestAssert::True(CProfitCloseCandidateCloseVolumeCalculator::VolumesMatch(TEST_EXPECTED_CLOSE_VOLUME,
                                                                              request.RequestedVolume(),
                                                                              constraints),
                     "request requestedVolume must be 0.05");

   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(quote);
   marketData.SetAccount(account);
   CSubmissionPreparationValidator prepValidator(&marketData,CMarketSafetyConfig());
   CExecutionSubmissionPreparer preparer(CSubmissionPreparationPolicy::Default(),prepValidator,&pendingRegistry,&pendingStore,&clock);
   preparer.ConfigureRiskReadModel(&snapshotStore,&marketData);
   CSubmissionPreparationResult prep=preparer.Prepare(request,basket,202607001);
   CTestAssert::True(prep.IsSuccess(),"pending preparation must succeed");
   CTestAssert::EqualInt((int)TEST_TICKET,(int)prep.Envelope().Ticket(),"prepared envelope must bind fixture ticket");
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)prep.Envelope().IntentType(),
                         "prepared envelope intent must be CLOSE_POSITION");
   CTestAssert::True(CProfitCloseCandidateCloseVolumeCalculator::VolumesMatch(TEST_EXPECTED_CLOSE_VOLUME,
                                                                              prep.Envelope().RequestedVolume(),
                                                                              constraints),
                     "prepared envelope requestedVolume must be 0.05");

   CPendingExecutionEntry pending;
   CTestAssert::True(pendingRegistry.TryGetByExecutionRequestId(request.ExecutionRequestId(),pending),
                     "pending registry must contain prepared entry");
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_CLOSE_POSITION,(int)pending.IntentType(),
                         "prepared pending intent must be CLOSE_POSITION");
   CTestAssert::True(StringFind(pending.IdempotencyKey(),":level:M2:")>=0,"pending idempotency must retain :level:M2:");
   CTestAssert::True(pending.BasketId().Value()!="","prepared pending basket id must be non-empty");
   CTestAssert::True(CProfitCloseCandidateCloseVolumeCalculator::VolumesMatch(TEST_EXPECTED_CLOSE_VOLUME,
                                                                              pending.RequestedVolume(),
                                                                              constraints),
                     "pending requestedVolume must equal planned closeVolume");

   CBrokerRequestCorrelation broker=pending.BrokerCorrelation();
   broker.SetPositionTicket(TEST_TICKET);
   broker.SetBrokerDealId(1294774509);
   broker.SetBrokerOrderId(1520524749);
   pending.SetBrokerCorrelation(broker);
   pending.SetStatus(BRE_TRADE_EXEC_STATUS_FILLED);
   pending.SetFilledVolume(TEST_EXPECTED_CLOSE_VOLUME);
   pendingRegistry.Upsert(pending);

   CTestSequentialIdGenerator idGenerator;
   SProfitClosePersistedCompletionOutcome completionOutcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository),
                                                                                                         completionOutcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test-8d6"),
                     "FILLED pending must complete M2");
   CTestAssert::EqualString("M2",completionOutcome.profitLevelId,"completion must target M2");

   CResult<CBasketAggregate> loaded=repository.Load(basket.Id());
   CBasketAggregate afterCompletion;
   loaded.TryGetValue(afterCompletion);
   CTestAssert::True(LevelIsCloseCompleted(afterCompletion,"M2"),"M2 must be CloseCompleted after FILLED pending");

   ulong openTickets[1];
   openTickets[0]=TEST_TICKET;
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(pendingRegistry,
                                                                                            afterCompletion.Id(),
                                                                                            openTickets,
                                                                                            1,
                                                                                            &pendingStore),
                      "FILLED registry pending must clear unresolved gate before M3 planning");

   SeedOpenPosition(snapshotStore,afterCompletion.Id(),TEST_TICKET,TEST_REMAINING_VOLUME,TEST_FLOATING_PROFIT_M3_DUE_USD);

   CRecoveryRiskGateInput gateInputM3=CRecoveryRiskGateInput::Create(quote,account,TEST_QUOTE_SEQUENCE_M3,5000,
                                                                     afterCompletion.StrategyProfileHash(),
                                                                     afterCompletion.CorrelationKey(),
                                                                     clock.Now());
   CStrategyEvaluationContext evalContextM3;
   CStrategyEvaluationContextFactory::TryBuild(afterCompletion,
                                               CMarketContext::Create(afterCompletion.Symbol(),quote.Bid(),quote.Ask(),quote.Point()),
                                               riskContext,
                                               &snapshotStore).TryGetValue(evalContextM3);
   CTestAssert::True(evalContextM3.FloatingProfitUsd()>=TEST_M3_TRIGGER_USD,
                     "final fixture floating profit must meet M3 trigger threshold");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(pendingRegistry,
                                                                                            afterCompletion.Id(),
                                                                                            openTickets,
                                                                                            1,
                                                                                            &pendingStore),
                      "unresolved pending gate must remain clear before M3 planning");
   CTestAssert::True(LevelIsCloseCompleted(afterCompletion,"M1"),"M1 must remain CloseCompleted before M3 planning");
   CTestAssert::True(LevelIsCloseCompleted(afterCompletion,"M2"),"M2 must remain CloseCompleted before M3 planning");
   CTestAssert::False(LevelIsCloseCompleted(afterCompletion,"M3"),"M3 must remain open before M3 planning");

   CProfitLevelCloseCandidate nextCandidate=planningService.EvaluateAndEmit(afterCompletion,evalContextM3,gateInputM3);
   CTestAssert::True(nextCandidate.IsDue(),"planner must emit DUE candidate after M2 completion");
   CTestAssert::EqualString("M3",nextCandidate.ProfitLevelId(),"next selected level must be M3");
   CTestAssert::True(StringFind(nextCandidate.IdempotencyKey(),":level:M3:")>=0,"next idempotency must contain :level:M3:");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestMultiLevelPendingRegistrationChain();
   CTestAssert::Summary("TestSprint8dMultiLevelPendingRegistrationChain");
  }
