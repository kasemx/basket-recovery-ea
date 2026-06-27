#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5TradeExecutor.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/MockMt5OrderCheckGateway.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5TradeRequestTranslator.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5RequestValidationPolicy.mqh>
#include <BasketRecovery/Infrastructure/Execution/Mt5/Mt5TradeCheckResultMapper.mqh>
#include <BasketRecovery/Infrastructure/Execution/ExecutionPolicy.mqh>
#include <BasketRecovery/Application/Execution/ExecutionDryRunGate.mqh>
#include <BasketRecovery/Application/Execution/ExecuteTradeIntentUseCase.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunManualCommandService.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionRequestRepository.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryExecutionJournal.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Tests/PersistenceTestPaths.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Application/Execution/ExecutionRuntimeCompositionGuard.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

CMarketQuote BuildFreshQuote(const string symbol,const double bid,const double ask,const int spreadPoints,const int ageMs)
  {
   return CMarketQuote::Create(symbol,bid,ask,spreadPoints,0.01,2,0.01,1.0,TimeCurrent(),ageMs,
                               BRE_TRADING_SESSION_OPEN,
                               CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
  }

CBasketAggregate BuildActiveBasket(const string basketIdValue,const long version)
  {
   CUtcTime boundAt(1000);
   string json=CStrategyProfileTestFixture::MinimalValidJson();
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(json,boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,json,boundAt);
   CExecutionProfileConfig execution;
   execution.SetMagicNumberBase(202606001);
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
   if(version>1)
      basket.SetVersionState(version,CCommandId("cmd-ver"),CEventId("evt-ver"),boundAt);
   return basket;
  }

CTradeExecutionRequest BuildOpenRequest(const string id,const ENUM_BRE_TRADE_DIRECTION direction)
  {
   return CTradeExecutionRequest::Create(id,"key-"+id,"corr",CBasketId("b-open"),1,"hash","EURUSD",
                                         BRE_EXEC_INTENT_OPEN_POSITION,direction,0,
                                         0.01,1.1000,0.0,0.0,1000,CCommandId("c1"),"test");
  }

void ConfigureDryRunExecutor(CMt5TradeExecutor &executor,
                             CInMemoryBasketRepository &repository,
                             CInMemoryMarketDataProvider &marketData,
                             CMockMt5OrderCheckGateway &gateway,
                             const CMarketSafetyConfig &safetyConfig,
                             const bool gateEnabled)
  {
   executor.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,&repository,&marketData,&gateway,NULL,safetyConfig,gateEnabled);
  }

void TestOpenTranslationBuyAndSell(void)
  {
   CExecutionPolicy policy;
   CMt5TradeRequestTranslator translator(policy);
   CBasketAggregate basket=BuildActiveBasket("tr-open",1);

   CMt5RequestTranslationResult buyResult;
   CTradeExecutionRequest buyRequest=BuildOpenRequest("buy",BRE_DIRECTION_BUY);
   CTestAssert::True(translator.TryTranslate(buyRequest,basket,202606001,1.0990,1.1000,buyResult),"BUY open translation must succeed");
   CTestAssert::EqualInt((int)ORDER_TYPE_BUY,(int)buyResult.Request().type,"BUY must map to ORDER_TYPE_BUY");

   CMt5RequestTranslationResult sellResult;
   CTradeExecutionRequest sellRequest=BuildOpenRequest("sell",BRE_DIRECTION_SELL);
   CTestAssert::True(translator.TryTranslate(sellRequest,basket,202606001,1.0990,1.1000,sellResult),"SELL open translation must succeed");
   CTestAssert::EqualInt((int)ORDER_TYPE_SELL,(int)sellResult.Request().type,"SELL must map to ORDER_TYPE_SELL");
  }

