#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Application/Execution/ProfitCloseFilledPendingCompletionService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
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

const string TEST_BASKET_ID="sprint8c-demo-xauusd-002";
const string TEST_LEVEL_ID="M1";
const string TEST_IDEMPOTENCY_KEY="profit-level-close:"+TEST_BASKET_ID+":level:"+TEST_LEVEL_ID+":q:0";
const string TEST_EXECUTION_REQUEST_ID="profit-close-manual:567354484-4A87-7247";
const string TEST_EXPIRED_ARTIFACT_PATH="BasketRecovery/validation/sprint-8c-filled-pending-expired-artifact.txt";

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

CPendingExecutionEntry BuildFilledPending(const string executionRequestId,
                                            const string basketId,
                                            const string idempotencyKey,
                                            const ulong ticket,
                                            const ulong dealId,
                                            const ulong orderId,
                                            const double requestedVolume)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(executionRequestId);
   entry.SetIdempotencyKey(idempotencyKey);
   entry.SetBasketId(CBasketId(basketId));
   entry.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_FILLED);
   entry.SetRequestedVolume(requestedVolume);
   entry.SetFilledVolume(requestedVolume);
   CBrokerRequestCorrelation broker;
   broker.SetPositionTicket(ticket);
   broker.SetBrokerDealId(dealId);
   broker.SetBrokerOrderId(orderId);
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

void CleanupExpiredArtifact(void)
  {
   FileDelete(TEST_EXPIRED_ARTIFACT_PATH,FILE_COMMON);
  }

CBasketAggregate RoundTripViaSerializer(const CBasketAggregate &source)
  {
   CBasketSerializer serializer;
   string json=serializer.Serialize(source);
   CResult<CBasketAggregate> loaded=serializer.Deserialize(json,false);
   CBasketAggregate output;
   loaded.TryGetValue(output);
   return output;
  }

bool TryDeserializeDtoFromBasketJson(const string json,CBasketPersistenceDto &dtoOut)
  {
   CBasketSerializer serializer;
   CJsonReader reader;
   reader.SetRecoveryMode(false);
   reader.SetContent(json);
   int schemaVersion=reader.ReadSchemaVersion();
   if(schemaVersion<=0)
      return false;
   return serializer.FromReader(reader,dtoOut,schemaVersion);
  }

void TestProfitLevelRuntimeStateRoundTripPreserved(void)
  {
   CTestClock clock;
   datetime now=clock.Now();

   CBasketAggregate basket=BuildActiveBasket(TEST_BASKET_ID);
   basket.ApplyProfitLevelReached(TEST_LEVEL_ID,CUtcTime(now),CCommandId("cmd-r"),CEventId("evt-r"));
   basket.ApplyProfitLevelCloseRequested(TEST_LEVEL_ID,CCommandId("cmd-q"),CEventId("evt-q"),CUtcTime(now+5));
   basket.ApplyProfitLevelCloseCompleted(TEST_LEVEL_ID,CMoney(1.23),CCommandId("cmd-c"),CEventId("evt-c"),
                                         CUtcTime(now+10));

   CBasketAggregate restored=RoundTripViaSerializer(basket);
   CBasketProfitLevelProgress progress;
   CTestAssert::True(restored.FindProfitLevelProgress(TEST_LEVEL_ID,progress),
                     "Restored basket must have profit level progress");
   CTestAssert::True(progress.Reached(),"Reached must survive round-trip");
   CTestAssert::True(progress.CloseRequested(),"CloseRequested must survive round-trip");
   CTestAssert::True(progress.CloseCompleted(),"CloseCompleted must survive round-trip");
   CTestAssert::EqualDouble(1.23,progress.RealizedProfit().Amount(),0.0000001,"RealizedProfit must survive round-trip");
   CTestAssert::EqualInt((int)(now+10),(int)progress.CompletedAtUtc().Value(),"CompletedAtUtc must survive round-trip");
  }

void TestValidFilledPendingCompletesM1(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   repository.Save(BuildActiveBasket(TEST_BASKET_ID));

   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     TEST_BASKET_ID,
                                                     TEST_IDEMPOTENCY_KEY,
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome outcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository),
                                                                                                         outcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test"),
                     "Valid FILLED pending must complete");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED,(int)outcome.result,
                         "First completion must be COMPLETED");
   CTestAssert::EqualString(TEST_LEVEL_ID,outcome.profitLevelId,"Profit level id must be M1");
   CTestAssert::True(IsLevelCompleted(repository,TEST_BASKET_ID,TEST_LEVEL_ID),
                     "Basket aggregate must mark M1 completed");
  }

