#ifndef BRE_INF_MT5_REQUEST_VALIDATION_POLICY_MQH
#define BRE_INF_MT5_REQUEST_VALIDATION_POLICY_MQH

#include <BasketRecovery/Infrastructure/Execution/TradeValidationService.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Basket/BasketRuntimeGuard.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5BasketPositionLookup.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMt5RequestValidationPolicy
  {
private:
   CTradeValidationService   m_validator;
   IMarketDataProvider      *m_marketDataProvider;
   CMarketSafetyConfig       m_marketSafetyConfig;

   CTradeExecutionResult Reject(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason,
                                const string message,
                                const double requestedVolume=0.0) const
     {
      return CTradeExecutionResult::Rejected(reason,message,requestedVolume);
     }

public:
                     CMt5RequestValidationPolicy(void)
     {
      m_marketDataProvider=NULL;
      m_marketSafetyConfig=CMarketSafetyConfig();
     }

                     CMt5RequestValidationPolicy(IMarketDataProvider *marketDataProvider,
                                                 const CMarketSafetyConfig &marketSafetyConfig)
     {
      m_marketDataProvider=marketDataProvider;
      m_marketSafetyConfig=marketSafetyConfig;
     }

   CResult<CTradeExecutionResult> ValidateBeforeOrderCheck(const CTradeExecutionRequest &request,
                                                           const CBasketAggregate &basket) const
     {
      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_BASKET_NOT_ACTIVE,"Basket lifecycle is not ACTIVE"));

      CVoidResult guardResult=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                                   request.ExpectedBasketVersion(),
                                                                                   request.StrategyProfileHash());
      if(guardResult.IsFail())
        {
         if(guardResult.ErrorCode()==BRE_ERR_BASKET_VERSION_STALE)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_STALE_BASKET_VERSION,guardResult.ErrorMessage()));
         if(guardResult.ErrorCode()==BRE_ERR_STRATEGY_HASH_MISMATCH)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH,guardResult.ErrorMessage()));
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,guardResult.ErrorMessage()));
        }

      CVoidResult symbolResult=m_validator.ValidateSymbolSelected(request.Symbol());
      if(symbolResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,symbolResult.ErrorMessage()));

      CVoidResult hoursResult=m_validator.ValidateTradingHours(request.Symbol());
      if(hoursResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MARKET_UNAVAILABLE,hoursResult.ErrorMessage()));

      if(m_marketDataProvider==NULL)
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Market data provider is not configured");

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(request.Symbol());
      if(quoteResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MARKET_UNAVAILABLE,quoteResult.ErrorMessage()));

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      if(quote.FreshnessAgeMs()>m_marketSafetyConfig.QuoteStaleThresholdMs())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_LIVE_QUOTE_STALE,"Quote is stale"));

      if(quote.SpreadPoints()>m_marketSafetyConfig.MaxSpreadPoints())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MAX_SPREAD,"Spread exceeds configured maximum"));

      CResult<CAccountContextSnapshot> accountResult=m_marketDataProvider.TryGetAccountSnapshot();
      if(accountResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED,"Account snapshot unavailable"));
      CAccountContextSnapshot account;
      accountResult.TryGetValue(account);
      if(!account.TradeAllowed())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED,"Account trade permission denied"));

      if(request.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
        {
         if(request.Direction()==BRE_DIRECTION_NONE)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Direction is required for open"));
         CVoidResult volumeResult=m_validator.ValidateVolume(request.Symbol(),request.RequestedVolume());
         if(volumeResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VOLUME_CONSTRAINT,volumeResult.ErrorMessage()));

         double price=(request.Direction()==BRE_DIRECTION_BUY) ? quote.Ask() : quote.Bid();
         if(request.RequestedPrice()>0.0)
           {
            if(request.Direction()==BRE_DIRECTION_BUY && request.RequestedPrice()<quote.Ask())
               return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Buy price below ask"));
            if(request.Direction()==BRE_DIRECTION_SELL && request.RequestedPrice()>quote.Bid())
               return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Sell price above bid"));
            price=request.RequestedPrice();
           }

         CVoidResult stopsResult=m_validator.ValidateStopsLevel(request.Symbol(),price,
                                                                request.RequestedStopLoss(),
                                                                request.RequestedTakeProfit());
         if(stopsResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,stopsResult.ErrorMessage()));

         CVoidResult freezeResult=m_validator.ValidateFreezeLevel(request.Symbol(),price,
                                                                  request.RequestedStopLoss(),
                                                                  request.RequestedTakeProfit());
         if(freezeResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,freezeResult.ErrorMessage()));
        }

      if(request.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION ||
         request.IntentType()==BRE_EXEC_INTENT_CLOSE_POSITION ||
         request.IntentType()==BRE_EXEC_INTENT_MODIFY_STOP_LOSS ||
         request.IntentType()==BRE_EXEC_INTENT_MODIFY_TAKE_PROFIT)
        {
         if(request.Ticket()==0)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Ticket is required"));
         if(!CMt5BasketPositionLookup::TicketBelongsToBasket(basket,request.Ticket()))
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET,"Ticket does not belong to basket"));
        }

      if(request.IntentType()==BRE_EXEC_INTENT_REDUCE_POSITION)
        {
         CVoidResult volumeResult=m_validator.ValidateVolume(request.Symbol(),request.RequestedVolume());
         if(volumeResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VOLUME_CONSTRAINT,volumeResult.ErrorMessage()));
        }

      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }

   CResult<CTradeExecutionResult> ValidateBeforeOrderCheckExceptAccount(const CTradeExecutionRequest &request,
                                                                        const CBasketAggregate &basket) const
     {
      if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_BASKET_NOT_ACTIVE,"Basket lifecycle is not ACTIVE"));

      CVoidResult guardResult=CBasketRuntimeGuard::ValidateStrategyCommandContext(basket,
                                                                                   request.ExpectedBasketVersion(),
                                                                                   request.StrategyProfileHash());
      if(guardResult.IsFail())
        {
         if(guardResult.ErrorCode()==BRE_ERR_BASKET_VERSION_STALE)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_STALE_BASKET_VERSION,guardResult.ErrorMessage()));
         if(guardResult.ErrorCode()==BRE_ERR_STRATEGY_HASH_MISMATCH)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH,guardResult.ErrorMessage()));
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,guardResult.ErrorMessage()));
        }

      CVoidResult symbolResult=m_validator.ValidateSymbolSelected(request.Symbol());
      if(symbolResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,symbolResult.ErrorMessage()));

      CVoidResult hoursResult=m_validator.ValidateTradingHours(request.Symbol());
      if(hoursResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MARKET_UNAVAILABLE,hoursResult.ErrorMessage()));

      if(m_marketDataProvider==NULL)
         return CResult<CTradeExecutionResult>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Market data provider is not configured");

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(request.Symbol());
      if(quoteResult.IsFail())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MARKET_UNAVAILABLE,quoteResult.ErrorMessage()));

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      if(quote.FreshnessAgeMs()>m_marketSafetyConfig.QuoteStaleThresholdMs())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_LIVE_QUOTE_STALE,"Quote is stale"));

      if(quote.SpreadPoints()>m_marketSafetyConfig.MaxSpreadPoints())
         return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_MAX_SPREAD,"Spread exceeds configured maximum"));

      if(request.IntentType()==BRE_EXEC_INTENT_OPEN_POSITION)
        {
         if(request.Direction()==BRE_DIRECTION_NONE)
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Direction is required for open"));
         CVoidResult volumeResult=m_validator.ValidateVolume(request.Symbol(),request.RequestedVolume());
         if(volumeResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VOLUME_CONSTRAINT,volumeResult.ErrorMessage()));

         double price=(request.Direction()==BRE_DIRECTION_BUY) ? quote.Ask() : quote.Bid();
         if(request.RequestedPrice()>0.0)
           {
            if(request.Direction()==BRE_DIRECTION_BUY && request.RequestedPrice()<quote.Ask())
               return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Buy price below ask"));
            if(request.Direction()==BRE_DIRECTION_SELL && request.RequestedPrice()>quote.Bid())
               return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,"Sell price above bid"));
            price=request.RequestedPrice();
           }

         CVoidResult stopsResult=m_validator.ValidateStopsLevel(request.Symbol(),price,
                                                                request.RequestedStopLoss(),
                                                                request.RequestedTakeProfit());
         if(stopsResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,stopsResult.ErrorMessage()));

         CVoidResult freezeResult=m_validator.ValidateFreezeLevel(request.Symbol(),price,
                                                                  request.RequestedStopLoss(),
                                                                  request.RequestedTakeProfit());
         if(freezeResult.IsFail())
            return CResult<CTradeExecutionResult>::Ok(Reject(BRE_EXEC_FAIL_VALIDATION,freezeResult.ErrorMessage()));
        }

      CTradeExecutionResult ok;
      return CResult<CTradeExecutionResult>::Ok(ok);
     }
  };

#endif
