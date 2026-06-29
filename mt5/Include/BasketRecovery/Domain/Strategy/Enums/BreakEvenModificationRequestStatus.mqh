#ifndef BRE_DOMAIN_BREAK_EVEN_MODIFICATION_REQUEST_STATUS_MQH
#define BRE_DOMAIN_BREAK_EVEN_MODIFICATION_REQUEST_STATUS_MQH

enum ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS
  {
   BRE_BREAK_EVEN_MOD_REQ_NONE=0,
   BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY,
   BRE_BREAK_EVEN_MOD_REQ_BLOCKED,
   BRE_BREAK_EVEN_MOD_REQ_NO_CHANGE_REQUIRED,
   BRE_BREAK_EVEN_MOD_REQ_INVALID
  };

class CBreakEvenModificationRequestStatusText
  {
public:
   static string     ToString(const ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS status)
     {
      switch(status)
        {
         case BRE_BREAK_EVEN_MOD_REQ_NONE: return "NONE";
         case BRE_BREAK_EVEN_MOD_REQ_DRY_RUN_READY: return "DRY_RUN_READY";
         case BRE_BREAK_EVEN_MOD_REQ_BLOCKED: return "BLOCKED";
         case BRE_BREAK_EVEN_MOD_REQ_NO_CHANGE_REQUIRED: return "NO_CHANGE_REQUIRED";
         case BRE_BREAK_EVEN_MOD_REQ_INVALID: return "INVALID";
         default:
           {
            ENUM_BRE_BREAK_EVEN_MODIFICATION_REQUEST_STATUS unreachable=status;
            return "UNKNOWN";
           }
        }
     }
  };

#endif
