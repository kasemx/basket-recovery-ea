#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_MODE_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_CLOSE_MODE_MQH

enum ENUM_BRE_CLOSE_MODE
  {
   BRE_CLOSE_MODE_NONE=0,
   BRE_CLOSE_MODE_WORST_ENTRY_FIRST,
   BRE_CLOSE_MODE_BEST_ENTRY_FIRST,
   BRE_CLOSE_MODE_FIFO,
   BRE_CLOSE_MODE_LIFO,
   BRE_CLOSE_MODE_LARGEST_LOT_FIRST,
   BRE_CLOSE_MODE_SMALLEST_LOT_FIRST,
   BRE_CLOSE_MODE_PROFIT_BASED,
   BRE_CLOSE_MODE_RISK_BASED
  };

class CCloseModeHelper
  {
public:
   static string     ToString(const ENUM_BRE_CLOSE_MODE mode)
     {
      switch(mode)
        {
         case BRE_CLOSE_MODE_WORST_ENTRY_FIRST: return "WORST_ENTRY_FIRST";
         case BRE_CLOSE_MODE_BEST_ENTRY_FIRST: return "BEST_ENTRY_FIRST";
         case BRE_CLOSE_MODE_FIFO: return "FIFO";
         case BRE_CLOSE_MODE_LIFO: return "LIFO";
         case BRE_CLOSE_MODE_LARGEST_LOT_FIRST: return "LARGEST_LOT_FIRST";
         case BRE_CLOSE_MODE_SMALLEST_LOT_FIRST: return "SMALLEST_LOT_FIRST";
         case BRE_CLOSE_MODE_PROFIT_BASED: return "PROFIT_BASED";
         case BRE_CLOSE_MODE_RISK_BASED: return "RISK_BASED";
         default: return "NONE";
        }
     }

   static ENUM_BRE_CLOSE_MODE FromString(const string value)
     {
      if(value=="WORST_ENTRY_FIRST")
         return BRE_CLOSE_MODE_WORST_ENTRY_FIRST;
      if(value=="BEST_ENTRY_FIRST")
         return BRE_CLOSE_MODE_BEST_ENTRY_FIRST;
      if(value=="FIFO")
         return BRE_CLOSE_MODE_FIFO;
      if(value=="LIFO")
         return BRE_CLOSE_MODE_LIFO;
      if(value=="LARGEST_LOT_FIRST")
         return BRE_CLOSE_MODE_LARGEST_LOT_FIRST;
      if(value=="SMALLEST_LOT_FIRST")
         return BRE_CLOSE_MODE_SMALLEST_LOT_FIRST;
      if(value=="PROFIT_BASED")
         return BRE_CLOSE_MODE_PROFIT_BASED;
      if(value=="RISK_BASED")
         return BRE_CLOSE_MODE_RISK_BASED;
      return BRE_CLOSE_MODE_NONE;
     }
  };

#endif
