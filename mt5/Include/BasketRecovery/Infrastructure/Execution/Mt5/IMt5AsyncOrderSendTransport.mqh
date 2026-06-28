#ifndef BRE_INF_IMT5_ASYNC_ORDER_SEND_TRANSPORT_MQH
#define BRE_INF_IMT5_ASYNC_ORDER_SEND_TRANSPORT_MQH

class IMt5AsyncOrderSendTransport
  {
public:
   virtual          ~IMt5AsyncOrderSendTransport(void) {}
   virtual bool      SendAsync(MqlTradeRequest &request,MqlTradeResult &result)=0;
  };

#endif
