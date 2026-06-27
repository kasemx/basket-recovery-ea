#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/TestSequentialIdGenerator.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Commands/InMemoryCommandQueue.mqh>
#include <BasketRecovery/Infrastructure/Idempotency/InMemoryIdempotencyStore.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketContextProviderAdapter.mqh>
#include <BasketRecovery/Infrastructure/Market/MarketSafetyGuard.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Application/Services/SystemHealthCheckService.mqh>
#include <BasketRecovery/Application/FastPath/FastCommandStagingBuffer.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Application/Services/StrategyEvaluationContextFactory.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationTimerPipeline.mqh>
#include <BasketRecovery/Application/Kernel/CommandProcessor.mqh>
#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Handlers/Commands/EvaluateStrategyCommandHandler.mqh>
#include <BasketRecovery/Application/UseCases/EvaluateBasketStrategyUseCase.mqh>
#include <BasketRecovery/Application/Services/ReconciliationSchedulerService.mqh>
#include <BasketRecovery/Application/FastPath/SymbolBasketIndex.mqh>
#include <BasketRecovery/Application/Services/TimerFallbackEvaluationService.mqh>
#include <BasketRecovery/Application/Ports/IStrategyEngine.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyExecutionStubHandlers.mqh>
#include <BasketRecovery/Application/Commands/StrategyCommands.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Configuration/ProfileSnapshot.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

CSymbolTradingConstraints DefaultConstraints(void)
  {
   return CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01);
  }

CMarketQuote BuildQuote(const string symbol,
                        const double bid,
                        const double ask,
                        const int freshnessAgeMs,
                        const int spreadPoints,
                        const ENUM_BRE_TRADING_SESSION_STATUS sessionStatus)
  {
   return CMarketQuote::Create(symbol,bid,ask,spreadPoints,0.01,2,0.01,1.0,1000,freshnessAgeMs,sessionStatus,DefaultConstraints());
  }

CBasketAggregate BuildActiveBasket(const string basketIdValue,const string symbol)
  {
   CUtcTime boundAt(1000);
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CStrategyProfileTestFixture::MinimalValidJson(),boundAt);
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,
                                                                                       CStrategyProfileTestFixture::MinimalValidJson(),
                                                                                       boundAt);
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),boundAt);
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(basketIdValue),legacy,snapshot,
                                                                      "corr-"+basketIdValue,BRE_DIRECTION_BUY,symbol,
                                                                      CSignalId("sig-"+basketIdValue),boundAt,
                                                                      CCommandId("cmd-create"),CEventId("evt-create"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   basket.SetLifecycleState(BRE_STATE_ACTIVE);
   return basket;
  }

void ConfigureMarket(CInMemoryMarketDataProvider &provider,
                     const CMarketQuote &quote,
                     const bool tradeAllowed)
  {
   provider.SetQuote(quote);
   provider.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,tradeAllowed));
  }

void TestFreshQuoteAccepted(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,100,20,BRE_TRADING_SESSION_OPEN),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("fresh-quote","XAUUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::True(adapter.TryBuildForBasket(basket,market,risk),"Fresh quote must be accepted");
  }

void TestStaleQuoteDeferred(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,9000,20,BRE_TRADING_SESSION_OPEN),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("stale-quote","XAUUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildForBasket(basket,market,risk),"Stale quote must defer evaluation");
  }

void TestSpreadThresholdDeferred(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2360.0,100,1000,BRE_TRADING_SESSION_OPEN),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("wide-spread","XAUUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildForBasket(basket,market,risk),"Wide spread must defer evaluation");
  }

void TestMarketClosedDeferred(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,100,20,BRE_TRADING_SESSION_CLOSED),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("market-closed","XAUUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildForBasket(basket,market,risk),"Closed market must defer evaluation");
  }

void TestSymbolUnavailableDeferred(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,100,20,BRE_TRADING_SESSION_OPEN),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("symbol-missing","EURUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildForBasket(basket,market,risk),"Unavailable symbol must defer evaluation");
  }

void TestAccountTradeDisabledDeferred(void)
  {
   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,100,20,BRE_TRADING_SESSION_OPEN),false);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));

   CBasketAggregate basket=BuildActiveBasket("trade-disabled","XAUUSD");
   CMarketContext market;
   CRiskRuntimeContext risk;
   CTestAssert::False(adapter.TryBuildForBasket(basket,market,risk),"Disabled account must defer evaluation");
  }

CPositionSnapshotEntry BuildBrokerEntry(const CBasketId &basketId,
                                        const ulong ticket,
                                        const double sl,
                                        const double tp,
                                        const double volume)
  {
   return CPositionSnapshotEntry::Create(basketId,ticket,202606001,"XAUUSD",BRE_DIRECTION_BUY,
                                         BRE_TRADE_ROLE_INITIAL,0,2350.0,2350.1,sl,tp,volume,10.0,0.0,0.0,
                                         1000,BRE_POSITION_SNAPSHOT_OPEN,"BRE|"+basketId.Value()+"|INITIAL|step=0");
  }

