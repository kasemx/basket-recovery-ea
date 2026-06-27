#ifndef BASKET_RECOVERY_INFRASTRUCTURE_TRADE_RESULT_MAPPER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_TRADE_RESULT_MAPPER_MQH

#include <BasketRecovery/Application/DTOs/ExecutionResult.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CTradeResultMapper
  {
public:
   static bool       IsRetryableRetcode(const uint retcode)
     {
      switch(retcode)
        {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_TOO_MANY_REQUESTS:
         case TRADE_RETCODE_SERVER_DISABLES_AT:
         case TRADE_RETCODE_CLIENT_DISABLES_AT:
         case TRADE_RETCODE_TRADE_TOO_MANY_ORDERS:
            return true;
         default:
            return false;
        }
     }

   static CExecutionResult Map(const MqlTradeResult &tradeResult,
                               const int attemptCount,
                               const int latencyMs)
     {
      CExecutionResult executionResult;
      executionResult.SetAttemptCount(attemptCount);
      executionResult.SetLatencyMs(latencyMs);
      executionResult.SetRetcode(tradeResult.retcode);
      executionResult.SetOrder(tradeResult.order);
      executionResult.SetTicket(tradeResult.deal);
      executionResult.SetPrice(tradeResult.price);
      executionResult.SetVolume(tradeResult.volume);

      if(tradeResult.retcode==TRADE_RETCODE_DONE ||
         tradeResult.retcode==TRADE_RETCODE_DONE_PARTIAL ||
         tradeResult.retcode==TRADE_RETCODE_PLACED)
        {
         executionResult.SetSuccess(true);
         executionResult.SetStatus(BRE_EXECUTION_STATUS_FILLED);
         executionResult.SetErrorCode(BRE_ERR_NONE);
         executionResult.SetMessage("Execution filled");
         executionResult.SetRetryable(false);
         return executionResult;
        }

      executionResult.SetSuccess(false);
      executionResult.SetRetryable(IsRetryableRetcode(tradeResult.retcode));

      switch(tradeResult.retcode)
        {
         case TRADE_RETCODE_NO_MONEY:
            executionResult.SetErrorCode(BRE_ERR_EXEC_BROKER_ERROR);
            executionResult.SetMessage("Insufficient margin at broker");
            break;
         case TRADE_RETCODE_INVALID_STOPS:
         case TRADE_RETCODE_INVALID_VOLUME:
         case TRADE_RETCODE_INVALID_PRICE:
         case TRADE_RETCODE_INVALID_FILL:
            executionResult.SetErrorCode(BRE_ERR_EXEC_VALIDATION_FAILED);
            executionResult.SetMessage(StringFormat("Broker rejected request | retcode=%u",tradeResult.retcode));
            executionResult.SetRetryable(false);
            break;
         case TRADE_RETCODE_REJECT:
            executionResult.SetErrorCode(BRE_ERR_EXEC_REJECTED);
            executionResult.SetMessage("Broker rejected request");
            executionResult.SetRetryable(false);
            break;
         case TRADE_RETCODE_TIMEOUT:
            executionResult.SetErrorCode(BRE_ERR_EXEC_TIMEOUT);
            executionResult.SetMessage("Broker execution timeout");
            break;
         default:
            executionResult.SetErrorCode(BRE_ERR_EXEC_BROKER_ERROR);
            executionResult.SetMessage(StringFormat("Broker error | retcode=%u | comment=%s",
                                                    tradeResult.retcode,
                                                    tradeResult.comment));
            break;
        }

      executionResult.SetStatus(BRE_EXECUTION_STATUS_REJECTED);
      return executionResult;
     }

   static CExecutionResult MapDryRun(const int attemptCount)
     {
      CExecutionResult executionResult;
      executionResult.SetSuccess(true);
      executionResult.SetStatus(BRE_EXECUTION_STATUS_DRY_RUN);
      executionResult.SetErrorCode(BRE_ERR_EXEC_DRY_RUN);
      executionResult.SetMessage("Dry run mode - request not sent");
      executionResult.SetAttemptCount(attemptCount);
      executionResult.SetRetryable(false);
      return executionResult;
     }

   static CExecutionResult MapSimulated(const int attemptCount,const double price,const double volume)
     {
      CExecutionResult executionResult;
      executionResult.SetSuccess(true);
      executionResult.SetStatus(BRE_EXECUTION_STATUS_SIMULATED);
      executionResult.SetErrorCode(BRE_ERR_NONE);
      executionResult.SetMessage("Simulation mode - request not sent to broker");
      executionResult.SetAttemptCount(attemptCount);
      executionResult.SetPrice(price);
      executionResult.SetVolume(volume);
      executionResult.SetRetryable(false);
      return executionResult;
     }
  };

#endif
