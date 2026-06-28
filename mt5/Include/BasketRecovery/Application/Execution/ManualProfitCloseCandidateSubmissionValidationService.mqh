#ifndef BRE_APP_MAN_PC_SUBMIT_VALIDATION_SVC_MQH
#define BRE_APP_MAN_PC_SUBMIT_VALIDATION_SVC_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Risk/RecoveryDecisionRiskGateService.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Market/AccountContextSnapshot.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>

class CManualProfitCloseCandidateSubmissionValidationService
  {
private:
   CDemoExecutionAuthorizationConfig           m_config;
   CManualProfitCloseSubmissionService        *m_service;
   IBasketRepository                          *m_basketRepository;
   IMarketDataProvider                        *m_marketDataProvider;
   int                                        m_quoteStaleThresholdMs;

   bool              IsManualProfitCloseRouteEnabled(void) const
     {
      return CExecutionAuthorizationPolicy::AllowsDemoManualSubmission(m_config);
     }

public:
                     CManualProfitCloseCandidateSubmissionValidationService(void)
     {
      m_service=NULL;
      m_basketRepository=NULL;
      m_marketDataProvider=NULL;
      m_quoteStaleThresholdMs=5000;
     }

   void              Configure(const CDemoExecutionAuthorizationConfig &config,
                               CManualProfitCloseSubmissionService *service,
                               IBasketRepository *basketRepository,
                               IMarketDataProvider *marketDataProvider,
                               const int quoteStaleThresholdMs=5000)
     {
      m_config=config;
      m_service=service;
      m_basketRepository=basketRepository;
      m_marketDataProvider=marketDataProvider;
      m_quoteStaleThresholdMs=quoteStaleThresholdMs>0 ? quoteStaleThresholdMs : 5000;
     }

   CDemoManualSubmissionResult TryProcessManualProfitCloseSubmission(const string candidateId,
                                                                     const string authorizationToken,
                                                                     const string triggerToken,
                                                                     const string basketIdValue,
                                                                     const long magicNumber)
     {
      if(!IsManualProfitCloseRouteEnabled())
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Manual profit close submission route disabled");

      if(m_service==NULL || m_basketRepository==NULL || m_marketDataProvider==NULL)
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_LIVE_DISABLED,
                                                      "Manual profit close submission route is not configured");

      if(candidateId=="" || basketIdValue=="")
         return CDemoManualSubmissionResult::Rejected(BRE_LIVE_SAFETY_REQUEST_NOT_FOUND,
                                                      "Candidate id and basket id are required");

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

      CResult<CAccountContextSnapshot> accountResult=m_marketDataProvider.TryGetAccountSnapshot();
      CAccountContextSnapshot account;
      if(accountResult.IsOk())
         accountResult.TryGetValue(account);

      CRecoveryRiskGateInput gateInput=CRecoveryRiskGateInput::Create(quote,
                                                                      account,
                                                                      0,
                                                                      m_quoteStaleThresholdMs,
                                                                      basket.StrategyProfileHash(),
                                                                      candidateId,
                                                                      quote.TimestampUtc());

      return m_service.TrySubmitProfitCloseCandidate(candidateId,
                                                     authorizationToken,
                                                     triggerToken,
                                                     basket,
                                                     quote,
                                                     gateInput,
                                                     magicNumber);
     }

   bool              IsWiredToStrategyEngine(void) const { return m_service!=NULL ? m_service.IsWiredToStrategyEngine() : false; }
   bool              IsWiredToRestIntake(void) const { return m_service!=NULL ? m_service.IsWiredToRestIntake() : false; }
   bool              IsWiredToOnTick(void) const { return m_service!=NULL ? m_service.IsWiredToOnTick() : false; }
   bool              IsWiredToOnTradeTransaction(void) const { return m_service!=NULL ? m_service.IsWiredToOnTradeTransaction() : false; }
   bool              IsWiredToAutomaticTimer(void) const { return m_service!=NULL ? m_service.IsWiredToAutomaticTimer() : false; }
  };

#endif
