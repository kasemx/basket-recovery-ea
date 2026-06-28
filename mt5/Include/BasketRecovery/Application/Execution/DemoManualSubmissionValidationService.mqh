#ifndef BRE_APP_DEMO_MANUAL_SUBMISSION_VALIDATION_SERVICE_MQH
#define BRE_APP_DEMO_MANUAL_SUBMISSION_VALIDATION_SERVICE_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Risk/BasketRiskReadModelService.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskCalculationSettings.mqh>
#include <BasketRecovery/Domain/Risk/ValueObjects/RiskValidationResult.mqh>

class CDemoManualSubmissionValidationService
  {
private:
   CDemoExecutionAuthorizationConfig m_config;
   CDemoManualSubmissionService     *m_service;
   IBasketRepository                *m_basketRepository;
   IMarketDataProvider              *m_marketDataProvider;
   IPositionSnapshotStore           *m_snapshotStore;
   string                            m_lastProcessedTriggerToken;
   CRiskValidationResult             m_lastReadOnlyRiskValidation;

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
      m_snapshotStore=NULL;
      m_lastProcessedTriggerToken="";
     }

   void              Configure(const CDemoExecutionAuthorizationConfig &config,
                               CDemoManualSubmissionService *service,
                               IBasketRepository *basketRepository,
                               IMarketDataProvider *marketDataProvider,
                               IPositionSnapshotStore *snapshotStore=NULL)
     {
      m_config=config;
      m_service=service;
      m_basketRepository=basketRepository;
      m_marketDataProvider=marketDataProvider;
      m_snapshotStore=snapshotStore;
     }

   CRiskValidationResult LastReadOnlyRiskValidation(void) const { return m_lastReadOnlyRiskValidation; }

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

      CResult<CAccountContextSnapshot> accountResult=m_marketDataProvider.TryGetAccountSnapshot();
      if(accountResult.IsOk())
        {
         CAccountContextSnapshot account;
         accountResult.TryGetValue(account);
         CTradeExecutionRequest probeRequest=CTradeExecutionRequest::Create(executionRequestId,
                                                                            "risk-readonly",
                                                                            "risk-readonly",
                                                                            basket.Id(),
                                                                            basket.Version(),
                                                                            "",
                                                                            basket.Symbol(),
                                                                            BRE_EXEC_INTENT_OPEN_POSITION,
                                                                            basket.Direction(),
                                                                            0,
                                                                            quote.Constraints().VolumeMin(),
                                                                            quote.Ask(),
                                                                            basket.SignalDetails().StopLoss().Value(),
                                                                            0.0,
                                                                            0,
                                                                            CCommandId(),
                                                                            "risk-readonly-probe");
         m_lastReadOnlyRiskValidation=CBasketRiskReadModelService::TryValidateProposedPositionReadOnly(
            basket,probeRequest,quote,account,m_snapshotStore,CRiskCalculationSettings::CreateDefault());
        }

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
