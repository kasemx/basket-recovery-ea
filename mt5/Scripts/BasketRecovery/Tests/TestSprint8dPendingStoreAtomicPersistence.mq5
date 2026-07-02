#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Infrastructure/Execution/FilePendingExecutionStore.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionPersistenceCodec.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

const string TEST_STORE_PATH="BasketRecovery/validation/sprint-8d-pending-atomic-test.dat";
const string TEST_STORE_TEMP_PATH=TEST_STORE_PATH+".tmp";
const string TEST_STORE_BACKUP_PATH=TEST_STORE_PATH+".bak";

const string ENTRY_A_REQUEST_ID="unrelated-entry-a:8d9c-001";
const string ENTRY_A_IDEMPOTENCY_KEY="unrelated-entry-a:idem:8d9c-001";
const string ENTRY_B_REQUEST_ID="demo-open-seed:8d9-fresh-001";
const string ENTRY_B_IDEMPOTENCY_KEY="demo-open-seed:sprint8d-demo-xauusd-fresh-001:q:1001";
const string TEST_BASKET_A_ID="unrelated-basket-a-8d9c";
const string TEST_BASKET_B_ID="sprint8d-demo-xauusd-fresh-001";

bool              TestFileExists(const string relativePath)
  {
   int handle=FileOpen(relativePath,FILE_READ|FILE_BIN);
   if(handle==INVALID_HANDLE)
      return false;
   FileClose(handle);
   return true;
  }

void              DeleteTestStoreArtifacts(void)
  {
   if(TestFileExists(TEST_STORE_PATH))
      FileDelete(TEST_STORE_PATH);
   if(TestFileExists(TEST_STORE_TEMP_PATH))
      FileDelete(TEST_STORE_TEMP_PATH);
   if(TestFileExists(TEST_STORE_BACKUP_PATH))
      FileDelete(TEST_STORE_BACKUP_PATH);
  }

void              WriteTestFileContent(const string relativePath,const string content)
  {
   int handle=FileOpen(relativePath,FILE_WRITE|FILE_TXT|FILE_ANSI);
   CTestAssert::True(handle!=INVALID_HANDLE,"Test snapshot file must open for write");
   FileWriteString(handle,content);
   FileClose(handle);
  }

void              BuildEntryA(CPendingExecutionEntry &entry)
  {
   entry=CPendingExecutionEntry();
   entry.SetExecutionRequestId(ENTRY_A_REQUEST_ID);
   entry.SetIdempotencyKey(ENTRY_A_IDEMPOTENCY_KEY);
   entry.SetBasketId(CBasketId(TEST_BASKET_A_ID));
   entry.SetExpectedBasketVersion(1);
   entry.SetStrategyProfileHash("profile-hash-a");
   entry.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   entry.SetSymbol("EURUSD");
   entry.SetRequestedVolume(0.01);
   entry.SetCreatedAtUtc(1000);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   entry.SetPreparedAtUtc(1000);
   entry.SetBrokerComment("comment-a");
  }

void              BuildEnvelopeA(CBrokerSubmissionEnvelope &envelope)
  {
   envelope=CBrokerSubmissionEnvelope();
   envelope.SetExecutionRequestId(ENTRY_A_REQUEST_ID);
   envelope.SetIdempotencyKey(ENTRY_A_IDEMPOTENCY_KEY);
   envelope.SetBasketId(CBasketId(TEST_BASKET_A_ID));
   envelope.SetExpectedBasketVersion(1);
   envelope.SetStrategyProfileHash("profile-hash-a");
   envelope.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   envelope.SetSymbol("EURUSD");
   envelope.SetTicket(1000001);
   envelope.SetRequestedVolume(0.01);
   envelope.SetPreparedAtUtc(1000);
   envelope.SetExpirationUtc(2000);
  }

