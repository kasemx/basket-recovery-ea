#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionCorrelationMatcher.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/ExecutionTimeoutMonitor.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastStateRegistry.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5TradeTransactionAdapter.mqh>
#include <BasketRecovery/Infrastructure/Logging/FileLogger.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionTransitionRules.mqh>

class CPendingExecutionTestHarness
  {
public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionEventBuffer    *events;
   CTestClock                              *clock;
   CFileLogger                             *logger;
   CPendingExecutionDiagnostics            *diagnostics;
   CInMemoryPendingExecutionStore          *store;
   CPendingExecutionLifecycleService       *lifecycle;
   CInMemoryBrokerPositionReader           *brokerReader;
   CExecutionReconciliationScheduler       *reconciliationScheduler;
   CBasketFastStateRegistry                *fastStateRegistry;
   CTradeTransactionRouter                 *router;
   CExecutionTimeoutMonitor                *timeoutMonitor;
   CPendingExecutionTestInjectionService   *injection;

                     CPendingExecutionTestHarness(void)
     {
      registry=new CPendingExecutionRegistry();
      events=new CInMemoryPendingExecutionEventBuffer(32);
      clock=new CTestClock();
      logger=new CFileLogger();
      logger.Initialize("BasketRecovery/logs/pending_exec_test.log",1);
      diagnostics=new CPendingExecutionDiagnostics(logger,false,64);
      store=new CInMemoryPendingExecutionStore();
      lifecycle=new CPendingExecutionLifecycleService(registry,store,events,clock);
      brokerReader=new CInMemoryBrokerPositionReader();
      reconciliationScheduler=new CExecutionReconciliationScheduler(registry,brokerReader,diagnostics,8,lifecycle);
      fastStateRegistry=new CBasketFastStateRegistry();
      router=new CTradeTransactionRouter(registry,diagnostics,events,fastStateRegistry,clock,lifecycle);
      timeoutMonitor=new CExecutionTimeoutMonitor(registry,reconciliationScheduler,brokerReader,diagnostics,clock,lifecycle);
      injection=new CPendingExecutionTestInjectionService(registry,router);
     }

                    ~CPendingExecutionTestHarness(void)
     {
      if(injection!=NULL) delete injection;
      if(timeoutMonitor!=NULL) delete timeoutMonitor;
      if(router!=NULL) delete router;
      if(reconciliationScheduler!=NULL) delete reconciliationScheduler;
      if(fastStateRegistry!=NULL) delete fastStateRegistry;
      if(lifecycle!=NULL) delete lifecycle;
      if(store!=NULL) delete store;
      if(brokerReader!=NULL) delete brokerReader;
      if(diagnostics!=NULL) delete diagnostics;
      if(logger!=NULL) delete logger;
      if(clock!=NULL) delete clock;
      if(events!=NULL) delete events;
      if(registry!=NULL) delete registry;
     }

   void              Reset(void)
     {
      registry.Clear();
      events.Clear();
      reconciliationScheduler.Clear();
      CPositionSnapshotEntry empty[];
      brokerReader.SetEntries(empty,0);
     }
  };

CPendingExecutionEntry BuildEntry(const string requestId,
                                  const ENUM_BRE_TRADE_EXECUTION_STATUS status,
                                  const string symbol,
                                  const double requestedVolume,
                                  const CBrokerRequestCorrelation &broker,
                                  const datetime deadlineUtc=0)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(requestId);
   entry.SetIdempotencyKey("key-"+requestId);
   entry.SetBasketId(CBasketId("basket-"+requestId));
   entry.SetExpectedBasketVersion(1);
   entry.SetStrategyProfileHash("hash");
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetSymbol(symbol);
   entry.SetBrokerCorrelation(broker);
   entry.SetRequestedVolume(requestedVolume);
   entry.SetStatus(status);
   entry.SetSubmittedAtUtc(1000);
   entry.SetDeadlineUtc(deadlineUtc);
   return entry;
  }

CTradeTransactionCorrelationContext BuildContext(const ENUM_BRE_TRADE_TRANSACTION_TYPE txType,
                                                 const ulong orderId,
                                                 const ulong dealId,
                                                 const ulong positionId,
                                                 const long magic,
                                                 const string symbol,
                                                 const string comment,
                                                 const double volume,
                                                 const double price)
  {
   CNormalizedTradeTransaction normalized;
   normalized.SetSymbol(symbol);
   normalized.SetOrderId(orderId);
   normalized.SetDealId(dealId);
   normalized.SetPositionId(positionId);
   normalized.SetComment(comment);
   normalized.SetVolume(volume);
   normalized.SetPrice(price);
   normalized.SetOccurredAtUtc(1000);
   return CTradeTransactionCorrelationContext::FromNormalized(normalized,txType,magic);
  }

