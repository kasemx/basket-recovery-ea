#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackManualTestOrchestrator.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionBridge.mqh>
#include <BasketRecovery/Application/Strategy/FastTrack/FastTrackDemoSubmissionAuthorizationBinder.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionRuntimeMode.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>
#include <BasketRecovery/Domain/Execution/DemoManualSubmissionResult.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionValidationService.mqh>
#include <BasketRecovery/Application/Execution/DemoManualSubmissionTriggerRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionAuthorizationRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionAuthorizationStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryAccountExecutionEligibilityProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5AsyncSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5AsyncOrderSendTransport.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>

const string SEED_SELL="Gold sell now";
const string SEED_BUY="Gold buy now";
const string DETAILS_SELL_VALID=
   "Gold sell now 4014 - 4017\n"
   "SL: 4020\n"
   "TP: 4007\n"
   "TP: 4005\n";
const string DETAILS_BUY_VALID=
   "Gold buy now 2400 - 2403\n"
   "SL: 2390\n"
   "TP: 2410\n";
const string DETAILS_SELL_NO_SL=
   "Gold sell now 4014 - 4017\n"
   "TP: 4007\n";
const string DETAILS_SELL_NO_TP=
   "Gold sell now 4014 - 4017\n"
   "SL: 4020\n";
const string DETAILS_SELL_HIGH_RISK=
   "Gold sell now 4014 - 4017\n"
   "SL: 4077\n"
   "TP: 4007\n";
const string TEST_BASKET_ID="sprint9e-d0e-justgold-xauusd-001";
const long   TEST_MAGIC=91001;

SFastTrackManualTestInputs BuildManualInputs(const string seedText,const string detailsText)
  {
   SFastTrackManualTestInputs inputs;
   inputs.enabled=true;
   inputs.seed_text=seedText;
   inputs.details_text=detailsText;
   inputs.seed_lot=0.01;
   inputs.seed_order_count=1;
   inputs.allow_demo_seed_execution=true;
   inputs.enable_recovery=false;
   inputs.enable_range_add=false;
   inputs.enable_de_risk=false;
   inputs.enable_break_even=false;
   inputs.observer_only_startup_isolation=false;
   inputs.global_execution_kill_switch=false;
   inputs.enable_live_demo_execution=true;
   inputs.execution_mode=(int)BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION;
   return inputs;
  }

SFastTrackDemoSubmissionEnvironment BuildValidEnvironment(void)
  {
   SFastTrackDemoSubmissionEnvironment environment;
   environment.Reset();
   environment.account_is_demo=true;
   environment.require_manual_demo_authorization=true;
   environment.audit_file_polling_enabled=true;
   environment.account_equity_usd=10000.0;
   environment.symbol_bid=4015.0;
   environment.symbol_ask=4015.5;
   environment.symbol_point=0.01;
   environment.symbol_tick_size=0.01;
   environment.symbol_tick_value=1.0;
   environment.symbol_stops_level=20;
   environment.symbol_freeze_level=0;
   environment.symbol_min_lot=0.01;
   environment.symbol_volume_step=0.01;
   environment.open_positions_for_symbol=0;
   environment.pending_orders_for_symbol=0;
   return environment;
  }

SFastTrackDemoSubmissionBridgeInputs BuildBridgeInputs(const SFastTrackDemoSubmissionEnvironment &environment)
  {
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs;
   bridgeInputs.Reset();
   bridgeInputs.enabled=true;
   bridgeInputs.require_manual_demo_authorization=true;
   bridgeInputs.audit_file_polling_enabled=true;
   bridgeInputs.allow_demo_seed_execution=true;
   bridgeInputs.observer_only_startup_isolation=false;
   bridgeInputs.global_execution_kill_switch=false;
   bridgeInputs.enable_live_demo_execution=true;
   bridgeInputs.execution_mode=(int)BRE_EXEC_RUNTIME_DEMO_MANUAL_SUBMISSION;
   bridgeInputs.seed_lot=0.01;
   bridgeInputs.seed_order_count=1;
   bridgeInputs.magic_number_override=TEST_MAGIC;
   bridgeInputs.manual_demo_authorization_basket_id=TEST_BASKET_ID;
   bridgeInputs.route_label="justgold-dashboard-route";
   bridgeInputs.target_label="d0e-vantage-xauusd-demo";
   bridgeInputs.environment=environment;
   return bridgeInputs;
  }

SFastTrackManualTestOutcome RunOrchestratorAllowed(const string seedText,const string detailsText)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildManualInputs(seedText,detailsText);
   return orchestrator.Process(inputs,1000);
  }