void              BuildEntryB(CPendingExecutionEntry &entry,const double volume)
  {
   entry=CPendingExecutionEntry();
   entry.SetExecutionRequestId(ENTRY_B_REQUEST_ID);
   entry.SetIdempotencyKey(ENTRY_B_IDEMPOTENCY_KEY);
   entry.SetBasketId(CBasketId(TEST_BASKET_B_ID));
   entry.SetExpectedBasketVersion(2);
   entry.SetStrategyProfileHash("profile-hash-b");
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetSymbol("XAUUSD");
   entry.SetRequestedVolume(volume);
   entry.SetCreatedAtUtc(3000);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_QUEUED);
   entry.SetPreparedAtUtc(3000);
   entry.SetBrokerComment("comment-b");
  }

void              BuildEnvelopeB(CBrokerSubmissionEnvelope &envelope,const double volume)
  {
   envelope=CBrokerSubmissionEnvelope();
   envelope.SetExecutionRequestId(ENTRY_B_REQUEST_ID);
   envelope.SetIdempotencyKey(ENTRY_B_IDEMPOTENCY_KEY);
   envelope.SetBasketId(CBasketId(TEST_BASKET_B_ID));
   envelope.SetExpectedBasketVersion(2);
   envelope.SetStrategyProfileHash("profile-hash-b");
   envelope.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   envelope.SetSymbol("XAUUSD");
   envelope.SetRequestedVolume(volume);
   envelope.SetPreparedAtUtc(3000);
   envelope.SetExpirationUtc(4000);
  }

string            BuildSnapshotPayloadEntryAOnly(void)
  {
   CPendingExecutionEntry entryA;
   CBrokerSubmissionEnvelope envelopeA;
   BuildEntryA(entryA);
   BuildEnvelopeA(envelopeA);
   return CPendingExecutionPersistenceCodec::EncodeEntry(entryA)+"\f"+
          CPendingExecutionPersistenceCodec::EncodeEnvelope(envelopeA);
  }

string            BuildSnapshotPayloadMergedAB(void)
  {
   CPendingExecutionEntry entryA;
   CBrokerSubmissionEnvelope envelopeA;
   BuildEntryA(entryA);
   BuildEnvelopeA(envelopeA);
   CPendingExecutionEntry entryB;
   CBrokerSubmissionEnvelope envelopeB;
   BuildEntryB(entryB,0.06);
   BuildEnvelopeB(envelopeB,0.06);
   return CPendingExecutionPersistenceCodec::EncodeEntry(entryA)+"\n"+
          CPendingExecutionPersistenceCodec::EncodeEntry(entryB)+"\f"+
          CPendingExecutionPersistenceCodec::EncodeEnvelope(envelopeA)+"\n"+
          CPendingExecutionPersistenceCodec::EncodeEnvelope(envelopeB);
  }

void              AssertEntryPresent(CFilePendingExecutionStore &store,
                                     const string executionRequestId,
                                     const string label)
  {
   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   bool found=false;
   for(int i=0;i<count;i++)
     {
      if(entries[i].ExecutionRequestId()==executionRequestId)
        {
         found=true;
         break;
        }
     }
   string message=label+" entry must exist";
   CTestAssert::True(found,message);
  }

void              AssertEnvelopePresent(CFilePendingExecutionStore &store,
                                        const string idempotencyKey,
                                        const string label)
  {
   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(idempotencyKey);
   bool envelopeFound=envelopeResult.IsOk();
   string message=label+" envelope must exist";
   CTestAssert::True(envelopeFound,message);
  }

void              AssertEntryAbsent(CFilePendingExecutionStore &store,
                                      const string executionRequestId,
                                      const string label)
  {
   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   bool found=false;
   for(int i=0;i<count;i++)
     {
      if(entries[i].ExecutionRequestId()==executionRequestId)
        {
         found=true;
         break;
        }
     }
   string message=label+" entry must be absent";
   CTestAssert::False(found,message);
  }