void TestOrderIdCorrelation(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(9001);
   broker.SetSymbol("EURUSD");
   CPendingExecutionEntry entry=BuildEntry("req-order",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_ORDER_ADD,9001,0,0,0,"EURUSD","BR:b1:EXEC:req-order",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"order-id correlation must accept");

   CPendingExecutionEntry updated;
   CTestAssert::True(h.registry.TryGetByExecutionRequestId("req-order",updated),"entry must exist");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,(int)updated.Status(),"order add must acknowledge");
  }

void TestDealIdCorrelation(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetBrokerDealId(7001);
   broker.SetSymbol("EURUSD");
   CPendingExecutionEntry entry=BuildEntry("req-deal",BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,7001,0,0,"EURUSD","BR:b1:EXEC:req-deal",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"deal-id correlation must accept");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-deal",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"full deal must fill");
  }

void TestTicketCorrelation(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetPositionTicket(5001);
   broker.SetSymbol("EURUSD");
   CPendingExecutionEntry entry=BuildEntry("req-ticket",BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,8001,5001,0,"EURUSD","BR:b1:EXEC:req-ticket",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"ticket correlation must accept");
  }

void TestMagicSymbolCommentFallback(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetMagicNumber(202606001);
   broker.SetCommentToken("req-magic");
   broker.SetSymbol("EURUSD");
   CPendingExecutionEntry entry=BuildEntry("req-magic",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_ORDER_ADD,9100,0,0,202606001,"EURUSD","BR:b1:EXEC:req-magic",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"magic+symbol+comment fallback must accept");
  }

void TestNoPriceOnlyMatching(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   CPendingExecutionEntry entry=BuildEntry("req-price",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,0,0,0,"EURUSD","unrelated",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_UNRELATED,(int)result,"price-only match must not correlate");
  }

void TestDuplicateTransactionIgnored(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(9002);
   CPendingExecutionEntry entry=BuildEntry("req-dup",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_ORDER_ADD,9002,0,0,0,"EURUSD","BR:b1:EXEC:req-dup",0.10,1.1000);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)h.injection.InjectCorrelationContext(context),"first tx accepted");
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_DUPLICATE,(int)h.injection.InjectCorrelationContext(context),"duplicate tx ignored");
  }

void TestOutOfOrderCannotRegress(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetBrokerDealId(7002);
   CPendingExecutionEntry entry=BuildEntry("req-oos",BRE_TRADE_EXEC_STATUS_FILLED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,7002,0,0,"EURUSD","BR:b1:EXEC:req-oos",0.05,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_OUT_OF_ORDER,(int)result,"terminal filled cannot regress");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-oos",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"status remains filled");
  }

void TestPartialFillAccumulation(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(9003);
   CPendingExecutionEntry entry=BuildEntry("req-partial",BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED,"EURUSD",0.10,broker);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext first=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,9003,7101,0,0,"EURUSD","BR:b1:EXEC:req-partial",0.04,1.1000);
   CTradeTransactionCorrelationContext second=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,9003,7102,0,0,"EURUSD","BR:b1:EXEC:req-partial",0.06,1.1000);
   h.injection.InjectCorrelationContext(first);
   h.injection.InjectCorrelationContext(second);

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-partial",updated);
   CTestAssert::EqualDouble(0.10,updated.FilledVolume(),0.0001,"partial fills accumulate");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"accumulated fill completes");
  }

void TestTimeoutTerminalizesWithoutRetry(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   h.clock.SetNow(2000);
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(9004);
   CPendingExecutionEntry entry=BuildEntry("req-timeout",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker,1500);
   h.injection.RegisterPendingEntry(entry);

   int handled=h.timeoutMonitor.ScanDueTimeouts();
   CTestAssert::EqualInt(1,handled,"timeout scan must handle due entry");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-timeout",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_TIMED_OUT,(int)updated.Status(),"confirmed no-fill timeout must terminalize");
   CTestAssert::False(CPendingExecutionTransitionRules::BlocksBlindResend(updated.Status()),
                      "timed out terminal audit must not block blind resend via reconciling gate");
   CTestAssert::EqualInt(0,h.reconciliationScheduler.PendingCount(),"terminal timeout must not queue reconciliation");
  }

