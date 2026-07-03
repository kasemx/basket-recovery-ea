#ifndef BRE_SPRINT8D_DEMO_M123_STRATEGY_PROFILE_MQH
#define BRE_SPRINT8D_DEMO_M123_STRATEGY_PROFILE_MQH

// Validation-only Sprint 8D controlled-demo M1/M2/M3 strategy profile.
// Do not include from production paths.

class CSprint8dDemoM123StrategyProfile
  {
public:
   static string     StrategyId(void)
     {
      return "sprint-8d-demo-xauusd-m123-v1";
     }

   static string     ExpectedHash(void)
     {
      return "53426F50";
     }

   static string     CanonicalJson(void)
     {
      return "{"
             "\"schema_version\":2,"
             "\"strategy_id\":\"sprint-8d-demo-xauusd-m123-v1\","
             "\"metadata\":{\"strategy_name\":\"Sprint 8D Demo XAUUSD M1/M2/M3\",\"description\":\"Controlled D0E validation profile\"},"
             "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
             "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":1,\"initial_lot_size\":0.06},"
             "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
             "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":["
             "{\"level_id\":\"M1\",\"level_index\":1,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":10.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":10.0,\"close_percent\":33.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
             "{\"level_id\":\"M2\",\"level_index\":2,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":20.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":20.0,\"close_percent\":50.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true},"
             "{\"level_id\":\"M3\",\"level_index\":3,\"source\":\"FLOATING_PROFIT_MONEY\",\"price\":30.0,\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":30.0,\"close_percent\":34.0,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}"
             "]},"
             "\"break_even_plan\":{\"rules\":[]},"
             "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":0,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
             "}";
     }
  };

#endif
