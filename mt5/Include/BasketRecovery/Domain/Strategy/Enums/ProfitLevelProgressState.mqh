#ifndef BRE_DOMAIN_PROFIT_LEVEL_PROGRESS_STATE_MQH
#define BRE_DOMAIN_PROFIT_LEVEL_PROGRESS_STATE_MQH

enum ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE
  {
   BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED=0,
   BRE_PROFIT_LEVEL_PROGRESS_CANDIDATE_GENERATED,
   BRE_PROFIT_LEVEL_PROGRESS_MANUALLY_SUBMITTED,
   BRE_PROFIT_LEVEL_PROGRESS_COMPLETED
  };

class CProfitLevelProgressStateText
  {
public:
   static string     ToString(const ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE state)
     {
      switch(state)
        {
         case BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED: return "NOT_STARTED";
         case BRE_PROFIT_LEVEL_PROGRESS_CANDIDATE_GENERATED: return "CANDIDATE_GENERATED";
         case BRE_PROFIT_LEVEL_PROGRESS_MANUALLY_SUBMITTED: return "MANUALLY_SUBMITTED";
         case BRE_PROFIT_LEVEL_PROGRESS_COMPLETED: return "COMPLETED";
         default:
           {
            ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE unreachable=state;
            return "UNKNOWN";
           }
        }
     }

   static ENUM_BRE_PROFIT_LEVEL_PROGRESS_STATE FromBasketProgress(const bool closeCompleted,
                                                                  const bool closeRequested)
     {
      if(closeCompleted)
         return BRE_PROFIT_LEVEL_PROGRESS_COMPLETED;
      if(closeRequested)
         return BRE_PROFIT_LEVEL_PROGRESS_MANUALLY_SUBMITTED;
      return BRE_PROFIT_LEVEL_PROGRESS_NOT_STARTED;
     }
  };

#endif
