#ifndef BRE_INF_MT5_ORDER_CHECK_GATEWAY_MQH
#define BRE_INF_MT5_ORDER_CHECK_GATEWAY_MQH

#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5OrderCheckGateway.mqh>

class CMt5OrderCheckGateway : public IMt5OrderCheckGateway
  {
public:
   virtual bool      Check(MqlTradeRequest &request,MqlTradeCheckResult &outResult)
     {
      ZeroMemory(outResult);
      return OrderCheck(request,outResult);
     }
  };

#endif
