#ifndef BRE_DOMAIN_ACCOUNT_POSITION_MODEL_MQH
#define BRE_DOMAIN_ACCOUNT_POSITION_MODEL_MQH

enum ENUM_BRE_ACCOUNT_POSITION_MODEL
  {
   BRE_ACCOUNT_POSITION_MODEL_UNKNOWN=0,
   BRE_ACCOUNT_POSITION_MODEL_NETTING,
   BRE_ACCOUNT_POSITION_MODEL_HEDGING,
   BRE_ACCOUNT_POSITION_MODEL_EXCHANGE
  };

class CAccountPositionModelHelper
  {
public:
   static string     ToString(const ENUM_BRE_ACCOUNT_POSITION_MODEL model)
     {
      switch(model)
        {
         case BRE_ACCOUNT_POSITION_MODEL_NETTING: return "NETTING";
         case BRE_ACCOUNT_POSITION_MODEL_HEDGING: return "HEDGING";
         case BRE_ACCOUNT_POSITION_MODEL_EXCHANGE: return "EXCHANGE";
         default:
           {
            ENUM_BRE_ACCOUNT_POSITION_MODEL unreachable=model;
            return "UNKNOWN";
           }
        }
     }

   static bool       SupportsExplicitTicketPartialClose(const ENUM_BRE_ACCOUNT_POSITION_MODEL model)
     {
      return model==BRE_ACCOUNT_POSITION_MODEL_HEDGING;
     }
  };

#endif
