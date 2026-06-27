#ifndef BASKET_RECOVERY_DOMAIN_EVENT_TYPE_MQH
#define BASKET_RECOVERY_DOMAIN_EVENT_TYPE_MQH

enum ENUM_BRE_EVENT_TYPE
  {
   BRE_EVENT_NONE=0,
   BRE_EVENT_BASKET_CREATED,
   BRE_EVENT_BASKET_ACTIVATED,
   BRE_EVENT_BASKET_FINISHED,
   BRE_EVENT_BASKET_CLOSING,
   BRE_EVENT_INITIAL_POSITIONS_OPENED,
   BRE_EVENT_WAIT_DETAILS_TIMEOUT,
   BRE_EVENT_CLOSE_BASKET_REQUESTED,
   BRE_EVENT_RECOVERY_POSITION_OPENED,
   BRE_EVENT_RECOVERY_STEP_CROSSED,
   BRE_EVENT_POSITION_CLOSED,
   BRE_EVENT_ALL_POSITIONS_CLOSED,
   BRE_EVENT_POSITION_SNAPSHOT_UPDATED,
   BRE_EVENT_TARGET_RISK_REACHED,
   BRE_EVENT_MAX_RISK_REACHED,
   BRE_EVENT_RISK_REDUCED,
   BRE_EVENT_STRATEGY_PROFILE_BOUND,
   BRE_EVENT_PROFIT_LEVEL_REACHED,
   BRE_EVENT_PROFIT_LEVEL_CLOSE_REQUESTED,
   BRE_EVENT_PROFIT_LEVEL_CLOSE_COMPLETED,
   BRE_EVENT_BREAK_EVEN_ACTIVATED,
   BRE_EVENT_RECOVERY_DISABLED,
   BRE_EVENT_RISK_REDUCTION_REQUESTED,
   BRE_EVENT_BASKET_LOCKED,
   BRE_EVENT_TP1_REACHED,
   BRE_EVENT_TP2_REACHED,
   BRE_EVENT_TP3_REACHED,
   BRE_EVENT_STATE_TRANSITIONED,
   BRE_EVENT_TRANSITION_REJECTED,
   BRE_EVENT_COMMAND_PROCESSED,
   BRE_EVENT_COMMAND_FAILED
  };

class CEventTypeHelper
  {
public:
   static string     ToString(const ENUM_BRE_EVENT_TYPE type)
     {
      switch(type)
        {
         case BRE_EVENT_BASKET_CREATED: return "BasketCreated";
         case BRE_EVENT_BASKET_ACTIVATED: return "BasketActivated";
         case BRE_EVENT_BASKET_FINISHED: return "BasketFinished";
         case BRE_EVENT_BASKET_CLOSING: return "BasketClosing";
         case BRE_EVENT_INITIAL_POSITIONS_OPENED: return "InitialPositionsOpened";
         case BRE_EVENT_WAIT_DETAILS_TIMEOUT: return "WaitDetailsTimeout";
         case BRE_EVENT_CLOSE_BASKET_REQUESTED: return "CloseBasketRequested";
         case BRE_EVENT_RECOVERY_POSITION_OPENED: return "RecoveryPositionOpened";
         case BRE_EVENT_RECOVERY_STEP_CROSSED: return "RecoveryStepCrossed";
         case BRE_EVENT_POSITION_CLOSED: return "PositionClosed";
         case BRE_EVENT_ALL_POSITIONS_CLOSED: return "AllPositionsClosed";
         case BRE_EVENT_POSITION_SNAPSHOT_UPDATED: return "PositionSnapshotUpdated";
         case BRE_EVENT_TARGET_RISK_REACHED: return "TargetRiskReached";
         case BRE_EVENT_MAX_RISK_REACHED: return "MaxRiskReached";
         case BRE_EVENT_RISK_REDUCED: return "RiskReduced";
         case BRE_EVENT_STRATEGY_PROFILE_BOUND: return "StrategyProfileBound";
         case BRE_EVENT_PROFIT_LEVEL_REACHED: return "ProfitLevelReached";
         case BRE_EVENT_PROFIT_LEVEL_CLOSE_REQUESTED: return "ProfitLevelCloseRequested";
         case BRE_EVENT_PROFIT_LEVEL_CLOSE_COMPLETED: return "ProfitLevelCloseCompleted";
         case BRE_EVENT_BREAK_EVEN_ACTIVATED: return "BreakEvenActivated";
         case BRE_EVENT_RECOVERY_DISABLED: return "RecoveryDisabled";
         case BRE_EVENT_RISK_REDUCTION_REQUESTED: return "RiskReductionRequested";
         case BRE_EVENT_BASKET_LOCKED: return "BasketLocked";
         case BRE_EVENT_TP1_REACHED: return "TP1Reached";
         case BRE_EVENT_TP2_REACHED: return "TP2Reached";
         case BRE_EVENT_TP3_REACHED: return "TP3Reached";
         case BRE_EVENT_STATE_TRANSITIONED: return "StateTransitioned";
         case BRE_EVENT_TRANSITION_REJECTED: return "TransitionRejected";
         case BRE_EVENT_COMMAND_PROCESSED: return "CommandProcessed";
         case BRE_EVENT_COMMAND_FAILED: return "CommandFailed";
         default: return "None";
        }
     }

   static ENUM_BRE_EVENT_TYPE NormalizeDeprecatedProfitEvent(const ENUM_BRE_EVENT_TYPE type)
     {
      switch(type)
        {
         case BRE_EVENT_TP1_REACHED:
         case BRE_EVENT_TP2_REACHED:
         case BRE_EVENT_TP3_REACHED:
            return BRE_EVENT_PROFIT_LEVEL_REACHED;
         default:
            return type;
        }
     }
  };

#endif
