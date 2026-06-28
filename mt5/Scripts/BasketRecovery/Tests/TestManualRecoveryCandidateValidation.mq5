#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyEngineTestFixture.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/RecoveryCandidateSubmissionValidator.mqh>
#include <BasketRecovery/Application/Execution/ManualRecoveryCandidateSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/RecoveryCandidateExecutionRequestFactory.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>

#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Types/Price.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>

const long TEST_MAGIC=202606003;

CBasketAggregate BuildActiveRecoveryBasket(void)
  {
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(
      CStrategyEngineTestFixture::LoadGoldenProfile(),
      CStrategyProfileTestFixture::MinimalValidJson(),
      CUtcTime(1000));
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),CUtcTime(1000));
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId("basket-rc-001"),legacy,snapshot,
                                                                      "corr",BRE_DIRECTION_BUY,"EURUSD",
                                                                      CSignalId("sig-rc"),CUtcTime(1000),
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   basket.SetRecoveryActive(true);
   basket.ApplyStopLossUpdate(CPrice(1.0950),CCommandId("cmd-sl"),CEventId("evt-sl"),CUtcTime(1000));
   return basket;
  }

CManualRecoveryCandidateEntry BuildSampleEntry(const string candidateId,
                                               const datetime createdAt,
                                               const datetime expiresAt)
  {
   return CManualRecoveryCandidateEntry::Create(candidateId,
                                                "recovery-manual:req-001",
                                                "recovery:decision:1",
                                                candidateId,
                                                CBasketId("basket-rc-001"),
                                                "hash-v1",
                                                1,
                                                "EURUSD",
                                                BRE_DIRECTION_BUY,
                                                1,
                                                1.0990,
                                                1.0990,
                                                1.1000,
                                                1.0980,
                                                1.1010,
                                                0.01,
                                                1.0950,
                                                10.0,
                                                15.0,
                                                20.0,
                                                30.0,
                                                42,
                                                createdAt,
                                                expiresAt);
  }

CMarketQuote BuildQuote(const int freshnessAgeMs)
  {
   return CMarketQuote::Create("EURUSD",1.0990,1.1000,10,0.01,2,0.01,1.0,1000,freshnessAgeMs,
                               BRE_TRADING_SESSION_OPEN,
                               CSymbolTradingConstraints::Create(20,10,0.01,0.10,0.01));
  }

CDemoExecutionAuthorizationConfig EnabledManualConfig(void)
  {
   CDemoExecutionAuthorizationConfig config;
   config.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION);
   config.SetEnableLiveDemoExecution(true);
   config.SetRequireManualDemoAuthorization(true);
   config.SetMaxAuthorizedRequestsPerSession(1);
   config.SetMaxRecoverySubmissionsPerSession(1);
   config.SetMaxManualDemoOpenVolume(0.10);
   config.SetManualRecoveryCandidateExpirySeconds(30);
   return config;
  }

void TestRegistryAcceptsEligibleCandidate(void)
  {
   CManualRecoveryCandidateRegistry registry;
   CManualRecoveryCandidateEntry entry=BuildSampleEntry("recovery-candidate:basket-rc-001:step:1:q:42",1000,1030);
   CTestAssert::True(registry.TryRegister(entry),"DUE risk-approved candidate must enter registry");
   CManualRecoveryCandidateEntry loaded;
   CTestAssert::True(registry.TryGetByCandidateId(entry.CandidateId(),loaded),"Registered candidate must be retrievable");
  }

void TestRegistryRejectsDuplicateStep(void)
  {
   CManualRecoveryCandidateRegistry registry;
   CManualRecoveryCandidateEntry first=BuildSampleEntry("candidate-a",1000,1030);
   CManualRecoveryCandidateEntry second=BuildSampleEntry("candidate-b",1000,1030);
   CTestAssert::True(registry.TryRegister(first),"First candidate registers");
   CTestAssert::False(registry.TryRegister(second),"Second active candidate for same step must be rejected");
  }

void TestCandidateExpiry(void)
  {
   CManualRecoveryCandidateRegistry registry;
   CManualRecoveryCandidateEntry entry=BuildSampleEntry("expiry-candidate",1000,1030);
   registry.TryRegister(entry);
   int expired=registry.ExpireStale(1030);
   CTestAssert::EqualInt(1,expired,"Candidate must expire after TTL");
   CManualRecoveryCandidateEntry loaded;
   registry.TryGetByCandidateId("expiry-candidate",loaded);
   CTestAssert::EqualInt((int)BRE_MANUAL_RECOVERY_CANDIDATE_EXPIRED,(int)loaded.Status(),"Expired status required");
  }

void TestFactoryBindsExactCandidateFields(void)
  {
   CManualRecoveryCandidateEntry entry=BuildSampleEntry("bind-candidate",1000,1030);
   CTradeExecutionRequest request=CRecoveryCandidateExecutionRequestFactory::CreateOpenRecoveryRequest(entry,1000);
   CTestAssert::True(request.IsSealed(),"Factory request must be sealed");
   CTestAssert::EqualString("EURUSD",request.Symbol(),"Symbol must come from candidate");
   CTestAssert::EqualInt((int)BRE_DIRECTION_BUY,(int)request.Direction(),"Direction must come from candidate");
   CTestAssert::EqualDouble(0.01,request.RequestedVolume(),0.0001,"Volume must come from candidate");
   CTestAssert::EqualInt((int)BRE_EXEC_INTENT_OPEN_POSITION,(int)request.IntentType(),"Only OPEN_POSITION allowed");
  }

