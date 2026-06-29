#ifndef BRE_DOMAIN_BREAK_EVEN_PROGRESS_STATE_MQH
#define BRE_DOMAIN_BREAK_EVEN_PROGRESS_STATE_MQH

enum ENUM_BRE_BREAK_EVEN_PROGRESS_STATE
  {
   BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED=0,
   BRE_BREAK_EVEN_PROGRESS_CANDIDATE_GENERATED,
   BRE_BREAK_EVEN_PROGRESS_ACTIVATED
  };

class CBreakEvenProgressStateText
  {
public:
   static string     ToString(const ENUM_BRE_BREAK_EVEN_PROGRESS_STATE state)
     {
      switch(state)
        {
         case BRE_BREAK_EVEN_PROGRESS_NOT_ACTIVATED: return "NOT_ACTIVATED";
         case BRE_BREAK_EVEN_PROGRESS_CANDIDATE_GENERATED: return "CANDIDATE_GENERATED";
         case BRE_BREAK_EVEN_PROGRESS_ACTIVATED: return "ACTIVATED";
         default:
           {
            ENUM_BRE_BREAK_EVEN_PROGRESS_STATE unreachable=state;
            return "UNKNOWN";
           }
        }
     }
  };

#endif