SFastTrackDemoSubmissionBridgeOutcome RunBridge(const string seedText,
                                                  const string detailsText,
                                                  CFastTrackDemoSubmissionCandidateRegistry &registry,
                                                  const SFastTrackDemoSubmissionBridgeInputs &bridgeInputs)
  {
   SFastTrackManualTestInputs inputs=BuildManualInputs(seedText,detailsText);
   SFastTrackManualTestOutcome manualOutcome=RunOrchestratorAllowed(seedText,detailsText);
   return CFastTrackDemoSubmissionBridge::TryCreateCandidate(inputs,manualOutcome,bridgeInputs,registry,1000);
  }

void TestValidSellCandidateCreated(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::True(outcome.candidate_created,"Valid SELL plan must create candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_CANDIDATE_CREATED,(int)outcome.status,
                         "Valid SELL status");
   CTestAssert::EqualString(TEST_BASKET_ID,outcome.candidate.basket_id,"Basket id");
   CTestAssert::EqualInt((int)BRE_DIRECTION_SELL,(int)outcome.candidate.direction,"SELL direction");
   CTestAssert::EqualInt(TEST_MAGIC,(int)outcome.candidate.magic_number,"Magic 91001");
  }

void TestValidBuyCandidateCreated(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionEnvironment environment=BuildValidEnvironment();
   environment.symbol_bid=2400.0;
   environment.symbol_ask=2400.5;
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(environment);
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_BUY,DETAILS_BUY_VALID,registry,bridgeInputs);
   CTestAssert::True(outcome.candidate_created,"Valid BUY plan must create candidate");
   CTestAssert::EqualInt((int)BRE_DIRECTION_BUY,(int)outcome.candidate.direction,"BUY direction");
  }

void TestMissingSlBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_NO_SL,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Missing SL must block candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_SLTP_INVALID,(int)outcome.status,
                         "Missing SL status");
  }

void TestMissingTpBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_NO_TP,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Missing TP must block candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_SLTP_INVALID,(int)outcome.status,
                         "Missing TP status");
  }

void TestStopsLevelViolationBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionEnvironment environment=BuildValidEnvironment();
   environment.symbol_stops_level=5000;
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(environment);
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Stops level violation must block candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_SLTP_INVALID,(int)outcome.status,
                         "Stops level status");
  }

void TestRiskLimitBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_HIGH_RISK,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Risk limit must block candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_RISK_BLOCKED,(int)outcome.status,
                         "Risk blocked status");
  }

void TestNonDemoAccountBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionEnvironment environment=BuildValidEnvironment();
   environment.account_is_demo=false;
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(environment);
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Non-demo account must block candidate");
   CTestAssert::EqualString("ACCOUNT_NOT_DEMO",outcome.block_reason,"Non-demo reason");
  }

void TestObserverIsolationBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   bridgeInputs.observer_only_startup_isolation=true;
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Observer isolation must block candidate");
  }

void TestKillSwitchBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   bridgeInputs.global_execution_kill_switch=true;
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Kill switch must block candidate");
  }

void TestRecoveryFlagBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   bridgeInputs.enable_recovery=true;
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Recovery flag must block candidate");
  }

void TestOpenExposureBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionEnvironment environment=BuildValidEnvironment();
   environment.open_positions_for_symbol=1;
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(environment);
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Open position must block candidate");
  }

void TestDuplicateIdempotencyBlocksSecondCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome first=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::True(first.candidate_created,"First candidate must be created");
   SFastTrackManualTestInputs inputs=BuildManualInputs(SEED_SELL,DETAILS_SELL_VALID);
   SFastTrackManualTestOutcome manualOutcome=RunOrchestratorAllowed(SEED_SELL,DETAILS_SELL_VALID);
   SFastTrackDemoSubmissionBridgeOutcome second=CFastTrackDemoSubmissionBridge::TryCreateCandidate(
      inputs,manualOutcome,bridgeInputs,registry,1001);
   CTestAssert::False(second.candidate_created,"Duplicate idempotency must block second candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_DUP_BLOCKED,(int)second.status,
                         "Duplicate status");
  }

void TestMultiTpUsesFirstBrokerTarget(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::True(outcome.candidate_created,"Multi TP candidate must be created");
   CTestAssert::True(MathAbs(outcome.candidate.broker_take_profit-4007.0)<0.0001,"First TP must be broker TP");
   CTestAssert::EqualInt(1,outcome.candidate.additional_tp_count,"One additional TP expected");
   CTestAssert::True(StringFind(outcome.candidate.broker_tp_note,"First TP")>=0,"Broker TP note expected");
  }

