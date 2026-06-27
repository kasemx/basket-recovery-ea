#ifndef BRE_INF_IMT5_ORDER_CHECK_GATEWAY_MQH
#define BRE_INF_IMT5_ORDER_CHECK_GATEWAY_MQH

class IMt5OrderCheckGateway
  {
public:
   virtual          ~IMt5OrderCheckGateway(void) {}
   virtual bool      Check(MqlTradeRequest &request,MqlTradeCheckResult &outResult)=0;
  };

#endif
