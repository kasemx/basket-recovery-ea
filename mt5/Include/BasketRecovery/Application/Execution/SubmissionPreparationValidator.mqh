#ifndef BRE_APP_SUBMISSION_PREPARATION_VALIDATOR_MQH
#define BRE_APP_SUBMISSION_PREPARATION_VALIDATOR_MQH

#include <BasketRecovery/Domain/Execution/TradeExecutionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionFailureReason.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5RequestValidationPolicy.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/SubmissionPreparationFailureReason.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>

class CSubmissionPreparationValidator
  {
private:
   CMt5RequestValidationPolicy m_policy;
   IMarketDataProvider        *m_marketDataProvider;

   static ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON MapFailureReason(const ENUM_BRE_TRADE_EXECUTION_FAILURE_REASON reason)
     {
      switch(reason)
        {
         case BRE_EXEC_FAIL_BASKET_NOT_ACTIVE: return BRE_PREP_FAIL_BASKET_NOT_ACTIVE;
         case BRE_EXEC_FAIL_STALE_BASKET_VERSION: return BRE_PREP_FAIL_STALE_BASKET_VERSION;
         case BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH: return BRE_PREP_FAIL_PROFILE_HASH_MISMATCH;
         case BRE_EXEC_FAIL_MARKET_UNAVAILABLE: return BRE_PREP_FAIL_MARKET_UNAVAILABLE;
         case BRE_EXEC_FAIL_LIVE_QUOTE_STALE: return BRE_PREP_FAIL_STALE_QUOTE;
         case BRE_EXEC_FAIL_MAX_SPREAD: return BRE_PREP_FAIL_MAX_SPREAD;
         case BRE_EXEC_FAIL_VOLUME_CONSTRAINT: return BRE_PREP_FAIL_INVALID_VOLUME;
         case BRE_EXEC_FAIL_TICKET_NOT_IN_BASKET: return BRE_PREP_FAIL_TICKET_NOT_IN_BASKET;
         case BRE_EXEC_FAIL_ACCOUNT_TRADE_DISABLED: return BRE_PREP_FAIL_ACCOUNT_TRADE_DISABLED;
         default: return BRE_PREP_FAIL_VALIDATION;
        }
     }

public:
                     CSubmissionPreparationValidator(void)
     {
      m_marketDataProvider=NULL;
     }

                     CSubmissionPreparationValidator(IMarketDataProvider *marketDataProvider,
                                                     const CMarketSafetyConfig &marketSafetyConfig)
     {
      m_marketDataProvider=marketDataProvider;
      m_policy=CMt5RequestValidationPolicy(marketDataProvider,marketSafetyConfig);
     }

   bool              ValidateSealedRequest(const CTradeExecutionRequest &request,
                                             ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON &failureReason,
                                             string &failureMessage) const
     {
      if(!request.IsSealed())
        {
         failureReason=BRE_PREP_FAIL_REQUEST_NOT_SEALED;
         failureMessage="Execution request must be sealed before preparation";
         return false;
        }
      if(request.ExecutionRequestId()=="" || request.IdempotencyKey()=="")
        {
         failureReason=BRE_PREP_FAIL_VALIDATION;
         failureMessage="Execution request id and idempotency key are required";
         return false;
        }
      return true;
     }

   bool              ValidateRequestContext(const CTradeExecutionRequest &request,
                                            const CBasketAggregate &basket,
                                            CMarketQuote &quoteOut,
                                            ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON &failureReason,
                                            string &failureMessage) const
     {
      CResult<CTradeExecutionResult> validation=m_policy.ValidateBeforeOrderCheck(request,basket);
      if(validation.IsFail())
        {
         failureReason=BRE_PREP_FAIL_VALIDATION;
         failureMessage=validation.ErrorMessage();
         return false;
        }

      CTradeExecutionResult validationResult;
      validation.TryGetValue(validationResult);
      if(validationResult.Status()==BRE_TRADE_EXEC_STATUS_REJECTED ||
         validationResult.Status()==BRE_TRADE_EXEC_STATUS_FAILED)
        {
         failureReason=MapFailureReason(validationResult.FailureReason());
         failureMessage=validationResult.Message();
         if(StringFind(failureMessage,"stops")>=0)
            failureReason=BRE_PREP_FAIL_INVALID_STOPS;
         if(StringFind(failureMessage,"freeze")>=0)
            failureReason=BRE_PREP_FAIL_INVALID_FREEZE;
         return false;
        }

      if(m_marketDataProvider==NULL)
        {
         failureReason=BRE_PREP_FAIL_MARKET_UNAVAILABLE;
         failureMessage="Market data provider is not configured";
         return false;
        }

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(request.Symbol());
      if(quoteResult.IsFail())
        {
         failureReason=BRE_PREP_FAIL_MARKET_UNAVAILABLE;
         failureMessage=quoteResult.ErrorMessage();
         return false;
        }
      quoteResult.TryGetValue(quoteOut);
      return true;
     }

   bool              ValidateRequestContextForValidationSeed(const CTradeExecutionRequest &request,
                                                             const CBasketAggregate &basket,
                                                             CMarketQuote &quoteOut,
                                                             ENUM_BRE_SUBMISSION_PREPARATION_FAILURE_REASON &failureReason,
                                                             string &failureMessage) const
     {
      CResult<CTradeExecutionResult> validation=m_policy.ValidateBeforeOrderCheckExceptAccount(request,basket);
      if(validation.IsFail())
        {
         failureReason=BRE_PREP_FAIL_VALIDATION;
         failureMessage=validation.ErrorMessage();
         return false;
        }

      CTradeExecutionResult validationResult;
      validation.TryGetValue(validationResult);
      if(validationResult.Status()==BRE_TRADE_EXEC_STATUS_REJECTED ||
         validationResult.Status()==BRE_TRADE_EXEC_STATUS_FAILED)
        {
         failureReason=MapFailureReason(validationResult.FailureReason());
         failureMessage=validationResult.Message();
         if(StringFind(failureMessage,"stops")>=0)
            failureReason=BRE_PREP_FAIL_INVALID_STOPS;
         if(StringFind(failureMessage,"freeze")>=0)
            failureReason=BRE_PREP_FAIL_INVALID_FREEZE;
         return false;
        }

      if(m_marketDataProvider==NULL)
        {
         failureReason=BRE_PREP_FAIL_MARKET_UNAVAILABLE;
         failureMessage="Market data provider is not configured";
         return false;
        }

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(request.Symbol());
      if(quoteResult.IsFail())
        {
         failureReason=BRE_PREP_FAIL_MARKET_UNAVAILABLE;
         failureMessage=quoteResult.ErrorMessage();
         return false;
        }
      quoteResult.TryGetValue(quoteOut);
      return true;
     }
  };

#endif