void TestCloseReduceRequiresTicket(void)
  {
   CExecutionPolicy policy;
   CMt5TradeRequestTranslator translator(policy);
   CBasketAggregate basket=BuildActiveBasket("tr-ticket",1);

   CTradeExecutionRequest closeRequest=CTradeExecutionRequest::Create("close","k","corr",CBasketId("tr-ticket"),1,"hash","EURUSD",
                                                                    BRE_EXEC_INTENT_CLOSE_POSITION,BRE_DIRECTION_NONE,0,
                                                                    0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CMt5RequestTranslationResult closeResult;
   CTestAssert::False(translator.TryTranslate(closeRequest,basket,202606001,1.0990,1.1000,closeResult),
                      "Close without ticket must fail translation");

   CTradeExecutionRequest reduceRequest=CTradeExecutionRequest::Create("reduce","k2","corr",CBasketId("tr-ticket"),1,"hash","EURUSD",
                                                                     BRE_EXEC_INTENT_REDUCE_POSITION,BRE_DIRECTION_NONE,0,
                                                                     0.01,0.0,0.0,0.0,1000,CCommandId("c2"),"test");
   CMt5RequestTranslationResult reduceResult;
   CTestAssert::False(translator.TryTranslate(reduceRequest,basket,202606001,1.0990,1.1000,reduceResult),
                      "Reduce without ticket must fail translation");
  }

void TestModifySltpTranslationRequiresTicket(void)
  {
   CExecutionPolicy policy;
   CMt5TradeRequestTranslator translator(policy);
   CBasketAggregate basket=BuildActiveBasket("tr-mod",1);

   CTradeExecutionRequest modifySl=CTradeExecutionRequest::Create("msl","k","corr",CBasketId("tr-mod"),1,"hash","EURUSD",
                                                                 BRE_EXEC_INTENT_MODIFY_STOP_LOSS,BRE_DIRECTION_NONE,0,
                                                                 0.0,0.0,1.0850,0.0,1000,CCommandId("c1"),"test");
   CMt5RequestTranslationResult slResult;
   CTestAssert::False(translator.TryTranslate(modifySl,basket,202606001,1.0990,1.1000,slResult),
                      "Modify SL without ticket must fail translation");

   CTradeExecutionRequest modifyTp=CTradeExecutionRequest::Create("mtp","k2","corr",CBasketId("tr-mod"),1,"hash","EURUSD",
                                                                 BRE_EXEC_INTENT_MODIFY_TAKE_PROFIT,BRE_DIRECTION_NONE,0,
                                                                 0.0,0.0,0.0,1.1200,1000,CCommandId("c2"),"test");
   CMt5RequestTranslationResult tpResult;
   CTestAssert::False(translator.TryTranslate(modifyTp,basket,202606001,1.0990,1.1000,tpResult),
                      "Modify TP without ticket must fail translation");
  }

void TestInvalidVolumeRejectedBeforeOrderCheck(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("vol-basket",1);
   repository.Save(basket);

   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));

   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   CMarketSafetyConfig safety=CMarketSafetyConfig::Create(5000,500,30000);
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,safety,true);

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("vol","k","corr",CBasketId("vol-basket"),basket.Version(),
                                                                 basket.StrategyProfileHash(),"EURUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.0001,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTestAssert::True(result.IsOk(),"Invalid volume must return receipt");
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)receipt.CurrentStatus(),"Invalid volume must reject");
   CTestAssert::EqualInt(0,gateway.CallCount(),"OrderCheck must not run for invalid volume");
  }

void TestStaleQuoteAndSpreadRejected(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("quote-basket",1);
   repository.Save(basket);

   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,600,6000));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));

   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   CMarketSafetyConfig safety=CMarketSafetyConfig::Create(5000,500,30000);
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,safety,true);

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("stale","k","corr",CBasketId("quote-basket"),basket.Version(),
                                                                basket.StrategyProfileHash(),"EURUSD",
                                                                BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> staleResult=executor.Execute(request);
   CTradeExecutionReceipt staleReceipt;
   staleResult.TryGetValue(staleReceipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_LIVE_QUOTE_STALE,(int)staleReceipt.Result().FailureReason(),
                         "Stale quote must fail with stale reason");

   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,600,0));
   CResult<CTradeExecutionReceipt> spreadResult=executor.Execute(request);
   CTradeExecutionReceipt spreadReceipt;
   spreadResult.TryGetValue(spreadReceipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_MAX_SPREAD,(int)spreadReceipt.Result().FailureReason(),
                         "Spread guard must reject");
   CTestAssert::EqualInt(0,gateway.CallCount(),"OrderCheck must not run when spread/stale rejects");
  }

void TestBasketVersionHashMismatchRejected(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("guard-basket",3);
   repository.Save(basket);

   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("hash","k","corr",CBasketId("guard-basket"),1,
                                                                "wrong-hash","EURUSD",
                                                                BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_PROFILE_HASH_MISMATCH,(int)receipt.Result().FailureReason(),
                         "Hash mismatch must reject before OrderCheck");
  }

