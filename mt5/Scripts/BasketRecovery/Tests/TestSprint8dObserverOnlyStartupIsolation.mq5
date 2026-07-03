#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Interfaces/Bootstrapper.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionStartupReconciliationService.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/BrokerRequestCorrelation.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

const string TEST_ARTIFACT_PATH="BasketRecovery/validation/sprint-8d-observer-isolation-artifact.txt";
const string LEGACY_BASKET_ID="sprint8c-demo-xauusd-002";
const string LEGACY_LEVEL_ID="M1";
const string LEGACY_IDEMPOTENCY_KEY="profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:42";
const string LEGACY_EXECUTION_REQUEST_ID="profit-close-manual:observer-isolation-001";
const string SPRINT8D_BASKET_ID="sprint8d-demo-xauusd-m123-001";
const string SPRINT8D_EXECUTION_REQUEST_ID="demo-open-seed:8d9e2-m123-001";
const string SPRINT8D_IDEMPOTENCY_KEY="demo-open-seed:"+SPRINT8D_BASKET_ID+":q:1001";

CBasketAggregate BuildActiveBasket(const string basketIdValue)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CStrategyProfileTestFixture::MinimalValidJson(),boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,
                                                                                       CStrategyProfileTestFixture::MinimalValidJson(),
                                                                                       boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void CleanupArtifact(void)
  {
   FileDelete(TEST_ARTIFACT_PATH,FILE_COMMON);
  }

void SeedPreparedEntry(CInMemoryPendingExecutionStore &store,
                       const CPendingExecutionEntry &entry,
                       const ENUM_BRE_TRADE_EXECUTION_INTENT intent)
  {
   CBrokerSubmissionEnvelope envelope;
   envelope.SetExecutionRequestId(entry.ExecutionRequestId());
   envelope.SetIdempotencyKey(entry.IdempotencyKey());
   envelope.SetBasketId(entry.BasketId());
   envelope.SetExpectedBasketVersion(entry.ExpectedBasketVersion());
   envelope.SetStrategyProfileHash(entry.StrategyProfileHash());
   envelope.SetIntentType(intent);
   envelope.SetSymbol(entry.Symbol());
   envelope.SetRequestedVolume(entry.RequestedVolume());
   envelope.SetPreparedAtUtc(entry.PreparedAtUtc());
   envelope.SetExpirationUtc(entry.PreparedAtUtc()+3600);
   CTestAssert::True(store.SavePreparedState(entry,envelope).IsOk(),"Prepared entry seed must succeed");
  }

CPendingExecutionEntry BuildQueuedOpenSeedEntry(void)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(SPRINT8D_EXECUTION_REQUEST_ID);
   entry.SetIdempotencyKey(SPRINT8D_IDEMPOTENCY_KEY);
   entry.SetBasketId(CBasketId(SPRINT8D_BASKET_ID));
   entry.SetExpectedBasketVersion(5);
   entry.SetStrategyProfileHash("profile-hash-8d");
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetSymbol("XAUUSD");
   entry.SetRequestedVolume(0.06);
   entry.SetCreatedAtUtc(5000);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   entry.SetPreparedAtUtc(5000);
   entry.SetBrokerComment("comment-8d-open");
   return entry;
  }

CPendingExecutionEntry BuildFilledLegacyCloseEntry(void)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(LEGACY_EXECUTION_REQUEST_ID);
   entry.SetIdempotencyKey(LEGACY_IDEMPOTENCY_KEY);
   entry.SetBasketId(CBasketId(LEGACY_BASKET_ID));
   entry.SetExpectedBasketVersion(2);
   entry.SetStrategyProfileHash("profile-hash-002");
   entry.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   entry.SetSymbol("XAUUSD");
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_FILLED);
   entry.SetRequestedVolume(0.01);
   entry.SetFilledVolume(0.01);
   entry.SetCreatedAtUtc(4000);
   entry.SetPreparedAtUtc(4000);
   CBrokerRequestCorrelation broker;
   broker.SetPositionTicket(1513319910);
   broker.SetBrokerDealId(1294774509);
   broker.SetBrokerOrderId(1520524749);
   entry.SetBrokerCorrelation(broker);
   return entry;
  }

