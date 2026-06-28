#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/AccountExecutionEligibilityClassification.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionValidationService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/SimulatedBrokerSubmissionInjector.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationContext.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeTransactionResultCode.mqh>
#include <BasketRecovery/Domain/Execution/LiveSubmissionSafetyRejectionReason.mqh>

const long TEST_MAGIC=202606002;

class CDemoManualSubmissionTestHarness
  {
private:
   CSubmissionPreparationValidator *m_validator;

public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionStore          *pendingStore;
   CInMemoryExecutionAuthorizationStore    *authStore;
   CExecutionAuthorizationRegistry         *authRegistry;
   CDemoManualSubmissionTriggerRegistry    *triggerRegistry;
   CInMemoryAccountExecutionEligibilityProvider *eligibility;
   CTestClock                              *clock;
   CInMemoryMarketDataProvider             *marketData;
   CExecutionSubmissionPreparer            *preparer;
   CMockMt5AsyncOrderSendTransport         *mockTransport;
   CMt5AsyncSubmissionGateway              *asyncGateway;
   CSubmitPreparedExecutionUseCase         *submitUseCase;
   CDemoExecutionAuthorizationConfig       config;
   CDemoManualSubmissionService            *service;
   CTradeTransactionRouter                 *router;
   CPendingExecutionTestInjectionService   *injection;
   CSimulatedBrokerSubmissionInjector      *brokerInjector;
   CInMemoryPendingExecutionEventBuffer    *events;

                     CDemoManualSubmissionTestHarness(void)
     {
      m_validator=NULL;
      registry=new CPendingExecutionRegistry();
      pendingStore=new CInMemoryPendingExecutionStore();
      authStore=new CInMemoryExecutionAuthorizationStore();
      authRegistry=new CExecutionAuthorizationRegistry(authStore);
      triggerRegistry=new CDemoManualSubmissionTriggerRegistry();
      eligibility=new CInMemoryAccountExecutionEligibilityProvider();
      clock=new CTestClock();
      clock.SetNow(1000);
      marketData=new CInMemoryMarketDataProvider();
      marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      m_validator=new CSubmissionPreparationValidator(marketData,CMarketSafetyConfig());
      preparer=new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                                *m_validator,registry,pendingStore,clock);
      mockTransport=new CMockMt5AsyncOrderSendTransport();
      asyncGateway=new CMt5AsyncSubmissionGateway(mockTransport,NULL,10);
      submitUseCase=new CSubmitPreparedExecutionUseCase(registry,asyncGateway,pendingStore,clock,NULL);
      config=EnabledManualConfig();
      service=new CDemoManualSubmissionService(config,authRegistry,triggerRegistry,registry,pendingStore,
                                             eligibility,clock,submitUseCase,asyncGateway,CMarketSafetyConfig());
      events=new CInMemoryPendingExecutionEventBuffer(32);
      router=new CTradeTransactionRouter(registry,NULL,events,NULL,clock);
      injection=new CPendingExecutionTestInjectionService(registry,router);
      brokerInjector=new CSimulatedBrokerSubmissionInjector(registry,injection);
      SetDemoEligibility(true,true,true);
     }

                    ~CDemoManualSubmissionTestHarness(void)
     {
      if(brokerInjector!=NULL) delete brokerInjector;
      if(injection!=NULL) delete injection;
      if(router!=NULL) delete router;
      if(events!=NULL) delete events;
      if(service!=NULL) delete service;
      if(submitUseCase!=NULL) delete submitUseCase;
      if(asyncGateway!=NULL) delete asyncGateway;
      if(mockTransport!=NULL) delete mockTransport;
      if(preparer!=NULL) delete preparer;
      if(m_validator!=NULL) delete m_validator;
      if(marketData!=NULL) delete marketData;
      if(clock!=NULL) delete clock;
      if(eligibility!=NULL) delete eligibility;
      if(triggerRegistry!=NULL) delete triggerRegistry;
      if(authRegistry!=NULL) delete authRegistry;
      if(authStore!=NULL) delete authStore;
      if(pendingStore!=NULL) delete pendingStore;
      if(registry!=NULL) delete registry;
     }

   static CMarketQuote BuildFreshQuote(const string symbol,const double bid,const double ask,
                                       const int spreadPoints,const int ageMs)
     {
      return CMarketQuote::Create(symbol,bid,ask,spreadPoints,0.01,2,0.01,1.0,TimeCurrent(),ageMs,
                                  BRE_TRADING_SESSION_OPEN,
                                  CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
     }

   static CDemoExecutionAuthorizationConfig EnabledManualConfig(void)
     {
      CDemoExecutionAuthorizationConfig config;
      config.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION);
      config.SetEnableLiveDemoExecution(true);
      config.SetRequireManualDemoAuthorization(true);
      config.SetMaxAuthorizedRequestsPerSession(1);
      config.SetAuthorizationTokenExpirySeconds(300);
      config.SetMaxManualDemoOpenVolume(0.10);
      return config;
     }

   void              Reset(void)
     {
      registry.Clear();
      pendingStore.Clear();
      authStore.Clear();
      authRegistry.Clear();
      triggerRegistry.Clear();
      mockTransport.Reset();
      submitUseCase.ClearCache();
      clock.SetNow(1000);
      config=EnabledManualConfig();
      delete service;
      service=new CDemoManualSubmissionService(config,authRegistry,triggerRegistry,registry,pendingStore,
                                             eligibility,clock,submitUseCase,asyncGateway,CMarketSafetyConfig());
      SetDemoEligibility(true,true,true);
     }

   void              SetDemoEligibility(const bool demo,const bool terminalAllowed,const bool chartAllowed)
     {
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetClassification(demo ? BRE_ACCOUNT_ELIGIBILITY_DEMO : BRE_ACCOUNT_ELIGIBILITY_REAL);
      snapshot.SetAccountTradeAllowed(true);
      snapshot.SetTerminalTradeAllowed(terminalAllowed);
      snapshot.SetChartExpertTradeAllowed(chartAllowed);
      eligibility.SetSnapshot(snapshot);
     }

   CBasketAggregate  BuildBasket(const string basketIdValue)
     {
      CUtcTime boundAt(1000);
      string json=CStrategyProfileTestFixture::MinimalValidJson();
      CStrategyProfileJsonParser parser;
      CResult<CStrategyProfile> profileResult=parser.Parse(json,boundAt);
      CStrategyProfile profile;
      profileResult.TryGetValue(profile);
      CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,boundAt);
      CExecutionProfileConfig execution;
      execution.SetMagicNumberBase(TEST_MAGIC);
      CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                     CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                     execution,boundAt);
      CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                         "corr-"+basketIdValue,BRE_DIRECTION_BUY,"EURUSD",
                                                                         CSignalId("sig-"+basketIdValue),boundAt,
                                                                         CCommandId("cmd-create"),CEventId("evt-create"));
      CBasketAggregate basket;
      created.TryGetValue(basket);
      basket.SetLifecycleState(BRE_STATE_ACTIVE);
      return basket;
     }

   bool              Prepare(const string requestId,const string idem,const string basketIdValue,
                             CBasketAggregate &basket,CBrokerSubmissionEnvelope &envelope,
                             const ENUM_BRE_TRADE_EXECUTION_INTENT intent=BRE_EXEC_INTENT_OPEN_POSITION,
                             const double volume=0.05)
     {
      basket=BuildBasket(basketIdValue);
      CTradeExecutionRequest request=CTradeExecutionRequest::Create(requestId,idem,"corr",CBasketId(basketIdValue),1,
                                                                    basket.StrategyProfileHash(),"EURUSD",intent,
                                                                    BRE_DIRECTION_BUY,0,volume,0.0,0.0,0.0,1000,
                                                                    CCommandId("cmd"),"test");
      CSubmissionPreparationResult prep=preparer.Prepare(request,basket,TEST_MAGIC);
      if(!prep.IsSuccess())
         return false;
      envelope=prep.Envelope();
      return true;
     }

   string            IssueToken(const CPendingExecutionEntry &entry,const datetime expiryUtc)
     {
      string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(entry.ExecutionRequestId(),
                                                                                 entry.BasketId(),
                                                                                 entry.Symbol(),
                                                                                 entry.IntentType(),
                                                                                 entry.RequestedVolume(),
                                                                                 entry.ExpectedBasketVersion(),
                                                                                 entry.StrategyProfileHash());
      return CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiryUtc);
     }

   CDemoManualSubmissionResult SubmitPrepared(const string requestId,const string basketIdValue,
                                              const string token,const string triggerToken)
     {
      CBasketAggregate basket=BuildBasket(basketIdValue);
      CMarketQuote quote=BuildFreshQuote("EURUSD",1.0990,1.1000,10,0);
      return service.TrySubmit(requestId,token,triggerToken,basket,quote);
     }
  };

