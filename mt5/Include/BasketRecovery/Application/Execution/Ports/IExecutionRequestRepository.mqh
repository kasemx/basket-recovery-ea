#ifndef BRE_APP_IEXECUTION_REQUEST_REPOSITORY_MQH
#define BRE_APP_IEXECUTION_REQUEST_REPOSITORY_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionReceipt.mqh>

class IExecutionRequestRepository
  {
public:
   virtual          ~IExecutionRequestRepository(void) {}
   virtual CVoidResult Save(const CTradeExecutionReceipt &receipt)=0;
   virtual CResult<CTradeExecutionReceipt> FindByExecutionRequestId(const string executionRequestId) const=0;
   virtual CResult<CTradeExecutionReceipt> FindByIdempotencyKey(const string idempotencyKey) const=0;
  };

#endif
