#ifndef BRE_DOMAIN_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT_MQH
#define BRE_DOMAIN_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT_MQH

enum ENUM_BRE_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT
  {
   BRE_BREAK_EVEN_MOD_INTENT_DRY_RUN_ONLY=0
  };

enum ENUM_BRE_BREAK_EVEN_MODIFICATION_APPLY_POLICY
  {
   BRE_BREAK_EVEN_MOD_POLICY_ALL_OR_NOTHING=0
  };

class CBreakEvenModificationExecutionIntentText
  {
public:
   static string     ToString(const ENUM_BRE_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT intent)
     {
      switch(intent)
        {
         case BRE_BREAK_EVEN_MOD_INTENT_DRY_RUN_ONLY: return "DRY_RUN_ONLY";
         default:
           {
            ENUM_BRE_BREAK_EVEN_MODIFICATION_EXECUTION_INTENT unreachable=intent;
            return "UNKNOWN";
           }
        }
     }

   static string     PolicyToString(const ENUM_BRE_BREAK_EVEN_MODIFICATION_APPLY_POLICY policy)
     {
      switch(policy)
        {
         case BRE_BREAK_EVEN_MOD_POLICY_ALL_OR_NOTHING: return "ALL_OR_NOTHING";
         default:
           {
            ENUM_BRE_BREAK_EVEN_MODIFICATION_APPLY_POLICY unreachable=policy;
            return "UNKNOWN";
           }
        }
     }
  };

#endif