void TestSecondInvocationIsAlreadyCompleted(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   repository.Save(BuildActiveBasket(TEST_BASKET_ID));

   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     TEST_BASKET_ID,
                                                     TEST_IDEMPOTENCY_KEY,
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome firstOutcome;
   CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                       GetPointer(repository),
                                                                                       firstOutcome,
                                                                                       GetPointer(clock),
                                                                                       GetPointer(idGenerator),
                                                                                       "test");

   SProfitClosePersistedCompletionOutcome secondOutcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository),
                                                                                                         secondOutcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test"),
                     "Second completion attempt must succeed as no-op");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED,(int)secondOutcome.result,
                         "Second completion must be ALREADY_COMPLETED");
  }

void TestRestartInvocationIsAlreadyCompleted(void)
  {
   CInMemoryBasketRepository repository1;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   repository1.Save(BuildActiveBasket(TEST_BASKET_ID));

   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     TEST_BASKET_ID,
                                                     TEST_IDEMPOTENCY_KEY,
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome firstOutcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository1),
                                                                                                         firstOutcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test"),
                     "First completion must succeed");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED,(int)firstOutcome.result,
                         "First completion must be COMPLETED");

   CResult<CBasketAggregate> loaded=repository1.Load(CBasketId(TEST_BASKET_ID));
   CBasketAggregate completed;
   loaded.TryGetValue(completed);
   CBasketAggregate restarted=RoundTripViaSerializer(completed);

   CInMemoryBasketRepository repository2;
   repository2.Save(restarted);

   SProfitClosePersistedCompletionOutcome secondOutcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository2),
                                                                                                         secondOutcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test"),
                     "Restart completion attempt must succeed as no-op");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_ALREADY_COMPLETED,(int)secondOutcome.result,
                         "profit_close_persisted_completion_result must be ALREADY_COMPLETED");
   CTestAssert::True(IsLevelCompleted(repository2,TEST_BASKET_ID,TEST_LEVEL_ID),
                     "profit_level_current_state must remain COMPLETED");
  }

void TestConflictingDtoNormalizeCompletedImpliesReachedRequested(void)
  {
   CTestClock clock;
   datetime now=clock.Now();
   CBasketAggregate basket=BuildActiveBasket(TEST_BASKET_ID);
   basket.ApplyProfitLevelReached(TEST_LEVEL_ID,CUtcTime(now),CCommandId("cmd-r"),CEventId("evt-r"));
   basket.ApplyProfitLevelCloseCompleted(TEST_LEVEL_ID,CMoney(2.0),CCommandId("cmd-c"),CEventId("evt-c"),
                                         CUtcTime(now+10));

   CBasketSerializer serializer;
   string json=serializer.Serialize(basket);

   CBasketPersistenceDto dto;
   CTestAssert::True(TryDeserializeDtoFromBasketJson(json,dto),
                     "DTO deserialize must succeed");

   for(int i=0;i<ArraySize(dto.profitLevelProgress);i++)
     {
      if(dto.profitLevelProgress[i].levelId==TEST_LEVEL_ID)
        {
         dto.profitLevelProgress[i].reached=false;
         dto.profitLevelProgress[i].closeRequested=false;
         dto.profitLevelProgress[i].closeCompleted=true;
        }
     }

   CBasketAggregate restored;
   CTestAssert::True(restored.RestoreFromDto(dto),
                     "Restore must succeed with normalized runtime state");

   CBasketProfitLevelProgress progress;
   CTestAssert::True(restored.FindProfitLevelProgress(TEST_LEVEL_ID,progress),
                     "Restored basket must have profit level progress");
   CTestAssert::True(progress.Reached(),"Completed must imply reached after normalize");
   CTestAssert::True(progress.CloseRequested(),"Completed must imply requested after normalize");
   CTestAssert::True(progress.CloseCompleted(),"CloseCompleted must remain true after normalize");
  }