void TestCandidateDoesNotContainRawTelegram(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   const string rawSeed="Gold sell now";
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(rawSeed,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::True(outcome.candidate_created,"Candidate required for telegram leak test");
   CTestAssert::True(StringFind(outcome.candidate.execution_request_id,rawSeed)<0,"Seed text must not leak");
   CTestAssert::True(StringFind(outcome.candidate.idempotency_key,"Telegram")<0,"Telegram label must not leak");
  }

void TestMagic91001InCandidateMetadata(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::EqualInt(91001,(int)outcome.candidate.magic_number,"Magic must be 91001");
  }

void TestMagicMissingBlocksCandidate(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeInputs bridgeInputs=BuildBridgeInputs(BuildValidEnvironment());
   bridgeInputs.magic_number_override=0;
   SFastTrackDemoSubmissionBridgeOutcome outcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,bridgeInputs);
   CTestAssert::False(outcome.candidate_created,"Missing magic must block candidate");
   CTestAssert::EqualInt((int)BRE_FT_DEMO_SUB_MAGIC_REQUIRED,(int)outcome.status,
                         "Magic configuration status");
  }

class CDemoSubmissionAuthHarness
  {
public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionStore          *pendingStore;
   CInMemoryExecutionAuthorizationStore    *authStore;
   CExecutionAuthorizationRegistry         *authRegistry;
   CDemoManualSubmissionTriggerRegistry    *triggerRegistry;
   CInMemoryAccountExecutionEligibilityProvider *eligibility;
   CTestClock                              *clock;
   CInMemoryMarketDataProvider             *marketData;
   CSubmissionPreparationValidator         *validator;
   CExecutionSubmissionPreparer            *preparer;
   CMockMt5AsyncOrderSendTransport         *mockTransport;
   CMt5AsyncSubmissionGateway              *asyncGateway;
   CSubmitPreparedExecutionUseCase         *submitUseCase;
   CDemoExecutionAuthorizationConfig       config;
   CDemoManualSubmissionService            *service;
   CInMemoryBasketRepository               *basketRepository;
   CDemoManualSubmissionValidationService  *validationService;

                     CDemoSubmissionAuthHarness(void)
     {
      registry=new CPendingExecutionRegistry();
      pendingStore=new CInMemoryPendingExecutionStore();
      authStore=new CInMemoryExecutionAuthorizationStore();
      authRegistry=new CExecutionAuthorizationRegistry(authStore);
      triggerRegistry=new CDemoManualSubmissionTriggerRegistry();
      eligibility=new CInMemoryAccountExecutionEligibilityProvider();
      clock=new CTestClock();
      clock.SetNow(1000);
      marketData=new CInMemoryMarketDataProvider();
      marketData.SetQuote(BuildQuote("XAUUSD",4015.0,4015.5));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      validator=new CSubmissionPreparationValidator(marketData,CMarketSafetyConfig());
      preparer=new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                                *validator,registry,pendingStore,clock);
      mockTransport=new CMockMt5AsyncOrderSendTransport();
      asyncGateway=new CMt5AsyncSubmissionGateway(mockTransport,NULL,10);
      submitUseCase=new CSubmitPreparedExecutionUseCase(registry,asyncGateway,pendingStore,clock,NULL);
      config=EnabledManualConfig();
      service=new CDemoManualSubmissionService(config,authRegistry,triggerRegistry,registry,pendingStore,
                                               eligibility,clock,submitUseCase,asyncGateway,CMarketSafetyConfig());
      basketRepository=new CInMemoryBasketRepository();
      validationService=new CDemoManualSubmissionValidationService();
      validationService.Configure(config,service,basketRepository,marketData,NULL);
      CAccountExecutionEligibilitySnapshot snapshot;
      snapshot.SetClassification(BRE_ACCOUNT_ELIGIBILITY_DEMO);
      snapshot.SetAccountTradeAllowed(true);
      snapshot.SetTerminalTradeAllowed(true);
      snapshot.SetChartExpertTradeAllowed(true);
      eligibility.SetSnapshot(snapshot);
     }

                    ~CDemoSubmissionAuthHarness(void)
     {
      delete validationService;
      delete basketRepository;
      delete service;
      delete submitUseCase;
      delete asyncGateway;
      delete mockTransport;
      delete preparer;
      delete validator;
      delete marketData;
      delete clock;
      delete eligibility;
      delete triggerRegistry;
      delete authRegistry;
      delete authStore;
      delete pendingStore;
      delete registry;
     }

   static CMarketQuote BuildQuote(const string symbol,const double bid,const double ask)
     {
      return CMarketQuote::Create(symbol,bid,ask,10,0.01,2,0.01,1.0,TimeCurrent(),0,
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

   void              SeedBasket(const string basketId,const ENUM_BRE_TRADE_DIRECTION direction)
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
      CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketId),legacy,snapshot,
                                                                         "corr-"+basketId,direction,"XAUUSD",
                                                                         CSignalId("sig-"+basketId),boundAt,
                                                                         CCommandId("cmd-create"),CEventId("evt-create"));
      CBasketAggregate basket;
      created.TryGetValue(basket);
      basket.SetLifecycleState(BRE_STATE_ACTIVE);
      basketRepository.Save(basket);
     }

   bool              PrepareCandidateRequest(const SFastTrackDemoSubmissionCandidate &candidate,
                                             const ENUM_BRE_TRADE_DIRECTION direction,
                                             const double stopLoss,
                                             const double takeProfit)
     {
      if(!basketRepository.Exists(CBasketId(candidate.basket_id)))
         return false;
      CResult<CBasketAggregate> loaded=basketRepository.Load(CBasketId(candidate.basket_id));
      if(loaded.IsFail())
         return false;
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      CTradeExecutionRequest request=CTradeExecutionRequest::Create(candidate.execution_request_id,
                                                                      candidate.idempotency_key,
                                                                      candidate.execution_request_id,
                                                                      CBasketId(candidate.basket_id),
                                                                      basket.Version(),
                                                                      basket.StrategyProfileHash(),
                                                                      candidate.symbol,
                                                                      BRE_EXEC_INTENT_OPEN_POSITION,
                                                                      direction,
                                                                      0,
                                                                      candidate.volume,
                                                                      0.0,
                                                                      stopLoss,
                                                                      takeProfit,
                                                                      1000,
                                                                      CCommandId(),
                                                                      "fasttrack-bridge-test");
      CSubmissionPreparationResult prep=preparer.PrepareForValidationSeed(request,basket,candidate.magic_number);
      return prep.IsSuccess();
     }

   string            BasketStrategyHash(const string basketId)
     {
      CResult<CBasketAggregate> loaded=basketRepository.Load(CBasketId(basketId));
      if(loaded.IsFail())
         return "";
      CBasketAggregate basket;
      loaded.TryGetValue(basket);
      return basket.StrategyProfileHash();
     }
  };