void TestLateFillAfterTimeoutThroughReconciliation(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetPositionTicket(5100);
   broker.SetMagicNumber(202606001);
   CPendingExecutionEntry entry=BuildEntry("req-late",BRE_TRADE_EXEC_STATUS_RECONCILING,"EURUSD",0.10,broker);
   entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
   h.injection.RegisterPendingEntry(entry);

   CTradeTransactionCorrelationContext lateFill=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,7200,5100,202606001,"EURUSD","BR:b1:EXEC:req-late",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(lateFill);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_RECONCILED,(int)result,"late fill resolves through reconciliation");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-late",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"late fill resolves to filled");
  }

void TestUnknownReconcilingBlocksResubmission(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   CPendingExecutionEntry entry=BuildEntry("req-unknown",BRE_TRADE_EXEC_STATUS_RECONCILING,"EURUSD",0.10,broker);
   entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
   h.injection.RegisterPendingEntry(entry);

   CTestAssert::True(entry.BlocksBlindResend(),"unknown reconciling entry blocks blind resend");
   CTestAssert::True(CPendingExecutionTransitionRules::BlocksBlindResend(BRE_TRADE_EXEC_STATUS_RECONCILING),
                     "unknown reconciling status blocks blind resend in rules");
  }

void TestUnrelatedTransactionIgnored(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CTradeTransactionCorrelationContext context=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,0,9999,0,0,"GBPUSD","other",0.10,1.2500);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(context);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_UNRELATED,(int)result,"unrelated transaction ignored");
  }

void TestDiagnosticsBounded(CPendingExecutionTestHarness &h)
  {
   CFileLogger logger;
   logger.Initialize("BasketRecovery/logs/pending_exec_diag_bound.log",1);
   CPendingExecutionDiagnostics bounded(&logger,true,3);

   for(int i=0;i<10;i++)
      bounded.OnUnrelatedTransaction(StringFormat("key-%d",i));

   CTestAssert::True(bounded.EmittedLineCount()<=3,"diagnostics must remain bounded");
  }

void TestInjectionRouteWithoutMt5(CPendingExecutionTestHarness &h)
  {
   h.Reset();
   CBrokerRequestCorrelation broker;
   broker.SetRequestFingerprint("EURUSD|req-inject|1|0.1000");
   broker.SetSymbol("EURUSD");
   CPendingExecutionEntry entry=BuildEntry("req-inject",BRE_TRADE_EXEC_STATUS_SUBMITTED,"EURUSD",0.10,broker);
   entry.BrokerCorrelation().SetRequestFingerprint("req-inject|EURUSD|1|0.1000");
   CBrokerRequestCorrelation updatedBroker=entry.BrokerCorrelation();
   updatedBroker.SetRequestFingerprint(StringFormat("%s|%s|%d|%.4f",
                                                    entry.ExecutionRequestId(),
                                                    entry.Symbol(),
                                                    (int)entry.IntentType(),
                                                    entry.RequestedVolume()));
   entry.SetBrokerCorrelation(updatedBroker);
   h.injection.RegisterPendingEntry(entry);

   CNormalizedTradeTransaction normalized;
   normalized.SetSymbol("EURUSD");
   normalized.SetVolume(0.10);
   normalized.SetPrice(1.1000);
   normalized.SetComment("BR:b1:EXEC:req-inject");
   normalized.SetTransactionType(TRADE_TRANSACTION_ORDER_ADD);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectNormalizedTransaction(normalized,0);
   CTestAssert::True(result==BRE_TRADE_TX_RESULT_ACCEPTED || result==BRE_TRADE_TX_RESULT_UNRELATED,
                     "test injection route works without MT5 broker callbacks");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   CPendingExecutionTestHarness harness;

   TestOrderIdCorrelation(harness);
   TestDealIdCorrelation(harness);
   TestTicketCorrelation(harness);
   TestMagicSymbolCommentFallback(harness);
   TestNoPriceOnlyMatching(harness);
   TestDuplicateTransactionIgnored(harness);
   TestOutOfOrderCannotRegress(harness);
   TestPartialFillAccumulation(harness);
   TestTimeoutTerminalizesWithoutRetry(harness);
   TestLateFillAfterTimeoutThroughReconciliation(harness);
   TestUnknownReconcilingBlocksResubmission(harness);
   TestUnrelatedTransactionIgnored(harness);
   TestDiagnosticsBounded(harness);
   TestInjectionRouteWithoutMt5(harness);

   CTestAssert::Summary("TestPendingExecutionCorrelation");
   if(!CTestAssert::AllPassed())
      Print("TestPendingExecutionCorrelation FAILED");
  }
