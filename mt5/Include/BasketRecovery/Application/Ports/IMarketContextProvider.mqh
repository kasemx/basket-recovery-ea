#ifndef BASKET_RECOVERY_APPLICATION_IMARKET_CONTEXT_PROVIDER_MQH
#define BASKET_RECOVERY_APPLICATION_IMARKET_CONTEXT_PROVIDER_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Strategy/Context/MarketContext.mqh>
#include <BasketRecovery/Domain/Strategy/Context/RiskRuntimeContext.mqh>

class IMarketContextProvider
  {
public:
   virtual          ~IMarketContextProvider(void) {}
   virtual bool      TryBuildForBasket(const CBasketAggregate &basket,
                                       CMarketContext &outMarket,
                                       CRiskRuntimeContext &outRiskContext)=0;
  };

#endif
