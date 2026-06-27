#ifndef BASKET_RECOVERY_DOMAIN_TRADE_DIRECTION_MQH
#define BASKET_RECOVERY_DOMAIN_TRADE_DIRECTION_MQH

enum ENUM_BRE_TRADE_DIRECTION
  {
   BRE_DIRECTION_NONE=0,
   BRE_DIRECTION_BUY,
   BRE_DIRECTION_SELL
  };

class CTradeDirectionHelper
  {
public:
   static string     ToString(const ENUM_BRE_TRADE_DIRECTION direction)
     {
      switch(direction)
        {
         case BRE_DIRECTION_BUY: return "BUY";
         case BRE_DIRECTION_SELL: return "SELL";
         default: return "NONE";
        }
     }
  };

#endif
