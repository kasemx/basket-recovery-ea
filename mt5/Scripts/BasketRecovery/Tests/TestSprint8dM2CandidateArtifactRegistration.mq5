#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Validation/Sprint8C/ManualProfitCloseCandidateValidationArtifact.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

const string TEST_ARTIFACT_PATH="BasketRecovery/validation/sprint-8d7b-test-m2-candidate.txt";
const string TEST_BASKET_ID="basket-8d7b-artifact-test";
const string TEST_CANDIDATE_ID="profit-level-close:basket-8d7b-artifact-test:level:M2:q:901";
const string TEST_EXECUTION_REQUEST_ID="profit-close-manual:8d7b-m2";
const string TEST_STRATEGY_PROFILE_HASH="profile-hash-8d7b-artifact-test";
const ulong TEST_POSITION_TICKET=1517000001;
const double TEST_ORIGINAL_VOLUME=0.10;
const double TEST_REQUESTED_CLOSE_VOLUME=0.05;
const ulong TEST_QUOTE_SEQUENCE=901;
const int TEST_REUSE_ELIGIBLE_ARTIFACT_TTL_SECONDS=720;
const datetime TEST_CREATED_AT_UTC=2000000;
const datetime TEST_NOW_UTC=TEST_CREATED_AT_UTC+60;
const datetime TEST_EXPIRES_AT_UTC=TEST_CREATED_AT_UTC+TEST_REUSE_ELIGIBLE_ARTIFACT_TTL_SECONDS;

void CleanupTestArtifact(void)
  {
   CManualProfitCloseCandidateValidationArtifact::TryRemoveRecord(TEST_ARTIFACT_PATH);
  }

CManualProfitCloseCandidateEntry BuildM2Entry(const string candidateId,
                                              const string profitLevelId,
                                              const int profitLevelIndex,
                                              const double proposedCloseVolume)
  {
   return CManualProfitCloseCandidateEntry::Create(candidateId,
                                                   TEST_EXECUTION_REQUEST_ID,
                                                   candidateId,
                                                   CBasketId(TEST_BASKET_ID),
                                                   profitLevelId,
                                                   profitLevelIndex,
                                                   TEST_STRATEGY_PROFILE_HASH,
                                                   2,
                                                   "XAUUSD",
                                                   BRE_DIRECTION_BUY,
                                                   BRE_DIRECTION_SELL,
                                                   TEST_POSITION_TICKET,
                                                   TEST_ORIGINAL_VOLUME,
                                                   proposedCloseVolume,
                                                   1.0,
                                                   BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
                                                   30.0,
                                                   TEST_QUOTE_SEQUENCE,
                                                   TEST_CREATED_AT_UTC,
                                                   TEST_EXPIRES_AT_UTC,
                                                   BRE_ACCOUNT_POSITION_MODEL_HEDGING);
  }

void TestFirstPersistSucceeds(void)
  {
   CleanupTestArtifact();
   CManualProfitCloseCandidateEntry entry=BuildM2Entry(TEST_CANDIDATE_ID,"M2",1,TEST_REQUESTED_CLOSE_VOLUME);
   bool reused=false;
   bool replacedExpired=false;
   CManualProfitCloseCandidateEntry persisted;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(entry,
                                                                                     "DUE",
                                                                                     TEST_NOW_UTC,
                                                                                     persisted,
                                                                                     reused,
                                                                                     replacedExpired,
                                                                                     diagnostics,
                                                                                     TEST_ARTIFACT_PATH),
                     "First TryPersistIdempotent must succeed");
   CTestAssert::False(reused,"First persist must not reuse existing artifact");
   CTestAssert::False(replacedExpired,"First persist must not replace expired artifact");
   CTestAssert::True(FileIsExist(TEST_ARTIFACT_PATH,FILE_COMMON),"Test artifact file must exist in FILE_COMMON");
  }

