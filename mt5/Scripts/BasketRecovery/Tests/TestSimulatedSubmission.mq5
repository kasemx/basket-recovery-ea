#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Domain/Execution/BrokerCommentStamp.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionStatus.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>
#include <BasketRecovery/Domain/Execution/SimulatedBrokerSubmissionScenario.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/ExecutionSubmissionPreparer.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationPolicy.mqh>
#include <BasketRecovery/Application/Execution/SubmissionPreparationValidator.mqh>
#include <BasketRecovery/Application/Execution/SubmitPreparedExecutionUseCase.mqh>
#include <BasketRecovery/Application/Execution/SubmissionGatewayCompositionGuard.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/SimulatedBrokerSubmissionInjector.mqh>
#include <BasketRecovery/Application/Execution/ExecutionTimeoutMonitor.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRestartService.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Kernel/ApplicationContext.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Execution/SimulatedSubmissionGateway.mqh>
#include <BasketRecovery/Infrastructure/Market/InMemoryMarketDataProvider.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileCanonicalSerializer.mqh>
#include <BasketRecovery/Domain/Factories/BasketFactory.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionRequest.mqh>

const long TEST_MAGIC=202606001;

class CSimulatedSubmissionTestHarness
  {
private:
   CSubmissionPreparationValidator         *m_validator;

public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionStore          *store;
   CTestClock                              *clock;
   CInMemoryMarketDataProvider             *marketData;
   CExecutionSubmissionPreparer            *preparer;
   CSimulatedSubmissionGateway             *gateway;
   CSubmitPreparedExecutionUseCase         *submitUseCase;
   CInMemoryPendingExecutionEventBuffer    *events;
   CTradeTransactionRouter                 *router;
   CPendingExecutionTestInjectionService   *injection;
   CSimulatedBrokerSubmissionInjector      *brokerInjector;
   CExecutionTimeoutMonitor                *timeoutMonitor;
   CExecutionReconciliationScheduler       *reconciliationScheduler;

                     CSimulatedSubmissionTestHarness(void)
     {
      m_validator=NULL;
      registry=new CPendingExecutionRegistry();
      store=new CInMemoryPendingExecutionStore();
      clock=new CTestClock();
      clock.SetNow(1000);
      marketData=new CInMemoryMarketDataProvider();
      marketData.SetQuote(BuildFreshQuote("EURUSD",1.0990,1.1000,10,0));
      marketData.SetAccount(CAccountContextSnapshot::Create(1,10000.0,10000.0,0.0,10000.0,true));
      m_validator=new CSubmissionPreparationValidator(marketData,CMarketSafetyConfig());
      preparer=new CExecutionSubmissionPreparer(CSubmissionPreparationPolicy::Default(),
                                                *m_validator,
                                                registry,store,clock);
      gateway=new CSimulatedSubmissionGateway();
      submitUseCase=new CSubmitPreparedExecutionUseCase(registry,gateway,store,clock,NULL);
      events=new CInMemoryPendingExecutionEventBuffer(32);
      router=new CTradeTransactionRouter(registry,NULL,events,NULL,clock);
      injection=new CPendingExecutionTestInjectionService(registry,router);
      brokerInjector=new CSimulatedBrokerSubmissionInjector(registry,injection);
      CInMemoryBrokerPositionReader *brokerReader=new CInMemoryBrokerPositionReader();
      reconciliationScheduler=new CExecutionReconciliationScheduler(registry,brokerReader,NULL,8);
      timeoutMonitor=new CExecutionTimeoutMonitor(registry,reconciliationScheduler,NULL,clock);
     }

                    ~CSimulatedSubmissionTestHarness(void)
     {
      if(timeoutMonitor!=NULL) delete timeoutMonitor;
      if(reconciliationScheduler!=NULL) delete reconciliationScheduler;
      if(brokerInjector!=NULL) delete brokerInjector;
      if(injection!=NULL) delete injection;
      if(router!=NULL) delete router;
      if(events!=NULL) delete events;
      if(submitUseCase!=NULL) delete submitUseCase;
      if(gateway!=NULL) delete gateway;
      if(preparer!=NULL) delete preparer;
      if(m_validator!=NULL) delete m_validator;
      if(marketData!=NULL) delete marketData;
      if(clock!=NULL) delete clock;
      if(store!=NULL) delete store;
      if(registry!=NULL) delete registry;
     }

   void              Reset(void)
     {
      registry.Clear();
      store.Clear();
      gateway.Clear();
      submitUseCase.ClearCache();
      events.Clear();
      clock.SetNow(1000);
     }

   static CMarketQuote BuildFreshQuote(const string symbol,const double bid,const double ask,
                                       const int spreadPoints,const int ageMs)
     {
      return CMarketQuote::Create(symbol,bid,ask,spreadPoints,0.01,2,0.01,1.0,TimeCurrent(),ageMs,
                                  BRE_TRADING_SESSION_OPEN,
                                  CSymbolTradingConstraints::Create(20,10,0.01,100.0,0.01));
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

   CTradeExecutionRequest BuildRequest(const string requestId,const string idempotencyKey,const string basketIdValue,
                                       const double volume=0.10)
     {
      return CTradeExecutionRequest::Create(requestId,idempotencyKey,"corr",CBasketId(basketIdValue),1,
                                            "hash","EURUSD",BRE_EXEC_INTENT_OPEN_POSITION,
                                            BRE_DIRECTION_BUY,0,volume,0.0,0.0,0.0,1000,
                                            CCommandId("cmd"),"test");
     }

   bool              PrepareRequest(const string requestId,const string idempotencyKey,const string basketIdValue,
                                    CBrokerSubmissionEnvelope &envelope,const double volume=0.10)
     {
      CBasketAggregate basket=BuildBasket(basketIdValue);
      CTradeExecutionRequest request=BuildRequest(requestId,idempotencyKey,basketIdValue,volume);
      CSubmissionPreparationResult prep=preparer.Prepare(request,basket,TEST_MAGIC);
      if(!prep.IsSuccess())
         return false;
      envelope=prep.Envelope();
      return true;
     }

   void              ConfigureBrokerCorrelation(const string requestId)
     {
      CPendingExecutionEntry entry;
      if(!registry.TryGetByExecutionRequestId(requestId,entry))
         return;
      CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
      broker.SetMagicNumber(TEST_MAGIC);
      broker.SetCommentToken(entry.CorrelationToken());
      entry.SetBrokerCorrelation(broker);
      registry.Upsert(entry);
     }
  };

void TestPreparedRemainsQueuedBeforeSubmit(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-q","idem-q","b-q",envelope),"preparation must succeed");
   CPendingExecutionEntry entry;
   CTestAssert::True(h.registry.TryGetByExecutionRequestId("req-q",entry),"entry must exist");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)entry.Status(),"prepared request remains QUEUED before submit");
  }

