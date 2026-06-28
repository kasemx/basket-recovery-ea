#ifndef BRE_INF_MT5_ACCOUNT_POSITION_MODEL_PROVIDER_MQH
#define BRE_INF_MT5_ACCOUNT_POSITION_MODEL_PROVIDER_MQH

#include <BasketRecovery/Application/Ports/IAccountPositionModelProvider.mqh>

class CMt5AccountPositionModelProvider : public IAccountPositionModelProvider
  {
public:
   virtual ENUM_BRE_ACCOUNT_POSITION_MODEL Capture(void) const
     {
      ENUM_ACCOUNT_MARGIN_MODE marginMode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      switch(marginMode)
        {
         case ACCOUNT_MARGIN_MODE_RETAIL_NETTING:
            return BRE_ACCOUNT_POSITION_MODEL_NETTING;
         case ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:
            return BRE_ACCOUNT_POSITION_MODEL_HEDGING;
         case ACCOUNT_MARGIN_MODE_EXCHANGE:
            return BRE_ACCOUNT_POSITION_MODEL_EXCHANGE;
         default:
            return BRE_ACCOUNT_POSITION_MODEL_UNKNOWN;
        }
     }
  };

#endif
