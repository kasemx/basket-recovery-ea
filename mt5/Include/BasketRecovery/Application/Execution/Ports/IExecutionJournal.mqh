#ifndef BRE_APP_IEXECUTION_JOURNAL_MQH
#define BRE_APP_IEXECUTION_JOURNAL_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionReceipt.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionStatusTransition.mqh>

class IExecutionJournal
  {
public:
   virtual          ~IExecutionJournal(void) {}
   virtual CVoidResult RecordReceipt(const CTradeExecutionReceipt &receipt)=0;
   virtual CVoidResult AppendTransition(const string executionRequestId,
                                        const CExecutionStatusTransition &transition)=0;
   virtual CResult<CTradeExecutionReceipt> FindByExecutionRequestId(const string executionRequestId) const=0;
   virtual CResult<CTradeExecutionReceipt> FindByIdempotencyKey(const string idempotencyKey) const=0;
  };

#endif