void TestRecoveryTriggerOneShot(void)
  {
   CManualRecoveryCandidateTriggerRegistry triggers;
   CTestAssert::False(triggers.IsConsumed("trigger-1"),"Fresh trigger must not be consumed");
   triggers.Consume("trigger-1");
   CTestAssert::True(triggers.IsConsumed("trigger-1"),"Trigger must be one-shot consumed");
  }

void TestStepTrackerFillOnce(void)
  {
   CRecoveryStepExecutionTracker tracker;
   tracker.MarkSubmitted("basket-rc-001",1,"recovery-manual:req-001");
   CTestAssert::False(tracker.IsStepExecuted("basket-rc-001",1),"Submit must not execute step");
   CTestAssert::True(tracker.TryMarkFilled("recovery-manual:req-001"),"First fill must advance");
   CTestAssert::True(tracker.IsStepExecuted("basket-rc-001",1),"Fill must mark step executed");
   CTestAssert::False(tracker.TryMarkFilled("recovery-manual:req-001"),"Duplicate fill must not advance twice");
  }

void TestNoAutomaticRecoverySubmissionWiring(void)
  {
   CManualRecoveryCandidateSubmissionService *service=NULL;
   CDemoExecutionAuthorizationConfig config=EnabledManualConfig();
   CManualRecoveryCandidateRegistry registry;
   CManualRecoveryCandidateTriggerRegistry recoveryTriggers;
   CManualRecoveryCandidateEventBuffer events;
   CRecoveryStepExecutionTracker tracker;
   CRecoveryCandidateSubmissionValidator validator(NULL,NULL,&tracker,5000);
   CExecutionAuthorizationRegistry authRegistry(NULL);
   service=new CManualRecoveryCandidateSubmissionService(config,&registry,&recoveryTriggers,&events,&validator,&tracker,
                                                         &authRegistry,NULL,NULL,NULL);
   CTestAssert::False(service.IsWiredToStrategyEngine(),"StrategyEngine must not auto-submit recovery");
   CTestAssert::False(service.IsWiredToRestIntake(),"REST must not auto-submit recovery");
   CTestAssert::False(service.IsWiredToOnTick(),"OnTick must not auto-submit recovery");
   CTestAssert::False(service.IsWiredToAutomaticTimer(),"Automatic timer must not auto-submit recovery");
   CTestAssert::False(service.IsWiredToOnTradeTransaction(),"OnTradeTransaction must not submit recovery");
   delete service;
  }

void TestStaleQuoteBlocksRevalidation(void)
  {
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CPendingExecutionRegistry pendingRegistry;
   CRecoveryStepExecutionTracker tracker;
   CRecoveryCandidateSubmissionValidator validator(&snapshotStore,&pendingRegistry,&tracker,5000);

   CBasketAggregate basket=BuildActiveRecoveryBasket();

   CManualRecoveryCandidateEntry entry=BuildSampleEntry("stale-candidate",1000,2000);
   CMarketQuote staleQuote=BuildQuote(6000);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(staleQuote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   42,5000,basket.StrategyProfileHash(),"corr",1000);
   CVoidResult result=validator.ValidateForSubmission(entry,basket,staleQuote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Stale quote must invalidate candidate");
  }

void TestPendingExecutionBlocksRevalidation(void)
  {
   CTestClock clock;
   clock.SetNow(1000);
   CInMemorySnapshotStore snapshotStore(&clock);
   CPendingExecutionRegistry pendingRegistry;
   CRecoveryStepExecutionTracker tracker;
   CRecoveryCandidateSubmissionValidator validator(&snapshotStore,&pendingRegistry,&tracker,5000);

   CPendingExecutionEntry pending;
   pending.SetExecutionRequestId("pending-other");
   pending.SetBasketId(CBasketId("basket-rc-001"));
   pending.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   pendingRegistry.Upsert(pending);

   CBasketAggregate basket=BuildActiveRecoveryBasket();

   CManualRecoveryCandidateEntry entry=BuildSampleEntry("pending-block",1000,2000);
   CMarketQuote quote=BuildQuote(10);
   CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                   CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true),
                                                                   42,5000,basket.StrategyProfileHash(),"corr",1000);
   CVoidResult result=validator.ValidateForSubmission(entry,basket,quote,gateInput,1000);
   CTestAssert::True(result.IsFail(),"Unresolved pending execution must block submission");
  }

void TestRecoverySessionCap(void)
  {
   CExecutionAuthorizationRegistry authRegistry(NULL);
   CTestAssert::True(authRegistry.HasRecoverySubmissionSessionCapacity(1),"First recovery submission allowed");
   authRegistry.IncrementRecoverySubmissionCount();
   CTestAssert::False(authRegistry.HasRecoverySubmissionSessionCapacity(1),"Second recovery submission blocked");
  }

void OnStart()
  {
   TestRegistryAcceptsEligibleCandidate();
   TestRegistryRejectsDuplicateStep();
   TestCandidateExpiry();
   TestFactoryBindsExactCandidateFields();
   TestRecoveryTriggerOneShot();
   TestStepTrackerFillOnce();
   TestNoAutomaticRecoverySubmissionWiring();
   TestStaleQuoteBlocksRevalidation();
   TestPendingExecutionBlocksRevalidation();
   TestRecoverySessionCap();

   CTestAssert::Summary("TestManualRecoveryCandidateValidation");
   if(!CTestAssert::AllPassed())
      Print("TestManualRecoveryCandidateValidation FAILED");
  }
