#ifndef BRE_APP_EXECUTION_REQUEST_VALIDATOR_MQH
#define BRE_APP_EXECUTION_REQUEST_VALIDATOR_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CExecutionRequestValidator
  {
public:
   static CResult<CTradeExecutionResult> ValidateForDispatch(const CTradeExecutionRequest &request)
     {
      if(!request.IsSealed())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Execution request is not sealed");

      if(request.ExecutionRequestId()=="")
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"executionRequestId is required");

      if(request.IdempotencyKey()=="")
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"idempotencyKey is required");

      if(request.CorrelationId()=="")
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"correlationId is required");

      if(request.BasketId().IsEmpty())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"basketId is required");

      if(request.ExpectedBasketVersion()<0)
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"expectedBasketVersion is required");

      if(request.StrategyProfileHash()=="")
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"strategyProfileHash is required");

      if(request.Symbol()=="")
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"symbol is required");

      if(request.SourceCommandId().IsEmpty())
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"source command id is required");

      if(request.RequestedAtUtc()<=0)
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"request timestamp is required");

      if(request.IntentType()==BRE_EXEC_INTENT_NONE)
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"intent type is required");

      switch(request.IntentType())
        {
         case BRE_EXEC_INTENT_OPEN_POSITION:
            if(request.Direction()==BRE_DIRECTION_NONE)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"direction is required for open");
            if(request.RequestedVolume()<=0.0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"requested volume is required for open");
            break;
         case BRE_EXEC_INTENT_CLOSE_POSITION:
         case BRE_EXEC_INTENT_REDUCE_POSITION:
            if(request.Ticket()<=0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"ticket is required for close/reduce");
            if(request.RequestedVolume()<=0.0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"requested volume is required");
            break;
         case BRE_EXEC_INTENT_MODIFY_STOP_LOSS:
            if(request.Ticket()<=0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"ticket is required for modify SL");
            if(request.RequestedStopLoss()<=0.0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"requested stop loss is required");
            break;
         case BRE_EXEC_INTENT_MODIFY_TAKE_PROFIT:
            if(request.Ticket()<=0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"ticket is required for modify TP");
            if(request.RequestedTakeProfit()<=0.0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"requested take profit is required");
            break;
         case BRE_EXEC_INTENT_CANCEL_PENDING_REQUEST:
            if(request.Ticket()<=0)
               return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"ticket is required for cancel pending");
            break;
         default:
            return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"unsupported intent type");
        }

      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }
  };

#endif