void TestReadAndValidateArtifact(void)
  {
   SSprint8cCandidateArtifactRecord loaded;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryLoadAndValidate(TEST_BASKET_ID,
                                                                                      TEST_POSITION_TICKET,
                                                                                      TEST_NOW_UTC,
                                                                                      loaded,
                                                                                      diagnostics,
                                                                                      TEST_ARTIFACT_PATH),
                     "TryLoadAndValidate must succeed for persisted M2 artifact");
   CTestAssert::EqualString("OK",diagnostics.validation,"Artifact validation must be OK");

   string integrityFailure="";
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::ValidateRecordIntegrity(loaded,integrityFailure),
                     "Artifact integrity must be valid");
   CTestAssert::EqualString("",integrityFailure,"Integrity validation must not set failure reason");
   CTestAssert::EqualString("DUE",loaded.status,"Artifact status must remain DUE");
   CTestAssert::EqualString("M2",loaded.profit_level_id,"profitLevelId must be M2");
   string levelMsg="candidateId must contain :level:M2:";
   CTestAssert::True(StringFind(loaded.candidate_id,":level:M2:")>=0,levelMsg);
   CTestAssert::EqualString(TEST_CANDIDATE_ID,loaded.candidate_id,"candidateId must be preserved");
   CTestAssert::EqualString(TEST_EXECUTION_REQUEST_ID,loaded.execution_request_id,"executionRequestId must be preserved");
   CTestAssert::EqualString(TEST_STRATEGY_PROFILE_HASH,loaded.strategy_profile_hash,"strategyProfileHash must be preserved");
   CTestAssert::EqualInt((int)TEST_POSITION_TICKET,(int)loaded.position_ticket,"positionTicket must be preserved");
   CTestAssert::EqualDouble(TEST_REQUESTED_CLOSE_VOLUME,loaded.requested_close_volume,0.00000001,"requestedCloseVolume must be 0.05");
  }

void TestIdempotentReuse(void)
  {
   SSprint8cCandidateArtifactRecord loaded;
   SSprint8cCandidateArtifactDiagnostics reusePrecheck;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryLoadAndValidate(TEST_BASKET_ID,
                                                                                      TEST_POSITION_TICKET,
                                                                                      TEST_NOW_UTC,
                                                                                      loaded,
                                                                                      reusePrecheck,
                                                                                      TEST_ARTIFACT_PATH),
                     "Reuse precheck load must succeed");
   CTestAssert::True(reusePrecheck.expiry_remaining_seconds>reusePrecheck.required_minimum_artifact_remaining_seconds,
                     "expiryRemainingSeconds must exceed requiredMinimumArtifactRemainingSeconds");
   CTestAssert::True(reusePrecheck.reuse_allowed,"reuseAllowed must be true before second persist");

   CManualProfitCloseCandidateEntry entry=BuildM2Entry(TEST_CANDIDATE_ID,"M2",1,TEST_REQUESTED_CLOSE_VOLUME);
   bool reused=false;
   bool replacedExpired=false;
   CManualProfitCloseCandidateEntry persisted;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(entry,
                                                                                     "DUE",
                                                                                     TEST_NOW_UTC,
                                                                                     persisted,
                                                                                     reused,
                                                                                     replacedExpired,
                                                                                     diagnostics,
                                                                                     TEST_ARTIFACT_PATH),
                     "Second TryPersistIdempotent with same binding must succeed");
   CTestAssert::True(reused,"Second persist must reuse existing artifact");
   CTestAssert::False(replacedExpired,"Idempotent reuse must not replace artifact");
   CTestAssert::EqualString(TEST_CANDIDATE_ID,persisted.CandidateId(),"Reused entry must keep original candidateId");
   CTestAssert::EqualString(TEST_EXECUTION_REQUEST_ID,persisted.ExecutionRequestId(),"Reused entry must keep original executionRequestId");
  }

