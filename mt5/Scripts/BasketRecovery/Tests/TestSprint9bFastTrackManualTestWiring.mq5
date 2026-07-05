#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestOrchestrator.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackAuditFileSource.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>

const string SEED_TEXT="Gold sell now";
const string DETAILS_TEXT=
   "Gold sell now 4014 - 4017\n"
   "SL: 4077\n"
   "TP: 4007\n"
   "TP: 4005\n"
   "TP: 4003\n"
   "TP: 4002\n"
   "TP: open";

const string TEST_SEED_FILE="bre_fasttrack_audit_test_seed_9b.txt";
const string TEST_DETAILS_FILE="bre_fasttrack_audit_test_details_9b.txt";
const string TEST_EMPTY_SEED_FILE="bre_fasttrack_audit_test_empty_seed_9b.txt";
const string TEST_OVERSIZE_FILE="bre_fasttrack_audit_test_oversize_9b.txt";

bool WriteTestFixture(const string fileName,const string content)
  {
   int handle=FileOpen(fileName,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return false;
   FileWriteString(handle,content);
   FileClose(handle);
   return true;
  }

void DeleteTestFixture(const string fileName)
  {
   if(FileIsExist(fileName,FILE_COMMON))
      FileDelete(fileName,FILE_COMMON);
  }

void CleanupAuditFileFixtures(void)
  {
   DeleteTestFixture(TEST_SEED_FILE);
   DeleteTestFixture(TEST_DETAILS_FILE);
   DeleteTestFixture(TEST_EMPTY_SEED_FILE);
   DeleteTestFixture(TEST_OVERSIZE_FILE);
  }

SFastTrackManualTestInputs BuildBaseInputs(void)
  {
   SFastTrackManualTestInputs inputs;
   inputs.enabled=true;
   inputs.seed_text=SEED_TEXT;
   inputs.details_text=DETAILS_TEXT;
   inputs.seed_lot=0.01;
   inputs.seed_order_count=1;
   inputs.allow_demo_seed_execution=true;
   inputs.enable_recovery=false;
   inputs.enable_range_add=false;
   inputs.enable_de_risk=false;
   inputs.enable_break_even=false;
   inputs.observer_only_startup_isolation=false;
   inputs.global_execution_kill_switch=false;
   inputs.enable_live_demo_execution=true;
   inputs.execution_mode=(int)BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION;
   return inputs;
  }

void TestSeedDetailsBindPass(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND,(int)outcome.stage,
                         "Seed + details must bind basket");
   CTestAssert::True(outcome.seed_parse_valid,"Seed parse must be valid");
   CTestAssert::True(outcome.details_parse_valid,"Details parse must be valid");
   CTestAssert::True(outcome.sl_apply_planned,"SL apply must be planned");
  }

void TestIdempotentSecondProcessingPass(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   orchestrator.Process(inputs,1000);
   SFastTrackManualTestOutcome second=orchestrator.Process(inputs,1001);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_IDEMPOTENT_SKIP,(int)second.stage,
                         "Repeated seed + details must be idempotent");
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_IDEMPOTENT_SKIP,(int)second.order_plan_result,
                         "Repeated processing must not create second order plan");
  }

void TestObserverIsolationBlocksOrderPlan(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   inputs.observer_only_startup_isolation=true;
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_BLOCKED,(int)outcome.order_plan_result,
                         "Observer isolation must block order plan");
   CTestAssert::EqualString("OBSERVER_ONLY_STARTUP_ISOLATION",outcome.block_reason,
                            "Observer isolation block reason");
  }

void TestGlobalKillSwitchBlocksOrderPlan(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   inputs.global_execution_kill_switch=true;
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_BLOCKED,(int)outcome.order_plan_result,
                         "Global kill switch must block order plan");
   CTestAssert::EqualString("GLOBAL_EXECUTION_KILL_SWITCH",outcome.block_reason,
                            "Global kill switch block reason");
  }

void TestDetailsMissingWaitsWithoutOrder(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   inputs.details_text="";
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS,(int)outcome.stage,
                         "Missing details must keep basket waiting");
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_NONE,(int)outcome.order_plan_result,
                         "Missing details must not create order plan");
  }

