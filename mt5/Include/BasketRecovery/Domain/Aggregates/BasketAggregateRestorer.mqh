#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORER_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_RESTORER_MQH

#include <BasketRecovery/Domain/Persistence/BasketPersistenceDto.mqh>
#include <BasketRecovery/Domain/Strategy/Aggregates/StrategyProfileSnapshot.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Domain/Basket/BasketProfitLevelProgress.mqh>

class CBasketAggregate;

class CBasketAggregateRestorer
  {
public:
   static bool       Restore(CBasketAggregate &aggregate,const CBasketPersistenceDto &dto);
  };

#endif