void TestBrokerPositionMatchesSnapshot(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CBasketId basketId("match-basket");
   CPositionSnapshotEntry brokerEntry=BuildBrokerEntry(basketId,1001,2340.0,2360.0,0.01);
   CPositionSnapshotEntry brokerEntries[1];
   brokerEntries[0]=brokerEntry;
   brokerReader.SetEntries(brokerEntries,1);
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,brokerEntries,1);

   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,NULL,NULL,&clock);
   CReconciliationResult result=reconciler.ReconcileBasket(basketId,brokerEntries,1);
   CTestAssert::False(result.HasIssues(),"Matching broker and local snapshots must have no issues");
  }

void TestOrphanPositionDetected(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CBasketId basketId("orphan-basket");
   CPositionSnapshotEntry brokerEntry=BuildBrokerEntry(basketId,1002,2340.0,2360.0,0.01);
   CPositionSnapshotEntry brokerEntries[1];
   brokerEntries[0]=brokerEntry;
   brokerReader.SetEntries(brokerEntries,1);
   snapshotStore.CreateEmpty(basketId);

   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,NULL,NULL,&clock);
   CReconciliationResult result=reconciler.ReconcileBasket(basketId,brokerEntries,1);
   CTestAssert::EqualInt(1,result.OrphanCount(),"Orphan broker position must be reported");
  }

void TestMissingLocalPositionDetected(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CBasketId basketId("missing-basket");
   CPositionSnapshotEntry localEntry=BuildBrokerEntry(basketId,1003,2340.0,2360.0,0.01);
   CPositionSnapshotEntry localEntries[1];
   localEntries[0]=localEntry;
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,localEntries,1);

   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,NULL,NULL,&clock);
   CPositionSnapshotEntry emptyBroker[];
   CReconciliationResult result=reconciler.ReconcileBasket(basketId,emptyBroker,0);
   CTestAssert::EqualInt(1,result.MissingCount(),"Missing broker position must be reported");
  }

void TestSlTpVolumeMismatchDetected(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBrokerPositionReader brokerReader;
   CBasketId basketId("mismatch-basket");
   CPositionSnapshotEntry localEntry=BuildBrokerEntry(basketId,1004,2340.0,2360.0,0.01);
   CPositionSnapshotEntry brokerEntry=BuildBrokerEntry(basketId,1004,2341.0,2360.0,0.02);
   CPositionSnapshotEntry localEntries[1];
   CPositionSnapshotEntry brokerEntries[1];
   localEntries[0]=localEntry;
   brokerEntries[0]=brokerEntry;
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,localEntries,1);
   brokerReader.SetEntries(brokerEntries,1);

   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,NULL,NULL,&clock);
   CReconciliationResult result=reconciler.ReconcileBasket(basketId,brokerEntries,1);
   CTestAssert::EqualInt(1,result.MismatchCount(),"SL/TP/volume mismatch must be reported");
  }

void TestReconciliationSuspendsOnlyAffectedBasket(void)
  {
   CTestClock clock;
   CInMemoryBasketRepository repository;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBrokerPositionReader brokerReader;

   CBasketAggregate affected=BuildActiveBasket("suspend-a","XAUUSD");
   CBasketAggregate unaffected=BuildActiveBasket("suspend-b","XAUUSD");
   repository.Save(affected);
   repository.Save(unaffected);

   CBasketId affectedId=affected.Id();
   CPositionSnapshotEntry orphanEntry=BuildBrokerEntry(affectedId,1005,2340.0,2360.0,0.01);
   CPositionSnapshotEntry brokerEntries[1];
   brokerEntries[0]=orphanEntry;
   brokerReader.SetEntries(brokerEntries,1);
   snapshotStore.CreateEmpty(affectedId);

   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,&repository,NULL,&clock);
   CReconciliationResult result=reconciler.ReconcileBasket(affectedId,brokerEntries,1);
   reconciler.ApplyReconciliationResult(result,brokerEntries,1);

   CResult<CBasketAggregate> affectedReload=repository.Load(affectedId);
   CBasketAggregate affectedUpdated;
   affectedReload.TryGetValue(affectedUpdated);
   CResult<CBasketAggregate> unaffectedReload=repository.Load(unaffected.Id());
   CBasketAggregate unaffectedUpdated;
   unaffectedReload.TryGetValue(unaffectedUpdated);

   CTestAssert::EqualInt((long)BRE_STATE_SUSPENDED,(long)affectedUpdated.LifecycleState(),"Affected basket must suspend");
   CTestAssert::EqualInt((long)BRE_STATE_ACTIVE,(long)unaffectedUpdated.LifecycleState(),"Unaffected basket must stay active");
  }

