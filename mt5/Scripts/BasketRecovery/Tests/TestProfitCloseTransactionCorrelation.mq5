#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseSubmissionService.mqh>
#include <BasketRecovery/Application/Execution/ManualProfitCloseCandidateRegistry.mqh>
#include <BasketRecovery/Application/Execution/ProfitLevelCloseExecutionTracker.mqh>
#include <BasketRecovery/Application/Execution/CompositePendingExecutionFillNotifier.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionReconciliationRequest.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionCommentFactory.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Market/Enums/AccountPositionModel.mqh>

const string TEST_REQUEST_ID="profit-close-manual:tx-correlation-001";
const ulong TEST_TICKET=1516503131;
const ulong TEST_DEAL_ID=1294774509;
const string TEST_BASKET_ID="sprint8c-tx-correlation";
const double TEST_BEFORE_VOLUME=0.02;
const double TEST_CLOSE_VOLUME=0.01;
const double TEST_REMAINING_VOLUME=0.01;

class CProfitCloseTransactionTestHarness
  {
public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionEventBuffer    *events;
   CTestClock                              *clock;
   CPendingExecutionDiagnostics            *diagnostics;
   CInMemoryPendingExecutionStore          *store;
   CPendingExecutionLifecycleService       *lifecycle;
   CInMemoryBrokerPositionReader           *brokerReader;
   CExecutionReconciliationScheduler       *reconciliationScheduler;
   CBasketFastStateRegistry                *fastStateRegistry;
   CTradeTransactionRouter                 *router;
   CPendingExecutionTestInjectionService   *injection;
   CManualProfitCloseCandidateRegistry     *candidateRegistry;
   CProfitLevelCloseExecutionTracker       *levelTracker;
   CInMemoryBasketRepository               *basketRepository;
   CManualProfitCloseSubmissionService     *submissionService;
   CCompositePendingExecutionFillNotifier  *fillNotifier;

                     CProfitCloseTransactionTestHarness(void)
     {
      registry=new CPendingExecutionRegistry();
      events=new CInMemoryPendingExecutionEventBuffer(32);
      clock=new CTestClock();
      diagnostics=new CPendingExecutionDiagnostics(NULL,false,64);
      store=new CInMemoryPendingExecutionStore();
      lifecycle=new CPendingExecutionLifecycleService(registry,store,events,clock);
      brokerReader=new CInMemoryBrokerPositionReader();
      reconciliationScheduler=new CExecutionReconciliationScheduler(registry,brokerReader,diagnostics,8,lifecycle);
      fastStateRegistry=new CBasketFastStateRegistry();
      router=new CTradeTransactionRouter(registry,diagnostics,events,fastStateRegistry,clock,lifecycle);
      injection=new CPendingExecutionTestInjectionService(registry,router);
      candidateRegistry=new CManualProfitCloseCandidateRegistry();
      levelTracker=new CProfitLevelCloseExecutionTracker();
      basketRepository=new CInMemoryBasketRepository();
      CDemoExecutionAuthorizationConfig config;
      submissionService=new CManualProfitCloseSubmissionService(config,
                                                                candidateRegistry,
                                                                NULL,
                                                                NULL,
                                                                NULL,
                                                                levelTracker,
                                                                NULL,
                                                                NULL,
                                                                NULL,
                                                                basketRepository,
                                                                clock,
                                                                NULL,
                                                                NULL,
                                                                registry,
                                                                NULL);
      fillNotifier=new CCompositePendingExecutionFillNotifier();
      fillNotifier.AddNotifier(submissionService);
      reconciliationScheduler.SetFillNotifier(fillNotifier);
     }

                    ~CProfitCloseTransactionTestHarness(void)
     {
      if(fillNotifier!=NULL) delete fillNotifier;
      if(submissionService!=NULL) delete submissionService;
      if(basketRepository!=NULL) delete basketRepository;
      if(levelTracker!=NULL) delete levelTracker;
      if(candidateRegistry!=NULL) delete candidateRegistry;
      if(injection!=NULL) delete injection;
      if(router!=NULL) delete router;
      if(reconciliationScheduler!=NULL) delete reconciliationScheduler;
      if(fastStateRegistry!=NULL) delete fastStateRegistry;
      if(lifecycle!=NULL) delete lifecycle;
      if(store!=NULL) delete store;
      if(brokerReader!=NULL) delete brokerReader;
      if(diagnostics!=NULL) delete diagnostics;
      if(clock!=NULL) delete clock;
      if(events!=NULL) delete events;
      if(registry!=NULL) delete registry;
     }

   void              Reset(void)
     {
      registry.Clear();
      events.Clear();
      reconciliationScheduler.Clear();
      candidateRegistry.Clear();
      levelTracker.Clear();
      basketRepository.Delete(CBasketId(TEST_BASKET_ID));
     }
  };