void TestDisabledModeAndDryRunGate(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("disabled-basket",1);
   repository.Save(basket);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;

   CMt5TradeExecutor disabledExecutor;
   disabledExecutor.Configure(BRE_EXEC_RUNTIME_DISABLED,&repository,&marketData,&gateway,NULL,
                              CMarketSafetyConfig::Create(5000,500,30000),false);
   CTestAssert::False(disabledExecutor.IsActive(),"Default DISABLED mode must be inactive");

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("dis","k","corr",CBasketId("disabled-basket"),1,"hash","EURUSD",
                                                               BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                               0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> disabledResult=disabledExecutor.Execute(request);
   CTradeExecutionReceipt disabledReceipt;
   disabledResult.TryGetValue(disabledReceipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_EXECUTION_DISABLED,(int)disabledReceipt.Result().FailureReason(),
                         "DISABLED mode must reject with execution_disabled");

   CMt5TradeExecutor gateClosedExecutor;
   gateClosedExecutor.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,&repository,&marketData,&gateway,NULL,
                                CMarketSafetyConfig::Create(5000,500,30000),false);
   CResult<CTradeExecutionReceipt> gateResult=gateClosedExecutor.Execute(request);
   CTradeExecutionReceipt gateReceipt;
   gateResult.TryGetValue(gateReceipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_EXECUTION_DISABLED,(int)gateReceipt.Result().FailureReason(),
                         "MT5_DRY_RUN without EnableExecutionDryRun must reject");

   CTestAssert::False(CExecutionDryRunGate::IsDryRunRouteEnabled(BRE_EXEC_RUNTIME_MT5_DRY_RUN,false),
                      "Dry-run gate requires both inputs");
   CTestAssert::True(CExecutionDryRunGate::IsDryRunRouteEnabled(BRE_EXEC_RUNTIME_MT5_DRY_RUN,true),
                     "Dry-run gate opens only with both inputs");
  }

void TestMockedOrderCheckAcceptedAndRejected(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("check-basket",1);
   repository.Save(basket);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);

   gateway.SetNextResult(true,TRADE_RETCODE_DONE,"done");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("ok","k","corr",CBasketId("check-basket"),basket.Version(),
                                                                   basket.StrategyProfileHash(),"EURUSD",
                                                                   BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                   0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> okResult=executor.Execute(request);
   CTradeExecutionReceipt okReceipt;
   okResult.TryGetValue(okReceipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_ACCEPTED,(int)okReceipt.CurrentStatus(),"Mock OrderCheck done maps to ACCEPTED");
   CTestAssert::True(okReceipt.Result().IsDryRun(),"Accepted dry-run must set isDryRun=true");
   CTestAssert::EqualInt(1,gateway.CallCount(),"OrderCheck must be invoked once");

   gateway.SetNextResult(true,TRADE_RETCODE_INVALID_VOLUME,"bad volume");
   CTradeExecutionRequest rejectRequest=CTradeExecutionRequest::Create("bad","k2","corr",CBasketId("check-basket"),basket.Version(),
                                                                       basket.StrategyProfileHash(),"EURUSD",
                                                                       BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                       0.01,0.0,0.0,0.0,1000,CCommandId("c2"),"test");
   CResult<CTradeExecutionReceipt> rejectResult=executor.Execute(rejectRequest);
   CTradeExecutionReceipt rejectReceipt;
   rejectResult.TryGetValue(rejectReceipt);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)rejectReceipt.CurrentStatus(),
                         "Mock invalid volume retcode maps to REJECTED");
  }

void TestManualDryRunGateRequiresBothInputs(void)
  {
   CExecutionDryRunManualCommandService service;
   service.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,false,false,BRE_PERSISTENCE_BASKET_SUBDIR,
                     NULL,NULL,NULL,NULL,NULL);
   CVoidResult closed=service.TryProcessManualDryRunOpen("b1","token-1",0.01);
   CTestAssert::True(closed.IsFail(),"Manual route must reject when dry-run flag is false");
   CTestAssert::EqualInt(BRE_ERR_EXEC_DISABLED,closed.ErrorCode(),"Manual route must use EXECUTION_DISABLED error code");
  }

void TestMt5ExecutorAbsentFromTimerPipelineGuard(void)
  {
   CTestAssert::False(CExecutionRuntimeCompositionGuard::AllowsMt5ExecutorInTimerOrFastPathPipeline(),
                      "Mt5 executor must not be wired into timer/fast-path composition");
  }

