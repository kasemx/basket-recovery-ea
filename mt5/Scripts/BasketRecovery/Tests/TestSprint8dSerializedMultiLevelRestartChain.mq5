#property script_show_inputs

#include "../../../Include/BasketRecovery/Tests/TestAssert.mqh"
#include "../../../Include/BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh"
#include "../../../Include/BasketRecovery/Domain/Aggregates/BasketAggregate.mqh"
#include "../../../Include/BasketRecovery/Domain/Factories/BasketFactory.mqh"
#include "../../../Include/BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh"
#include "../../../Include/BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh"
#include "../../../Include/BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh"
#include "../../../Include/BasketRecovery/Domain/Enums/BasketLifecycleState.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Money.mqh"
#include "../../../Include/BasketRecovery/Shared/Types/Identifiers.mqh"

const string TEST_BASKET_ID="basket-8d5-serialized-chain";
const string TEST_FILE_PATH="BasketRecovery/validation/sprint-8d5-serialized-multi-level-chain.json";
const double M1_REALIZED_PROFIT=1.11;
const double M2_REALIZED_PROFIT=2.22;
const double M3_REALIZED_PROFIT=3.33;
const datetime M1_COMPLETED_AT=1101;
const datetime M2_COMPLETED_AT=1202;
const datetime M3_COMPLETED_AT=1303;