void TestDefaultModeRejects(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.config.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DISABLED);
   delete h.service;
   h.service=new CDemoManualSubmissionService(h.config,h.authRegistry,h.triggerRegistry,h.registry,h.pendingStore,
                                              h.eligibility,h.clock,h.submitUseCase,h.asyncGateway,CMarketSafetyConfig());
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-def","idem-def","b-def",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-def",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-def","b-def",token,"trigger-def");
   CTestAssert::False(result.IsSuccess(),"default mode rejects");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_LIVE_DISABLED,(int)result.RejectionReason(),"live disabled");
  }

void TestRealAccountRejected(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.SetDemoEligibility(false,true,true);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-real","idem-real","b-real",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-real",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-real","b-real",token,"trigger-real");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_ACCOUNT_NOT_DEMO,(int)result.RejectionReason(),"real account rejected");
  }

void TestOnlyOpenPositionAllowed(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-close","idem-close","b-close",basket,envelope,BRE_EXEC_INTENT_CLOSE_POSITION,0.05),
                     "prepare close");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-close",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-close","b-close",token,"trigger-close");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_INTENT_NOT_ALLOWED,(int)result.RejectionReason(),"close intent rejected");
  }

void TestMaxVolumeEnforced(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-vol","idem-vol","b-vol",basket,envelope,BRE_EXEC_INTENT_OPEN_POSITION,0.50),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-vol",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-vol","b-vol",token,"trigger-vol");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_VOLUME_EXCEEDS_DEMO_MAX,(int)result.RejectionReason(),"max volume");
  }

