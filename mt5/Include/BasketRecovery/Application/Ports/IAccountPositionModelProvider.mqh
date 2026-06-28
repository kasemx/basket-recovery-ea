#ifndef BRE_APP_PORTS_I_ACCOUNT_POSITION_MODEL_PROVIDER_MQH
#define BRE_APP_PORTS_I_ACCOUNT_POSITION_MODEL_PROVIDER_MQH

#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

class IAccountPositionModelProvider
  {
public:
   virtual          ~IAccountPositionModelProvider(void) {}
   virtual ENUM_BRE_ACCOUNT_POSITION_MODEL Capture(void) const=0;
  };

#endif
