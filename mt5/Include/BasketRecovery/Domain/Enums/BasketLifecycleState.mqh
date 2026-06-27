#ifndef BASKET_RECOVERY_DOMAIN_BASKET_LIFECYCLE_STATE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_LIFECYCLE_STATE_MQH

enum ENUM_BRE_BASKET_LIFECYCLE_STATE
  {
   BRE_STATE_NONE=0,
   BRE_STATE_PENDING_OPEN,
   BRE_STATE_WAIT_DETAILS,
   BRE_STATE_ACTIVE,
   BRE_STATE_SUSPENDED,
   BRE_STATE_CLOSING,
   BRE_STATE_FINISHED,
   BRE_STATE_ERROR
  };

#define BRE_LEGACY_STATE_TP1           4
#define BRE_LEGACY_STATE_BREAK_EVEN    5
#define BRE_LEGACY_STATE_TP2           6
#define BRE_LEGACY_STATE_TP3           7
#define BRE_LEGACY_STATE_CLOSING_V1    8
#define BRE_LEGACY_STATE_SUSPENDED_V1  9
#define BRE_LEGACY_STATE_FINISHED_V1   10
#define BRE_LEGACY_STATE_ERROR_V1      11

class CBasketLifecycleStateHelper
  {
public:
   static string     ToString(const ENUM_BRE_BASKET_LIFECYCLE_STATE state)
     {
      switch(state)
        {
         case BRE_STATE_PENDING_OPEN: return "PENDING_OPEN";
         case BRE_STATE_WAIT_DETAILS: return "WAIT_DETAILS";
         case BRE_STATE_ACTIVE: return "ACTIVE";
         case BRE_STATE_SUSPENDED: return "SUSPENDED";
         case BRE_STATE_CLOSING: return "CLOSING";
         case BRE_STATE_FINISHED: return "FINISHED";
         case BRE_STATE_ERROR: return "ERROR";
         default: return "NONE";
        }
     }

   static ENUM_BRE_BASKET_LIFECYCLE_STATE FromLegacyInt(const int rawState)
     {
      switch(rawState)
        {
         case BRE_STATE_NONE:
         case BRE_STATE_PENDING_OPEN:
         case BRE_STATE_WAIT_DETAILS:
         case BRE_STATE_ACTIVE:
         case BRE_STATE_SUSPENDED:
         case BRE_STATE_CLOSING:
         case BRE_STATE_FINISHED:
         case BRE_STATE_ERROR:
            return (ENUM_BRE_BASKET_LIFECYCLE_STATE)rawState;
         case BRE_LEGACY_STATE_TP1:
         case BRE_LEGACY_STATE_BREAK_EVEN:
         case BRE_LEGACY_STATE_TP2:
         case BRE_LEGACY_STATE_TP3:
            return BRE_STATE_ACTIVE;
         case BRE_LEGACY_STATE_CLOSING_V1:
            return BRE_STATE_CLOSING;
         case BRE_LEGACY_STATE_SUSPENDED_V1:
            return BRE_STATE_SUSPENDED;
         case BRE_LEGACY_STATE_FINISHED_V1:
            return BRE_STATE_FINISHED;
         case BRE_LEGACY_STATE_ERROR_V1:
            return BRE_STATE_ERROR;
         default:
            return BRE_STATE_NONE;
        }
     }

   static bool       WasLegacyProfitState(const int rawState)
     {
      return rawState==BRE_LEGACY_STATE_TP1 ||
             rawState==BRE_LEGACY_STATE_BREAK_EVEN ||
             rawState==BRE_LEGACY_STATE_TP2 ||
             rawState==BRE_LEGACY_STATE_TP3;
     }
  };

#endif
