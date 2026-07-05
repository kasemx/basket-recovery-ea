#ifndef BRE_APP_FAST_TRACK_MANUAL_TEST_TYPES_MQH
#define BRE_APP_FAST_TRACK_MANUAL_TEST_TYPES_MQH

enum ENUM_BRE_FAST_TRACK_MANUAL_TEST_STAGE
  {
   BRE_FAST_TRACK_MANUAL_STAGE_NONE=0,
   BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS,
   BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND,
   BRE_FAST_TRACK_MANUAL_STAGE_IDEMPOTENT_SKIP,
   BRE_FAST_TRACK_MANUAL_STAGE_REJECTED
  };

enum ENUM_BRE_FAST_TRACK_ORDER_PLAN_RESULT
  {
   BRE_FAST_TRACK_ORDER_PLAN_NONE=0,
   BRE_FAST_TRACK_ORDER_PLAN_BLOCKED,
   BRE_FAST_TRACK_ORDER_PLAN_ALLOWED,
   BRE_FAST_TRACK_ORDER_PLAN_IDEMPOTENT_SKIP
  };

struct SFastTrackManualTestInputs
  {
   bool              enabled;
   string            seed_text;
   string            details_text;
   double            seed_lot;
   int               seed_order_count;
   bool              allow_demo_seed_execution;
   bool              enable_recovery;
   bool              enable_range_add;
   bool              enable_de_risk;
   bool              enable_break_even;
   bool              observer_only_startup_isolation;
   bool              global_execution_kill_switch;
   bool              enable_live_demo_execution;
   int               execution_mode;
  };

struct SFastTrackManualTestOutcome
  {
   ENUM_BRE_FAST_TRACK_MANUAL_TEST_STAGE stage;
   ENUM_BRE_FAST_TRACK_ORDER_PLAN_RESULT order_plan_result;
   string            basket_id;
   string            block_reason;
   string            detail;
   bool              seed_parse_valid;
   bool              details_parse_valid;
   bool              sl_apply_planned;
   bool              runner_enabled;

   void              Reset(void)
     {
      stage=BRE_FAST_TRACK_MANUAL_STAGE_NONE;
      order_plan_result=BRE_FAST_TRACK_ORDER_PLAN_NONE;
      basket_id="";
      block_reason="";
      detail="";
      seed_parse_valid=false;
      details_parse_valid=false;
      sl_apply_planned=false;
      runner_enabled=false;
     }
  };

class CFastTrackManualTestTypeText
  {
public:
   static string     StageToString(const ENUM_BRE_FAST_TRACK_MANUAL_TEST_STAGE stage)
     {
      switch(stage)
        {
         case BRE_FAST_TRACK_MANUAL_STAGE_WAIT_DETAILS: return "WAIT_DETAILS";
         case BRE_FAST_TRACK_MANUAL_STAGE_DETAILS_BOUND: return "DETAILS_BOUND";
         case BRE_FAST_TRACK_MANUAL_STAGE_IDEMPOTENT_SKIP: return "IDEMPOTENT_SKIP";
         case BRE_FAST_TRACK_MANUAL_STAGE_REJECTED: return "REJECTED";
         default: return "NONE";
        }
     }

   static string     OrderPlanToString(const ENUM_BRE_FAST_TRACK_ORDER_PLAN_RESULT result)
     {
      switch(result)
        {
         case BRE_FAST_TRACK_ORDER_PLAN_BLOCKED: return "BLOCKED";
         case BRE_FAST_TRACK_ORDER_PLAN_ALLOWED: return "ALLOWED";
         case BRE_FAST_TRACK_ORDER_PLAN_IDEMPOTENT_SKIP: return "IDEMPOTENT_SKIP";
         default: return "NONE";
        }
     }
  };

#endif
