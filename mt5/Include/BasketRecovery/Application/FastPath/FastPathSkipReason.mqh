#ifndef BRE_APP_FAST_PATH_SKIP_REASON_MQH
#define BRE_APP_FAST_PATH_SKIP_REASON_MQH

enum ENUM_BRE_FAST_PATH_SKIP_REASON
  {
   BRE_FAST_SKIP_NONE=0,
   BRE_FAST_SKIP_NO_MATCHING_BASKET=1,
   BRE_FAST_SKIP_DUPLICATE_QUOTE_SEQUENCE=2,
   BRE_FAST_SKIP_MIN_INTERVAL_GATE=3,
   BRE_FAST_SKIP_STALE_QUOTE=4,
   BRE_FAST_SKIP_BUDGET_EXHAUSTED=5,
   BRE_FAST_SKIP_TRIGGER_POLICY=6
  };

inline string FastPathSkipReasonLabel(const ENUM_BRE_FAST_PATH_SKIP_REASON reason)
  {
   switch(reason)
     {
      case BRE_FAST_SKIP_NONE: return "none";
      case BRE_FAST_SKIP_NO_MATCHING_BASKET: return "no_matching_basket";
      case BRE_FAST_SKIP_DUPLICATE_QUOTE_SEQUENCE: return "duplicate_quote_sequence";
      case BRE_FAST_SKIP_MIN_INTERVAL_GATE: return "min_interval_gate";
      case BRE_FAST_SKIP_STALE_QUOTE: return "stale_quote";
      case BRE_FAST_SKIP_BUDGET_EXHAUSTED: return "budget_exhausted";
      case BRE_FAST_SKIP_TRIGGER_POLICY: return "trigger_policy";
      default:
        {
         ENUM_BRE_FAST_PATH_SKIP_REASON unexpected=reason;
         return "unknown";
        }
     }
  }

#endif
