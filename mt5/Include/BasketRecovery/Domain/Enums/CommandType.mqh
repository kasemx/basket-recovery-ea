#ifndef BASKET_RECOVERY_DOMAIN_COMMAND_TYPE_MQH
#define BASKET_RECOVERY_DOMAIN_COMMAND_TYPE_MQH

enum ENUM_BRE_COMMAND_TYPE
  {
   BRE_COMMAND_NONE=0,
   BRE_COMMAND_CREATE_BASKET,
   BRE_COMMAND_ACTIVATE_BASKET,
   BRE_COMMAND_UPDATE_SL,
   BRE_COMMAND_UPDATE_TP,
   BRE_COMMAND_CLOSE_BASKET,
   BRE_COMMAND_OPEN_RECOVERY,
   BRE_COMMAND_REDUCE_RISK,
   BRE_COMMAND_TP_PARTIAL_CLOSE,
   BRE_COMMAND_ACTIVATE_BREAK_EVEN,
   BRE_COMMAND_CLOSE_ALL
  };

enum ENUM_BRE_COMMAND_STATUS
  {
   BRE_COMMAND_STATUS_PENDING=0,
   BRE_COMMAND_STATUS_PROCESSING,
   BRE_COMMAND_STATUS_COMPLETED,
   BRE_COMMAND_STATUS_FAILED,
   BRE_COMMAND_STATUS_DEAD_LETTER
  };

class CCommandTypeHelper
  {
public:
   static string     ToString(const ENUM_BRE_COMMAND_TYPE type)
     {
      switch(type)
        {
         case BRE_COMMAND_CREATE_BASKET: return "CreateBasketCommand";
         case BRE_COMMAND_ACTIVATE_BASKET: return "ActivateBasketCommand";
         case BRE_COMMAND_UPDATE_SL: return "UpdateSLCommand";
         case BRE_COMMAND_UPDATE_TP: return "UpdateTPCommand";
         case BRE_COMMAND_CLOSE_BASKET: return "CloseBasketCommand";
         case BRE_COMMAND_OPEN_RECOVERY: return "OpenRecoveryPositionCommand";
         case BRE_COMMAND_REDUCE_RISK: return "ReduceRiskCloseCommand";
         case BRE_COMMAND_TP_PARTIAL_CLOSE: return "ExecuteTPPartialCloseCommand";
         case BRE_COMMAND_ACTIVATE_BREAK_EVEN: return "ActivateBreakEvenCommand";
         case BRE_COMMAND_CLOSE_ALL: return "CloseAllPositionsCommand";
         default: return "None";
        }
     }
  };

#endif