CTradeTransactionCorrelationContext BuildDealContext(const ulong dealId,
                                                   const ulong positionId,
                                                   const string comment,
                                                   const double volume)
  {
   CNormalizedTradeTransaction normalized;
   normalized.SetSymbol("XAUUSD");
   normalized.SetDealId(dealId);
   normalized.SetPositionId(positionId);
   normalized.SetComment(comment);
   normalized.SetVolume(volume);
   normalized.SetPrice(2650.0);
   normalized.SetOccurredAtUtc(1000);
   return CTradeTransactionCorrelationContext::FromNormalized(normalized,BRE_TRADE_TX_TYPE_DEAL_ADD,202606001);
  }

CPendingExecutionEntry BuildProfitClosePending(const string requestId,
                                               const ulong ticket,
                                               const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                                               const double requestedVolume)
  {
   string comment=CBrokerExecutionCommentFactory::BuildProfitCloseComment(requestId,ticket);
   CBrokerRequestCorrelation broker;
   broker.SetPositionTicket(ticket);
   broker.SetMagicNumber(202606001);
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(requestId);
   entry.SetIdempotencyKey("key-"+requestId);
   entry.SetBasketId(CBasketId(TEST_BASKET_ID));
   entry.SetExpectedBasketVersion(1);
   entry.SetStrategyProfileHash("hash");
   entry.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   entry.SetSymbol("XAUUSD");
   entry.SetBrokerCorrelation(broker);
   entry.SetRequestedVolume(requestedVolume);
   entry.SetBrokerComment(comment);
   entry.SetStatus(status);
   entry.SetSubmittedAtUtc(1000);
   return entry;
  }

void SeedCompletionFixture(CProfitCloseTransactionTestHarness &h,
                           const string requestId,
                           const ulong ticket,
                           const double closeVolume)
  {
   CStrategyProfileJsonParser parser;
   CResult<CStrategyProfile> profileResult=parser.Parse(CStrategyProfileTestFixture::MinimalValidJson(),CUtcTime(1000));
   CStrategyProfile profile;
   profileResult.TryGetValue(profile);
   CStrategyProfileSnapshot snapshot=CStrategyProfileCanonicalSerializer::CreateSnapshot(profile,
                                                                                       CStrategyProfileTestFixture::MinimalValidJson(),
                                                                                       CUtcTime(1000));
   CProfileSnapshot legacy=CProfileSnapshot::Create("default",CRiskProfileConfig(),CRecoveryProfileConfig(),
                                                  CTakeProfitProfileConfig(),CBreakEvenProfileConfig(),
                                                  CExecutionProfileConfig(),CUtcTime(1000));
   CResult<CBasketAggregate> created=CBasketFactory::CreateWithStrategy(CBasketId(TEST_BASKET_ID),legacy,snapshot,
                                                                      "corr",BRE_DIRECTION_BUY,"XAUUSD",
                                                                      CSignalId("sig"),CUtcTime(1000),
                                                                      CCommandId("cmd"),CEventId("evt"));
   CBasketAggregate basket;
   created.TryGetValue(basket);
   datetime now=1000;
   CTestAssert::True(basket.ApplyProfitLevelReached("M1",CUtcTime(now),CCommandId("cmd-m1-reached"),CEventId("evt-m1-reached")).IsOk(),
                     "fixture must seed M1 reached progress");
   h.basketRepository.Save(basket);

   CManualProfitCloseCandidateEntry candidate=CManualProfitCloseCandidateEntry::Create(
      "candidate-"+requestId,
      requestId,
      "idempotency-"+requestId,
      CBasketId(TEST_BASKET_ID),
      "M1",
      1,
      basket.StrategyProfileHash(),
      basket.Version(),
      "XAUUSD",
      BRE_DIRECTION_BUY,
      BRE_DIRECTION_BUY,
      ticket,
      TEST_BEFORE_VOLUME,
      closeVolume,
      1.0,
      BRE_PROFIT_LEVEL_TRIGGER_FLOATING_PROFIT_MONEY,
      50.0,
      1,
      now,
      now+300,
      BRE_ACCOUNT_POSITION_MODEL_HEDGING);
   CTestAssert::True(h.candidateRegistry.TryRegister(candidate),"fixture candidate must register");
   h.levelTracker.MarkSubmitted(TEST_BASKET_ID,"M1",requestId);
  }

ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE RouteProfitCloseDealFill(CProfitCloseTransactionTestHarness &h,
                                                              const string requestId,
                                                              const ulong ticket,
                                                              const ulong dealId,
                                                              const double closeVolume)
  {
   CPendingExecutionEntry entry=BuildProfitClosePending(requestId,ticket,BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,closeVolume);
   h.injection.RegisterPendingEntry(entry);
   string comment=entry.BrokerComment();
   CTradeTransactionCorrelationContext context=BuildDealContext(dealId,ticket,comment,closeVolume);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   if(result==BRE_TRADE_TX_RESULT_ACCEPTED || result==BRE_TRADE_TX_RESULT_RECONCILED)
     {
      CPendingExecutionEntry updated;
      if(h.registry.TryGetByExecutionRequestId(requestId,updated) &&
         updated.Status()==BRE_TRADE_EXEC_STATUS_FILLED)
         h.fillNotifier.OnBrokerFillConfirmed(requestId,"trade_transaction");
     }
   return result;
  }