void TestSeededBasketIncludesStrategySnapshotAndValidCrc(void)
  {
   CPersistenceTestPaths::Cleanup();
   CTestClock clock;
   CTestSequentialIdGenerator idGenerator;
   CFileBasketRepository repository(BRE_TEST_PERSISTENCE_BASKET_SUBDIR);
   CExecutionDryRunTestBasketSeedService seedService;
   CTestAssert::True(seedService.Initialize(&repository,&clock,&idGenerator,"default"),
                     "Seed service must initialize against file repository");

   string strategyJson=CStrategyProfileTestFixture::MinimalValidJson();
   CResult<CBasketAggregate> seedResult=seedService.SeedActiveBasket(CBasketId("seed-crc-001"),"EURUSD",
                                                                       BRE_DIRECTION_BUY,strategyJson);
   CTestAssert::True(seedResult.IsOk(),"Production-flow seed must succeed");
   CBasketAggregate seeded;
   seedResult.TryGetValue(seeded);
   CTestAssert::True(seeded.HasStrategyProfile(),"Seeded basket must include immutable strategy snapshot");
   CTestAssert::False(seeded.StrategyProfileHash()=="","Seeded basket must expose strategy profile hash");

   CResult<CBasketAggregate> roundTrip=seedService.VerifyPersistedRoundTrip(CBasketId("seed-crc-001"));
   CTestAssert::True(roundTrip.IsOk(),"Persisted basket must reload with valid serializer CRC");
   CBasketAggregate reloaded;
   roundTrip.TryGetValue(reloaded);
   CTestAssert::EqualString(seeded.StrategyProfileHash(),reloaded.StrategyProfileHash(),"Reload must preserve profile hash");
   CTestAssert::EqualInt((int)seeded.Version(),(int)reloaded.Version(),"Reload must preserve basket version");
   CPersistenceTestPaths::Cleanup();
  }

void TestManualRouteRejectsUnpersistedBasket(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);
   CTestClock clock;
   CInMemoryExecutionRequestRepository executionRequestRepository;
   CInMemoryExecutionJournal executionJournal(&executionRequestRepository);
   CExecuteTradeIntentUseCase useCase(&repository,&executor,&executionJournal,&executionRequestRepository,&clock);
   CExecutionDryRunManualCommandService service;
   service.Configure(BRE_EXEC_RUNTIME_MT5_DRY_RUN,true,false,BRE_PERSISTENCE_BASKET_SUBDIR,
                     &useCase,&repository,NULL,NULL,NULL);

   CVoidResult result=service.TryProcessManualDryRunOpen("missing-basket-id","token-missing",0.01);
   CTestAssert::True(result.IsFail(),"Manual route must reject unpersisted basket");
   CTestAssert::EqualInt(0,gateway.CallCount(),"Unpersisted basket must not invoke OrderCheck");
  }

void TestOrderCheckInvokedOnlyAfterLocalGuardsPass(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("invoke-guard",1);
   repository.Save(basket);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);

   CTradeExecutionRequest blocked=CTradeExecutionRequest::Create("blocked","k","corr",CBasketId("invoke-guard"),1,
                                                                 "wrong-hash","EURUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> blockedResult=executor.Execute(blocked);
   CTradeExecutionReceipt blockedReceipt;
   blockedResult.TryGetValue(blockedReceipt);
   CTestAssert::False(blockedReceipt.Result().OrderCheckInvoked(),"Local guard rejection must keep order_check_invoked=false");
   CTestAssert::EqualInt(0,gateway.CallCount(),"Local guard must block OrderCheck gateway");

   gateway.SetNextResult(true,TRADE_RETCODE_DONE,"done");
   CTradeExecutionRequest allowed=CTradeExecutionRequest::Create("allowed","k2","corr",CBasketId("invoke-guard"),basket.Version(),
                                                                   basket.StrategyProfileHash(),"EURUSD",
                                                                   BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                   0.01,0.0,0.0,0.0,1000,CCommandId("c2"),"test");
   CResult<CTradeExecutionReceipt> allowedResult=executor.Execute(allowed);
   CTradeExecutionReceipt allowedReceipt;
   allowedResult.TryGetValue(allowedReceipt);
   CTestAssert::True(allowedReceipt.Result().OrderCheckInvoked(),"OrderCheck flag must become true after guards pass");
   CTestAssert::EqualInt(1,gateway.CallCount(),"OrderCheck gateway must run once after guards pass");
  }

