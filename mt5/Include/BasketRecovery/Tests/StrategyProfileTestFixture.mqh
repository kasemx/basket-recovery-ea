#ifndef BASKET_RECOVERY_TESTS_STRATEGY_PROFILE_TEST_FIXTURE_MQH
#define BASKET_RECOVERY_TESTS_STRATEGY_PROFILE_TEST_FIXTURE_MQH

#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfile.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileBundle.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>

class CStrategyProfileTestFixture
  {
public:
   static CStrategyProfile BuildValidProfile(void)
     {
      CExecutionZone zone=CExecutionZone::CreateSignalRange(BRE_ZONE_EXPANSION_SYMMETRIC,3.0,3.0,false,0.0,false);

      CRecoveryStep steps[2];
      steps[0]=CRecoveryStep::Create(1,0.2,0.01);
      steps[1]=CRecoveryStep::Create(2,0.4,0.01);
      CRecoveryPlan recovery=CRecoveryPlan::CreateCustom(steps,2,true,true,3,0.01);

      CProfitLevel levels[1];
      levels[0]=CProfitLevel::Create("L1",1,BRE_PROFIT_LEVEL_SOURCE_SIGNAL_TP,0.0,false,33.0,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,true,false,true);
      CProfitDistributionPlan profitPlan=CProfitDistributionPlan::Create(true,BRE_CLOSE_MODE_WORST_ENTRY_FIRST,levels,1);

      CBreakEvenTrigger trigger=CBreakEvenTrigger::Create(BRE_BE_TRIGGER_REALIZED_PROFIT,10.0,true,0.0,false,0.0,false,"","","","");
      CBreakEvenAction actions[1];
      actions[0]=CBreakEvenAction::Create(BRE_BE_ACTION_MOVE_SL_TO_AVERAGE,0.0,0.5,true,false);
      CBreakEvenRule rules[1];
      rules[0]=CBreakEvenRule::Create("BE_REALIZED",true,10,true,trigger,actions,1);
      CBreakEvenPlan breakEvenPlan=CBreakEvenPlan::Create(rules,1);

      CRiskPlan riskPlan=CRiskPlan::Create(1.0,1.2,0.95,true,BRE_RISK_REDUCTION_MODE_WORST_ENTRY,0.0,false,30,100);
      CExecutionProfileConfig executionPolicy;
      CStrategyMetadata metadata=CStrategyMetadata::Create("Test Strategy","fixture","tests");

      return CStrategyProfile::Create("test-strategy",
                                      BRE_STRATEGY_SCHEMA_VERSION,
                                      metadata,
                                      zone,
                                      recovery,
                                      profitPlan,
                                      breakEvenPlan,
                                      riskPlan,
                                      executionPolicy,
                                      CUtcTime(0));
     }

   static CProfileBundle BuildDefaultV1Bundle(void)
     {
      CProfileBundle bundle;
      bundle.SetProfileName("default");
      bundle.SetBoundAt(CUtcTime(0));
      return bundle;
     }

   static string     MinimalValidJson(void)
     {
      return "{"
             "\"schema_version\":2,"
             "\"strategy_id\":\"json-test\","
             "\"metadata\":{\"strategy_name\":\"JSON Test\"},"
             "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
             "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
             "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
             "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[{\"level_id\":\"L1\",\"level_index\":1,\"source\":\"SIGNAL_TP\",\"close_percent\":33,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}]},"
             "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE1\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"REALIZED_PROFIT\",\"realized_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5}]}]},"
             "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
             "}";
     }
  };

#endif
