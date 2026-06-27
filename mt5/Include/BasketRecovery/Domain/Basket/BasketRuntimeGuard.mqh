#ifndef BASKET_RECOVERY_DOMAIN_BASKET_RUNTIME_GUARD_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_RUNTIME_GUARD_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>

class CBasketRuntimeGuard
  {
public:
   static CVoidResult ValidateStrategyCommandContext(const CBasketAggregate &basket,
                                                     const long expectedBasketVersion,
                                                     const string strategyProfileHash)
     {
      if(!basket.HasStrategyProfile())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_NOT_BOUND,"Basket has no bound strategy profile");
      if(basket.StrategyMigrationRequired())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_MIGRATION_REQUIRED,"Basket requires explicit strategy migration");
      if(expectedBasketVersion!=basket.Version())
         return CVoidResult::Fail(BRE_ERR_BASKET_VERSION_STALE,"Command targets stale basket version");
      if(strategyProfileHash!="" && strategyProfileHash!=basket.StrategyProfileHash())
         return CVoidResult::Fail(BRE_ERR_STRATEGY_HASH_MISMATCH,"Command strategy profile hash mismatch");
      return CVoidResult::Ok();
     }

   static CVoidResult ValidateProfitLevelReach(const CBasketAggregate &basket,const string levelId)
     {
      CBasketProfitLevelProgress existing;
      if(basket.FindProfitLevelProgress(levelId,existing) && existing.Reached())
         return CVoidResult::Fail(BRE_ERR_PROFIT_LEVEL_ALREADY_REACHED,"Profit level already reached");
      return CVoidResult::Ok();
     }

   static CVoidResult ValidateBreakEvenExecution(const CBasketAggregate &basket,const string ruleId)
     {
      if(basket.HasExecutedBreakEvenRule(ruleId))
         return CVoidResult::Fail(BRE_ERR_BREAK_EVEN_ALREADY_EXECUTED,"Break-even rule already executed");
      return CVoidResult::Ok();
     }
  };

#endif
