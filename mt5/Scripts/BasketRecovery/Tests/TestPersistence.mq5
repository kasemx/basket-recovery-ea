#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/PersistenceTestPaths.mqh>
#include <BasketRecovery/Tests/AggregateTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketMigration.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonWriter.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileCommandPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistentCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileIdempotencyPersistence.mqh>
#include <BasketRecovery/Infrastructure/Persistence/PersistenceSaveQueue.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>
#include <BasketRecovery/Application/Commands/CreateBasketCommand.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

CBasketAggregate BuildTestAggregate(CAggregateTestFixture &fixture,const string basketIdValue)
  {
   CBasketId basketId(basketIdValue);
   CResult<CBasketAggregate> created=CBasketFactory::Create(basketId,
                                                          fixture.BuildProfileSnapshot(),
                                                          "corr-"+basketIdValue,
                                                          BRE_DIRECTION_BUY,
                                                          "XAUUSD",
                                                          CSignalId("sig-"+basketIdValue),
                                                          CUtcTime(fixture.Clock().Now()),
                                                          CCommandId("cmd-create-"+basketIdValue),
                                                          CEventId("evt-create-"+basketIdValue));
   CBasketAggregate aggregate;
   created.TryGetValue(aggregate);
   return aggregate;
  }

void TestRestartSimulation(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketAggregate aggregate=BuildTestAggregate(fixture,"persist-restart-001");
   CTestAssert::True(repository.Save(aggregate).IsOk(),"Restart simulation save must succeed");

   CFileBasketRepository restartedRepository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CResult<CBasketAggregate> loaded=restartedRepository.Load(CBasketId("persist-restart-001"));
   CTestAssert::True(loaded.IsOk(),"Restart simulation load must succeed");
   CBasketAggregate loadedAggregate;
   CTestAssert::True(loaded.TryGetValue(loadedAggregate),"Restart simulation aggregate must exist");
   CTestAssert::EqualInt(BRE_STATE_PENDING_OPEN,loadedAggregate.LifecycleState(),"Restart simulation lifecycle must match");
   CTestAssert::EqualString("persist-restart-001",loadedAggregate.Id().Value(),"Restart simulation basket id must match");
  }

void TestCorruptedFile(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketAggregate aggregate=BuildTestAggregate(fixture,"persist-corrupt-001");
   repository.Save(aggregate);

   string relativePath=BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/persist-corrupt-001.json";
   int handle=FileOpen(relativePath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   CTestAssert::True(handle!=INVALID_HANDLE,"Corrupt test file handle must open");
   FileWriteString(handle,"{\"schema_version\":1,\"crc32\":\"00000000\",\"basket_id\":\"broken\"}");
   FileClose(handle);

   CResult<CBasketAggregate> loaded=repository.Load(CBasketId("persist-corrupt-001"));
   CTestAssert::False(loaded.IsOk(),"Corrupted file load must fail");
   CTestAssert::EqualInt(BRE_ERR_PERSIST_CRC_MISMATCH,loaded.ErrorCode(),"Corrupted file must report CRC mismatch");
  }

void TestMissingFile(void)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CResult<CBasketAggregate> loaded=repository.Load(CBasketId("missing-basket"));
   CTestAssert::False(loaded.IsOk(),"Missing file load must fail");
   CTestAssert::EqualInt(BRE_ERR_BASKET_NOT_FOUND,loaded.ErrorCode(),"Missing file must report basket not found");
  }

void TestPartialWriteRecovery(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CBasketAggregate aggregate=BuildTestAggregate(fixture,"persist-partial-001");
   CTestAssert::True(repository.Save(aggregate).IsOk(),"Partial write initial save must succeed");
   CTestAssert::True(repository.Save(aggregate).IsOk(),"Partial write backup save must succeed");

   string relativePath=BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/persist-partial-001.json";
   FileDelete(relativePath,FILE_COMMON);

   CFileBasketRepository recoveryRepository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR,true);
   CResult<CBasketAggregate> loaded=recoveryRepository.Load(CBasketId("persist-partial-001"));
   CTestAssert::True(loaded.IsOk(),"Partial write recovery must load backup");
  }

void TestMultipleBaskets(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   repository.Save(BuildTestAggregate(fixture,"persist-multi-001"));
   repository.Save(BuildTestAggregate(fixture,"persist-multi-002"));
   repository.Save(BuildTestAggregate(fixture,"persist-multi-003"));

   CBasketAggregate aggregates[];
   int count=repository.LoadAll(aggregates);
   CTestAssert::EqualInt(3,count,"Multiple baskets load all count must be 3");
   CTestAssert::EqualInt(3,repository.Count(),"Multiple baskets repository count must be 3");
  }

