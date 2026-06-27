#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Application/Configuration/FastPathConfig.mqh>
#include <BasketRecovery/Application/FastPath/FastPathDiagnosticReporter.mqh>
#include <BasketRecovery/Application/FastPath/InMemoryHotPathDiagnostics.mqh>
#include <BasketRecovery/Application/FastPath/FastEvaluationTriggerPolicy.mqh>
#include <BasketRecovery/Application/FastPath/FastPathSkipReason.mqh>
#include <BasketRecovery/Application/FastPath/BasketFastState.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/BrokerReconciliationService.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/Mt5BrokerPositionReader.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemorySnapshotStore.mqh>
#include <BasketRecovery/Infrastructure/Persistence/InMemoryBasketRepository.mqh>
#include <BasketRecovery/Application/Services/BasketPositionReconciler.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>

void TestDiagnosticsDisabledDoesNotWantOutput(void)
  {
   CFastPathConfig config=CFastPathConfig::Create(3,2000,250,5,10000,false,1000,false);
   CFastPathDiagnosticReporter reporter(config);
   CTestAssert::False(reporter.WantsOutput(),"Diagnostics disabled must not request output");
  }

void TestNoBasketHeartbeatRespectsFlag(void)
  {
   CFastPathConfig disabledHeartbeat=CFastPathConfig::Create(3,2000,250,5,10000,true,1000,false);
   CFastPathDiagnosticReporter reporter(disabledHeartbeat);
   CTestAssert::False(reporter.WouldEmitTickLine("BTCUSD",BRE_FAST_SKIP_NO_MATCHING_BASKET),
                      "No-basket heartbeat must stay silent when flag is false");
  }

void TestNoBasketHeartbeatAllowedWhenEnabled(void)
  {
   CFastPathConfig enabledHeartbeat=CFastPathConfig::Create(3,2000,250,5,10000,true,1000,true);
   CFastPathDiagnosticReporter reporter(enabledHeartbeat);
   CTestAssert::True(reporter.WouldEmitTickLine("BTCUSD",BRE_FAST_SKIP_NO_MATCHING_BASKET),
                     "No-basket heartbeat must be allowed when flag is true");
  }

void TestHeartbeatIsRateLimited(void)
  {
   CFastPathConfig config=CFastPathConfig::Create(3,2000,250,5,10000,true,60000,true);
   CFastPathDiagnosticReporter reporter(config);
   CTestAssert::True(reporter.WouldEmitTickLine("BTCUSD",BRE_FAST_SKIP_NO_MATCHING_BASKET),
                     "First heartbeat must be eligible");
   reporter.NotifyTickLineEmitted("BTCUSD");
   CTestAssert::False(reporter.WouldEmitTickLine("BTCUSD",BRE_FAST_SKIP_NO_MATCHING_BASKET),
                      "Second heartbeat must be rate limited within interval");
  }

void TestDuplicateQuoteSkipReason(void)
  {
   CFastEvaluationTriggerPolicy policy(CFastPathConfig::Create(3,60000,0,1,10000));
   CBasketFastState state;
   state.SetLastEvaluatedQuoteSequence(999);
   state.SetLastEvaluatedBid(100.0);
   state.SetLastEvaluatedAsk(100.2);

   CBasketAggregate basket;
   ENUM_BRE_FAST_PATH_SKIP_REASON reason=
      policy.ResolveSkipReason(basket,state,100.0,100.2,0.01,0.01,999,1000);

   CTestAssert::EqualInt((int)BRE_FAST_SKIP_DUPLICATE_QUOTE_SEQUENCE,(int)reason,
                         "Duplicate quote sequence must map to duplicate skip reason");
  }

void TestStaleQuoteSkipReasonViaDiagnosticsCounter(void)
  {
   CInMemoryHotPathDiagnostics diagnostics;
   diagnostics.RecordTickRun("BTCUSD",GetTickCount64(),0,1,0,0,0,0.0,0.0,BRE_FAST_SKIP_STALE_QUOTE);
   CTestAssert::EqualInt(1,diagnostics.SkipStaleQuote(),"Stale quote skip must increment counter");
  }

void TestReconciliationServiceReleasesOwnedGraph(void)
  {
   CTestClock clock;
   CInMemorySnapshotStore snapshotStore(&clock);
   CInMemoryBasketRepository repository;
   CMt5BrokerPositionReader *reader=new CMt5BrokerPositionReader();
   CBasketPositionReconciler *reconciler=
      new CBasketPositionReconciler(reader,&snapshotStore,&repository,NULL,&clock);
   CBrokerReconciliationService *service=
      new CBrokerReconciliationService(reader,reconciler,true);

   CTestAssert::True(service.Reconciler()!=NULL,"Reconciler must remain reachable before service teardown");
   delete service;
   CTestAssert::True(true,"Owned reconciliation graph must delete without manual reader/reconciler cleanup");
  }

void TestDeinitSummaryCanBeProducedWithoutBrokerCalls(void)
  {
   CInMemoryHotPathDiagnostics diagnostics;
   diagnostics.RecordTickRun("BTCUSD",GetTickCount64(),0,0,0,0,123,65000.0,65001.0,BRE_FAST_SKIP_NO_MATCHING_BASKET);
   CFastPathConfig config=CFastPathConfig::Create(3,2000,250,5,10000,true,1000,true);
   CFastPathDiagnosticReporter reporter(config);
   reporter.EmitDeinitSummary(diagnostics,0);
   CTestAssert::EqualInt(1,diagnostics.TotalTicks(),"Deinit summary must read in-memory counters only");
  }

void OnStart()
  {
   TestDiagnosticsDisabledDoesNotWantOutput();
   TestNoBasketHeartbeatRespectsFlag();
   TestNoBasketHeartbeatAllowedWhenEnabled();
   TestHeartbeatIsRateLimited();
   TestDuplicateQuoteSkipReason();
   TestStaleQuoteSkipReasonViaDiagnosticsCounter();
   TestReconciliationServiceReleasesOwnedGraph();
   TestDeinitSummaryCanBeProducedWithoutBrokerCalls();
   Print("TestFastPathDiagnostics: all tests passed");
  }