void TestLocalRejectionKeepsOrderCheckInvokedFalse(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("local-reject",1);
   repository.Save(basket);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,600,6000));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);

   CTradeExecutionRequest request=CTradeExecutionRequest::Create("stale","k","corr",CBasketId("local-reject"),basket.Version(),
                                                                 basket.StrategyProfileHash(),"EURUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::EqualInt((int)BRE_EXEC_FAIL_LIVE_QUOTE_STALE,(int)receipt.Result().FailureReason(),
                         "Stale quote must reject locally");
   CTestAssert::False(receipt.Result().OrderCheckInvoked(),"Local rejection must keep order_check_invoked=false");
   CTestAssert::EqualInt(0,gateway.CallCount(),"Stale quote must not invoke OrderCheck");
  }

void TestBrokerRetcodeMappingPreservesIsDryRun(void)
  {
   CInMemoryBasketRepository repository;
   CBasketAggregate basket=BuildActiveBasket("broker-map",1);
   repository.Save(basket);
   CInMemoryMarketDataProvider marketData;
   marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
   marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
   CMockMt5OrderCheckGateway gateway;
   CMt5TradeExecutor executor;
   ConfigureDryRunExecutor(executor,repository,marketData,gateway,CMarketSafetyConfig::Create(5000,500,30000),true);

   gateway.SetNextResult(true,TRADE_RETCODE_INVALID_VOLUME,"bad volume");
   CTradeExecutionRequest request=CTradeExecutionRequest::Create("broker","k","corr",CBasketId("broker-map"),basket.Version(),
                                                                 basket.StrategyProfileHash(),"EURUSD",
                                                                 BRE_EXEC_INTENT_OPEN_POSITION,BRE_DIRECTION_BUY,0,
                                                                 0.01,0.0,0.0,0.0,1000,CCommandId("c1"),"test");
   CResult<CTradeExecutionReceipt> result=executor.Execute(request);
   CTradeExecutionReceipt receipt;
   result.TryGetValue(receipt);
   CTestAssert::True(receipt.Result().IsDryRun(),"Broker retcode mapping must preserve isDryRun=true");
   CTestAssert::True(receipt.Result().OrderCheckInvoked(),"Broker retcode path must mark order_check_invoked=true");
   CTestAssert::EqualInt((int)TRADE_RETCODE_INVALID_VOLUME,(int)receipt.Result().Mt5Retcode(),
                         "Broker retcode must propagate to execution result");
  }

void TestProductionDryRunUsesOrderCheckGatewayOnly(void)
  {
   CMt5OrderCheckGateway gateway;
   MqlTradeRequest request;
   MqlTradeCheckResult checkResult;
   ZeroMemory(request);
   ZeroMemory(checkResult);
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=0.01;
   request.type=ORDER_TYPE_BUY;
   request.type_filling=ORDER_FILLING_IOC;
   bool invoked=gateway.Check(request,checkResult);
   CTestAssert::True(invoked || checkResult.retcode>0,"Production OrderCheck gateway must call MT5 OrderCheck API");
  }

void OnStart()
  {
   CTestAssert::Reset();
   TestOpenTranslationBuyAndSell();
   TestCloseReduceRequiresTicket();
   TestModifySltpTranslationRequiresTicket();
   TestInvalidVolumeRejectedBeforeOrderCheck();
   TestStaleQuoteAndSpreadRejected();
   TestBasketVersionHashMismatchRejected();
   TestDisabledModeAndDryRunGate();
   TestMockedOrderCheckAcceptedAndRejected();
   TestManualDryRunGateRequiresBothInputs();
   TestMt5ExecutorAbsentFromTimerPipelineGuard();
   TestSeededBasketIncludesStrategySnapshotAndValidCrc();
   TestManualRouteRejectsUnpersistedBasket();
   TestOrderCheckInvokedOnlyAfterLocalGuardsPass();
   TestLocalRejectionKeepsOrderCheckInvokedFalse();
   TestBrokerRetcodeMappingPreservesIsDryRun();
   TestProductionDryRunUsesOrderCheckGatewayOnly();
   CTestAssert::Summary("TestMt5DryRunExecution");
   if(!CTestAssert::AllPassed())
      Print("TestMt5DryRunExecution FAILED");
   else
      Print("TestMt5DryRunExecution: all tests passed");
  }