void TestProfitCloseCommentDealAddMarksPendingFilled(CProfitCloseTransactionTestHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildProfitClosePending(TEST_REQUEST_ID,TEST_TICKET,BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,TEST_CLOSE_VOLUME);
   h.injection.RegisterPendingEntry(entry);
   string comment=entry.BrokerComment();

   CTradeTransactionCorrelationContext context=BuildDealContext(TEST_DEAL_ID,TEST_TICKET,comment,TEST_CLOSE_VOLUME);
   ENUM_BRE_CORRELATION_MATCH_STRATEGY strategy=BRE_CORRELATION_MATCH_NONE;
   CTestAssert::True(h.registry.TryCorrelate(context,strategy)>=0,"BRE|PC| comment must correlate");
   CTestAssert::EqualInt((int)BRE_CORRELATION_MATCH_PROFIT_CLOSE_COMMENT,(int)strategy,"profit close comment strategy");

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"DEAL_ADD must accept profit close transaction");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId(TEST_REQUEST_ID,updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"pending must be FILLED");
   CTestAssert::EqualDouble(TEST_CLOSE_VOLUME,updated.FilledVolume(),0.0000001,"filled volume must match partial close");
  }

void TestProfitCloseDealAddCompletesProfitLevel(CProfitCloseTransactionTestHarness &h)
  {
   h.Reset();
   SeedCompletionFixture(h,TEST_REQUEST_ID,TEST_TICKET,TEST_CLOSE_VOLUME);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=
      RouteProfitCloseDealFill(h,TEST_REQUEST_ID,TEST_TICKET,TEST_DEAL_ID,TEST_CLOSE_VOLUME);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"profit close DEAL_ADD must accept");

   CResult<CBasketAggregate> loaded=h.basketRepository.Load(CBasketId(TEST_BASKET_ID));
   CBasketAggregate basket;
   CTestAssert::True(loaded.TryGetValue(basket),"basket must load");
   CBasketProfitLevelProgress progress;
   CTestAssert::True(basket.FindProfitLevelProgress("M1",progress),"M1 progress must exist");
   CTestAssert::True(progress.CloseCompleted(),"M1 must be COMPLETED");
   CTestAssert::True(h.levelTracker.IsLevelCompleted(TEST_BASKET_ID,"M1"),"tracker must mark M1 filled");
  }

void TestTimerReconciliationCompletesProfitLevel(CProfitCloseTransactionTestHarness &h)
  {
   h.Reset();
   SeedCompletionFixture(h,"profit-close-manual:timer-001",TEST_TICKET,TEST_CLOSE_VOLUME);
   CPendingExecutionEntry entry=BuildProfitClosePending("profit-close-manual:timer-001",TEST_TICKET,
                                                        BRE_TRADE_EXEC_STATUS_RECONCILING,TEST_CLOSE_VOLUME);
   entry.SetFilledVolume(TEST_CLOSE_VOLUME);
   h.injection.RegisterPendingEntry(entry);

   CExecutionReconciliationRequest request;
   request.SetExecutionRequestId("profit-close-manual:timer-001");
   h.reconciliationScheduler.Enqueue(request);
   CTestAssert::EqualInt(1,h.reconciliationScheduler.ProcessBatch(),"timer reconciliation must process entry");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("profit-close-manual:timer-001",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"timer path must mark FILLED");

   CResult<CBasketAggregate> loaded=h.basketRepository.Load(CBasketId(TEST_BASKET_ID));
   CBasketAggregate basket;
   loaded.TryGetValue(basket);
   CBasketProfitLevelProgress progress;
   CTestAssert::True(basket.FindProfitLevelProgress("M1",progress),"M1 progress must exist after timer");
   CTestAssert::True(progress.CloseCompleted(),"timer path must complete M1");
  }

