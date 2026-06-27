#ifndef BRE_INF_MT5_TRADE_EXECUTOR_MQH
#define BRE_INF_MT5_TRADE_EXECUTOR_MQH

#include <BasketRecovery/Application/Execution/Ports/ITradeExecutor.mqh>
#include <BasketRecovery/Application/Execution/ExecutionDryRunGate.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedTradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5TradeRequestTranslator.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5RequestValidationPolicy.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5TradeCheckResultMapper.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/IMt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5ExecutionDiagnostics.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionStatusTransition.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>

class CMt5TradeExecutor : public ITradeExecutor
  {
private:
   ENUM_BRE_EXECUTION_RUNTIME_MODE m_mode;
   IBasketRepository              *m_basketRepository;
   IMarketDataProvider            *m_marketDataProvider;
   IMt5OrderCheckGateway          *m_orderCheckGateway;
   CMt5ExecutionDiagnostics       *m_diagnostics;
   CExecutionPolicy                m_policy;
   CMt5TradeRequestTranslator      m_translator;
   CMt5RequestValidationPolicy     m_validationPolicy;
   CSimulatedTradeExecutor         m_simulatedExecutor;
   int                             m_executeCallCount;
   bool                            m_dryRunGateEnabled;

   void              AppendTransition(CTradeExecutionReceipt &receipt,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS fromStatus,
                                      const ENUM_BRE_TRADE_EXECUTION_STATUS toStatus,
                                      const datetime occurredAtUtc,
                                      const string detail)
     {
      receipt.AppendTransition(CExecutionStatusTransition::Create(fromStatus,toStatus,occurredAtUtc,detail));
      receipt.SetCurrentStatus(toStatus);
     }

   CResult<CTradeExecutionReceipt> BuildReceipt(const CTradeExecutionRequest &request,
                                                const CTradeExecutionResult &result,
                                                const ENUM_BRE_TRADE_EXECUTION_STATUS terminalStatus,
                                                const datetime nowUtc,
                                                const string transitionDetail)
     {
      CTradeExecutionReceipt receipt;
      receipt.SetRequest(request);
      receipt.SetCurrentStatus(BRE_TRADE_EXEC_STATUS_CREATED);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_NONE,BRE_TRADE_EXEC_STATUS_SUBMITTED,nowUtc,"mt5 executor submit");
      receipt.SetResult(result);
      AppendTransition(receipt,BRE_TRADE_EXEC_STATUS_SUBMITTED,terminalStatus,nowUtc,transitionDetail);
      return CResult<CTradeExecutionReceipt>::Ok(receipt);
     }

   long              ResolveMagic(const CBasketAggregate &basket) const
     {
      return (long)basket.ProfileSnapshot().Execution().MagicNumberBase();
     }

   CResult<CTradeExecutionReceipt> ExecuteDisabled(const CTradeExecutionRequest &request,const datetime nowUtc)
     {
      if(m_diagnostics!=NULL)
         m_diagnostics.OnExecutionDisabled("runtime mode DISABLED or dry-run gate closed");

      CTradeExecutionResult result=CExecutionDryRunGate::BuildDisabledRejection(nowUtc);
      return BuildReceipt(request,result,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"execution disabled");
     }

   CResult<CTradeExecutionReceipt> ExecuteDryRun(const CTradeExecutionRequest &request,const datetime nowUtc)
     {
      if(m_basketRepository==NULL)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Basket repository is not configured");

      if(m_orderCheckGateway==NULL)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"OrderCheck gateway is not configured");

      CResult<CBasketAggregate> loaded=m_basketRepository.Load(request.BasketId());
      if(loaded.IsFail())
        {
         CTradeExecutionResult result=CMt5TradeCheckResultMapper::MapLocalRejected(BRE_EXEC_FAIL_VALIDATION,
                                                                                   loaded.ErrorMessage(),
                                                                                   nowUtc,
                                                                                   request.RequestedVolume());
         return BuildReceipt(request,result,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"basket load failed");
        }

      CBasketAggregate basket;
      loaded.TryGetValue(basket);

      CResult<CTradeExecutionResult> validation=m_validationPolicy.ValidateBeforeOrderCheck(request,basket);
      if(validation.IsFail())
         return CResult<CTradeExecutionReceipt>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      CTradeExecutionResult validationValue;
      validation.TryGetValue(validationValue);
      if(validationValue.Status()==BRE_TRADE_EXEC_STATUS_REJECTED)
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnRejection(request,validationValue.Message());
         validationValue.SetCompletedAtUtc(nowUtc);
         validationValue.SetIsDryRun(true);
         return BuildReceipt(request,validationValue,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"local validation rejected");
        }

      if(m_marketDataProvider==NULL)
         return CResult<CTradeExecutionReceipt>::Fail(BRE_ERR_EXEC_REQUEST_INVALID,"Market data provider is not configured");

      CResult<CMarketQuote> quoteResult=m_marketDataProvider.TryGetQuote(request.Symbol());
      if(quoteResult.IsFail())
        {
         CTradeExecutionResult result=CMt5TradeCheckResultMapper::MapLocalRejected(BRE_EXEC_FAIL_MARKET_UNAVAILABLE,
                                                                                   quoteResult.ErrorMessage(),
                                                                                   nowUtc,
                                                                                   request.RequestedVolume());
         return BuildReceipt(request,result,BRE_TRADE_EXEC_STATUS_FAILED,nowUtc,"quote unavailable");
        }

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);

      CMt5RequestTranslationResult translation;
      if(!m_translator.TryTranslate(request,basket,ResolveMagic(basket),quote.Bid(),quote.Ask(),translation))
        {
         if(m_diagnostics!=NULL)
            m_diagnostics.OnTranslationFailed(request,translation.Message());
         CTradeExecutionResult result=CMt5TradeCheckResultMapper::MapLocalRejected(translation.FailureReason(),
                                                                                   translation.Message(),
                                                                                   nowUtc,
                                                                                   request.RequestedVolume());
         return BuildReceipt(request,result,BRE_TRADE_EXEC_STATUS_REJECTED,nowUtc,"translation failed");
        }

      if(m_diagnostics!=NULL)
         m_diagnostics.OnTranslationSucceeded(request,translation.Summary());

      MqlTradeRequest mt5Request=translation.Request();
      MqlTradeCheckResult checkResult;
      ZeroMemory(checkResult);
      if(m_diagnostics!=NULL)
         m_diagnostics.OnLocalValidationSucceeded(request);
      if(m_diagnostics!=NULL)
         m_diagnostics.OnOrderCheckInvoked(request);
      bool checkSucceeded=m_orderCheckGateway.Check(mt5Request,checkResult);

      CTradeExecutionResult mapped=CMt5TradeCheckResultMapper::MapOrderCheckOutcome(translation,checkSucceeded,checkResult,nowUtc);
      if(m_diagnostics!=NULL)
         m_diagnostics.OnOrderCheckResult(request,checkResult.retcode,checkResult.comment,
                                        mapped.Status()==BRE_TRADE_EXEC_STATUS_ACCEPTED);

      ENUM_BRE_TRADE_EXECUTION_STATUS terminal=mapped.Status();
      if(terminal==BRE_TRADE_EXEC_STATUS_NONE)
         terminal=BRE_TRADE_EXEC_STATUS_REJECTED;
      return BuildReceipt(request,mapped,terminal,nowUtc,"ordercheck dry-run complete");
     }