void TestFalseOrderSendAsyncNotSubmitted(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(false,TRADE_RETCODE_REJECT,10006,0);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-fail","idem-fail","b-fail",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-fail",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-fail","b-fail",token,"trigger-fail");
   CTestAssert::False(result.IsSuccess(),"submit rejected");
   CTestAssert::True(result.BrokerInvoked(),"broker attempted");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)result.ResultingStatus(),"rejected status");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-fail",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)updated.Status(),"not submitted");
  }

void TestAcceptedOrderSendAsyncSubmittedNotFilled(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910100);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-ok","idem-ok","b-ok",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-ok",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-ok","b-ok",token,"trigger-ok");
   CTestAssert::True(result.IsSuccess(),"submit accepted");
   CTestAssert::True(result.OrderSendAsyncAccepted(),"async accepted");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-ok",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)updated.Status(),"submitted only");
   CTestAssert::False(updated.Status()==BRE_TRADE_EXEC_STATUS_FILLED,"not filled");
  }

void TestTriggerOneShot(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910101);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-trg","idem-trg","b-trg",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-trg",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CTestAssert::True(h.SubmitPrepared("req-trg","b-trg",token,"trigger-one").IsSuccess(),"first trigger");
   CDemoManualSubmissionResult second=h.SubmitPrepared("req-trg","b-trg",token,"trigger-one");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_TRIGGER_TOKEN_CONSUMED,(int)second.RejectionReason(),"trigger consumed");
  }

void TestTokenConsumedOnSubmissionAttempt(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910102);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-tok","idem-tok","b-tok",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-tok",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   string tokenHash=CExecutionAuthorizationToken::ComputeTokenHash(token);
   CTestAssert::False(h.authRegistry.IsTokenConsumed(tokenHash),"token not consumed before submit");
   CDemoManualSubmissionResult result=h.SubmitPrepared("req-tok","b-tok",token,"trigger-tok");
   CTestAssert::True(result.AuthTokenConsumed(),"token consumed after attempt");
   CTestAssert::True(h.authRegistry.IsTokenConsumed(tokenHash),"token consumed in registry");
  }

