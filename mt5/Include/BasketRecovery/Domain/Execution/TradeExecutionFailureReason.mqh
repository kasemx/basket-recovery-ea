#ifndef BRE_DOMAIN_TRADE_EXECUTION_FAILURE_REASON_MQH
#define BRE_DOMAIN_TRADE_EXECUTION_FAILURE_REASON_MQH

enum ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON
  {
   BRE_EXEC_FAIL_NONE=0,
   BRE_EXEC_FAIL_VALIDATION=1,
   BRE_EXEC_FAIL_STALE_BASKET_VERSION=2,
   BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH=3,
   BRE_EXEC_FAIL_DUPLICATE_IDEMPOTENCY=4,
   BRE_EXEC_FAIL_TERMINAL_STATE=5,
   BRE_EXEC_FAIL_BROKER_REJECTED=6,
   BRE_EXEC_FAIL_TIMEOUT=7,
   BRE_EXEC_FAIL_UNKNOWN_BROKER=8,
   BRE_EXEC_FAIL_LIVE_QUOTE_STALE=9,
   BRE_EXEC_FAIL_MAX_SPREAD=10,
   BRE_EXEC_FAIL_MARKET_UNAVAILABLE=11,
   BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED=12,
   BRE_EXEC_FAIL_BASKET_NOT_ACTIVE=13,
   BRE_EXEC_FAIL_BASKET_LOCKED=14,
   BRE_EXEC_FAIL_RECOVERY_DISABLED=15,
   BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET=16,
   BRE_EXEC_FAIL_VOLUME_CONSTRAINT=17
  };

inline string TradeExecutionFailureReasonLabel(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason)
  {
   switch(reason)
     {
      case BRE_EXEC_FAIL_VALIDATION: return "validation";
      case BRE_EXEC_FAIL_STALE_BASKET_VERSION: return "stale_basket_version";
      case BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH: return "profile_hash_mismatch";
      case BRE_EXEC_FAIL_DUPLICATE_IDEMPOTENCY: return "duplicate_idempotency";
      case BRE_EXEC_FAIL_TERMINAL_STATE: return "terminal_state";
      case BRE_EXEC_FAIL_BROKER_REJECTED: return "broker_rejected";
      case BRE_EXEC_FAIL_TIMEOUT: return "timeout";
      case BRE_EXEC_FAIL_UNKNOWN_BROKER: return "unknown_broker";
      case BRE_EXEC_FAIL_LIVE_QUOTE_STALE: return "live_quote_stale";
      case BRE_EXEC_FAIL_MAX_SPREAD: return "max_spread";
      case BRE_EXEC_FAIL_MARKET_UNAVAILABLE: return "market_unavailable";
      case BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED: return "account_trade_disabled";
      case BRE_EXEC_FAIL_BASKET_NOT_ACTIVE: return "basket_not_active";
      case BRE_EXEC_FAIL_BASKET_LOCKED: return "basket_locked";
      case BRE_EXEC_FAIL_RECOVERY_DISABLED: return "recovery_disabled";
      case BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET: return "ticket_not_in_basket";
      case BRE_EXEC_FAIL_VOLUME_CONSTRAINT: return "volume_constraint";
      default: return "none";
     }
  }

#endif
