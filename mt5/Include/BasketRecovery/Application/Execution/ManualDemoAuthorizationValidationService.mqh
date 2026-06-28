#ifndef BRE_APP_MANUAL_DEMO_AUTHORIZATION_VALIDATION_SERVICE_MQH
#define BRE_APP_MANUAL_DEMO_AUTHORIZATION_VALIDATION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationUseCase.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationResult.mqh>

class CManualDemoAuthorizationValidationService
  {
private:
   CDemoExecutionAuthorizationConfig m_config;
   CManualDemoAuthorizationUseCase  *m_useCase;
   IBasketRepository                *m_basketRepository;
   IMarketDataProvider              *m_marketDataProvider;
   string                            m_lastProcessedToken;

   bool              IsManualRouteEnabled(void) const
     {
      return m_config.EnableLiveDemoExecution() &&
             m_config.ExecutionRuntimeMode()==BRE_EXEC_RUNTIME_DEMO_AUTHORIZATION;
     }

public:
                     CManualDemoAuthorizationValidationService(void)
     {
      m_useCase=NULL;
      m_basketRepository=NULL;
      m_marketDataProvider=NULL;
      m_lastProcessedToken="";
     }

   void              Configure(const CDemoExecutionAuthorizationConfig &config,
                               CManualDemoAuthorizationUseCase *useCase,
                               IBasketRepository *basketRepository,
                               IMarketDataProvider *marketDataProvider)
     {
      m_config=config;
      m_useCase=useCase;
      m_basketRepository=basketRepository;
      m_marketDataProvider=marketDataProvider;
     }

   CExecutionAuthorizationResult TryProcessManualAuthorizationForBasket(const string executionRequestId,
                                                                          const string authorizationToken,
                                                                          const string basketIdValue)
     {
      if(!IsManualRouteEnabled())
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                        "Manual demo authorization route disabled");

      if(m_useCase==NULL || m_basketRepository==NULL || m_marketDataProvider==NULL)
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                        "Manual demo authorization route is not configured");

      if(executionRequestId=="" || basketIdValue=="")
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                        "Execution request id and basket id are required");

      CResult<CBasketAggregate> basketResult=m_basketRepository.Load(CBasketId(basketIdValue));
      if(basketResult.IsFail())
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_BASKET_NOT_ACTIVE,
                                                        basketResult.ErrorMessage());

      CBasketAggregate basket;
      basketResult.TryGetValue(basket);

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(basket.Symbol());
      if(quoteResult.IsFail())
         return CExecutionAuthorizationResult::Rejected(BRE_LIVE_SAFETY_MARKET_UNAVAILABLE,
                                                        quoteResult.ErrorMessage());

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      CExecutionAuthorizationResult result=m_useCase.Authorize(executionRequestId,authorizationToken,basket,quote);
      if(result.IsSuccess())
         m_lastProcessedToken=authorizationToken;
      return result;
     }

   bool              IsWiredToAutomaticTimer(void) const { return false; }
   bool              IsWiredToStrategyEngine(void) const { return false; }
   bool              IsWiredToRestIntake(void) const { return false; }
   bool              IsWiredToOnTick(void) const { return false; }
  };

#endif
