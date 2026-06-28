#ifndef BRE_APP_DEMO_MANUAL_SUBMISSION_VALIDATION_SERVICE_MQH
#define BRE_APP_DEMO_MANUAL_SUBMISSION_VALIDATION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>

class CDemoManualSubmissionValidationService
  {
private:
   CDemoExecutionAuthorizationConfig m_config;
   CDemoManualSubmissionService     *m_service;
   IBasketRepository                *m_basketRepository;
   IMarketDataProvider              *m_marketDataProvider;
   string                            m_lastProcessedTriggerToken;

   bool              IsManualRouteEnabled(void) const
     {
      return CExecutionAuthorizationPolicy::AllowsDemoManualSubmission(m_config);
     }

public:
                     CDemoManualSubmissionValidationService(void)
     {
      m_service=NULL;
      m_basketRepository=NULL;
      m_marketDataProvider=NULL;
      m_lastProcessedTriggerToken="";
     }

   void              Configure(const CDemoExecutionAuthorizationConfig &config,
                               CDemoManualSubmissionService *service,
                               IBasketRepository *basketRepository,
                               IMarketDataProvider *marketDataProvider)
     {
      m_config=config;
      m_service=service;
      m_basketRepository=basketRepository;
      m_marketDataProvider=marketDataProvider;
     }

   CDemoManualSubmissionResult TryProcessManualSubmission(const string executionRequestId,
                                                          const string authorizationToken,
                                                          const string triggerToken,
                                                          const string basketIdValue)
     {
      if(!IsManualRouteEnabled())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Demo manual submission route disabled");

      if(m_service==NULL || m_basketRepository==NULL || m_marketDataProvider==NULL)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Demo manual submission route is not configured");

      if(executionRequestId=="" || basketIdValue=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Execution request id and basket id are required");

      if(triggerToken!="" && triggerToken==m_lastProcessedTriggerToken)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,
                                                      "Manual submission trigger already processed in this session");

      CResult<CBasketAggregate> basketResult=m_basketRepository.Load(CBasketId(basketIdValue));
      if(basketResult.IsFail())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_BASKET_NOT_ACTIVE,
                                                      basketResult.ErrorMessage());

      CBasketAggregate basket;
      basketResult.TryGetValue(basket);

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(basket.Symbol());
      if(quoteResult.IsFail())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_MARKET_UNAVAILABLE,
                                                      quoteResult.ErrorMessage());

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      CDemoManualSubmissionResult result=m_service.TrySubmit(executionRequestId,
                                                             authorizationToken,
                                                             triggerToken,
                                                             basket,
                                                             quote);
      if(result.TriggerTokenConsumed())
         m_lastProcessedTriggerToken=triggerToken;
      return result;
     }

   bool              IsWiredToStrategyEngine(void) const { return false; }
   bool              IsWiredToRestIntake(void) const { return false; }
   bool              IsWiredToOnTick(void) const { return false; }
   bool              IsWiredToOnTradeTransaction(void) const { return false; }
   bool              IsWiredToAutomaticTimer(void) const { return false; }
  };

#endif
