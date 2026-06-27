#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonLoader.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

void TestJsonLoadSuccess(void)
  {
   CStrategyProfileJsonLoader loader;
   CResult<CStrategyProfile> result=loader.LoadFromJsonContent(CStrategyProfileTestFixture::MinimalValidJson());
   CTestAssert::True(result.IsOk(),"Minimal valid JSON must load successfully");
   CStrategyProfile profile;
   CTestAssert::True(result.TryGetValue(profile),"Loaded profile must exist");
   CTestAssert::EqualString("json-test",profile.StrategyId(),"Loaded strategy id must match");
  }

void TestJsonMissingRequiredField(void)
  {
   string invalidJson="{"
                      "\"schema_version\":2,"
                      "\"strategy_id\":\"missing-risk\","
                      "\"metadata\":{\"strategy_name\":\"Missing Risk\"},"
                      "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
                      "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
                      "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[{\"level_id\":\"L1\",\"level_index\":1,\"source\":\"SIGNAL_TP\",\"close_percent\":33,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}]},"
                      "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE1\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"REALIZED_PROFIT\",\"realized_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5}]}]},"
                      "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
                      "}";

   CStrategyProfileJsonLoader loader;
   CResult<CStrategyProfile> result=loader.LoadFromJsonContent(invalidJson);
   CTestAssert::False(result.IsOk(),"JSON missing risk_plan must fail");
   CTestAssert::EqualInt(BRE_ERR_STRATEGY_SCHEMA_INVALID,result.ErrorCode(),"Missing section must report schema invalid");
  }

void TestGoldenFileLoad(void)
  {
   CStrategyProfileJsonLoader loader;
   CResult<CStrategyProfile> result=loader.LoadFromStrategyId(BRE_STRATEGY_DEFAULT_ID);
   CTestAssert::True(result.IsOk(),"Golden strategy profile file must load successfully");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestJsonLoadSuccess();
   TestJsonMissingRequiredField();
   TestGoldenFileLoad();
   CTestAssert::Summary("TestStrategyProfileJsonLoader");
   if(!CTestAssert::AllPassed())
      Print("TestStrategyProfileJsonLoader FAILED");
  }