string ThreeLevelStrategyJson(void)
  {
   return "{"
          "\"schema_version\":2,"
          "\"strategy_id\":\"sprint-8d5-profile\","
          "\"metadata\":{\"strategy_name\":\"Sprint 8D5\"},"
          "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
          "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
          "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
          "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":["
          "{\"level_id\":\"M1\",\"level_index\":1,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":10.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":10.0,\"close_percent\":33.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
          "{\"level_id\":\"M2\",\"level_index\":2,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":20.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":20.0,\"close_percent\":33.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
          "{\"level_id\":\"M3\",\"level_index\":3,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":30.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":30.0,\"close_percent\":34.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}"
          "]},"
          "\"break_even_plan\":{\"rules\":[]},"
          "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
          "}";
  }

CStrategyProfile BuildThreeLevelProfileFromJson(void)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(ThreeLevelStrategyJson(),CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   return profile;
  }

bool CleanupTestFile(void)
  {
   if(FileIsExist(TEST_FILE_PATH,FILE_COMMON))
      return FileDelete(TEST_FILE_PATH,FILE_COMMON);
   return true;
  }

bool WriteJsonToTestFile(const string json)
  {
   int handle=FileOpen(TEST_FILE_PATH,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return false;
   FileWriteString(handle,json);
   FileClose(handle);
   return true;
  }

bool ReadJsonFromTestFile(string &jsonOut)
  {
   jsonOut="";
   if(!FileIsExist(TEST_FILE_PATH,FILE_COMMON))
      return false;
   int handle=FileOpen(TEST_FILE_PATH,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return false;
   while(!FileIsEnding(handle))
      jsonOut+=FileReadString(handle);
   FileClose(handle);
   return true;
  }

CBasketAggregate BuildBasketWithReachedLevels(void)
  {
   CStrategyProfile profile=BuildThreeLevelProfileFromJson();
   string canonicalJson=ThreeLevelStrategyJson();
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
   return basket;
  }

void MarkLevelCompleted(CBasketAggregate &basket,
                        const string levelId,
                        const double realizedProfit,
                        const datetime completedAt)
  {
   basket.ApplyProfitLevelCloseCompleted(levelId,CMoney(realizedProfit),CCommandId("close-"+levelId),
                                         CEventId("close-evt-"+levelId),CUtcTime(completedAt));
  }

void AssertLevelRuntimeState(const CBasketAggregate &basket,
                             const string levelId,
                             const bool expectedReached,
                             const bool expectedCloseRequested,
                             const bool expectedCloseCompleted,
                             const double expectedRealizedProfit,
                             const datetime expectedCompletedAtUtc,
                             const string messagePrefix)
  {
   CBasketProfitLevelProgress progress;
   string msg="";
   msg=messagePrefix+" progress must exist";
   CTestAssert::True(basket.FindProfitLevelProgress(levelId,progress),msg);
   msg=messagePrefix+" reached";
   CTestAssert::True(progress.Reached()==expectedReached,msg);
   msg=messagePrefix+" closeRequested";
   CTestAssert::True(progress.CloseRequested()==expectedCloseRequested,msg);
   msg=messagePrefix+" closeCompleted";
   CTestAssert::True(progress.CloseCompleted()==expectedCloseCompleted,msg);
   msg=messagePrefix+" realizedProfit";
   CTestAssert::EqualDouble(expectedRealizedProfit,progress.RealizedProfit().Amount(),0.0000001,msg);
   msg=messagePrefix+" completedAtUtc";
   CTestAssert::EqualInt((int)expectedCompletedAtUtc,(int)progress.CompletedAtUtc().Value(),msg);
  }

bool TryGetProfileFromBasket(const CBasketAggregate &basket,CStrategyProfile &profile)
  {
   return basket.StrategyProfile(profile);
  }

void AssertStrategyBindingRestored(const CBasketAggregate &basket,const string messagePrefix)
  {
   string msg=messagePrefix+" strategy profile must be bound";
   CTestAssert::True(basket.HasStrategyProfile(),msg);
   msg=messagePrefix+" strategy profile hash must be non-empty";
   CTestAssert::True(basket.StrategyProfileHash()!="",msg);
   CStrategyProfile profile;
   msg=messagePrefix+" strategy profile must deserialize from canonical json";
   CTestAssert::True(basket.StrategyProfile(profile),msg);
   msg=messagePrefix+" strategy must retain three profit levels";
   CTestAssert::EqualInt(3,profile.ProfitDistributionPlan().LevelCount(),msg);
  }

bool SerializeWriteReadDeserialize(const CBasketAggregate &source,
                                   CBasketAggregate &restoredOut,
                                   string &readBackJsonOut,
                                   const string phaseLabel)
  {
   readBackJsonOut="";
   CBasketSerializer serializer;
   string serialized=serializer.Serialize(source);
   string msg=phaseLabel+" serialized json must be non-empty";
   CTestAssert::True(serialized!="",msg);
   msg=phaseLabel+" file write must succeed";
   CTestAssert::True(WriteJsonToTestFile(serialized),msg);
   msg=phaseLabel+" file must exist after write";
   CTestAssert::True(FileIsExist(TEST_FILE_PATH,FILE_COMMON),msg);
   msg=phaseLabel+" file read must succeed";
   CTestAssert::True(ReadJsonFromTestFile(readBackJsonOut),msg);
   msg=phaseLabel+" read-back json must be non-empty";
   CTestAssert::True(readBackJsonOut!="",msg);

   CResult<CBasketAggregate> loaded=serializer.Deserialize(readBackJsonOut,false);
   msg=phaseLabel+" deserialize must succeed";
   CTestAssert::True(loaded.IsOk(),msg);
   return loaded.TryGetValue(restoredOut);
  }

void TestSerializedMultiLevelRestartChain(void)
  {
   CTestAssert::True(CleanupTestFile(),"pre-test cleanup delete must succeed");
   CTestAssert::False(FileIsExist(TEST_FILE_PATH,FILE_COMMON),"test file must not exist before chain");

   CBasketAggregate basket=BuildBasketWithReachedLevels();
   MarkLevelCompleted(basket,"M1",M1_REALIZED_PROFIT,M1_COMPLETED_AT);

   string readBackAfterM1="";
   CBasketAggregate restoredAfterM1;
   CTestAssert::True(SerializeWriteReadDeserialize(basket,restoredAfterM1,readBackAfterM1,"after M1"),
                     "first serialize/write/read/deserialize must restore aggregate");

   AssertLevelRuntimeState(restoredAfterM1,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after first file restore M1");
   AssertStrategyBindingRestored(restoredAfterM1,"after first file restore");

   CStrategyProfile profileAfterM1;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM1,profileAfterM1),
                     "first restored basket must expose strategy profile");
   string selectedAfterM1="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM1,
                                                                                                   profileAfterM1,
                                                                                                   selectedAfterM1),
                     "after first file restore planner must select a level");
   CTestAssert::EqualString("M2",selectedAfterM1,"after first file restore planner must select M2");
   CTestAssert::True(selectedAfterM1!="M1","after first file restore planner must not select M1");

   MarkLevelCompleted(restoredAfterM1,"M2",M2_REALIZED_PROFIT,M2_COMPLETED_AT);
   string readBackAfterM2="";
   CBasketAggregate restoredAfterM2;
   CTestAssert::True(SerializeWriteReadDeserialize(restoredAfterM1,restoredAfterM2,readBackAfterM2,"after M2"),
                     "second serialize/write/read/deserialize must restore aggregate");

   AssertLevelRuntimeState(restoredAfterM2,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after second file restore M1");
   AssertLevelRuntimeState(restoredAfterM2,"M2",true,true,true,M2_REALIZED_PROFIT,M2_COMPLETED_AT,
                           "after second file restore M2");
   AssertStrategyBindingRestored(restoredAfterM2,"after second file restore");

   CStrategyProfile profileAfterM2;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM2,profileAfterM2),
                     "second restored basket must expose strategy profile");
   string selectedAfterM2="";
   CTestAssert::True(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM2,
                                                                                                   profileAfterM2,
                                                                                                   selectedAfterM2),
                     "after second file restore planner must select a level");
   CTestAssert::EqualString("M3",selectedAfterM2,"after second file restore planner must select M3");
   CTestAssert::True(selectedAfterM2!="M1" && selectedAfterM2!="M2",
                     "after second file restore planner must not select M1 or M2");

   MarkLevelCompleted(restoredAfterM2,"M3",M3_REALIZED_PROFIT,M3_COMPLETED_AT);
   string readBackAfterM3="";
   CBasketAggregate restoredAfterM3;
   CTestAssert::True(SerializeWriteReadDeserialize(restoredAfterM2,restoredAfterM3,readBackAfterM3,"after M3"),
                     "final serialize/write/read/deserialize must restore aggregate");

   AssertLevelRuntimeState(restoredAfterM3,"M1",true,true,true,M1_REALIZED_PROFIT,M1_COMPLETED_AT,
                           "after final file restore M1");
   AssertLevelRuntimeState(restoredAfterM3,"M2",true,true,true,M2_REALIZED_PROFIT,M2_COMPLETED_AT,
                           "after final file restore M2");
   AssertLevelRuntimeState(restoredAfterM3,"M3",true,true,true,M3_REALIZED_PROFIT,M3_COMPLETED_AT,
                           "after final file restore M3");
   AssertStrategyBindingRestored(restoredAfterM3,"after final file restore");

   CStrategyProfile profileAfterM3;
   CTestAssert::True(TryGetProfileFromBasket(restoredAfterM3,profileAfterM3),
                     "final restored basket must expose strategy profile");
   string selectedAfterM3="";
   CTestAssert::False(CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevelFromBasket(restoredAfterM3,
                                                                                                    profileAfterM3,
                                                                                                    selectedAfterM3),
                      "after final file restore planner must return no eligible level");
   CTestAssert::EqualString("",selectedAfterM3,"after final file restore no level should be selected");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CleanupTestFile();
   TestSerializedMultiLevelRestartChain();
   CTestAssert::True(CleanupTestFile(),"post-test cleanup delete must succeed");
   CTestAssert::False(FileIsExist(TEST_FILE_PATH,FILE_COMMON),"test file must not exist after cleanup");
   CTestAssert::Summary("TestSprint8dSerializedMultiLevelRestartChain");
  }
