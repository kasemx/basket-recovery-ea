#ifndef BASKET_RECOVERY_INFRASTRUCTURE_MT5_TRADE_EXECUTOR_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_MT5_TRADE_EXECUTOR_MQH

#include <BasketRecovery/Application/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeValidationService.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeRequestBuilder.mqh>
#include <BasketRecovery/Infrastructure/Execution/TradeResultMapper.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionAuditLogger.mqh>
#include <BasketRecovery/Shared/Constants/FeatureFlags.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5TradeExecutor : public ITradeExecutor
  {
private:
   CExecutionPolicy          m_policy;
   CTradeValidationService   m_validator;
   CTradeRequestBuilder      m_builder;
   CExecutionAuditLogger     m_audit;

   bool              BrokerSendOrder(MqlTradeRequest &request,MqlTradeResult &result) const
     {
      return OrderSend(request,result);
     }

   bool              BrokerCheckOrder(MqlTradeRequest &request,MqlTradeResult &result) const
     {
      return OrderCheck(request,result);
     }

   bool              BrokerSelectPosition(const ulong ticket) const
     {
      return PositionSelectByTicket(ticket);
     }

   bool              BrokerSelectOrder(const ulong ticket) const
     {
      return OrderSelect(ticket);
     }

   CResult<CExecutionResult> ExecuteRequest(const CTradeContext &context,
                                            const string operation,
                                            MqlTradeRequest &request,
                                            const double simulatedPrice,
                                            const double simulatedVolume)
     {
      if(!m_policy.EnableExecution() && !m_policy.DryRunMode() && !m_policy.SimulationMode())
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_DISABLED,"Execution is disabled by policy");

      for(int attempt=0;attempt<=m_policy.MaxRetries();attempt++)
        {
         if(m_policy.DryRunMode())
           {
            m_audit.LogRequest(context,operation,request,attempt);
            CExecutionResult dryRunResult=CTradeResultMapper::MapDryRun(attempt+1);
            m_audit.LogResponse(context,operation,dryRunResult);
            return CResult<CExecutionResult>::Ok(dryRunResult);
           }

         if(m_policy.SimulationMode())
           {
            m_audit.LogRequest(context,operation,request,attempt);
            CExecutionResult simulatedResult=CTradeResultMapper::MapSimulated(attempt+1,simulatedPrice,simulatedVolume);
            m_audit.LogResponse(context,operation,simulatedResult);
            return CResult<CExecutionResult>::Ok(simulatedResult);
           }

         m_audit.LogRequest(context,operation,request,attempt);

         MqlTradeResult checkResult;
         ZeroMemory(checkResult);
         if(!BrokerCheckOrder(request,checkResult))
           {
            m_audit.LogRejection(context,operation,"OrderCheck failed",BRE_ERR_EXEC_VALIDATION_FAILED);
            if(!m_policy.IsRetryAllowed(attempt))
               break;
            Sleep(m_policy.RetryDelayMs());
            continue;
           }

         ulong startedMs=GetTickCount();
         MqlTradeResult sendResult;
         ZeroMemory(sendResult);
         if(!BrokerSendOrder(request,sendResult))
           {
            m_audit.LogRejection(context,operation,"OrderSend returned false",BRE_ERR_EXEC_BROKER_ERROR);
            if(!m_policy.IsRetryAllowed(attempt))
               break;
            Sleep(m_policy.RetryDelayMs());
            continue;
           }

         int latencyMs=(int)(GetTickCount()-startedMs);
         CExecutionResult mapped=CTradeResultMapper::Map(sendResult,attempt+1,latencyMs);
         m_audit.LogResponse(context,operation,mapped);

         if(mapped.Success())
            return CResult<CExecutionResult>::Ok(mapped);

         if(mapped.Retryable() && m_policy.IsRetryAllowed(attempt))
           {
            m_audit.LogRetry(context,operation,attempt,sendResult.retcode);
            Sleep(m_policy.RetryDelayMs());
            continue;
           }

         return CResult<CExecutionResult>::Fail(mapped.ErrorCode(),mapped.Message());
        }

      CExecutionResult exhausted;
      exhausted.SetSuccess(false);
      exhausted.SetStatus(BRE_EXECUTION_STATUS_REJECTED);
      exhausted.SetErrorCode(BRE_ERR_EXEC_RETRY_EXHAUSTED);
      exhausted.SetMessage("Execution retries exhausted");
      m_audit.LogRejection(context,operation,exhausted.Message(),exhausted.ErrorCode());
      return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_RETRY_EXHAUSTED,exhausted.Message());
     }