void              TestRecoveryActiveValidUsesActive(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_PATH,BuildSnapshotPayloadMergedAB());
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,BuildSnapshotPayloadEntryAOnly());

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario A restore must succeed");
   AssertEntryPresent(store,ENTRY_A_REQUEST_ID,"Scenario A active");
   AssertEntryPresent(store,ENTRY_B_REQUEST_ID,"Scenario A active");
  }

void              TestRecoveryMissingActiveUsesTemp(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_TEMP_PATH,BuildSnapshotPayloadMergedAB());
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,BuildSnapshotPayloadEntryAOnly());

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario B restore must succeed");
   CTestAssert::True(TestFileExists(TEST_STORE_PATH),"Scenario B must recover active from temp");
   CTestAssert::False(TestFileExists(TEST_STORE_TEMP_PATH),"Scenario B must consume temp during recovery");
   AssertEntryPresent(store,ENTRY_A_REQUEST_ID,"Scenario B recovered");
   AssertEntryPresent(store,ENTRY_B_REQUEST_ID,"Scenario B recovered");
  }

void              TestRecoveryMissingActiveUsesBackup(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,BuildSnapshotPayloadEntryAOnly());

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario C restore must succeed");
   CTestAssert::True(TestFileExists(TEST_STORE_PATH),"Scenario C must recover active from backup");
   AssertEntryPresent(store,ENTRY_A_REQUEST_ID,"Scenario C recovered");
   AssertEntryAbsent(store,ENTRY_B_REQUEST_ID,"Scenario C backup-only");
  }

void              TestRecoveryCorruptActiveUsesTemp(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_PATH,"CORRUPT_ACTIVE_SNAPSHOT");
   WriteTestFileContent(TEST_STORE_TEMP_PATH,BuildSnapshotPayloadMergedAB());

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario D restore must succeed");
   AssertEntryPresent(store,ENTRY_A_REQUEST_ID,"Scenario D recovered");
   AssertEntryPresent(store,ENTRY_B_REQUEST_ID,"Scenario D recovered");
  }

void              TestRecoveryCorruptActiveUsesBackup(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_PATH,"CORRUPT_ACTIVE_SNAPSHOT");
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,BuildSnapshotPayloadEntryAOnly());

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario E restore must succeed");
   AssertEntryPresent(store,ENTRY_A_REQUEST_ID,"Scenario E recovered");
   AssertEntryAbsent(store,ENTRY_B_REQUEST_ID,"Scenario E backup-only");
  }

void              TestRecoveryFailsClosedWhenNoValidSnapshot(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_PATH,"CORRUPT_ACTIVE_SNAPSHOT");
   WriteTestFileContent(TEST_STORE_TEMP_PATH,"CORRUPT_TEMP_SNAPSHOT");
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,"CORRUPT_BACKUP_SNAPSHOT");

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsFail(),"Scenario F restore must fail closed");
   CTestAssert::EqualInt(BRE_ERR_PERSIST_READ_FAILED,restored.ErrorCode(),"Scenario F must report persist read failure");

   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   CTestAssert::EqualInt(0,count,"Scenario F must not load records into memory");
  }

void              TestPristineEmptyStoreSucceeds(void)
  {
   DeleteTestStoreArtifacts();
   CTestAssert::False(TestFileExists(TEST_STORE_PATH),"Scenario G active must be absent");
   CTestAssert::False(TestFileExists(TEST_STORE_TEMP_PATH),"Scenario G temp must be absent");
   CTestAssert::False(TestFileExists(TEST_STORE_BACKUP_PATH),"Scenario G backup must be absent");

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsOk(),"Scenario G pristine restore must succeed");
   CTestAssert::EqualString(BRE_PENDING_RESTORE_OUTCOME_PRISTINE_EMPTY,
                            store.LastRestoreOutcome(),
                            "Scenario G must report pristine empty restore outcome");

   CPendingExecutionEntry entries[];
   int entryCount=store.RestoreEntries(entries);
   CTestAssert::EqualInt(0,entryCount,"Scenario G must have zero entries");

   CResult<CBrokerSubmissionEnvelope> envelopeResult=store.FindEnvelopeByIdempotencyKey(ENTRY_A_IDEMPOTENCY_KEY);
   CTestAssert::True(envelopeResult.IsFail(),"Scenario G must have zero envelopes");
  }

