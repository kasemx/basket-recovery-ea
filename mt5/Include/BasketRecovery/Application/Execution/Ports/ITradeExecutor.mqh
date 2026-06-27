#ifndef BRE_APP_EXECUTION_ITRADE_EXECUTOR_MQH
#define BRE_APP_EXECUTION_ITRADE_EXECUTOR_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionReceipt.mqh>

class ITradeExecutor
  {
public:
   virtual          ~ITradeExecutor(void) {}
   virtual CResult<CTradeExecutionReceipt> Execute(const CTradeExecutionRequest &request)=0;
  };

#endif