void TestDuplicateDealIsIdempotent(CProfitCloseTransactionTestHarness &h)
  {
   h.Reset();
   SeedCompletionFixture(h,TEST_REQUEST_ID,TEST_TICKET,TEST_CLOSE_VOLUME);
   CPendingExecutionEntry entry=BuildProfitClosePending(TEST_REQUEST_ID,TEST_TICKET,BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,TEST_CLOSE_VOLUME);
   h.injection.RegisterPendingEntry(entry);
   string comment=entry.BrokerComment();
   CTradeTransactionCorrelationContext context=BuildDealContext(TEST_DEAL_ID,TEST_TICKET,comment,TEST_CLOSE_VOLUME);

   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)h.injection.InjectCorrelationContext(context),
                         "first deal must accept");
   h.fillNotifier.OnBrokerFillConfirmed(TEST_REQUEST_ID,"trade_transaction");

   CPendingExecutionEntry afterFirstPending;
   h.registry.TryGetByExecutionRequestId(TEST_REQUEST_ID,afterFirstPending);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)afterFirstPending.Status(),
                         "first deal must terminalize pending to FILLED");

   CResult<CBasketAggregate> afterFirst=h.basketRepository.Load(CBasketId(TEST_BASKET_ID));
   CBasketAggregate basketAfterFirst;
   afterFirst.TryGetValue(basketAfterFirst);
   CBasketProfitLevelProgress progressAfterFirst;
   basketAfterFirst.FindProfitLevelProgress("M1",progressAfterFirst);
   int versionAfterFirst=basketAfterFirst.Version();
   CTestAssert::True(progressAfterFirst.CloseCompleted(),"first deal must complete profit level");

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE duplicateResult=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_DUPLICATE,(int)duplicateResult,
                         "duplicate deal must be ignored");

   CPendingExecutionEntry afterDuplicatePending;
   h.registry.TryGetByExecutionRequestId(TEST_REQUEST_ID,afterDuplicatePending);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)afterDuplicatePending.Status(),
                         "duplicate deal must not mutate pending status");
   CTestAssert::EqualDouble(afterFirstPending.FilledVolume(),afterDuplicatePending.FilledVolume(),0.0000001,
                            "duplicate deal must not mutate filled volume");

   CResult<CBasketAggregate> afterSecond=h.basketRepository.Load(CBasketId(TEST_BASKET_ID));
   CBasketAggregate basketAfterSecond;
   afterSecond.TryGetValue(basketAfterSecond);
   CBasketProfitLevelProgress progressAfterSecond;
   basketAfterSecond.FindProfitLevelProgress("M1",progressAfterSecond);
   CTestAssert::EqualInt(versionAfterFirst,basketAfterSecond.Version(),"duplicate fill must not mutate basket");
   CTestAssert::EqualInt(progressAfterFirst.CloseCompleted()?1:0,progressAfterSecond.CloseCompleted()?1:0,
                         "duplicate fill must not re-complete profit level");
  }

void TestLegacyBrokerStampFlowStillCorrelates(CProfitCloseTransactionTestHarness &h)
  {
   h.Reset();
   const string legacyRequestId="req-legacy-stamp";
   string stampComment=CBrokerCommentStamp::Build(legacyRequestId,
                                                  "key-"+legacyRequestId,
                                                  CBasketId("basket-legacy"),
                                                  BRE_EXEC_INTENT_CLOSE_POSITION);
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(88001);
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(legacyRequestId);
   entry.SetBasketId(CBasketId("basket-legacy"));
   entry.SetSymbol("EURUSD");
   entry.SetRequestedVolume(0.10);
   entry.SetIntentType(BRE_EXEC_INTENT_CLOSE_POSITION);
   entry.SetBrokerCorrelation(broker);
   entry.SetBrokerComment(stampComment);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   h.injection.RegisterPendingEntry(entry);

   CNormalizedTradeTransaction normalized;
   normalized.SetSymbol("EURUSD");
   normalized.SetOrderId(88001);
   normalized.SetComment(stampComment);
   normalized.SetVolume(0.10);
   normalized.SetPrice(1.1000);
   normalized.SetOccurredAtUtc(1000);
   CTradeTransactionCorrelationContext context=
      CTradeTransactionCorrelationContext::FromNormalized(normalized,BRE_TRADE_TX_TYPE_ORDER_ADD,0);

   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"legacy BRE stamp must still correlate");
   CTestAssert::True(context.CorrelationToken()!="" ,"legacy stamp must expose correlation token");
  }

void OnStart()
  {
   CTestAssert::Reset();
   CProfitCloseTransactionTestHarness harness;
   TestProfitCloseCommentDealAddMarksPendingFilled(harness);
   TestProfitCloseDealAddCompletesProfitLevel(harness);
   TestTimerReconciliationCompletesProfitLevel(harness);
   TestDuplicateDealIsIdempotent(harness);
   TestLegacyBrokerStampFlowStillCorrelates(harness);
   CTestAssert::Summary("TestProfitCloseTransactionCorrelation");
  }