void TestCloseVolumeBindingMismatchRejected(void)
  {
   CManualProfitCloseCandidateEntry mismatched=BuildM2Entry(TEST_CANDIDATE_ID,"M2",1,0.04);
   bool reused=false;
   bool replacedExpired=false;
   CManualProfitCloseCandidateEntry persisted;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   CTestAssert::False(CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(mismatched,
                                                                                      "DUE",
                                                                                      TEST_NOW_UTC,
                                                                                      persisted,
                                                                                      reused,
                                                                                      replacedExpired,
                                                                                      diagnostics,
                                                                                      TEST_ARTIFACT_PATH),
                      "Close volume binding mismatch must be rejected");
   CTestAssert::EqualString("invalid",diagnostics.existing_state,"Volume mismatch must classify existing artifact as invalid");
   string mismatchMsg="Volume mismatch failure reason must mention binding mismatch";
   CTestAssert::True(StringFind(diagnostics.failure_reason,"binding")>=0,mismatchMsg);

   SSprint8cCandidateArtifactRecord loaded;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryReadRecord(TEST_ARTIFACT_PATH,loaded),
                     "Original M2 artifact must remain on disk after volume mismatch");
   CTestAssert::EqualString(TEST_CANDIDATE_ID,loaded.candidate_id,"Volume mismatch must not replace candidateId");
   CTestAssert::EqualDouble(TEST_REQUESTED_CLOSE_VOLUME,loaded.requested_close_volume,0.00000001,
                            "Volume mismatch must not replace requestedCloseVolume");
  }

void TestCandidateLevelBindingMismatchRejected(void)
  {
   const string m3CandidateId="profit-level-close:basket-8d7b-artifact-test:level:M3:q:902";
   CManualProfitCloseCandidateEntry mismatched=BuildM2Entry(m3CandidateId,"M3",2,TEST_REQUESTED_CLOSE_VOLUME);
   bool reused=false;
   bool replacedExpired=false;
   CManualProfitCloseCandidateEntry persisted;
   SSprint8cCandidateArtifactDiagnostics diagnostics;
   CTestAssert::False(CManualProfitCloseCandidateValidationArtifact::TryPersistIdempotent(mismatched,
                                                                                      "DUE",
                                                                                      TEST_NOW_UTC,
                                                                                      persisted,
                                                                                      reused,
                                                                                      replacedExpired,
                                                                                      diagnostics,
                                                                                      TEST_ARTIFACT_PATH),
                      "M3 candidate level binding mismatch must be rejected");
   CTestAssert::EqualString("invalid",diagnostics.existing_state,"Level mismatch must classify existing artifact as invalid");
   string levelMismatchMsg="Level mismatch failure reason must mention binding mismatch";
   CTestAssert::True(StringFind(diagnostics.failure_reason,"binding")>=0,levelMismatchMsg);

   SSprint8cCandidateArtifactRecord loaded;
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryReadRecord(TEST_ARTIFACT_PATH,loaded),
                     "Original M2 artifact must remain on disk after level mismatch");
   CTestAssert::EqualString("M2",loaded.profit_level_id,"Level mismatch must not replace profitLevelId");
   CTestAssert::EqualString(TEST_CANDIDATE_ID,loaded.candidate_id,"Level mismatch must not replace candidateId");
  }

void TestCleanupRemovesArtifact(void)
  {
   CTestAssert::True(CManualProfitCloseCandidateValidationArtifact::TryRemoveRecord(TEST_ARTIFACT_PATH),
                     "TryRemoveRecord must succeed for test artifact");
   CTestAssert::False(FileIsExist(TEST_ARTIFACT_PATH,FILE_COMMON),"Test artifact must no longer exist after cleanup");
  }

void OnStart(void)
  {
   CleanupTestArtifact();
   TestFirstPersistSucceeds();
   TestReadAndValidateArtifact();
   TestIdempotentReuse();
   TestCloseVolumeBindingMismatchRejected();
   TestCandidateLevelBindingMismatchRejected();
   TestCleanupRemovesArtifact();
   CleanupTestArtifact();
   CTestAssert::Summary("TestSprint8dM2CandidateArtifactRegistration");
   if(!CTestAssert::AllPassed())
      return;
   Print("TestSprint8dM2CandidateArtifactRegistration: ALL PASSED");
  }