public:
                     CMt5TradeExecutor(ILogger *logger=NULL)
     {
      m_policy.SetEnableExecution(BRE_FEATURE_EXECUTION);
      m_policy.SetDryRunMode(BRE_FEATURE_DRY_RUN);
      m_policy.SetSimulationMode(BRE_FEATURE_SIMULATION_MODE);
      m_builder=CTradeRequestBuilder(m_policy);
      m_audit=CExecutionAuditLogger(logger);
     }

                     CMt5TradeExecutor(const CExecutionPolicy &policy,ILogger *logger=NULL)
     : m_policy(policy),
       m_builder(policy)
     {
      m_audit=CExecutionAuditLogger(logger);
     }

   CExecutionPolicy& Policy(void) { return m_policy; }

   virtual CResult<CExecutionResult> OpenPosition(const CTradeContext &context,
                                                  const SOpenPositionParams &params,
                                                  const CTradeRequest &request)
     {
      CVoidResult validation=m_validator.ValidateOpenRequest(params.symbol,
                                                             params.direction,
                                                             params.volume,
                                                             params.stopLoss,
                                                             params.takeProfit);
      if(validation.IsFail())
        {
         m_audit.LogRejection(context,"OpenPosition",validation.ErrorMessage(),validation.ErrorCode());
         return CResult<CExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());
        }

      CTradeRequest requestCopy=request;
      requestCopy.SetSymbol(params.symbol);
      requestCopy.SetDirection(params.direction);
      requestCopy.SetLot(params.volume);
      requestCopy.SetStopLoss(params.stopLoss);
      requestCopy.SetTakeProfit(params.takeProfit);

      MqlTradeRequest tradeRequest;
      if(!m_builder.BuildOpenRequest(context,requestCopy,tradeRequest))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Failed to build open request");

      return ExecuteRequest(context,"OpenPosition",tradeRequest,tradeRequest.price,params.volume);
     }

   virtual CResult<CExecutionResult> ModifyPosition(const CTradeContext &context,
                                                      const SModifyPositionParams &params,
                                                      const CTradeRequest &request)
     {
      if(!BrokerSelectPosition(params.ticket))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Position not found");

      string symbol=PositionGetString(POSITION_SYMBOL);
      double price=PositionGetDouble(POSITION_PRICE_OPEN);

      CVoidResult validation=m_validator.ValidateStopsLevel(symbol,price,params.stopLoss,params.takeProfit);
      if(validation.IsFail())
        {
         m_audit.LogRejection(context,"ModifyPosition",validation.ErrorMessage(),validation.ErrorCode());
         return CResult<CExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());
        }

      MqlTradeRequest tradeRequest;
      if(!m_builder.BuildModifyRequest(context,params.ticket,symbol,params.stopLoss,params.takeProfit,request,tradeRequest))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Failed to build modify request");

      return ExecuteRequest(context,"ModifyPosition",tradeRequest,price,0.0);
     }

   virtual CResult<CExecutionResult> ClosePosition(const CTradeContext &context,
                                                     const SClosePositionParams &params,
                                                     const CTradeRequest &request)
     {
      if(!BrokerSelectPosition(params.ticket))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Position not found");

      string symbol=PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE positionType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume=(params.volume>0.0) ? params.volume : PositionGetDouble(POSITION_VOLUME);

      CVoidResult validation=m_validator.ValidateVolume(symbol,volume);
      if(validation.IsFail())
        {
         m_audit.LogRejection(context,"ClosePosition",validation.ErrorMessage(),validation.ErrorCode());
         return CResult<CExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());
        }

      MqlTradeRequest tradeRequest;
      if(!m_builder.BuildCloseRequest(context,params.ticket,symbol,volume,positionType,request,tradeRequest))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Failed to build close request");

      return ExecuteRequest(context,"ClosePosition",tradeRequest,tradeRequest.price,volume);
     }

   virtual CResult<CExecutionResult> ClosePartial(const CTradeContext &context,
                                                    const SClosePositionParams &params,
                                                    const CTradeRequest &request)
     {
      if(params.volume<=0.0)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Partial close volume must be positive");
      return ClosePosition(context,params,request);
     }

   virtual CResult<CExecutionResult> CloseBasket(const CTradeContext &context,
                                                   const ulong &tickets[],
                                                   const int ticketCount,
                                                   const CTradeRequest &request)
     {
      if(ticketCount<=0)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"CloseBasket requires at least one ticket");

      CExecutionResult lastResult;
      bool anySuccess=false;

      for(int i=0;i<ticketCount;i++)
        {
         SClosePositionParams params;
         params.ticket=tickets[i];
         params.volume=0.0;
         params.symbol="";

         CResult<CExecutionResult> closeResult=ClosePosition(context,params,request);
         if(closeResult.IsOk())
           {
            anySuccess=true;
            closeResult.TryGetValue(lastResult);
           }
         else if(i==ticketCount-1 && !anySuccess)
            return closeResult;
        }

      if(!anySuccess)
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_BROKER_ERROR,"CloseBasket failed for all tickets");

      return CResult<CExecutionResult>::Ok(lastResult);
     }

   virtual CResult<CExecutionResult> CancelPending(const CTradeContext &context,
                                                     const ulong orderTicket,
                                                     const CTradeRequest &request)
     {
      if(!BrokerSelectOrder(orderTicket))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Pending order not found");

      string symbol=OrderGetString(ORDER_SYMBOL);
      MqlTradeRequest tradeRequest;
      if(!m_builder.BuildCancelPendingRequest(context,orderTicket,symbol,request,tradeRequest))
         return CResult<CExecutionResult>::Fail(BRE_ERR_EXEC_VALIDATION_FAILED,"Failed to build cancel request");

      return ExecuteRequest(context,"CancelPending",tradeRequest,0.0,0.0);
     }
  };

#endif
