#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationStatus.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/AccountExecutionEligibilityClassification.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationUseCase.mqh>
#include <BasketRecovery/Application/Execution/ManualDemoAuthorizationValidationService.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationPolicy.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationContext.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>

const long TEST_MAGIC=202606001;

class CDemoAuthorizationTestHarness
  {
private:
   CSubmissionPreparationValidator         *m_validator;

public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionStore          *pendingStore;
   CInMemoryExecutionAuthorizationStore    *authStore;
   CExecutionAuthorizationRegistry         *authRegistry;
   CInMemoryAccountExecutionEligibilityProvider *eligibility;
   CTestClock                              *clock;
   CInMemoryMarketDataProvider             *marketData;
   CExecutionSubmissionPreparer            *preparer;
   CDemoExecutionAuthorizationConfig       config;
   CManualDemoAuthorizationUseCase         *useCase;
   CManualDemoAuthorizationValidationService *validationService;

                     CDemoAuthorizationTestHarness(void)
     {
      m_validator=NULL;
      registry=new CPendingExecutionRegistry();
      pendingStore=new CInMemoryPendingExecutionStore();
      authStore=new CInMemoryExecutionAuthorizationStore();
      authRegistry=new CExecutionAuthorizationRegistry(authStore);
      eligibility=new CInMemoryAccountExecutionEligibilityProvider();
      clock=new CTestClock();
      clock.SetNow(1000);
      marketData=new CInMemoryMarketDataProvider();
      marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      m_validator=new CSubmissionPreparationValidator(marketData,CMarketSafetyConfig());
      preparer=new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                                *m_validator,registry,pendingStore,clock);
      config=EnabledDemoConfig();
      useCase=new CManualDemoAuthorizationUseCase(config,authRegistry,registry,pendingStore,eligibility,clock,
                                                  CMarketSafetyConfig());
      validationService=new CManualDemoAuthorizationValidationService();
      validationService.Configure(config,useCase,NULL,marketData);
     }

                    ~CDemoAuthorizationTestHarness(void)
     {
      if(validationService!=NULL) delete validationService;
      if(useCase!=NULL) delete useCase;
      if(preparer!=NULL) delete preparer;
      if(m_validator!=NULL) delete m_validator;
      if(marketData!=NULL) delete marketData;
      if(clock!=NULL) delete clock;
      if(eligibility!=NULL) delete eligibility;
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

   static CDemoExecutionAuthorizationConfig EnabledDemoConfig(void)
     {
      CDemoExecutionAuthorizationConfig config;
      config.SetExecutionRuntimeMode(BRE_EXEC_RUNTIME_DEMO_AUTHORIZATION);
      config.SetEnableLiveDemoExecution(true);
      config.SetRequireManualDemoAuthorization(true);
      config.SetMaxAuthorizedRequestsPerSession(2);
      config.SetAuthorizationTokenExpirySeconds(300);
      return config;
     }

   void              Reset(void)
     {
      registry.Clear();
      pendingStore.Clear();
      authStore.Clear();
      authRegistry.Clear();
      clock.SetNow(1000);
      config=EnabledDemoConfig();
      delete useCase;
      useCase=new CManualDemoAuthorizationUseCase(config,authRegistry,registry,pendingStore,eligibility,clock,
                                                  CMarketSafetyConfig());
      validationService.Configure(config,useCase,NULL,marketData);
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

   void              SetRealAccount(void)
     {
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_REAL);
      snapshot.SetAccountTradeAllowed(true);
      snapshot.SetTerminalTradeAllowed(true);
      snapshot.SetChartExpertTradeAllowed(true);
      eligibility.SetSnapshot(snapshot);
     }

   void              SetUnknownAccount(void)
     {
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_UNKNOWN);
      eligibility.SetSnapshot(snapshot);
     }

   CBasketAggregate  BuildBasket(const string basketIdValue,const string profileHash="hash")
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
                             CBasketAggregate &basket,CBrokerSubmissionEnvelope &envelope,const double volume=0.10)
     {
      basket=BuildBasket(basketIdValue);
      CTradeExecutionRequest request=CTradeExecutionRequest::Create(requestId,idem,"corr",CBasketId(basketIdValue),1,
                                                                    basket.StrategyProfileHash(),"EURUSD",
                                                                    BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                    volume,0.0,0.0,0.0,1000,CCommandId("cmd"),"test");
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

   CExecutionAuthorizationResult AuthorizePrepared(const string requestId,const string basketIdValue,const string token)
     {
      CBasketAggregate basket=BuildBasket(basketIdValue);
      CMarketQuote quote=BuildFreshQuote("EURUSD",1.0990,1.1000,10,0);
      return useCase.Authorize(requestId,token,basket,quote);
     }
  };

