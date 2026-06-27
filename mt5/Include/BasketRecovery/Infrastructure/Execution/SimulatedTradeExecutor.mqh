#ifndef BRE_INF_SIMULATED_TRADE_EXECUTOR_MQH
#define BRE_INF_SIMULATED_TRADE_EXECUTOR_MQH

#include <BasketRecovery/Application/Execution/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedExecutionPolicy.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionLifecycleRules.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CSimulatedTradeExecutor : public ITradeExecutor
  {
private:
   CSimulatedExecutionPolicy m_policy;
   int                       m_executeCallCount;

   void              AppendTransition(CTradeExecutionReceipt &receipt,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                      const datetime occurredAtUtc,
                                      const string detail)
     {
      receipt.AppendTransition(CExecutionStatusTransition::Create(fromStatus,toStatus,occurredAtUtc,detail));
      receipt.SetCurrentStatus(toStatus);
     }

   CTradeExecutionReceipt BuildAcceptedFillReceipt(const CTradeExecutionRequest &request,
                                                   const datetime nowUtc,
                                                   const double filledVolume,
                                                   const ENUM_BRE_TRADE_EXECUTION_STATUS terminalStatus)
     {
      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_CREATED);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_NONE,BRE_TRADE_EXEC_STATUS_SUBMITTED,nowUtc,"simulated submit");
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_SUBMITTED,BRE_TRADE_EXEC_STATUS_ACCEPTED,nowUtc,"simulated accept");

      if(terminalStatus==BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED)
        {
         double partial=filledVolume*0.5;
         CTradeExecutionResult partialResult;
         partialResult.SetStatus(BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
         partialResult.SetRequestedVolume(request.RequestedVolume());
         partialResult.SetFilledVolume(partial);
         partialResult.SetFillPrice(request.RequestedPrice());
         partialResult.SetBrokerCorrelationId("sim-partial");
         partialResult.SetCompletedAtUtc(nowUtc);
         receipt.SetResult(partialResult);
         AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_ACCEPTED,BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED,nowUtc,"simulated partial fill");
         return receipt;
        }

      CTradeExecutionResult result;
      result.SetStatus(terminalStatus);
      result.SetRequestedVolume(request.RequestedVolume());
      result.SetFilledVolume(filledVolume);
      result.SetFillPrice(request.RequestedPrice());
      result.SetBrokerTicket(900000+(ulong)m_executeCallCount);
      result.SetBrokerCorrelationId("sim-"+request.ExecutionRequestId());
      result.SetCompletedAtUtc(nowUtc);
      receipt.SetResult(result);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_ACCEPTED,terminalStatus,nowUtc,"simulated terminal");
      return receipt;
     }

public:
                     CSimulatedTradeExecutor(void)
     {
      m_executeCallCount=0;
     }

   int               ExecuteCallCount(void) const { return m_executeCallCount; }

   void              SetScenarioForIdempotencyKey(const string idempotencyKey,
                                                  const ENUM_BRE_SIMULATED_EXECUTION_SCENARIO scenario)
     {
      m_policy.SetScenarioForIdempotencyKey(idempotencyKey,scenario);
     }

   virtual CResult<CTradeExecutionReceipt> Execute(const CTradeExecutionRequest &request)
     {
      m_executeCallCount++;
      datetime nowUtc=request.RequestedAtUtc()>0 ? request.RequestedAtUtc() : TimeCurrent();
      ENUM_BRE_SIMULATED_EXECUTION_SCENARIO scenario=m_policy.ResolveScenario(request.IdempotencyKey());

      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_CREATED);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_NONE,BRE_TRADE_EXEC_STATUS_SUBMITTED,nowUtc,"simulated submit");

      switch(scenario)
        {
         case BRE_SIM_EXEC_REJECTED:
           {
            CTradeExecutionResult result=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_BROKER_REJECTED,
                                                                         "Simulated broker rejection",
                                                                         request.RequestedVolume());
            result.SetCompletedAtUtc(nowUtc);
            receipt.SetResult(result);
            AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_SUBMITTED,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"simulated reject");
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
         case BRE_SIM_EXEC_TIMEOUT:
           {
            CTradeExecutionResult result;
            result.SetStatus(BRE_TRADE_EXEC_STATUS_TIMED_OUT);
            result.SetFailureReason(BRE_EXEC_FAIL_TIMEOUT);
            result.SetMessage("Simulated broker timeout");
            result.SetRequestedVolume(request.RequestedVolume());
            result.SetCompletedAtUtc(nowUtc);
            receipt.SetResult(result);
            AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_SUBMITTED,BRE_TRADE_EXEC_STATUS_TIMED_OUT,nowUtc,"simulated timeout");
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
         case BRE_SIM_EXEC_PARTIAL_THEN_FILLED:
           {
            receipt=BuildAcceptedFillReceipt(request,nowUtc,request.RequestedVolume(),BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
            CTradeExecutionResult fillResult;
            fillResult.SetStatus(BRE_TRADE_EXEC_STATUS_FILLED);
            fillResult.SetRequestedVolume(request.RequestedVolume());
            fillResult.SetFilledVolume(request.RequestedVolume());
            fillResult.SetFillPrice(request.RequestedPrice());
            fillResult.SetCompletedAtUtc(nowUtc);
            receipt.SetResult(fillResult);
            AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED,BRE_TRADE_EXEC_STATUS_FILLED,nowUtc,"simulated final fill");
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
         case BRE_SIM_EXEC_PARTIAL_THEN_REJECTED:
           {
            receipt=BuildAcceptedFillReceipt(request,nowUtc,request.RequestedVolume(),BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED);
            CTradeExecutionResult rejectResult=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_BROKER_REJECTED,
                                                                               "Simulated reject after partial",
                                                                               request.RequestedVolume());
            rejectResult.SetFilledVolume(request.RequestedVolume()*0.5);
            rejectResult.SetCompletedAtUtc(nowUtc);
            receipt.SetResult(rejectResult);
            AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"simulated reject after partial");
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
         case BRE_SIM_EXEC_UNKNOWN:
           {
            CTradeExecutionResult result;
            result.SetStatus(BRE_TRADE_EXEC_STATUS_UNKNOWN);
            result.SetFailureReason(BRE_EXEC_FAIL_UNKNOWN_BROKER);
            result.SetMessage("Simulated unknown broker result");
            result.SetRequestedVolume(request.RequestedVolume());
            result.SetCompletedAtUtc(nowUtc);
            receipt.SetResult(result);
            AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_SUBMITTED,BRE_TRADE_EXEC_STATUS_UNKNOWN,nowUtc,"simulated unknown");
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
         default:
           {
            receipt=BuildAcceptedFillReceipt(request,nowUtc,request.RequestedVolume(),BRE_TRADE_EXEC_STATUS_FILLED);
            return CResult<CTradeExecutionReceipt>::Ok(receipt);
           }
        }
     }
  };

#endif