void TestExpiredArtifactDoesNotBlockPersistedCompletion(void)
  {
   CleanupExpiredArtifact();
   CManualProfitCloseCandidateRegistry candidateRegistry;
   datetime now=TimeCurrent();
   CManualProfitCloseCandidateEntry expired=CManualProfitCloseCandidateEntry::Create(TEST_IDEMPOTENCY_KEY,
                                                                                     TEST_EXECUTION_REQUEST_ID,
                                                                                     TEST_IDEMPOTENCY_KEY,
                                                                                     CBasketId(TEST_BASKET_ID),
                                                                                     TEST_LEVEL_ID,
                                                                                     1,
                                                                                     "profile-hash-002",
                                                                                     2,
                                                                                     "XAUUSD",
                                                                                     BRE_DIRECTION_BUY,
                                                                                     BRE_DIRECTION_BUY,
                                                                                     1516503131,
                                                                                     0.02,
                                                                                     0.01,
                                                                                     1.0,
                                                                                     BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                                                     0.01,
                                                                                     0,
                                                                                     now-300,
                                                                                     now-60,
                                                                                     BRE_ACCOUNT_POSITION_MODEL_HEDGING);
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::WriteEntry(expired,"DUE",TEST_EXPIRED_ARTIFACT_PATH),
                     "Expired artifact write must succeed");

   CManualProfitCloseCandidateEntry restored;
   CTestAssert::False(candidateRegistry.TryGetByExecutionRequestId(TEST_EXECUTION_REQUEST_ID,restored),
                      "Candidate registry must remain empty without artifact restore");

   CInMemoryBasketRepository repository;
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   repository.Save(BuildActiveBasket(TEST_BASKET_ID));
   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     TEST_BASKET_ID,
                                                     TEST_IDEMPOTENCY_KEY,
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome outcome;
   CTestAssert::True(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                         GetPointer(repository),
                                                                                                         outcome,
                                                                                                         GetPointer(clock),
                                                                                                         GetPointer(idGenerator),
                                                                                                         "test"),
                     "Expired artifact must not block persisted pending completion");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_COMPLETED,(int)outcome.result,
                         "profit_close_persisted_completion_result must be COMPLETED");
   CTestAssert::True(IsLevelCompleted(repository,TEST_BASKET_ID,TEST_LEVEL_ID),
                     "profit_level_current_state must be COMPLETED");
   CleanupExpiredArtifact();
  }

void TestInvalidIdempotencyKeyRejected(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   repository.Save(BuildActiveBasket(TEST_BASKET_ID));

   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     TEST_BASKET_ID,
                                                     "manual-close:invalid-key",
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome outcome;
   CTestAssert::False(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                          GetPointer(repository),
                                                                                                          outcome,
                                                                                                          GetPointer(clock),
                                                                                                          NULL,
                                                                                                          "test"),
                      "Invalid idempotency key must be rejected");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_REJECTED,(int)outcome.result,
                         "Invalid idempotency must return REJECTED");
   CTestAssert::False(IsLevelCompleted(repository,TEST_BASKET_ID,TEST_LEVEL_ID),
                        "Invalid idempotency must not mutate basket progress");
  }

void TestBasketIdMismatchRejected(void)
  {
   CInMemoryBasketRepository repository;
   CTestClock clock;
   repository.Save(BuildActiveBasket(TEST_BASKET_ID));

   CPendingExecutionEntry pending=BuildFilledPending(TEST_EXECUTION_REQUEST_ID,
                                                     "other-basket-id",
                                                     TEST_IDEMPOTENCY_KEY,
                                                     1516503131,
                                                     1294774509,
                                                     1520524749,
                                                     0.01);
   SProfitClosePersistedCompletionOutcome outcome;
   CTestAssert::False(CProfitCloseFilledPendingCompletionService::TryCompleteFilledProfitCloseFromPending(pending,
                                                                                                          GetPointer(repository),
                                                                                                          outcome,
                                                                                                          GetPointer(clock),
                                                                                                          NULL,
                                                                                                          "test"),
                      "Basket id mismatch must be rejected");
   CTestAssert::EqualInt((int)BRE_PROFIT_CLOSE_PERSISTED_COMPLETION_REJECTED,(int)outcome.result,
                         "Basket id mismatch must return REJECTED");
   CTestAssert::False(IsLevelCompleted(repository,TEST_BASKET_ID,TEST_LEVEL_ID),
                        "Basket id mismatch must not mutate basket progress");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestProfitLevelRuntimeStateRoundTripPreserved();
   TestValidFilledPendingCompletesM1();
   TestSecondInvocationIsAlreadyCompleted();
   TestRestartInvocationIsAlreadyCompleted();
   TestConflictingDtoNormalizeCompletedImpliesReachedRequested();
   TestExpiredArtifactDoesNotBlockPersistedCompletion();
   TestInvalidIdempotencyKeyRejected();
   TestBasketIdMismatchRejected();
   CTestAssert::Summary("TestSprint8cProfitCloseFilledPendingCompletion");
  }