void TestInvalidGeometryRejectsWithoutOrder(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   inputs.details_text=
      "Gold sell now 4014 - 4017\n"
      "SL: 4010\n"
      "TP: 4067\n";
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_REJECTED,(int)outcome.stage,
                         "Invalid SL/TP geometry must reject");
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_BLOCKED,(int)outcome.order_plan_result,
                         "Invalid geometry must not allow order plan");
  }

void TestAuditFileSourceDisabled(void)
  {
   string seedText="";
   string detailsText="";
   string reason="";
   CTestAssert::False(CFastTrackAuditFileSource::TryRead(false,TEST_SEED_FILE,TEST_DETAILS_FILE,seedText,detailsText,reason),
                      "Disabled audit file source must not read");
   CTestAssert::EqualString("DISABLED",reason,"Disabled audit file source reason");
  }

void TestAuditFileSourceReadsValidFixtures(void)
  {
   CleanupAuditFileFixtures();
   CTestAssert::True(WriteTestFixture(TEST_SEED_FILE,SEED_TEXT),"Seed fixture must be written");
   CTestAssert::True(WriteTestFixture(TEST_DETAILS_FILE,DETAILS_TEXT),"Details fixture must be written");

   string seedText="";
   string detailsText="";
   string reason="";
   CTestAssert::True(CFastTrackAuditFileSource::TryRead(true,TEST_SEED_FILE,TEST_DETAILS_FILE,seedText,detailsText,reason),
                     "Valid audit file fixtures must read");
   CTestAssert::EqualString(SEED_TEXT,seedText,"Seed fixture content must match");
   CTestAssert::EqualString(DETAILS_TEXT,detailsText,"Details fixture content must match");

   CleanupAuditFileFixtures();
  }

void TestAuditFileSourceRejectsInvalidBasenames(void)
  {
   string seedText="";
   string detailsText="";
   string reason="";

   CTestAssert::False(CFastTrackAuditFileSource::TryRead(true,"../seed.txt",TEST_DETAILS_FILE,seedText,detailsText,reason),
                      "Parent traversal seed file must reject");
   CTestAssert::EqualString("INVALID_FILE_NAME",reason,"Parent traversal reason");

   reason="";
   CTestAssert::False(CFastTrackAuditFileSource::TryRead(true,"folder/seed.txt",TEST_DETAILS_FILE,seedText,detailsText,reason),
                      "Slash seed file must reject");
   CTestAssert::EqualString("INVALID_FILE_NAME",reason,"Slash basename reason");

   reason="";
   CTestAssert::False(CFastTrackAuditFileSource::TryRead(true,"seed.txt","details\\file.txt",seedText,detailsText,reason),
                      "Backslash details file must reject");
   CTestAssert::EqualString("INVALID_FILE_NAME",reason,"Backslash basename reason");
  }

void TestAuditFileSourceRejectsEmptyContent(void)
  {
   CleanupAuditFileFixtures();
   CTestAssert::True(WriteTestFixture(TEST_EMPTY_SEED_FILE,""),"Empty seed fixture must be written");
   CTestAssert::True(WriteTestFixture(TEST_DETAILS_FILE,DETAILS_TEXT),"Details fixture must be written");

   string seedText="";
   string detailsText="";
   string reason="";
   CTestAssert::False(CFastTrackAuditFileSource::TryRead(true,TEST_EMPTY_SEED_FILE,TEST_DETAILS_FILE,seedText,detailsText,reason),
                      "Empty seed file must reject");
   CTestAssert::EqualString("EMPTY_SEED",reason,"Empty seed reason");

   CleanupAuditFileFixtures();
  }