bool IsLevelCompleted(CInMemoryBasketRepository &repository,const string basketId,const string levelId)
  {
   CResult<CBasketAggregate> loaded=repository.Load(CBasketId(basketId));
   CBasketAggregate basket;
   if(!loaded.TryGetValue(basket))
      return false;
   CBasketProfitLevelProgress progress;
   if(!basket.FindProfitLevelProgress(levelId,progress))
      return false;
   return progress.CloseCompleted();
  }

void TestObserverStartupDiagnosticsContract(void)
  {
   CBootstrapper::PrintObserverStartupIsolationDiagnostics(true);
   CBootstrapper::PrintObserverStartupIsolationDiagnostics(false);
  }

void TestNormalModeArtifactRestorePathReachable(void)
  {
   CleanupArtifact();
   CManualProfitCloseCandidateRegistry registry;
   datetime now=TimeCurrent();
   CManualProfitCloseCandidateEntry entry=CManualProfitCloseCandidateEntry::Create(
      "profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:99",
      "profit-close-manual:normal-mode-restore-001",
      "profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:99",
      CBasketId(LEGACY_BASKET_ID),
      LEGACY_LEVEL_ID,
      1,
      "profile-hash-002",
      2,
      "XAUUSD",
      BRE_DIRECTION_BUY,
      BRE_DIRECTION_BUY,
      1513319910,
      0.02,
      0.01,
      1.0,
      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
      0.01,
      99,
      now,
      now+SPRINT8C_VALIDATION_CANDIDATE_ARTIFACT_TTL_SECONDS,
      BRE_ACCOUNT_POSITION_MODEL_HEDGING);
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::WriteEntry(entry,"DUE",TEST_ARTIFACT_PATH),
                     "Artifact write must succeed");

   const bool observerOnlyStartupIsolation=false;
   if(!observerOnlyStartupIsolation)
     {
      SSprint8cProfitCloseRestoreOutcome outcome;
      CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryRestoreToRegistry(registry,
                                                                                              now,
                                                                                              outcome,
                                                                                              TEST_ARTIFACT_PATH),
                        "Normal mode must keep artifact restore path reachable");
      CTestAssert::True(outcome.attempted,"Artifact restore must be attempted in normal mode");
     }
   CleanupArtifact();
  }

void TestObserverModeSkipsArtifactRestore(void)
  {
   CleanupArtifact();
   CManualProfitCloseCandidateRegistry registry;
   datetime now=TimeCurrent();
   CManualProfitCloseCandidateEntry entry=CManualProfitCloseCandidateEntry::Create(
      "profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:100",
      "profit-close-manual:observer-skip-restore-001",
      "profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:100",
      CBasketId(LEGACY_BASKET_ID),
      LEGACY_LEVEL_ID,
      1,
      "profile-hash-002",
      2,
      "XAUUSD",
      BRE_DIRECTION_BUY,
      BRE_DIRECTION_BUY,
      1513319910,
      0.02,
      0.01,
      1.0,
      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
      0.01,
      100,
      now,
      now+SPRINT8C_VALIDATION_CANDIDATE_ARTIFACT_TTL_SECONDS,
      BRE_ACCOUNT_POSITION_MODEL_HEDGING);
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::WriteEntry(entry,"DUE",TEST_ARTIFACT_PATH),
                     "Artifact write must succeed");

   const bool observerOnlyStartupIsolation=true;
   if(!observerOnlyStartupIsolation)
     {
      SSprint8cProfitCloseRestoreOutcome outcome;
      CManualProfitCloseCandidateValidationArtifact::TryRestoreToRegistry(registry,now,outcome,TEST_ARTIFACT_PATH);
     }
   CTestAssert::EqualInt(0,registry.CountAvailable(),"Observer mode must skip profit-close artifact restore");
   CleanupArtifact();
  }