void TestDefaultRuntimeRejects(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.config.ApplyDefaultOff();
   delete h.useCase;
   h.useCase=new CManualDemoAuthorizationUseCase(h.config,h.authRegistry,h.registry,h.pendingStore,h.eligibility,h.clock,
                                                 CMarketSafetyConfig());
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-def","idem-def","b-def",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-def",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-def","b-def",token);
   CTestAssert::False(result.IsSuccess(),"default runtime must reject");
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_LIVE_DISABLED,(int)result.RejectionReason(),"live disabled reason");
  }

void TestDemoAccountPasses(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.SetDemoEligibility(true,true,true);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-demo","idem-demo","b-demo",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-demo",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-demo","b-demo",token);
   CTestAssert::True(result.IsSuccess(),"demo eligibility must authorize");
  }

void TestRealAccountRejected(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.SetRealAccount();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-real","idem-real","b-real",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-real",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-real","b-real",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_ACCOUNT_NOT_DEMO,(int)result.RejectionReason(),"real account rejected");
  }

void TestUnknownAccountRejected(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.SetUnknownAccount();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-unk","idem-unk","b-unk",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-unk",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-unk","b-unk",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_ACCOUNT_UNKNOWN,(int)result.RejectionReason(),"unknown account rejected");
  }

void TestTokenBindingMismatch(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-bind","idem-bind","b-bind",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-bind",entry);
   string wrongToken=CExecutionAuthorizationToken::IssuePlaintextToken("WRONGFP01",h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-bind","b-bind",wrongToken);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_TOKEN_BINDING_MISMATCH,(int)result.RejectionReason(),"binding mismatch");
  }

void TestTokenCannotBeReused(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-reuse","idem-reuse","b-reuse",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-reuse",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CTestAssert::True(h.AuthorizePrepared("req-reuse","b-reuse",token).IsSuccess(),"first authorize");
   CExecutionAuthorizationResult second=h.AuthorizePrepared("req-reuse","b-reuse",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_TOKEN_CONSUMED,(int)second.RejectionReason(),"token consumed");
  }

void TestExpiredTokenRejected(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-exp","idem-exp","b-exp",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-exp",entry);
   string token=h.IssueToken(entry,h.clock.Now()-1);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-exp","b-exp",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_TOKEN_EXPIRED,(int)result.RejectionReason(),"expired token");
  }

void TestGlobalKillSwitch(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.config.SetGlobalExecutionKillSwitch(true);
   delete h.useCase;
   h.useCase=new CManualDemoAuthorizationUseCase(h.config,h.authRegistry,h.registry,h.pendingStore,h.eligibility,h.clock,
                                                 CMarketSafetyConfig());
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-gks","idem-gks","b-gks",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-gks",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-gks","b-gks",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_GLOBAL_KILL_SWITCH,(int)result.RejectionReason(),"global kill switch");
  }

void TestBasketKillSwitch(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.config.SetBasketExecutionKillSwitch(true);
   h.config.SetBasketExecutionKillSwitchBasketId("b-bks");
   delete h.useCase;
   h.useCase=new CManualDemoAuthorizationUseCase(h.config,h.authRegistry,h.registry,h.pendingStore,h.eligibility,h.clock,
                                                 CMarketSafetyConfig());
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-bks","idem-bks","b-bks",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-bks",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-bks","b-bks",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_BASKET_KILL_SWITCH,(int)result.RejectionReason(),"basket kill switch");
  }

void TestStaleQuoteAndWideSpreadReject(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.marketData.SetQuote(CDemoAuthorizationTestHarness::BuildFreshQuote("EURUSD",1.0990,1.1000,600,6000));
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-stale","idem-stale","b-stale",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-stale",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult stale=h.AuthorizePrepared("req-stale","b-stale",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_STALE_QUOTE,(int)stale.RejectionReason(),"stale quote");

   h.Reset();
   h.marketData.SetQuote(CDemoAuthorizationTestHarness::BuildFreshQuote("EURUSD",1.0990,1.1000,600,0));
   CTestAssert::True(h.Prepare("req-spread","idem-spread","b-spread",basket,envelope),"prepare");
   h.registry.TryGetByExecutionRequestId("req-spread",entry);
   token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult spread=h.AuthorizePrepared("req-spread","b-spread",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_WIDE_SPREAD,(int)spread.RejectionReason(),"wide spread");
  }

void TestExpiredEnvelopeRejects(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-env","idem-env","b-env",basket,envelope),"prepare");
   h.clock.SetNow(envelope.ExpirationUtc()+1);
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-env",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-env","b-env",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_ENVELOPE_EXPIRED,(int)result.RejectionReason(),"expired envelope");
  }

void TestReconcilingBlocksBasket(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry blocker;
   blocker.SetExecutionRequestId("req-block");
   blocker.SetBasketId(CBasketId("b-rec"));
   blocker.SetStatus(BRE_TRADE_EXEC_STATUS_RECONCILING);
   h.registry.Register(blocker);
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-rec","idem-rec","b-rec",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-rec",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-rec","b-rec",token);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_BASKET_RECONCILING_BLOCK,(int)result.RejectionReason(),"reconciling block");
  }

