#ifndef BRE_DOMAIN_SUBMISSION_PREPARATION_FAILURE_REASON_MQH
#define BRE_DOMAIN_SUBMISSION_PREPARATION_FAILURE_REASON_MQH

enum ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON
  {
   BRE_PREP_FAIL_NONE=0,
   BRE_PREP_FAIL_REQUEST_NOT_SEALED=1,
   BRE_PREP_FAIL_BASKET_NOT_ACTIVE=2,
   BRE_PREP_FAIL_STALE_BASKET_VERSION=3,
   BRE_PREP_FAIL_PROFILE_HASH_MISMATCH=4,
   BRE_PREP_FAIL_MARKET_UNAVAILABLE=5,
   BRE_PREP_FAIL_STALE_QUOTE=6,
   BRE_PREP_FAIL_MAX_SPREAD=7,
   BRE_PREP_FAIL_INVALID_VOLUME=8,
   BRE_PREP_FAIL_INVALID_STOPS=9,
   BRE_PREP_FAIL_INVALID_FREEZE=10,
   BRE_PREP_FAIL_VALIDATION=11,
   BRE_PREP_FAIL_COMMENT_COLLISION=12,
   BRE_PREP_FAIL_CORRELATION_COLLISION=13,
   BRE_PREP_FAIL_ENVELOPE_EXPIRED=14,
   BRE_PREP_FAIL_TICKET_NOT_IN_BASKET=15,
   BRE_PREP_FAIL_ACCOUNT_TRADE_DISABLED=16
  };

inline string SubmissionPreparationFailureReasonLabel(const ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON reason)
  {
   switch(reason)
     {
      case BRE_PREP_FAIL_REQUEST_NOT_SEALED: return "request_not_sealed";
      case BRE_PREP_FAIL_BASKET_NOT_ACTIVE: return "basket_not_active";
      case BRE_PREP_FAIL_STALE_BASKET_VERSION: return "stale_basket_version";
      case BRE_PREP_FAIL_PROFILE_HASH_MISMATCH: return "profile_hash_mismatch";
      case BRE_PREP_FAIL_MARKET_UNAVAILABLE: return "market_unavailable";
      case BRE_PREP_FAIL_STALE_QUOTE: return "stale_quote";
      case BRE_PREP_FAIL_MAX_SPREAD: return "max_spread";
      case BRE_PREP_FAIL_INVALID_VOLUME: return "invalid_volume";
      case BRE_PREP_FAIL_INVALID_STOPS: return "invalid_stops";
      case BRE_PREP_FAIL_INVALID_FREEZE: return "invalid_freeze";
      case BRE_PREP_FAIL_VALIDATION: return "validation";
      case BRE_PREP_FAIL_COMMENT_COLLISION: return "comment_collision";
      case BRE_PREP_FAIL_CORRELATION_COLLISION: return "correlation_collision";
      case BRE_PREP_FAIL_ENVELOPE_EXPIRED: return "envelope_expired";
      case BRE_PREP_FAIL_TICKET_NOT_IN_BASKET: return "ticket_not_in_basket";
      case BRE_PREP_FAIL_ACCOUNT_TRADE_DISABLED: return "account_trade_disabled";
      default: return "none";
     }
  }

#endif
