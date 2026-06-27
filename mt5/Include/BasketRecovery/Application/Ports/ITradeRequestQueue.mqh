#ifndef BASKET_RECOVERY_APPLICATION_ITRADE_REQUEST_QUEUE_MQH
#define BASKET_RECOVERY_APPLICATION_ITRADE_REQUEST_QUEUE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/TradeRequests/TradeRequest.mqh>

class ITradeRequestQueue
  {
public:
   virtual          ~ITradeRequestQueue(void) {}
   virtual CVoidResult Enqueue(CTradeRequest *request)=0;
   virtual CTradeRequest* DequeueNext(void)=0;
   virtual CVoidResult MarkFilled(const CRequestId &requestId)=0;
   virtual CVoidResult MarkRejected(const CRequestId &requestId,const int errorCode,const string &message)=0;
   virtual CTradeRequest* FindByIdempotencyKey(const string idempotencyKey)=0;
   virtual int       QueuedCount(void) const=0;
  };

#endif
