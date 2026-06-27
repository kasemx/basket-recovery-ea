#ifndef BRE_INF_MT5_TRADE_EXECUTOR_MQH
#define BRE_INF_MT5_TRADE_EXECUTOR_MQH

#include <BasketRecovery/Application/Execution/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionReceipt.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionStatusTransition.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5TradeExecutor : public ITradeExecutor
  {
private:
   int m_executeCallCount;

public:
                     CMt5TradeExecutor(void)
     {
      m_executeCallCount=0;
     }

   bool              IsActive(void) const { return false; }
   int               ExecuteCallCount(void) const { return m_executeCallCount; }

   virtual CResult<CTradeExecutionReceipt> Execute(const CTradeExecutionRequest &request)
     {
      m_executeCallCount++;

      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_REJECTED);

      CTradeExecutionResult result=CTradeExecutionResult::Rejected(BRE_EXEC_FAIL_VALIDATION,
                                                                   "Mt5TradeExecutor is inactive until Sprint 6B wiring");
      result.SetCompletedAtUtc(request.RequestedAtUtc()>0 ? request.RequestedAtUtc() : TimeCurrent());
      receipt.SetResult(result);
      receipt.AppendTransition(CExecutionStatusTransition::Create(BRE_TRADE_EXEC_STATUS_NONE,
                                                                    BRE_TRADE_EXEC_STATUS_REJECTED,
                                                                    result.CompletedAtUtc(),
                                                                    "inactive placeholder"));

      return CResult<CTradeExecutionReceipt>::Ok(receipt);
     }
  };

#endif