void              TestInvalidTempWithoutArtifactsFailsClosed(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_TEMP_PATH,"CORRUPT_TEMP_SNAPSHOT");

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsFail(),"Scenario H restore must fail closed");
   CTestAssert::EqualInt(BRE_ERR_PERSIST_READ_FAILED,restored.ErrorCode(),"Scenario H must report persist read failure");

   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   CTestAssert::EqualInt(0,count,"Scenario H must not load records into memory");
  }

void              TestInvalidBackupWithoutArtifactsFailsClosed(void)
  {
   DeleteTestStoreArtifacts();
   WriteTestFileContent(TEST_STORE_BACKUP_PATH,"CORRUPT_BACKUP_SNAPSHOT");

   CFilePendingExecutionStore store(TEST_STORE_PATH);
   CVoidResult restored=store.RestoreFromDisk();
   CTestAssert::True(restored.IsFail(),"Scenario I restore must fail closed");
   CTestAssert::EqualInt(BRE_ERR_PERSIST_READ_FAILED,restored.ErrorCode(),"Scenario I must report persist read failure");

   CPendingExecutionEntry entries[];
   int count=store.RestoreEntries(entries);
   CTestAssert::EqualInt(0,count,"Scenario I must not load records into memory");
  }

void              TestMergedSnapshotPreservesUnrelatedRecords(void)
  {
   DeleteTestStoreArtifacts();

   CFilePendingExecutionStore writer(TEST_STORE_PATH);
   CPendingExecutionEntry entryA;
   CBrokerSubmissionEnvelope envelopeA;
   BuildEntryA(entryA);
   BuildEnvelopeA(envelopeA);
   CVoidResult saveA=writer.SavePreparedState(entryA,envelopeA);
   CTestAssert::True(saveA.IsOk(),"Persist unrelated entry A");

   CFilePendingExecutionStore reload(TEST_STORE_PATH);
   CVoidResult restoreA=reload.RestoreFromDisk();
   CTestAssert::True(restoreA.IsOk(),"Reload entry A from disk");
   CTestAssert::EqualInt(1,reload.CountPersistedEntriesOnDisk(),"Disk must contain entry A before merge");

   CPendingExecutionEntry entryB;
   CBrokerSubmissionEnvelope envelopeB;
   BuildEntryB(entryB,0.06);
   BuildEnvelopeB(envelopeB,0.06);
   CVoidResult saveB=reload.SavePreparedState(entryB,envelopeB);
   CTestAssert::True(saveB.IsOk(),"Persist merged entry B");

   CTestAssert::True(TestFileExists(TEST_STORE_PATH),"Active snapshot must exist after save");
   CTestAssert::False(TestFileExists(TEST_STORE_TEMP_PATH),"Temp file must be removed after successful save");

   CFilePendingExecutionStore verify(TEST_STORE_PATH);
   CVoidResult restoreMerged=verify.RestoreFromDisk();
   CTestAssert::True(restoreMerged.IsOk(),"Reload merged snapshot");
   CPendingExecutionEntry entries[];
   int entryCount=verify.RestoreEntries(entries);
   CTestAssert::EqualInt(2,entryCount,"Merged snapshot must contain two entries");
   AssertEntryPresent(verify,ENTRY_A_REQUEST_ID,"Unrelated record A");
   AssertEntryPresent(verify,ENTRY_B_REQUEST_ID,"Sprint8D record B");
   AssertEnvelopePresent(verify,ENTRY_A_IDEMPOTENCY_KEY,"Unrelated record A");
   AssertEnvelopePresent(verify,ENTRY_B_IDEMPOTENCY_KEY,"Sprint8D record B");
  }