void TestSimulatedSubmitTransitionsToSubmitted(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-sub","idem-sub","b-sub",envelope),"preparation must succeed");
   CPreparedSubmissionResult result=h.submitUseCase.Execute("req-sub");
   CTestAssert::True(result.IsSuccess(),"simulated submit must succeed");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)result.ResultingStatus(),"submit must reach SUBMITTED");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-sub",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)entry.Status(),"registry entry must be SUBMITTED");
   CTestAssert::True(entry.BrokerCorrelation().BrokerOrderId()>0,"broker placeholder id must be assigned");
  }

void TestAcknowledgementTransitionsToAcknowledged(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-ack","idem-ack","b-ack",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-ack").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-ack");
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE routeResult=h.brokerInjector.InjectAcknowledgement("req-ack",91001,TEST_MAGIC);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)routeResult,"ack must route");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-ack",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,(int)entry.Status(),"ack transitions to ACKNOWLEDGED");
  }

void TestFullFillThroughRouter(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-fill","idem-fill","b-fill",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-fill").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-fill");
   h.brokerInjector.InjectAcknowledgement("req-fill",91002,TEST_MAGIC);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE fillResult=h.brokerInjector.InjectFullFill("req-fill",72001,TEST_MAGIC);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)fillResult,"fill must route");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-fill",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)entry.Status(),"full fill reaches FILLED");
  }

void TestPartialFillAccumulation(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-partial","idem-partial","b-partial",envelope,0.10),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-partial").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-partial");
   h.brokerInjector.InjectAcknowledgement("req-partial",91003,TEST_MAGIC);
   h.brokerInjector.InjectPartialFill("req-partial",72002,0.04,TEST_MAGIC);
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-partial",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED,(int)entry.Status(),"first partial fill");
   h.brokerInjector.InjectPartialFill("req-partial",72003,0.06,TEST_MAGIC);
   h.registry.TryGetByExecutionRequestId("req-partial",entry);
   CTestAssert::EqualDouble(0.10,entry.FilledVolume(),0.0001,"partial fills accumulate");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)entry.Status(),"accumulated fill completes");
  }

void TestPartialFillThenReject(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-prej","idem-prej","b-prej",envelope,0.10),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-prej").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-prej");
   h.brokerInjector.InjectAcknowledgement("req-prej",91004,TEST_MAGIC);
   h.brokerInjector.InjectPartialFill("req-prej",72004,0.04,TEST_MAGIC);
   h.brokerInjector.InjectRejection("req-prej",91004,TEST_MAGIC);
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-prej",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)entry.Status(),"partial then reject preserved");
   CTestAssert::EqualDouble(0.04,entry.FilledVolume(),0.0001,"partial fill volume preserved");
  }