void TestSessionCapBlocksSecondOrder(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910103);
   CBrokerSubmissionEnvelope envelope1;
   CBasketAggregate basket1;
   CTestAssert::True(h.Prepare("req-cap1","idem-cap1","b-cap1",basket1,envelope1),"prepare1");
   CPendingExecutionEntry entry1;
   h.registry.TryGetByExecutionRequestId("req-cap1",entry1);
   string token1=h.IssueToken(entry1,h.clock.Now()+300);
   CTestAssert::True(h.SubmitPrepared("req-cap1","b-cap1",token1,"trigger-cap1").IsSuccess(),"first order");

   CBrokerSubmissionEnvelope envelope2;
   CBasketAggregate basket2;
   CTestAssert::True(h.Prepare("req-cap2","idem-cap2","b-cap2",basket2,envelope2),"prepare2");
   CPendingExecutionEntry entry2;
   h.registry.TryGetByExecutionRequestId("req-cap2",entry2);
   string token2=h.IssueToken(entry2,h.clock.Now()+300);
   CDemoManualSubmissionResult second=h.SubmitPrepared("req-cap2","b-cap2",token2,"trigger-cap2");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_SUBMISSION_SESSION_CAP,(int)second.RejectionReason(),"session cap");
  }

void TestStaleQuoteBlocks(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-stale","idem-stale","b-stale",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-stale",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CMarketQuote staleQuote=CDemoManualSubmissionTestHarness::BuildFreshQuote("EURUSD",1.0990,1.1000,10,6000);
   CDemoManualSubmissionResult result=h.service.TrySubmit("req-stale",token,"trigger-stale",basket,staleQuote);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_STALE_QUOTE,(int)result.RejectionReason(),"stale quote");
   CTestAssert::EqualInt(0,h.mockTransport.CallCount(),"no broker call");
  }

void TestManualRouteIsolation(CDemoManualSubmissionTestHarness &h)
  {
   CApplicationContext context;
   CDemoManualSubmissionValidationService validationService;
   CTestAssert::False(context.IsDemoManualSubmissionWiredToStrategy(),"not strategy");
   CTestAssert::False(context.IsDemoManualSubmissionWiredToAutomaticTimer(),"not auto timer");
   CTestAssert::False(context.IsDemoManualSubmissionWiredToRestIntake(),"not REST");
   CTestAssert::False(context.IsDemoManualSubmissionWiredToOnTick(),"not OnTick");
   CTestAssert::False(context.IsDemoManualSubmissionWiredToOnTradeTransaction(),"not OnTradeTransaction");
   CTestAssert::False(context.IsLiveSubmissionApiWiredToProductionRuntime(),"not production auto");
   CTestAssert::False(validationService.IsWiredToStrategyEngine(),"validation isolated");
  }

void TestRouterResolvesInjectedTransaction(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910200);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-rtr","idem-rtr","b-rtr",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-rtr",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CTestAssert::True(h.SubmitPrepared("req-rtr","b-rtr",token,"trigger-rtr").IsSuccess(),"submit");
   h.registry.TryGetByExecutionRequestId("req-rtr",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,
                         (int)h.brokerInjector.InjectAcknowledgement("req-rtr",910200,TEST_MAGIC),"inject ack");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-rtr",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,(int)updated.Status(),"acknowledged via router");
  }

void TestMockTransportIsOnlyBrokerCall(CDemoManualSubmissionTestHarness &h)
  {
   h.Reset();
   h.mockTransport.SetNextAccepted(true,TRADE_RETCODE_PLACED,0,910300);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-mock","idem-mock","b-mock",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-mock",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   h.SubmitPrepared("req-mock","b-mock",token,"trigger-mock");
   CTestAssert::EqualInt(1,h.mockTransport.CallCount(),"single broker transport call");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CDemoManualSubmissionTestHarness harness;

   TestDefaultModeRejects(harness);
   TestRealAccountRejected(harness);
   TestOnlyOpenPositionAllowed(harness);
   TestMaxVolumeEnforced(harness);
   TestFalseOrderSendAsyncNotSubmitted(harness);
   TestAcceptedOrderSendAsyncSubmittedNotFilled(harness);
   TestTriggerOneShot(harness);
   TestTokenConsumedOnSubmissionAttempt(harness);
   TestSessionCapBlocksSecondOrder(harness);
   TestStaleQuoteBlocks(harness);
   TestManualRouteIsolation(harness);
   TestRouterResolvesInjectedTransaction(harness);
   TestMockTransportIsOnlyBrokerCall(harness);

   CTestAssert::Summary("TestManualDemoOrderSendAsyncSubmission");
   if(!CTestAssert::AllPassed())
      Print("TestManualDemoOrderSendAsyncSubmission FAILED");
  }