void TestSessionCapEnforced(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   h.config.SetMaxAuthorizedRequestsPerSession(1);
   delete h.useCase;
   h.useCase=new CManualDemoAuthorizationUseCase(h.config,h.authRegistry,h.registry,h.pendingStore,h.eligibility,h.clock,
                                                 CMarketSafetyConfig());
   CBrokerSubmissionEnvelope envelope1;
   CBasketAggregate basket1;
   CTestAssert::True(h.Prepare("req-cap1","idem-cap1","b-cap1",basket1,envelope1),"prepare1");
   CPendingExecutionEntry entry1;
   h.registry.TryGetByExecutionRequestId("req-cap1",entry1);
   string token1=h.IssueToken(entry1,h.clock.Now()+300);
   CTestAssert::True(h.AuthorizePrepared("req-cap1","b-cap1",token1).IsSuccess(),"first cap slot");

   CBrokerSubmissionEnvelope envelope2;
   CBasketAggregate basket2;
   CTestAssert::True(h.Prepare("req-cap2","idem-cap2","b-cap2",basket2,envelope2),"prepare2");
   CPendingExecutionEntry entry2;
   h.registry.TryGetByExecutionRequestId("req-cap2",entry2);
   string token2=h.IssueToken(entry2,h.clock.Now()+300);
   CExecutionAuthorizationResult second=h.AuthorizePrepared("req-cap2","b-cap2",token2);
   CTestAssert::EqualInt((int)BRE_LIVE_SAFETY_SESSION_CAP_EXCEEDED,(int)second.RejectionReason(),"session cap");
  }

void TestSuccessfulAuthorizationStatus(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-ok","idem-ok","b-ok",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-ok",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CExecutionAuthorizationResult result=h.AuthorizePrepared("req-ok","b-ok",token);
   CTestAssert::True(result.IsSuccess(),"authorize success");
   CTestAssert::EqualInt((int)BRE_AUTH_STATUS_AUTHORIZED_FOR_FUTURE_SUBMISSION,(int)result.Status(),"future submission status");
   CTestAssert::False(result.BrokerInvoked(),"no broker invocation");
   CTestAssert::True(result.TokenConsumed(),"token consumed once");
  }

void TestRestartPreservesConsumedToken(CDemoAuthorizationTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CBasketAggregate basket;
   CTestAssert::True(h.Prepare("req-rst","idem-rst","b-rst",basket,envelope),"prepare");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-rst",entry);
   string token=h.IssueToken(entry,h.clock.Now()+300);
   CTestAssert::True(h.AuthorizePrepared("req-rst","b-rst",token).IsSuccess(),"authorize before restart");

   string exported=h.authStore.ExportText();
   CInMemoryExecutionAuthorizationStore *newStore=new CInMemoryExecutionAuthorizationStore();
   newStore.ImportText(exported);
   CExecutionAuthorizationRegistry restoredRegistry(newStore);
   restoredRegistry.RestoreFromStore();
   string tokenHash=CExecutionAuthorizationToken::ComputeTokenHash(token);
   CTestAssert::True(restoredRegistry.IsTokenConsumed(tokenHash),"consumed token persists after restart");
   delete newStore;
  }

void TestManualRouteIsolation(CDemoAuthorizationTestHarness &h)
  {
   CApplicationContext context;
   CTestAssert::False(context.IsDemoAuthorizationWiredToStrategy(),"not wired to strategy");
   CTestAssert::False(context.IsDemoAuthorizationWiredToAutomaticTimer(),"not wired to automatic timer");
   CTestAssert::False(context.IsDemoAuthorizationWiredToRestIntake(),"not wired to REST");
   CTestAssert::False(context.IsDemoAuthorizationWiredToOnTick(),"not wired to OnTick");
   CTestAssert::False(context.IsLiveSubmissionApiWiredToProductionRuntime(),"no live submission api");
   CTestAssert::False(h.validationService.IsWiredToStrategyEngine(),"validation service isolated");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CDemoAuthorizationTestHarness harness;

   TestDefaultRuntimeRejects(harness);
   TestDemoAccountPasses(harness);
   TestRealAccountRejected(harness);
   TestUnknownAccountRejected(harness);
   TestTokenBindingMismatch(harness);
   TestTokenCannotBeReused(harness);
   TestExpiredTokenRejected(harness);
   TestGlobalKillSwitch(harness);
   TestBasketKillSwitch(harness);
   TestStaleQuoteAndWideSpreadReject(harness);
   TestExpiredEnvelopeRejects(harness);
   TestReconcilingBlocksBasket(harness);
   TestSessionCapEnforced(harness);
   TestSuccessfulAuthorizationStatus(harness);
   TestRestartPreservesConsumedToken(harness);
   TestManualRouteIsolation(harness);

   CTestAssert::Summary("TestLiveSubmissionSafetyAndDemoAuthorization");
   if(!CTestAssert::AllPassed())
      Print("TestLiveSubmissionSafetyAndDemoAuthorization FAILED");
  }
