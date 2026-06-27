#ifndef BASKET_RECOVERY_DOMAIN_BASKET_LIFECYCLE_STATE_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_LIFECYCLE_STATE_MQH

enum ENUM_BRE_BASKET_LIFECYCLE_STATE
  {
   BRE_STATE_NONE=0,
   BRE_STATE_PENDING_OPEN,
   BRE_STATE_WAIT_DETAILS,
   BRE_STATE_ACTIVE,
   BRE_STATE_TP1,
   BRE_STATE_BREAK_EVEN,
   BRE_STATE_TP2,
   BRE_STATE_TP3,
   BRE_STATE_CLOSING,
   BRE_STATE_SUSPENDED,
   BRE_STATE_FINISHED,
   BRE_STATE_ERROR
  };

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
         case BRE_STATE_TP1: return "TP1";
         case BRE_STATE_BREAK_EVEN: return "BREAK_EVEN";
         case BRE_STATE_TP2: return "TP2";
         case BRE_STATE_TP3: return "TP3";
         case BRE_STATE_CLOSING: return "CLOSING";
         case BRE_STATE_SUSPENDED: return "SUSPENDED";
         case BRE_STATE_FINISHED: return "FINISHED";
         case BRE_STATE_ERROR: return "ERROR";
         default: return "NONE";
        }
     }
  };

#endif