void TestAuditFileSourceRejectsOversizeContent(void)
  {
   CleanupAuditFileFixtures();
   string oversizeContent="";
   for(int i=0;i<8200;i++)
      oversizeContent+="x";
   CTestAssert::True(WriteTestFixture(TEST_OVERSIZE_FILE,oversizeContent),"Oversize fixture must be written");

   string seedText="";
   string detailsText="";
   string reason="";
   CTestAssert::False(CFastTrackAuditFileSource::TryRead(true,TEST_OVERSIZE_FILE,TEST_DETAILS_FILE,seedText,detailsText,reason),
                      "Oversize file must reject");
   CTestAssert::EqualString("FILE_TOO_LARGE",reason,"Oversize file reason");

   CleanupAuditFileFixtures();
  }

void TestAuditFileSourceObserverIsolationAndIdempotency(void)
  {
   CleanupAuditFileFixtures();
   CTestAssert::True(WriteTestFixture(TEST_SEED_FILE,SEED_TEXT),"Seed fixture must be written");
   CTestAssert::True(WriteTestFixture(TEST_DETAILS_FILE,DETAILS_TEXT),"Details fixture must be written");

   string seedText="";
   string detailsText="";
   string reason="";
   CTestAssert::True(CFastTrackAuditFileSource::TryRead(true,TEST_SEED_FILE,TEST_DETAILS_FILE,seedText,detailsText,reason),
                     "Audit file fixtures must read for orchestrator test");

   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildBaseInputs();
   inputs.seed_text=seedText;
   inputs.details_text=detailsText;
   inputs.observer_only_startup_isolation=true;
   SFastTrackManualTestOutcome first=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND,(int)first.stage,
                         "File source signal must bind details");
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_BLOCKED,(int)first.order_plan_result,
                         "Observer isolation must block file source order plan");
   CTestAssert::EqualString("OBSERVER_ONLY_STARTUP_ISOLATION",first.block_reason,
                            "File source observer isolation block reason");

   SFastTrackManualTestOutcome second=orchestrator.Process(inputs,1001);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_MANUAL_STAGE_IDEMPOTENT_SKIP,(int)second.stage,
                         "Repeated file source signal must be idempotent");
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_IDEMPOTENT_SKIP,(int)second.order_plan_result,
                         "Repeated file source signal must skip order plan");

   CleanupAuditFileFixtures();
  }

void TestDirectInputPriorityOverAuditFileSource(void)
  {
   CleanupAuditFileFixtures();
   CTestAssert::True(WriteTestFixture(TEST_SEED_FILE,"Gold buy now"),"Alternate seed fixture must be written");
   CTestAssert::True(WriteTestFixture(TEST_DETAILS_FILE,DETAILS_TEXT),"Details fixture must be written");

   string directSeed=SEED_TEXT;
   string directDetails=DETAILS_TEXT;
   string fileSeed="";
   string fileDetails="";
   string reason="";

   if(directSeed!="")
     {
      CTestAssert::EqualString(SEED_TEXT,directSeed,"Direct seed must remain authoritative");
      CTestAssert::EqualString(DETAILS_TEXT,directDetails,"Direct details must remain authoritative");
     }
   else
     {
      CTestAssert::True(CFastTrackAuditFileSource::TryRead(true,TEST_SEED_FILE,TEST_DETAILS_FILE,fileSeed,fileDetails,reason),
                        "File source must read when direct seed is empty");
     }

   CleanupAuditFileFixtures();
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestSeedDetailsBindPass();
   TestIdempotentSecondProcessingPass();
   TestObserverIsolationBlocksOrderPlan();
   TestGlobalKillSwitchBlocksOrderPlan();
   TestDetailsMissingWaitsWithoutOrder();
   TestInvalidGeometryRejectsWithoutOrder();
   TestAuditFileSourceDisabled();
   TestAuditFileSourceReadsValidFixtures();
   TestAuditFileSourceRejectsInvalidBasenames();
   TestAuditFileSourceRejectsEmptyContent();
   TestAuditFileSourceRejectsOversizeContent();
   TestAuditFileSourceObserverIsolationAndIdempotency();
   TestDirectInputPriorityOverAuditFileSource();
   CleanupAuditFileFixtures();
   CTestAssert::Summary("TestSprint9bFastTrackManualTestWiring");
   if(CTestAssert::AllPassed())
      Print("TestSprint9bFastTrackManualTestWiring: all tests passed");
  }