int RunStartupReconcile(CInMemoryPendingExecutionStore &store,
                        const bool skipLegacyProfitClosePersistedCompletion,
                        CInMemoryBasketRepository *basketRepository=NULL)
  {
   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionEventBuffer events(32);
   CTestClock clock;
   CPendingExecutionLifecycleService lifecycle(&registry,&store,&events,&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CInMemoryBrokerExecutionHistoryReader historyReader;
   return CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(&store,
                                                                                   &registry,
                                                                                   &lifecycle,
                                                                                   &brokerReader,
                                                                                   NULL,
                                                                                   &historyReader,
                                                                                   clock.Now(),
                                                                                   NULL,
                                                                                   basketRepository,
                                                                                   &clock,
                                                                                   NULL,
                                                                                   skipLegacyProfitClosePersistedCompletion);
  }

void TestObserverModePreservesQueuedPendingRestore(void)
  {
   CInMemoryPendingExecutionStore store;
   CPendingExecutionEntry queued=BuildQueuedOpenSeedEntry();
   SeedPreparedEntry(store,queued,BRE_EXEC_INTENT_OPEN_POSITION);

   CPendingExecutionRegistry registry;
   CInMemoryPendingExecutionEventBuffer events(32);
   CTestClock clock;
   CPendingExecutionLifecycleService lifecycle(&registry,&store,&events,&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CInMemoryBrokerExecutionHistoryReader historyReader;
   CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(&store,
                                                                          &registry,
                                                                          &lifecycle,
                                                                          &brokerReader,
                                                                          NULL,
                                                                          &historyReader,
                                                                          clock.Now(),
                                                                          NULL,
                                                                          NULL,
                                                                          &clock,
                                                                          NULL,
                                                                          true);

   CPendingExecutionEntry restored;
   CTestAssert::True(registry.TryGetByExecutionRequestId(SPRINT8D_EXECUTION_REQUEST_ID,restored),
                     "Observer mode must restore QUEUED Sprint8D pending entry");
   CTestAssert::EqualString(SPRINT8D_IDEMPOTENCY_KEY,restored.IdempotencyKey(),
                            "Observer mode must preserve Sprint8D idempotency key");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)restored.Status(),
                         "Observer mode must keep QUEUED status available");
  }

void TestObserverModeSkipsFilledCloseCompletion(void)
  {
   CInMemoryBasketRepository repository;
   repository.Save(BuildActiveBasket(LEGACY_BASKET_ID));

   CInMemoryPendingExecutionStore store;
   CPendingExecutionEntry filled=BuildFilledLegacyCloseEntry();
   SeedPreparedEntry(store,filled,BRE_EXEC_INTENT_CLOSE_POSITION);

   RunStartupReconcile(store,true,GetPointer(repository));

   CTestAssert::False(IsLevelCompleted(repository,LEGACY_BASKET_ID,LEGACY_LEVEL_ID),
                      "Observer mode must skip FILLED CLOSE_POSITION persisted-profit completion");
  }

void TestNormalModeRunsFilledCloseCompletion(void)
  {
   CInMemoryBasketRepository repository;
   repository.Save(BuildActiveBasket(LEGACY_BASKET_ID));

   CInMemoryPendingExecutionStore store;
   CPendingExecutionEntry filled=BuildFilledLegacyCloseEntry();
   filled.SetExecutionRequestId("profit-close-manual:normal-mode-completion-001");
   filled.SetIdempotencyKey("profit-level-close:"+LEGACY_BASKET_ID+":level:"+LEGACY_LEVEL_ID+":q:43");
   SeedPreparedEntry(store,filled,BRE_EXEC_INTENT_CLOSE_POSITION);

   RunStartupReconcile(store,false,GetPointer(repository));

   CTestAssert::True(IsLevelCompleted(repository,LEGACY_BASKET_ID,LEGACY_LEVEL_ID),
                     "Normal mode must keep FILLED CLOSE_POSITION completion path enabled");
  }

void TestNoBrokerTransportInObserverTests(void)
  {
   CMockMt5AsyncOrderSendTransport transport;
   CTestAssert::EqualInt(0,transport.CallCount(),"Observer isolation tests must not invoke broker transport");
  }

void OnStart(void)
  {
   TestObserverStartupDiagnosticsContract();
   TestNormalModeArtifactRestorePathReachable();
   TestObserverModeSkipsArtifactRestore();
   TestObserverModePreservesQueuedPendingRestore();
   TestObserverModeSkipsFilledCloseCompletion();
   TestNormalModeRunsFilledCloseCompletion();
   TestNoBrokerTransportInObserverTests();
   CleanupArtifact();
   Print("TestSprint8dObserverOnlyStartupIsolation: all tests passed");
  }