void TestGatewayRejectionWithoutSubmitted(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   h.gateway.SetScenario("idem-rej",BRE_SIM_SUBMIT_REJECT_BEFORE_ACK);
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-rej","idem-rej","b-rej",envelope),"preparation must succeed");
   CPreparedSubmissionResult result=h.submitUseCase.Execute("req-rej");
   CTestAssert::False(result.IsSuccess(),"gateway rejection must fail submit result");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)result.ResultingStatus(),"rejection terminal status");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-rej",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)entry.Status(),"entry must be REJECTED not SUBMITTED");
  }

void TestExpiredEnvelopeCannotSubmit(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-exp","idem-exp","b-exp",envelope),"preparation must succeed");
   h.clock.SetNow(envelope.ExpirationUtc()+1);
   CPreparedSubmissionResult result=h.submitUseCase.Execute("req-exp");
   CTestAssert::False(result.IsSuccess(),"expired envelope must block submit");
   CTestAssert::EqualInt((int)BRE_SUBMIT_FAIL_ENVELOPE_EXPIRED,(int)result.FailureReason(),"expired reason");
  }

void TestDuplicateSubmissionReturnsOriginalWithoutGatewayRecall(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-dup","idem-dup","b-dup",envelope),"preparation must succeed");
   CPreparedSubmissionResult first=h.submitUseCase.Execute("req-dup");
   CTestAssert::True(first.IsSuccess(),"first submit must succeed");
   int callsAfterFirst=h.gateway.GetSubmitCallCount("idem-dup");
   CPreparedSubmissionResult second=h.submitUseCase.Execute("req-dup");
   CTestAssert::True(second.IsDuplicateReplay(),"duplicate must replay original outcome");
   CTestAssert::False(second.GatewayInvoked(),"duplicate must not invoke gateway again");
   CTestAssert::EqualInt(callsAfterFirst,h.gateway.GetSubmitCallCount("idem-dup"),"gateway call count unchanged");
  }

void TestSubmittedRequestCannotResubmit(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-nore","idem-nore","b-nore",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-nore").IsSuccess(),"initial submit succeeds");
   h.submitUseCase.ClearCache();
   CPreparedSubmissionResult retry=h.submitUseCase.Execute("req-nore");
   CTestAssert::True(retry.IsDuplicateReplay(),"already submitted must replay");
   CTestAssert::False(retry.GatewayInvoked(),"resubmit must not call gateway");
  }

void TestTimeoutEntersReconciliationWithoutRetry(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-to","idem-to","b-to",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-to").IsSuccess(),"submit must succeed");
   h.clock.SetNow(envelope.ExpirationUtc()+1);
   int handled=h.timeoutMonitor.ScanDueTimeouts();
   CTestAssert::EqualInt(1,handled,"timeout must be handled");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-to",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)entry.Status(),"timeout enters reconciling");
   CTestAssert::True(CPendingExecutionTransitionRules::BlocksBlindResend(entry.Status()),"no blind resend after timeout");
   CPreparedSubmissionResult resubmit=h.submitUseCase.Execute("req-to");
   CTestAssert::False(resubmit.IsSuccess(),"resubmit blocked after timeout");
  }

void TestLateFillAfterTimeoutThroughReconciliation(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-late","idem-late","b-late",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-late").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-late");
   h.clock.SetNow(envelope.ExpirationUtc()+1);
   h.timeoutMonitor.ScanDueTimeouts();
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-late",entry);
   entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetPositionTicket(5100);
   entry.SetBrokerCorrelation(broker);
   h.registry.Upsert(entry);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.brokerInjector.InjectFullFill("req-late",73001,TEST_MAGIC);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_RECONCILED,(int)result,"late fill uses reconciliation path");
   h.registry.TryGetByExecutionRequestId("req-late",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)entry.Status(),"late fill resolves to FILLED");
  }

void TestRestartRestoresQueuedAndSubmitted(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelopeQueued;
   CTestAssert::True(h.PrepareRequest("req-rq","idem-rq","b-rq",envelopeQueued),"preparation must succeed");
   CBrokerSubmissionEnvelope envelopeSubmitted;
   CTestAssert::True(h.PrepareRequest("req-rs","idem-rs","b-rs",envelopeSubmitted),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-rs").IsSuccess(),"submit before restart");

   CPendingExecutionRegistry restored;
   string warnings[];
   int count=CPendingExecutionRestartService::RestorePreparedEntries(h.store,&restored,warnings);
   CTestAssert::True(count>=2,"restart restores entries");
   CPendingExecutionEntry restoredQueued;
   CTestAssert::True(restored.TryGetByExecutionRequestId("req-rq",restoredQueued),"queued entry restored");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_QUEUED,(int)restoredQueued.Status(),"restored queued stays QUEUED");
   CPendingExecutionEntry restoredSubmitted;
   CTestAssert::True(restored.TryGetByExecutionRequestId("req-rs",restoredSubmitted),"submitted entry restored");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)restoredSubmitted.Status(),"submitted metadata restored");
  }

