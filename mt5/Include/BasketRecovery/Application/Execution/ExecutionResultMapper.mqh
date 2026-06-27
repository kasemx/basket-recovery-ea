#ifndef BRE_APP_EXECUTION_RESULT_MAPPER_MQH
#define BRE_APP_EXECUTION_RESULT_MAPPER_MQH

#include <BasketRecovery/Domain/Events/ExecutionDomainEvent.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionReceipt.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CExecutionResultMapper
  {
private:
   static ENUM_BRE_EVENT_TYPE MapEventType(const ENUM_BRE_TRADE_EXECUTION_STATUS status)
     {
      switch(status)
        {
         case BRE_TRADE_EXEC_STATUS_CREATED:
         case BRE_TRADE_EXEC_STATUS_QUEUED:
         case BRE_TRADE_EXEC_STATUS_SUBMITTED:
            return BRE_EVENT_EXECUTION_REQUESTED;
         case BRE_TRADE_EXEC_STATUS_ACCEPTED:
            return BRE_EVENT_EXECUTION_ACCEPTED;
         case BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED:
            return BRE_EVENT_EXECUTION_PARTIALLY_FILLED;
         case BRE_TRADE_EXEC_STATUS_FILLED:
            return BRE_EVENT_EXECUTION_FILLED;
         case BRE_TRADE_EXEC_STATUS_REJECTED:
         case BRE_TRADE_EXEC_STATUS_FAILED:
         case BRE_TRADE_EXEC_STATUS_CANCELLED:
            return BRE_EVENT_EXECUTION_REJECTED;
         case BRE_TRADE_EXEC_STATUS_TIMED_OUT:
            return BRE_EVENT_EXECUTION_TIMED_OUT;
         case BRE_TRADE_EXEC_STATUS_UNKNOWN:
            return BRE_EVENT_EXECUTION_UNKNOWN;
         default:
            return BRE_EVENT_NONE;
        }
     }

public:
   static CExecutionDomainEvent ToDomainEvent(const CTradeExecutionReceipt &receipt,
                                              const datetime occurredAtUtc)
     {
      CExecutionDomainEvent event;
      event.SetEventType(MapEventType(receipt.CurrentStatus()));
      event.SetBasketId(receipt.Request().BasketId());
      event.SetCorrelationId(receipt.Request().CorrelationId());
      event.SetOccurredAt(occurredAtUtc);
      event.SetExecutionRequestId(receipt.Request().ExecutionRequestId());
      event.SetIdempotencyKey(receipt.Request().IdempotencyKey());
      event.SetIntentType(receipt.Request().IntentType());
      event.SetExecutionStatus(receipt.CurrentStatus());
      event.SetFailureReason(receipt.Result().FailureReason());
      event.SetRequestedVolume(receipt.Result().RequestedVolume());
      event.SetFilledVolume(receipt.Result().FilledVolume());
      return event;
     }
  };

#endif