void              TestUpsertPreservesUnrelatedRecord(void)
  {
   DeleteTestStoreArtifacts();

   CFilePendingExecutionStore writer(TEST_STORE_PATH);
   CPendingExecutionEntry entryA;
   CBrokerSubmissionEnvelope envelopeA;
   BuildEntryA(entryA);
   BuildEnvelopeA(envelopeA);
   CTestAssert::True(writer.SavePreparedState(entryA,envelopeA).IsOk(),"Persist unrelated entry A");

   CPendingExecutionEntry entryB;
   CBrokerSubmissionEnvelope envelopeB;
   BuildEntryB(entryB,0.06);
   BuildEnvelopeB(envelopeB,0.06);
   CTestAssert::True(writer.SavePreparedState(entryB,envelopeB).IsOk(),"Persist initial entry B");

   CPendingExecutionEntry entryBUpsert;
   CBrokerSubmissionEnvelope envelopeBUpsert;
   BuildEntryB(entryBUpsert,0.07);
   BuildEnvelopeB(envelopeBUpsert,0.07);
   CTestAssert::True(writer.SavePreparedState(entryBUpsert,envelopeBUpsert).IsOk(),"Upsert entry B by request id");

   CFilePendingExecutionStore verify(TEST_STORE_PATH);
   CTestAssert::True(verify.RestoreFromDisk().IsOk(),"Reload upserted snapshot");
   CTestAssert::EqualInt(2,verify.CountPersistedEntriesOnDisk(),"Upsert must keep total entry count at two");
   AssertEntryPresent(verify,ENTRY_A_REQUEST_ID,"Unrelated record A after upsert");
   AssertEntryPresent(verify,ENTRY_B_REQUEST_ID,"Upserted record B");

   CPendingExecutionEntry entries[];
   verify.RestoreEntries(entries);
   for(int i=0;i<ArraySize(entries);i++)
     {
      if(entries[i].ExecutionRequestId()==ENTRY_B_REQUEST_ID)
        {
         CTestAssert::EqualDouble(0.07,entries[i].RequestedVolume(),0.0000001,"Upsert must update entry B volume");
         break;
        }
     }

   CResult<CBrokerSubmissionEnvelope> envelopeResult=verify.FindEnvelopeByIdempotencyKey(ENTRY_B_IDEMPOTENCY_KEY);
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(envelopeResult.TryGetValue(envelope),"Envelope B must be readable after upsert");
   CTestAssert::EqualDouble(0.07,envelope.RequestedVolume(),0.0000001,"Upsert must update envelope B volume");
   AssertEnvelopePresent(verify,ENTRY_A_IDEMPOTENCY_KEY,"Unrelated record A envelope after upsert");
   CTestAssert::False(TestFileExists(TEST_STORE_TEMP_PATH),"Temp file must be removed after upsert save");
  }

void OnStart(void)
  {
   bool markerOk=CFilePendingExecutionStore::BuildMarker()=="S8D_FILE_PENDING_STORE_PRISTINE_V1";
   CTestAssert::True(markerOk,"Pending store build marker must identify pristine-empty restore contract");
   TestRecoveryActiveValidUsesActive();
   TestRecoveryMissingActiveUsesTemp();
   TestRecoveryMissingActiveUsesBackup();
   TestRecoveryCorruptActiveUsesTemp();
   TestRecoveryCorruptActiveUsesBackup();
   TestRecoveryFailsClosedWhenNoValidSnapshot();
   TestPristineEmptyStoreSucceeds();
   TestInvalidTempWithoutArtifactsFailsClosed();
   TestInvalidBackupWithoutArtifactsFailsClosed();
   TestMergedSnapshotPreservesUnrelatedRecords();
   TestUpsertPreservesUnrelatedRecord();
   DeleteTestStoreArtifacts();
   CTestAssert::Summary("TestSprint8dPendingStoreAtomicPersistence");
   if(!CTestAssert::AllPassed())
      return;
   Print("TestSprint8dPendingStoreAtomicPersistence: ALL PASSED");
  }
