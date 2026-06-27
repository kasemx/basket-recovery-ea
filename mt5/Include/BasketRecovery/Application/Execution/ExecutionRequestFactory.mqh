#ifndef BRE_APP_EXECUTION_REQUEST_FACTORY_MQH
#define BRE_APP_EXECUTION_REQUEST_FACTORY_MQH

#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/CommandType.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CExecutionRequestFactory
  {
private:
   static ENUM_BRE_TRADE_EXECUTION_INTENT ResolveIntent(const ENUM_BRE_COMMAND_TYPE commandType)
     {
      switch(commandType)
        {
         case BRE_COMMAND_OPEN_RECOVERY_POSITION: return BRE_EXEC_INTENT_OPEN_POSITION;
         case BRE_COMMAND_CLOSE_POSITIONS: return BRE_EXEC_INTENT_CLOSE_POSITION;
         case BRE_COMMAND_MOVE_BASKET_STOP_LOSS: return BRE_EXEC_INTENT_MODIFY_STOP_LOSS;
         case BRE_COMMAND_REDUCE_BASKET_RISK: return BRE_EXEC_INTENT_REDUCE_POSITION;
         default: return BRE_EXEC_INTENT_NONE;
        }
     }

public:
   static CResult<CTradeExecutionRequest> FromStrategyCommand(const CStrategyCommandBase &command,
                                                              const string executionRequestId,
                                                              const string symbol,
                                                              const ENUM_BRE_TRADE_DIRECTION direction,
                                                              const ulong ticket,
                                                              const double requestedVolume,
                                                              const double requestedPrice,
                                                              const double requestedStopLoss,
                                                              const double requestedTakeProfit,
                                                              const datetime requestedAtUtc,
                                                              const string reason)
     {
      ENUM_BRE_TRADE_EXECUTION_INTENT intent=ResolveIntent(command.Type());
      if(intent==BRE_EXEC_INTENT_NONE)
         return CResult<CTradeExecutionRequest>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Command type is not execution-eligible");

      CTradeExecutionRequest request=CTradeExecutionRequest::Create(executionRequestId,
                                                                    command.IdempotencyKey(),
                                                                    command.CorrelationKey(),
                                                                    command.BasketId(),
                                                                    command.ExpectedBasketVersion(),
                                                                    command.StrategyProfileHash(),
                                                                    symbol,
                                                                    intent,
                                                                    direction,
                                                                    ticket,
                                                                    requestedVolume,
                                                                    requestedPrice,
                                                                    requestedStopLoss,
                                                                    requestedTakeProfit,
                                                                    requestedAtUtc,
                                                                    command.Id(),
                                                                    reason);
      return CResult<CTradeExecutionRequest>::Ok(request);
     }
  };

#endif