void TestContextFactoryUsesSnapshotStoreOnly(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CBasketAggregate basket=BuildActiveBasket("context-factory","XAUUSD");
   CBasketId basketId=basket.Id();
   CPositionSnapshotEntry entry=BuildBrokerEntry(basketId,2001,2340.0,2360.0,0.01);
   CPositionSnapshotEntry entries[1];
   entries[0]=entry;
   snapshotStore.CreateEmpty(basketId);
   snapshotStore.ReplaceEntries(basketId,entries,1);

   CMarketContext market=CMarketContext::Create("XAUUSD",2350.0,2350.2,0.01);
   CRiskRuntimeContext risk=CRiskRuntimeContext::Create(10000.0,1.0,2.0,0.0,true,false);
   CResult<CStrategyEvaluationContext> built=CStrategyEvaluationContextFactory::TryBuild(basket,market,risk,&snapshotStore);
   CTestAssert::True(built.IsOk(),"Context factory must build from in-memory snapshot store");

   CStrategyEvaluationContext context;
   built.TryGetValue(context);
   CTestAssert::EqualInt(1,context.PositionCount(),"Context factory must map snapshot entries");
   CTestAssert::EqualInt(2001,(int)context.PositionAt(0).Ticket(),"Context factory must preserve broker ticket");
  }

void TestSchedulerOrderingAndIntervalGates(void)
  {
   CInMemoryBasketRepository repository;
   CInMemoryCommandQueue queue;
   CTestClock clock;
   CInMemoryIdempotencyStore idempotencyStore;

   CBasketAggregate basket=BuildActiveBasket("timer-gate","XAUUSD");
   repository.Save(basket);

   CClosePositionsCommandHandler closeHandler(&repository,&clock);
   CCommandDispatcher commandDispatcher;
   commandDispatcher.RegisterHandler(&closeHandler,50);
   CEventDispatcher eventDispatcher;
   CCommandProcessor processor(&queue,&commandDispatcher,&eventDispatcher,&idempotencyStore);

   CInMemoryMarketDataProvider marketData;
   ConfigureMarket(marketData,BuildQuote("XAUUSD",2350.0,2350.2,100,20,BRE_TRADING_SESSION_OPEN),true);
   CMarketContextProviderAdapter adapter(&marketData,CMarketSafetyConfig::Create(5000,500,30000));
   CStrategyEngineAdapter strategyEngine;
   CTestSequentialIdGenerator idGenerator;
   CInMemorySnapshotStore snapshotStore(&clock);
   CEvaluateBasketStrategyUseCase useCase(&repository,&strategyEngine,&queue,&clock,&idGenerator,&snapshotStore);
   CSymbolBasketIndex symbolIndex;
   symbolIndex.Rebuild(&repository);
   CFastCommandStagingBuffer stagingQueue;
   CTimerFallbackEvaluationService fallback(&repository,&adapter,&useCase,&stagingQueue,&symbolIndex,
                                            CFastPathConfig::Create(1,2000,250,5,60000));
   fallback.NotifyTick();
   CInMemoryHotPathDiagnostics diagnostics;
   CSystemHealthCheckService healthCheck(&diagnostics,60000);
   CInMemoryBrokerPositionReader brokerReader;
   CBasketPositionReconciler reconciler(&brokerReader,&snapshotStore,&repository,NULL,&clock);
   CReconciliationSchedulerService reconciliationService(&reconciler,60000,3);
   CApplicationTimerPipeline pipeline(NULL,&processor,NULL,&reconciliationService,&fallback,&healthCheck,&stagingQueue,0);

   CClosePositionsCommand *closeCommand=new CClosePositionsCommand();
   closeCommand.SetId(CCommandId("cmd-timer"));
   closeCommand.SetBasketId(basket.Id());
   closeCommand.SetCorrelationKey(basket.CorrelationKey());
   closeCommand.SetExpectedBasketVersion(basket.Version());
   closeCommand.SetStrategyProfileHash(basket.StrategyProfileHash());
   closeCommand.SetIdempotencyKey("timer-gate-close");
   closeCommand.SetLevelId("L1");
   closeCommand.SetClosePercent(25.0);
   queue.Enqueue(closeCommand);

   int commandsProcessed=0;
   int eventsProcessed=0;
   int evaluationsScheduled=0;
   CTestAssert::True(pipeline.OnTimer(commandsProcessed,eventsProcessed,evaluationsScheduled).IsOk(),"Timer pipeline must succeed");
   CTestAssert::EqualInt(1,commandsProcessed,"Command processor must run on timer slow path");
   CTestAssert::EqualInt(0,evaluationsScheduled,"Fallback must not run while ticks are recent");
   CTestAssert::EqualInt(0,reconciliationService.RunIfDue(),"Reconciliation interval gate must block second pass");
  }

void OnStart()
  {
   TestFreshQuoteAccepted();
   TestStaleQuoteDeferred();
   TestSpreadThresholdDeferred();
   TestMarketClosedDeferred();
   TestSymbolUnavailableDeferred();
   TestAccountTradeDisabledDeferred();
   TestBrokerPositionMatchesSnapshot();
   TestOrphanPositionDetected();
   TestMissingLocalPositionDetected();
   TestSlTpVolumeMismatchDetected();
   TestReconciliationSuspendsOnlyAffectedBasket();
   TestContextFactoryUsesSnapshotStoreOnly();
   TestSchedulerOrderingAndIntervalGates();
   Print("TestLiveMarketContext: all tests passed");
  }
