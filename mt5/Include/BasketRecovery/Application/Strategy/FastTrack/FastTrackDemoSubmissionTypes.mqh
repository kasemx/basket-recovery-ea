#ifndef BRE_APP_FAST_TRACK_DEMO_SUBMISSION_TYPES_MQH
#define BRE_APP_FAST_TRACK_DEMO_SUBMISSION_TYPES_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

enum ENUM_BRE_FT_DEMO_SUB_STATUS
  {
   BRE_FT_DEMO_SUB_NONE=0,
   BRE_FT_DEMO_SUB_PLAN_ALLOWED,
   BRE_FT_DEMO_SUB_CANDIDATE_CREATED,
   BRE_FT_DEMO_SUB_AWAIT_AUTH,
   BRE_FT_DEMO_SUB_AUTH_REJECTED,
   BRE_FT_DEMO_SUB_RISK_BLOCKED,
   BRE_FT_DEMO_SUB_SLTP_INVALID,
   BRE_FT_DEMO_SUB_DUP_BLOCKED,
   BRE_FT_DEMO_SUB_MAGIC_REQUIRED,
   BRE_FT_DEMO_SUB_READY,
   BRE_FT_DEMO_SUB_REJECTED
  };

enum ENUM_BRE_FT_DEMO_SUB_SOURCE
  {
   BRE_FT_DEMO_SUB_SRC_NONE=0,
   BRE_FT_DEMO_SUB_SRC_FILE_COMMON
  };

struct SFastTrackDemoSubmissionEnvironment
  {
   bool              account_is_demo;
   bool              require_manual_demo_authorization;
   bool              audit_file_polling_enabled;
   double            account_equity_usd;
   double            symbol_bid;
   double            symbol_ask;
   double            symbol_point;
   double            symbol_tick_size;
   double            symbol_tick_value;
   int               symbol_stops_level;
   int               symbol_freeze_level;
   double            symbol_min_lot;
   double            symbol_volume_step;
   int               open_positions_for_symbol;
   int               pending_orders_for_symbol;

   void              Reset(void)
     {
      account_is_demo=false;
      require_manual_demo_authorization=true;
      audit_file_polling_enabled=false;
      account_equity_usd=0.0;
      symbol_bid=0.0;
      symbol_ask=0.0;
      symbol_point=0.0;
      symbol_tick_size=0.0;
      symbol_tick_value=0.0;
      symbol_stops_level=0;
      symbol_freeze_level=0;
      symbol_min_lot=0.01;
      symbol_volume_step=0.01;
      open_positions_for_symbol=0;
      pending_orders_for_symbol=0;
     }
  };

struct SFastTrackDemoSubmissionBridgeInputs
  {
   bool              enabled;
   bool              require_manual_demo_authorization;
   bool              audit_file_polling_enabled;
   bool              allow_demo_seed_execution;
   bool              enable_recovery;
   bool              enable_range_add;
   bool              enable_de_risk;
   bool              enable_break_even;
   bool              enable_re_entry;
   bool              enable_partial_close;
   bool              enable_trailing;
   bool              observer_only_startup_isolation;
   bool              global_execution_kill_switch;
   bool              enable_live_demo_execution;
   int               execution_mode;
   double            seed_lot;
   int               seed_order_count;
   long              magic_number_override;
   string            manual_demo_authorization_basket_id;
   string            route_label;
   string            target_label;
   SFastTrackDemoSubmissionEnvironment environment;

   void              Reset(void)
     {
      enabled=false;
      require_manual_demo_authorization=true;
      audit_file_polling_enabled=false;
      allow_demo_seed_execution=false;
      enable_recovery=false;
      enable_range_add=false;
      enable_de_risk=false;
      enable_break_even=false;
      enable_re_entry=false;
      enable_partial_close=false;
      enable_trailing=false;
      observer_only_startup_isolation=false;
      global_execution_kill_switch=false;
      enable_live_demo_execution=false;
      execution_mode=0;
      seed_lot=0.01;
      seed_order_count=1;
      magic_number_override=0;
      manual_demo_authorization_basket_id="";
      route_label="";
      target_label="";
      environment.Reset();
     }
  };

