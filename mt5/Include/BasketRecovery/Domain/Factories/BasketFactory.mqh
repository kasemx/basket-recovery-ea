#ifndef BASKET_RECOVERY_DOMAIN_BASKET_FACTORY_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_FACTORY_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Domain/Entities/TradingSignal.mqh>
#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Types/UtcTime.mqh>
#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketFactory
  {
public:
   static CResult<CBasketAggregate> Create(const CBasketId &basketId,
                                           const CProfileSnapshot &profileSnapshot,
                                           const string correlationKey,
                                           const ENUM_BRE_TRADE_DIRECTION direction,
                                           const string symbol,
                                           const CSignalId &signalId,
                                           const CUtcTime createdAtUtc,
                                           const CCommandId &commandId,
                                           const CEventId &eventId)
     {
      if(basketId.IsEmpty())
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Basket id is empty");
      if(symbol=="")
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Symbol is empty");

      CTradingSignal signal;
      signal.SetId(signalId);
      signal.SetCorrelationKey(correlationKey);
      signal.SetDirection(direction);
      signal.SetSymbol(symbol);
      signal.SetReceivedAt(createdAtUtc.Value());

      CBasketAggregate aggregate;
      if(!aggregate.InitializeFromFactory(basketId,correlationKey,direction,symbol,profileSnapshot,signal,
                                          createdAtUtc,commandId,eventId))
         return CResult<CBasketAggregate>::Fail(BRE_ERR_BASKET_INVALID,"Basket factory initialization failed");

      return CResult<CBasketAggregate>::Ok(aggregate);
     }
  };

#endif