void TestMigrationPassThrough(CAggregateTestFixture &fixture)
  {
   CBasketAggregate aggregate=BuildTestAggregate(fixture,"persist-migrate-001");
   CBasketSerializer serializer;
   string json=serializer.Serialize(aggregate);
   CResult<string> migrated=CBasketMigration::MigrateToCurrent(json);
   CTestAssert::True(migrated.IsOk(),"Migration pass-through must succeed");
   string migratedJson;
   CTestAssert::True(migrated.TryGetValue(migratedJson),"Migration pass-through result must exist");
   CTestAssert::True(StringFind(migratedJson,"schema_version")>=0,"Migration pass-through must preserve schema version");
  }

void TestPendingCommandRecovery(void)
  {
   CPersistenceTestPaths::Cleanup();
   CFileCommandPersistence persistence(BRE_TEST_PERSISTENCE_COMMANDS_FILE);
   CPersistentCommandQueue queue(&persistence);

   CCreateBasketCommand *command=new CCreateBasketCommand();
   command.SetId(CCommandId("cmd-pending-001"));
   command.SetIdempotencyKey("idem-pending-001");
   command.SetBasketId(CBasketId("basket-pending-001"));
   command.SetCorrelationKey("corr-pending-001");
   command.SetSymbol("XAUUSD");
   command.SetDirection(BRE_DIRECTION_BUY);
   command.SetSignalId(CSignalId("sig-pending-001"));
   command.SetEnqueuedAt(TimeCurrent());
   CTestAssert::True(queue.Enqueue(command).IsOk(),"Pending command enqueue must succeed");

   CPersistentCommandQueue recoveredQueue(&persistence);
   CTestAssert::True(recoveredQueue.RecoverFromPersistence().IsOk(),"Pending command recovery must succeed");
   CTestAssert::EqualInt(1,recoveredQueue.PendingCount(),"Pending command recovery count must be 1");
   CTestAssert::True(recoveredQueue.FindByIdempotencyKey("idem-pending-001")!=NULL,"Pending command must be restored by idempotency key");
  }

void TestIdempotencyPersistence(void)
  {
   CPersistenceTestPaths::Cleanup();
   CFileIdempotencyPersistence persistence(BRE_TEST_PERSISTENCE_IDEMPOTENCY_FILE);
   CTestAssert::True(persistence.SaveProcessedKey("idem-key-001").IsOk(),"Idempotency save must succeed");
   CTestAssert::True(persistence.SaveProcessedKey("idem-key-002").IsOk(),"Idempotency save second key must succeed");

   string keys[];
   CTestAssert::True(persistence.LoadProcessedKeys(keys).IsOk(),"Idempotency load must succeed");
   CTestAssert::EqualInt(2,ArraySize(keys),"Idempotency load count must be 2");

   CInMemoryIdempotencyStore store(&persistence);
   CTestAssert::True(store.RecoverFromPersistence().IsOk(),"Idempotency store recovery must succeed");
   CTestAssert::True(store.IsProcessed("idem-key-001"),"Idempotency store must contain first key");
   CTestAssert::True(store.IsProcessed("idem-key-002"),"Idempotency store must contain second key");
  }

void TestDebouncedBatchSave(CAggregateTestFixture &fixture)
  {
   CPersistenceTestPaths::Cleanup();
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CPersistenceSaveQueue saveQueue(500);
   CBasketAggregate aggregate=BuildTestAggregate(fixture,"persist-batch-001");

   saveQueue.QueueSave(aggregate);
   CTestAssert::True(saveQueue.HasPending(),"Debounced queue must have pending save");
   CTestAssert::False(saveQueue.ShouldFlush(),"Debounced queue must not flush immediately");

   saveQueue.SetDebounceMs(0);
   saveQueue.QueueSave(aggregate);
   CTestAssert::True(saveQueue.ShouldFlush(),"Zero debounce queue must flush immediately");
   CTestAssert::True(saveQueue.Flush(repository).IsOk(),"Debounced batch flush must succeed");
   CTestAssert::False(saveQueue.HasPending(),"Debounced queue must be empty after flush");
   CTestAssert::True(repository.Exists(CBasketId("persist-batch-001")),"Debounced batch save must persist basket");
  }

void OnStart()
  {
   CTestAssert::Reset();
   CAggregateTestFixture fixture;
   CTestAssert::True(fixture.Initialize(),"Persistence fixture must initialize");

   TestRestartSimulation(fixture);
   TestCorruptedFile(fixture);
   TestMissingFile();
   TestPartialWriteRecovery(fixture);
   TestMultipleBaskets(fixture);
   TestMigrationPassThrough(fixture);
   TestPendingCommandRecovery();
   TestIdempotencyPersistence();
   TestDebouncedBatchSave(fixture);

   CPersistenceTestPaths::Cleanup();
   CTestAssert::Summary("TestPersistence");
   if(!CTestAssert::AllPassed())
      Print("TestPersistence FAILED");
  }
