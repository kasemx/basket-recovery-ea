#ifndef BASKET_RECOVERY_DOMAIN_TRADE_ROLE_MQH
#define BASKET_RECOVERY_DOMAIN_TRADE_ROLE_MQH

enum ENUM_BRE_TRADE_ROLE
  {
   BRE_TRADE_ROLE_NONE=0,
   BRE_TRADE_ROLE_INITIAL,
   BRE_TRADE_ROLE_RECOVERY,
   BRE_TRADE_ROLE_HEDGE,
   BRE_TRADE_ROLE_CLOSEOUT
  };

class CTradeRoleHelper
  {
public:
   static string     ToString(const ENUM_BRE_TRADE_ROLE role)
     {
      switch(role)
        {
         case BRE_TRADE_ROLE_INITIAL: return "INITIAL";
         case BRE_TRADE_ROLE_RECOVERY: return "RECOVERY";
         case BRE_TRADE_ROLE_HEDGE: return "HEDGE";
         case BRE_TRADE_ROLE_CLOSEOUT: return "CLOSEOUT";
         default: return "NONE";
        }
     }
  };

#endif