public:
                     CMt5TradeExecutor(void)
     {
      m_mode=BRE_EXEC_RUNTIME_DISABLED;
      m_basketRepository=NULL;
      m_marketDataProvider=NULL;
      m_orderCheckGateway=NULL;
      m_diagnostics=NULL;
      m_policy=CExecutionPolicy();
      m_translator=CMt5TradeRequestTranslator(m_policy);
      m_validationPolicy=CMt5RequestValidationPolicy(NULL,CMarketSafetyConfig());
      m_executeCallCount=0;
      m_dryRunGateEnabled=false;
     }

   void              Configure(const ENUM_BRE_EXECUTION_RUNTIME_MODE mode,
                               IBasketRepository *basketRepository,
                               IMarketDataProvider *marketDataProvider,
                               IMt5OrderCheckGateway *orderCheckGateway,
                               CMt5ExecutionDiagnostics *diagnostics,
                               const CMarketSafetyConfig &marketSafetyConfig,
                               const bool dryRunGateEnabled)
     {
      m_mode=mode;
      m_basketRepository=basketRepository;
      m_marketDataProvider=marketDataProvider;
      m_orderCheckGateway=orderCheckGateway;
      m_diagnostics=diagnostics;
      m_validationPolicy=CMt5RequestValidationPolicy(marketDataProvider,marketSafetyConfig);
      m_dryRunGateEnabled=dryRunGateEnabled;
     }

   ENUM_BRE_EXECUTION_RUNTIME_MODE Mode(void) const { return m_mode; }
   int               ExecuteCallCount(void) const { return m_executeCallCount; }

   bool              IsActive(void) const
     {
      return CExecutionDryRunGate::IsMt5DryRunExecutorActive(m_mode);
     }

   virtual CResult<CTradeExecutionReceipt> Execute(const CTradeExecutionRequest &request)
     {
      m_executeCallCount++;
      datetime nowUtc=request.RequestedAtUtc()>0 ? request.RequestedAtUtc() : TimeCurrent();

      if(m_mode==BRE_EXEC_RUNTIME_SIMULATED)
         return m_simulatedExecutor.Execute(request);

      if(m_mode!=BRE_EXEC_RUNTIME_MT5_DRY_RUN || !m_dryRunGateEnabled)
         return ExecuteDisabled(request,nowUtc);

      return ExecuteDryRun(request,nowUtc);
     }
  };

#endif