struct SFastTrackDemoSubmissionCandidate
  {
   string            basket_id;
   string            execution_request_id;
   string            idempotency_key;
   string            symbol;
   ENUM_BRE_TRADE_DIRECTION direction;
   double            volume;
   string            entry_mode;
   double            stop_loss;
   double            broker_take_profit;
   int               additional_tp_count;
   ENUM_BRE_FT_DEMO_SUB_SOURCE source;
   string            route_label;
   string            target_label;
   datetime          requested_at_utc;
   long              magic_number;
   double            risk_estimate_usd;
   ENUM_BRE_FT_DEMO_SUB_STATUS status;
   string            broker_tp_note;
   string            safe_error_code;
   string            safe_error_message;

   void              Reset(void)
     {
      basket_id="";
      execution_request_id="";
      idempotency_key="";
      symbol="";
      direction=BRE_DIRECTION_NONE;
      volume=0.0;
      entry_mode="MARKET";
      stop_loss=0.0;
      broker_take_profit=0.0;
      additional_tp_count=0;
      source=BRE_FT_DEMO_SUB_SRC_NONE;
      route_label="";
      target_label="";
      requested_at_utc=0;
      magic_number=0;
      risk_estimate_usd=0.0;
      status=BRE_FT_DEMO_SUB_NONE;
      broker_tp_note="";
      safe_error_code="";
      safe_error_message="";
     }
  };

struct SFastTrackDemoSubmissionBridgeOutcome
  {
   ENUM_BRE_FT_DEMO_SUB_STATUS status;
   string            block_reason;
   string            detail;
   bool              candidate_created;
   SFastTrackDemoSubmissionCandidate candidate;

   void              Reset(void)
     {
      status=BRE_FT_DEMO_SUB_NONE;
      block_reason="";
      detail="";
      candidate_created=false;
      candidate.Reset();
     }
  };

class CFastTrackDemoSubmissionTypeText
  {
public:
   static string     StatusToAuditCode(const ENUM_BRE_FT_DEMO_SUB_STATUS status)
     {
      switch(status)
        {
         case BRE_FT_DEMO_SUB_PLAN_ALLOWED: return "FASTTRACK_PLAN_ALLOWED";
         case BRE_FT_DEMO_SUB_CANDIDATE_CREATED: return "FASTTRACK_CANDIDATE_CREATED";
         case BRE_FT_DEMO_SUB_AWAIT_AUTH: return "FASTTRACK_AWAITING_AUTHORIZATION";
         case BRE_FT_DEMO_SUB_AUTH_REJECTED: return "FASTTRACK_AUTHORIZATION_REJECTED";
         case BRE_FT_DEMO_SUB_RISK_BLOCKED: return "FASTTRACK_RISK_BLOCKED";
         case BRE_FT_DEMO_SUB_SLTP_INVALID: return "FASTTRACK_SLTP_INVALID";
         case BRE_FT_DEMO_SUB_DUP_BLOCKED: return "FASTTRACK_DUPLICATE_BLOCKED";
         case BRE_FT_DEMO_SUB_MAGIC_REQUIRED: return "MAGIC_CONFIGURATION_REQUIRED";
         case BRE_FT_DEMO_SUB_READY: return "FASTTRACK_READY_FOR_SINGLE_DEMO_SUBMISSION";
         case BRE_FT_DEMO_SUB_REJECTED: return "FASTTRACK_REJECTED";
         default: return "FASTTRACK_NONE";
        }
     }

   static string     SourceToString(const ENUM_BRE_FT_DEMO_SUB_SOURCE source)
     {
      switch(source)
        {
         case BRE_FT_DEMO_SUB_SRC_FILE_COMMON: return "FASTTRACK_FILE_COMMON";
         default: return "NONE";
        }
     }
  };

#endif
