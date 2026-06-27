#ifndef BASKET_RECOVERY_DOMAIN_BASKET_VALIDATOR_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_VALIDATOR_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketValidator
  {
public:
   static CVoidResult Validate(const CBasketAggregate &aggregate)
     {
      if(aggregate.Id().IsEmpty())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Basket id is required");

      if(!aggregate.HasProfileSnapshot())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Profile snapshot is required");

      if(aggregate.LifecycleState()==BRE_STATE_NONE)
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Lifecycle state is invalid");

      if(aggregate.Version()<1)
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Version must be at least 1");

      if(aggregate.CommandHistoryCount()<1)
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Command history must contain at least one record");

      if(aggregate.EventHistoryCount()<1)
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Event history must contain at least one record");

      if(aggregate.CommandHistoryCount()!=aggregate.EventHistoryCount())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Command and event history counts must match");

      if(aggregate.Symbol()=="")
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Symbol is required");

      if(aggregate.LifecycleState()==BRE_STATE_ACTIVE && !aggregate.SignalDetails().HasDetails())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Active basket requires signal details");

      CAuditRecord latestCommand;
      CAuditRecord latestEvent;
      if(!aggregate.CommandHistoryAt(aggregate.CommandHistoryCount()-1,latestCommand))
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Latest command audit record missing");
      if(!aggregate.EventHistoryAt(aggregate.EventHistoryCount()-1,latestEvent))
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Latest event audit record missing");

      if(latestCommand.Version()!=aggregate.Version())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Latest audit version must match aggregate version");

      if(latestEvent.Version()!=aggregate.Version())
         return CVoidResult::Fail(BRE_ERR_BASKET_VALIDATION_FAILED,"Latest event audit version must match aggregate version");

      return CVoidResult::Ok();
     }
  };

#endif