void TestCandidateWithoutAuthorizationDoesNotSubmit(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeOutcome bridgeOutcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,
                                                                 BuildBridgeInputs(BuildValidEnvironment()));
   CTestAssert::True(bridgeOutcome.candidate_created,"Candidate required");

   CDemoSubmissionAuthHarness harness;
   harness.SeedBasket(TEST_BASKET_ID,BRE_DIRECTION_SELL);
   const string strategyHash=harness.BasketStrategyHash(TEST_BASKET_ID);
   CTestAssert::True(strategyHash!="","Strategy hash required");
   CTestAssert::True(harness.PrepareCandidateRequest(bridgeOutcome.candidate,BRE_DIRECTION_SELL,
                                                     bridgeOutcome.candidate.stop_loss,
                                                     bridgeOutcome.candidate.broker_take_profit),
                     "Prepared pending must exist");

   CDemoManualSubmissionResult result=harness.validationService.TryProcessManualSubmission(
      bridgeOutcome.candidate.execution_request_id,"","trigger-token",TEST_BASKET_ID);
   CTestAssert::False(result.IsSuccess(),"Missing authorization must reject submit");
   CTestAssert::EqualInt(0,harness.mockTransport.CallCount(),"OrderSend must not be called");
  }

void TestWrongBindingRejectsAuthorization(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeOutcome bridgeOutcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,
                                                                 BuildBridgeInputs(BuildValidEnvironment()));
   SFastTrackDemoSubmissionAuthorizationCheckOutcome binding=
      CFastTrackDemoSubmissionAuthorizationBinder::ValidateCandidateBinding(registry,
                                                                            bridgeOutcome.candidate.execution_request_id,
                                                                            "wrong-basket-id",
                                                                            bridgeOutcome.candidate.idempotency_key);
   CTestAssert::False(binding.accepted,"Wrong basket must reject binding");
  }