void TestDuplicateTransactionAfterRestartIgnored(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-dtx","idem-dtx","b-dtx",envelope),"preparation must succeed");
   CTestAssert::True(h.submitUseCase.Execute("req-dtx").IsSuccess(),"submit must succeed");
   h.ConfigureBrokerCorrelation("req-dtx");
   h.brokerInjector.InjectAcknowledgement("req-dtx",91005,TEST_MAGIC);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE first=h.brokerInjector.InjectFullFill("req-dtx",72005,TEST_MAGIC);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)first,"first fill accepted");
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE duplicate=h.brokerInjector.InjectFullFill("req-dtx",72005,TEST_MAGIC);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_DUPLICATE,(int)duplicate,"duplicate transaction ignored");
  }

void TestSimulatedGatewayNeverCallsMt5(CSimulatedSubmissionTestHarness &h)
  {
   CTestAssert::True(h.gateway.IsSimulated(),"gateway must declare simulated mode");
  }

void TestCompositionGuardBlocksProductionAutoWire(void)
  {
   CSimulatedSubmissionGateway gateway;
   CTestAssert::True(gateway.IsSimulated(),"simulated gateway flag");
   CTestAssert::False(CSubmissionGatewayCompositionGuard::AllowsProductionAutoWire(0,&gateway),
                      "simulated gateway blocked from production auto-wire");
   CTestAssert::True(CSubmissionGatewayCompositionGuard::BlocksBootstrapRegistration(&gateway),
                     "bootstrap must block simulated gateway registration");
  }

void TestApplicationContextDoesNotWireSubmission(void)
  {
   CApplicationContext context;
   CTestAssert::False(context.IsSubmissionGatewayWiredToProduction(),"production gateway not wired");
   CTestAssert::False(context.IsSubmitPreparedExecutionWiredToTimer(),"timer route does not invoke submission");
   CTestAssert::False(context.IsMt5ExecutorWiredToTimerPipeline(),"mt5 executor not on timer pipeline");
  }

void TestGatewayUnknownBlocksWithoutSubmitted(CSimulatedSubmissionTestHarness &h)
  {
   h.Reset();
   h.gateway.SetScenario("idem-unk",BRE_SIM_SUBMIT_ACCEPT_UNKNOWN);
   CBrokerSubmissionEnvelope envelope;
   CTestAssert::True(h.PrepareRequest("req-unk","idem-unk","b-unk",envelope),"preparation must succeed");
   CPreparedSubmissionResult result=h.submitUseCase.Execute("req-unk");
   CTestAssert::False(result.IsSuccess(),"unknown gateway outcome fails submit");
   CPendingExecutionEntry entry;
   h.registry.TryGetByExecutionRequestId("req-unk",entry);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_UNKNOWN,(int)entry.Status(),"unknown terminal without submitted");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CSimulatedSubmissionTestHarness harness;

   TestPreparedRemainsQueuedBeforeSubmit(harness);
   TestSimulatedSubmitTransitionsToSubmitted(harness);
   TestAcknowledgementTransitionsToAcknowledged(harness);
   TestFullFillThroughRouter(harness);
   TestPartialFillAccumulation(harness);
   TestPartialFillThenReject(harness);
   TestGatewayRejectionWithoutSubmitted(harness);
   TestExpiredEnvelopeCannotSubmit(harness);
   TestDuplicateSubmissionReturnsOriginalWithoutGatewayRecall(harness);
   TestSubmittedRequestCannotResubmit(harness);
   TestTimeoutEntersReconciliationWithoutRetry(harness);
   TestLateFillAfterTimeoutThroughReconciliation(harness);
   TestRestartRestoresQueuedAndSubmitted(harness);
   TestDuplicateTransactionAfterRestartIgnored(harness);
   TestSimulatedGatewayNeverCallsMt5(harness);
   TestCompositionGuardBlocksProductionAutoWire();
   TestApplicationContextDoesNotWireSubmission();
   TestGatewayUnknownBlocksWithoutSubmitted(harness);

   CTestAssert::Summary("TestSimulatedSubmission");
   if(!CTestAssert::AllPassed())
      Print("TestSimulatedSubmission FAILED");
  }
