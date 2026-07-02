#ifndef BRE_SPRINT8C_VALIDATION_PROFILE_MQH
#define BRE_SPRINT8C_VALIDATION_PROFILE_MQH

// Validation-only Sprint 8C strategy profile. Do not include from production paths.

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

const string SPRINT8C_VALIDATION_PROFILE_VERSION="S8C_V2";
const string SPRINT8C_VALIDATION_PROFILE_ID="sprint8c-profit-close-v2";
const string SPRINT8C_VALIDATION_DEFAULT_BASKET_ID="sprint8c-demo-xauusd-002";
const double SPRINT8C_VALIDATION_FLOATING_PROFIT_TRIGGER_USD=0.01;

class CSprint8cValidationProfile
  {
public:
   static string     DefaultBrokerValidationBasketId(void) { return SPRINT8C_VALIDATION_DEFAULT_BASKET_ID; }
   static string     ProfileVersionLabel(void) { return SPRINT8C_VALIDATION_PROFILE_VERSION; }
   static string     ProfileId(void) { return SPRINT8C_VALIDATION_PROFILE_ID; }
   static double     FloatingProfitTriggerUsd(void) { return SPRINT8C_VALIDATION_FLOATING_PROFIT_TRIGGER_USD; }
   static string     FloatingProfitTriggerTypeLabel(void) { return "FLOATING_PROFIT_MONEY"; }

   static bool       TryParseSeedDirection(const string seedDirectionInput,ENUM_BRE_TRADE_DIRECTION &outDirection)
     {
      string normalized=seedDirectionInput;
      StringToUpper(normalized);
      if(normalized=="BUY")
        {
         outDirection=BRE_DIRECTION_BUY;
         return true;
        }
      if(normalized=="SELL")
        {
         outDirection=BRE_DIRECTION_SELL;
         return true;
        }
      outDirection=BRE_DIRECTION_NONE;
      return false;
     }

   static string     SeedDirectionLabel(const ENUM_BRE_TRADE_DIRECTION direction)
     {
      if(direction==BRE_DIRECTION_BUY)
         return "BUY";
      if(direction==BRE_DIRECTION_SELL)
         return "SELL";
      return "NONE";
     }

   static string     BuildStrategyJson(void)
     {
      string triggerValue=DoubleToString(SPRINT8C_VALIDATION_FLOATING_PROFIT_TRIGGER_USD,2);
      return "{"
             "\"schema_version\":2,"
             "\"strategy_id\":\""+SPRINT8C_VALIDATION_PROFILE_ID+"\","
             "\"metadata\":{\"strategy_name\":\"Sprint 8C Profit Close Validation "+SPRINT8C_VALIDATION_PROFILE_VERSION+"\"},"
             "\"execution_zone\":{\"source\":\"SIGNAL_RANGE\",\"expansion_mode\":\"SYMMETRIC\",\"above_entry_pips\":3,\"below_entry_pips\":3,\"expansion_disabled\":false},"
             "\"recovery_plan\":{\"algorithm\":\"CONSTANT\",\"constant_distance_pips\":0.2,\"constant_lot\":0.01,\"max_steps\":50,\"allow_during_profit_taking\":true,\"disable_after_break_even\":true,\"initial_position_count\":3,\"initial_lot_size\":0.01},"
             "\"risk_plan\":{\"target_risk_pct\":1.0,\"max_risk_pct\":1.2,\"risk_reduction_threshold_pct\":0.95,\"risk_reduction_mode\":\"WORST_ENTRY\",\"wait_details_timeout_minutes\":30,\"risk_eval_debounce_ms\":100},"
             "\"profit_distribution_plan\":{\"require_floating_profit_positive\":true,\"default_close_mode\":\"WORST_ENTRY_FIRST\",\"levels\":[{\"level_id\":\"M1\",\"level_index\":1,\"source\":\"FLOATING_PROFIT_MONEY\",\"trigger_type\":\"FLOATING_PROFIT_MONEY\",\"trigger_value\":"+triggerValue+",\"close_percent\":50,\"close_mode\":\"WORST_ENTRY_FIRST\",\"partial_close\":true,\"enabled\":true}]},"
             "\"break_even_plan\":{\"rules\":[{\"rule_id\":\"BE1\",\"enabled\":true,\"priority\":1,\"run_once\":true,\"trigger\":{\"type\":\"REALIZED_PROFIT\",\"realized_profit_usd\":10},\"actions\":[{\"type\":\"MOVE_SL_TO_AVERAGE\",\"buffer_pips\":0.5}]}]},"
             "\"execution_policy\":{\"slippage_points\":10,\"max_trade_retries\":3,\"magic_number_base\":202606000,\"command_batch_size\":10,\"trade_request_batch_size\":5,\"rest_poll_interval_ms\":3000}"
             "}";
     }

   static void       LogProfileMarkers(void)
     {
      Print("validation_profile_version=",SPRINT8C_VALIDATION_PROFILE_VERSION);
      Print("validation_profile_id=",SPRINT8C_VALIDATION_PROFILE_ID);
      Print("validation_profit_trigger_type=",FloatingProfitTriggerTypeLabel());
      Print("validation_profit_trigger_value_usd=",DoubleToString(FloatingProfitTriggerUsd(),2));
      Print("validation_require_floating_profit_positive=true");
     }
  };

#endif