void TestExpiredAuthorizationRejectsSubmit(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeOutcome bridgeOutcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,
                                                                 BuildBridgeInputs(BuildValidEnvironment()));
   CDemoSubmissionAuthHarness harness;
   harness.SeedBasket(TEST_BASKET_ID,BRE_DIRECTION_SELL);
   const string strategyHash=harness.BasketStrategyHash(TEST_BASKET_ID);
   string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(
      bridgeOutcome.candidate.execution_request_id,
      CBasketId(bridgeOutcome.candidate.basket_id),
      bridgeOutcome.candidate.symbol,
      BRE_EXEC_INTENT_OPEN_POSITION,
      bridgeOutcome.candidate.volume,
      1,
      strategyHash);
   string token=CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,500);
   SFastTrackDemoSubmissionAuthorizationCheckOutcome auth=
      CFastTrackDemoSubmissionAuthorizationBinder::ValidateAuthorizationToken(
         bridgeOutcome.candidate,token,1000,1,strategyHash);
   CTestAssert::False(auth.accepted,"Expired authorization must reject");
  }

void TestValidAuthorizationBindingAccepts(void)
  {
   CFastTrackDemoSubmissionCandidateRegistry registry;
   registry.ResetForTests();
   SFastTrackDemoSubmissionBridgeOutcome bridgeOutcome=RunBridge(SEED_SELL,DETAILS_SELL_VALID,registry,
                                                                 BuildBridgeInputs(BuildValidEnvironment()));
   SFastTrackDemoSubmissionAuthorizationCheckOutcome binding=
      CFastTrackDemoSubmissionAuthorizationBinder::ValidateCandidateBinding(registry,
                                                                            bridgeOutcome.candidate.execution_request_id,
                                                                            TEST_BASKET_ID,
                                                                            bridgeOutcome.candidate.idempotency_key);
   CTestAssert::True(binding.accepted,"Valid binding must accept");

   CDemoSubmissionAuthHarness harness;
   harness.SeedBasket(TEST_BASKET_ID,BRE_DIRECTION_SELL);
   const string strategyHash=harness.BasketStrategyHash(TEST_BASKET_ID);
   string fingerprint=CExecutionAuthorizationToken::ComputeBindingFingerprint(
      bridgeOutcome.candidate.execution_request_id,
      CBasketId(bridgeOutcome.candidate.basket_id),
      bridgeOutcome.candidate.symbol,
      BRE_EXEC_INTENT_OPEN_POSITION,
      bridgeOutcome.candidate.volume,
      1,
      strategyHash);
   string token=CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,2000);
   SFastTrackDemoSubmissionAuthorizationCheckOutcome auth=
      CFastTrackDemoSubmissionAuthorizationBinder::ValidateAuthorizationToken(
         bridgeOutcome.candidate,token,1000,1,strategyHash);
   CTestAssert::True(auth.accepted,"Valid authorization token must accept");
  }

void TestFastTrackObserverRegressionStillAllowsPlan(void)
  {
   CFastTrackManualTestOrchestrator orchestrator;
   SFastTrackManualTestInputs inputs=BuildManualInputs(SEED_SELL,DETAILS_SELL_VALID);
   SFastTrackManualTestOutcome outcome=orchestrator.Process(inputs,1000);
   CTestAssert::EqualInt((int)BRE_FAST_TRACK_ORDER_PLAN_ALLOWED,(int)outcome.order_plan_result,
                         "Observer regression order plan");
  }

void OnStart(void)
  {
   TestValidSellCandidateCreated();
   TestValidBuyCandidateCreated();
   TestMissingSlBlocksCandidate();
   TestMissingTpBlocksCandidate();
   TestStopsLevelViolationBlocksCandidate();
   TestRiskLimitBlocksCandidate();
   TestNonDemoAccountBlocksCandidate();
   TestObserverIsolationBlocksCandidate();
   TestKillSwitchBlocksCandidate();
   TestRecoveryFlagBlocksCandidate();
   TestOpenExposureBlocksCandidate();
   TestDuplicateIdempotencyBlocksSecondCandidate();
   TestMultiTpUsesFirstBrokerTarget();
   TestCandidateDoesNotContainRawTelegram();
   TestMagic91001InCandidateMetadata();
   TestMagicMissingBlocksCandidate();
   TestCandidateWithoutAuthorizationDoesNotSubmit();
   TestWrongBindingRejectsAuthorization();
   TestExpiredAuthorizationRejectsSubmit();
   TestValidAuthorizationBindingAccepts();
   TestFastTrackObserverRegressionStillAllowsPlan();
   Print("TestSprint9eFastTrackDemoSubmissionBridge: PASS");
  }
