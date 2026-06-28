#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Tests/TestClock.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionLifecycleService.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionStartupReconciliationService.mqh>
#include <BasketRecovery/Application/Execution/TradeTransactionRouter.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionDiagnostics.mqh>
#include <BasketRecovery/Application/Execution/InMemoryPendingExecutionEventBuffer.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionTestInjectionService.mqh>
#include <BasketRecovery/Application/Execution/RecoveryStepExecutionTracker.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Infrastructure/Execution/InMemoryPendingExecutionStore.mqh>
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerPositionReader.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionQuery.mqh>

class CTestFillNotifier : public IPendingExecutionFillNotifier
  {
private:
   CRecoveryStepExecutionTracker *m_tracker;
   int                            m_fillCalls;

public:
                     CTestFillNotifier(CRecoveryStepExecutionTracker *tracker)
     {
      m_tracker=tracker;
      m_fillCalls=0;
     }

   int               FillCalls(void) const { return m_fillCalls; }

   virtual void      OnBrokerFillConfirmed(const string executionRequestId) override
     {
      m_fillCalls++;
      if(m_tracker!=NULL)
         m_tracker.TryMarkFilled(executionRequestId);
     }
  };

#include <BasketRecovery/Application/Execution/ExecutionTimeoutMonitor.mqh>
#include <BasketRecovery/Application/Execution/ExecutionReconciliationScheduler.mqh>
#include <BasketRecovery/Domain/Snapshots/PositionSnapshotEntry.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFailingBrokerPositionReader : public IBrokerPositionReader
  {
public:
   virtual CResult<int> ReadOpenPositions(CPositionSnapshotEntry &outEntries[],const int maxEntries) const
     {
      return CResult<int>::Fail(BRE_ERR_SNAPSHOT_APPLY_FAILED,"indeterminate broker read");
     }
  };

class CTerminalizationHarness
  {
public:
   CPendingExecutionRegistry               *registry;
   CInMemoryPendingExecutionStore          *store;
   CInMemoryPendingExecutionEventBuffer    *events;
   CTestClock                              *clock;
   CPendingExecutionLifecycleService       *lifecycle;
   CTradeTransactionRouter                 *router;
   CPendingExecutionTestInjectionService   *injection;
   CRecoveryStepExecutionTracker           *stepTracker;
   CInMemoryBrokerPositionReader           *brokerReader;
   CFailingBrokerPositionReader            *failingReader;
   CExecutionReconciliationScheduler       *reconciliationScheduler;
   CExecutionTimeoutMonitor                *timeoutMonitor;

                     CTerminalizationHarness(void)
     {
      registry=new CPendingExecutionRegistry();
      store=new CInMemoryPendingExecutionStore();
      events=new CInMemoryPendingExecutionEventBuffer(32);
      clock=new CTestClock();
      lifecycle=new CPendingExecutionLifecycleService(registry,store,events,clock);
      router=new CTradeTransactionRouter(registry,NULL,events,NULL,clock,lifecycle);
      injection=new CPendingExecutionTestInjectionService(registry,router);
      stepTracker=new CRecoveryStepExecutionTracker();
      brokerReader=new CInMemoryBrokerPositionReader();
      failingReader=new CFailingBrokerPositionReader();
      reconciliationScheduler=new CExecutionReconciliationScheduler(registry,brokerReader,NULL,8,lifecycle);
      timeoutMonitor=new CExecutionTimeoutMonitor(registry,reconciliationScheduler,brokerReader,NULL,clock,lifecycle);
     }

                    ~CTerminalizationHarness(void)
     {
      if(timeoutMonitor!=NULL) delete timeoutMonitor;
      if(reconciliationScheduler!=NULL) delete reconciliationScheduler;
      if(failingReader!=NULL) delete failingReader;
      if(brokerReader!=NULL) delete brokerReader;
      if(stepTracker!=NULL) delete stepTracker;
      if(injection!=NULL) delete injection;
      if(router!=NULL) delete router;
      if(lifecycle!=NULL) delete lifecycle;
      if(clock!=NULL) delete clock;
      if(events!=NULL) delete events;
      if(store!=NULL) delete store;
      if(registry!=NULL) delete registry;
     }

   void              Reset(void)
     {
      registry.Clear();
      store.Clear();
      events.Clear();
      CPositionSnapshotEntry empty[];
      brokerReader.SetEntries(empty,0);
     }
  };

CPendingExecutionEntry BuildSubmittedEntry(const string requestId,const CBasketId &basketId)
  {
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId(requestId);
   entry.SetIdempotencyKey("idem-"+requestId);
   entry.SetBasketId(basketId);
   entry.SetExpectedBasketVersion(1);
   entry.SetStrategyProfileHash("hash");
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetSymbol("EURUSD");
   entry.SetRequestedVolume(0.10);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   entry.SetSubmittedAtUtc(1000);
   CBrokerRequestCorrelation broker;
   broker.SetBrokerOrderId(9001);
   entry.SetBrokerCorrelation(broker);
   return entry;
  }

CBrokerSubmissionEnvelope BuildEnvelope(const CPendingExecutionEntry &entry)
  {
   CBrokerSubmissionEnvelope envelope;
   envelope.SetIdempotencyKey(entry.IdempotencyKey());
   envelope.SetExecutionRequestId(entry.ExecutionRequestId());
   envelope.SetSymbol(entry.Symbol());
   return envelope;
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

void TestFillPersistsTerminalState(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-fill");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-fill",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetBrokerDealId(7001);
   entry.SetBrokerCorrelation(broker);
   CBrokerSubmissionEnvelope envelope=BuildEnvelope(entry);
   h.store.SavePreparedState(entry,envelope);
   h.registry.Upsert(entry);

   CTradeTransactionCorrelationContext dealContext=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,
                                                                0,7001,0,0,"EURUSD","BR:b1:EXEC:req-fill",0.10,1.1000);
   ENUM_BRE_TRADE_TRANSACTION_RESULT_CODE result=h.injection.InjectCorrelationContext(dealContext);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,(int)result,"deal fill must accept");

   CPendingExecutionEntry updated;
   CTestAssert::True(h.registry.TryGetByExecutionRequestId("req-fill",updated),"registry entry must exist");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"registry must be FILLED");

   CPendingExecutionEntry persisted[];
   int count=h.store.RestoreEntries(persisted);
   CTestAssert::EqualInt(1,count,"store must contain one entry");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)persisted[0].Status(),"persisted entry must be FILLED");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*h.registry,basketId),
                      "FILLED must not block recovery");
  }

void TestDuplicateFillIsIdempotent(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-dup");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-dup",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);
   h.stepTracker.MarkSubmitted(basketId.Value(),1,"req-dup");

   CTradeTransactionCorrelationContext dealContext=BuildContext(BRE_TRADE_TX_TYPE_DEAL_ADD,
                                                                0,7002,0,0,"EURUSD","BR:b1:EXEC:req-dup",0.10,1.1000);
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_ACCEPTED,
                         (int)h.injection.InjectCorrelationContext(dealContext),
                         "first fill must accept");
   CTestAssert::EqualInt((int)BRE_TRADE_TX_RESULT_DUPLICATE,
                         (int)h.injection.InjectCorrelationContext(dealContext),
                         "duplicate fill must not transition again");

   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-dup",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"status remains FILLED");
  }

void TestRecoveryStepAdvancesOnce(CTerminalizationHarness &h)
  {
   h.Reset();
   CTestFillNotifier notifier(h.stepTracker);
   CBasketId basketId("basket-step");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-step",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);
   h.stepTracker.MarkSubmitted(basketId.Value(),2,"req-step");

   h.lifecycle.MarkFilled("req-step",0.10);
   notifier.OnBrokerFillConfirmed("req-step");
   notifier.OnBrokerFillConfirmed("req-step");

   CTestAssert::True(h.stepTracker.IsStepExecuted(basketId.Value(),2),"step must be filled once");
   CTestAssert::EqualInt(2,notifier.FillCalls(),"fill notifier invoked twice but step idempotent");
  }

void TestRejectedDoesNotAdvanceStep(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-reject");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-reject",basketId);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);
   h.stepTracker.MarkSubmitted(basketId.Value(),1,"req-reject");

   CTestAssert::True(h.lifecycle.MarkRejected("req-reject"),"reject must terminalize");
   CTestAssert::False(h.stepTracker.IsStepExecuted(basketId.Value(),1),"reject must not fill step");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*h.registry,basketId),
                      "rejected must not block as unresolved");
  }

void TestPersistedFilledNotUnresolvedAfterRestart(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-restart-filled");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-restart-filled",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_FILLED);
   entry.SetFilledVolume(0.10);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CTestFillNotifier notifier(h.stepTracker);
   int reconciled=CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                                           &restartedRegistry,
                                                                                           &restartedLifecycle,
                                                                                           h.brokerReader,
                                                                                           &notifier);
   CTestAssert::EqualInt(0,reconciled,"terminal FILLED should not reconcile");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "persisted FILLED must not be unresolved");
   CPendingExecutionEntry history[];
   CTestAssert::EqualInt(1,
                         CPendingExecutionLifecycleService::GetTerminalExecutionHistory(restartedRegistry,basketId,history),
                         "terminal history must include FILLED");
  }

void TestPersistedSubmittedReconciledOnRestart(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-restart-submitted");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-restart-submitted",basketId);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetPositionTicket(5001);
   entry.SetBrokerCorrelation(broker);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CPositionSnapshotEntry positions[];
   ArrayResize(positions,1);
   positions[0]=CPositionSnapshotEntry::Create(CBasketId("basket-restart-submitted"),
                                               5001,0,"EURUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_RECOVERY,3,
                                               1.1000,1.1000,0.0,0.0,0.10,0.0,0.0,0.0,1000,
                                               BRE_POSITION_SNAPSHOT_OPEN,"");
   h.brokerReader.SetEntries(positions,1);

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CTestFillNotifier notifier(h.stepTracker);
   h.stepTracker.MarkSubmitted(basketId.Value(),3,"req-restart-submitted");
   int reconciled=CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                                           &restartedRegistry,
                                                                                           &restartedLifecycle,
                                                                                           h.brokerReader,
                                                                                           &notifier);
   CTestAssert::EqualInt(1,reconciled,"submitted must reconcile to terminal");
   CPendingExecutionEntry updated;
   CTestAssert::True(restartedRegistry.TryGetByExecutionRequestId("req-restart-submitted",updated),"entry restored");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"restart must resolve FILLED");
   CPendingExecutionEntry persisted[];
   h.store.RestoreEntries(persisted);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)persisted[0].Status(),"disk must persist FILLED");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "reconciled fill must not block recovery");
  }

void TestTerminalHistoryDoesNotAutoSubmit(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-history");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-history",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_REJECTED);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                            &restartedRegistry,
                                                                            &restartedLifecycle,
                                                                            h.brokerReader,
                                                                            NULL);
   CTestAssert::EqualInt(1,restartedRegistry.Count(),"restart loads terminal history without auto submit");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "terminal rejected must not block");
  }

void TestTimedOutIsTerminalAndDoesNotBlockRecovery(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-timed-out");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-timed-out",basketId);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);

   CTestAssert::True(h.lifecycle.MarkTimedOut("req-timed-out"),"timed out must terminalize");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-timed-out",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_TIMED_OUT,(int)updated.Status(),"status must be TIMED_OUT");
   CTestAssert::True(CPendingExecutionQuery::IsTerminalStatus(updated.Status()),"TIMED_OUT is terminal");
   CTestAssert::False(CPendingExecutionQuery::IsUnresolvedStatus(updated.Status()),"TIMED_OUT must not be unresolved");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*h.registry,basketId),
                      "TIMED_OUT must not block recovery");
   CPendingExecutionEntry history[];
   CTestAssert::EqualInt(1,
                         CPendingExecutionLifecycleService::GetTerminalExecutionHistory(*h.registry,basketId,history),
                         "terminal history must include TIMED_OUT");
   CPendingExecutionEntry persisted[];
   h.store.RestoreEntries(persisted);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_TIMED_OUT,(int)persisted[0].Status(),"TIMED_OUT must persist");
  }

void TestUnknownReconcilingBlocksRecovery(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-unknown");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-unknown",basketId);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);

   CTestAssert::True(h.lifecycle.MarkUnknownReconciling("req-unknown"),"unknown reconciling must apply");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-unknown",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)updated.Status(),"status must be UNKNOWN_RECONCILING");
   CTestAssert::True(CPendingExecutionQuery::IsUnknownReconcilingStatus(updated.Status()),"reconciling is unknown reconciling");
   CTestAssert::True(CPendingExecutionQuery::IsUnresolvedStatus(updated.Status()),"unknown reconciling is unresolved");
   CTestAssert::True(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*h.registry,basketId),
                     "UNKNOWN_RECONCILING must block recovery");
  }

void TestRestartLoadsTimedOutAsTerminalAudit(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-restart-timeout");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-restart-timeout",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_TIMED_OUT);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   int reconciled=CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                                           &restartedRegistry,
                                                                                           &restartedLifecycle,
                                                                                           h.brokerReader,
                                                                                           NULL);
   CTestAssert::EqualInt(0,reconciled,"TIMED_OUT restart is audit only");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "persisted TIMED_OUT must not be unresolved");
  }

void TestRestartLoadsUnknownReconcilingAsUnresolved(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-restart-unknown");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-restart-unknown",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_RECONCILING);
   entry.SetCorrelationState(BRE_PENDING_CORRELATION_RECONCILING);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CPositionSnapshotEntry positions[];
   ArrayResize(positions,1);
   positions[0]=CPositionSnapshotEntry::Create(basketId,5100,0,"EURUSD",BRE_DIRECTION_BUY,BRE_TRADE_ROLE_RECOVERY,1,
                                               1.1000,1.1000,0.0,0.0,0.10,0.0,0.0,0.0,1000,
                                               BRE_POSITION_SNAPSHOT_OPEN,"");
   h.brokerReader.SetEntries(positions,1);
   int reconciled=CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                                           &restartedRegistry,
                                                                                           &restartedLifecycle,
                                                                                           h.brokerReader,
                                                                                           NULL);
   CTestAssert::EqualInt(1,reconciled,"unknown reconciling must reconcile on restart");
   CPendingExecutionEntry updated;
   CTestAssert::True(restartedRegistry.TryGetByExecutionRequestId("req-restart-unknown",updated),"entry restored");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),"unknown reconciling can resolve FILLED");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "resolved fill must not block recovery");
  }

void TestTimeoutWithIndeterminateOutcomeEntersUnknownReconciling(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-indeterminate");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-indeterminate",basketId);
   entry.SetDeadlineUtc(900);
   h.clock.SetNow(1000);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);

   CExecutionTimeoutMonitor indeterminateMonitor(h.registry,h.reconciliationScheduler,h.failingReader,NULL,h.clock,h.lifecycle);
   CTestAssert::EqualInt(1,indeterminateMonitor.ScanDueTimeouts(),"indeterminate timeout must be handled");
   CPendingExecutionEntry updated;
   h.registry.TryGetByExecutionRequestId("req-indeterminate",updated);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)updated.Status(),"indeterminate timeout must enter UNKNOWN_RECONCILING");
   CTestAssert::True(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(*h.registry,basketId),
                     "indeterminate timeout must block recovery");
   CTestAssert::True(h.reconciliationScheduler.PendingCount()>0,"unknown reconciling must queue read-only reconciliation");
  }

void TestDuplicateTerminalEventEmittedOnce(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-event-dup");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-event-dup",basketId);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_ACKNOWLEDGED);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   h.registry.Upsert(entry);

   int eventsBefore=h.events.Count();
   h.lifecycle.MarkFilled("req-event-dup",0.10);
   h.lifecycle.MarkFilled("req-event-dup",0.10);
   CTestAssert::EqualInt(eventsBefore+1,h.events.Count(),"terminal event must emit once for duplicate fill mark");
  }


void TestStartupReconciliationIsReadOnly(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-readonly",CBasketId("basket-readonly"));
   h.store.SavePreparedState(entry,BuildEnvelope(entry));
   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                            &restartedRegistry,
                                                                            &restartedLifecycle,
                                                                            h.brokerReader,
                                                                            NULL);
   CTestAssert::EqualInt(1,restartedRegistry.Count(),"restart loads persisted entry without broker submit");
  }

void OnStart(void)
  {
   CTerminalizationHarness harness;
   TestFillPersistsTerminalState(harness);
   TestDuplicateFillIsIdempotent(harness);
   TestRecoveryStepAdvancesOnce(harness);
   TestRejectedDoesNotAdvanceStep(harness);
   TestPersistedFilledNotUnresolvedAfterRestart(harness);
   TestPersistedSubmittedReconciledOnRestart(harness);
   TestTerminalHistoryDoesNotAutoSubmit(harness);
   TestTimedOutIsTerminalAndDoesNotBlockRecovery(harness);
   TestUnknownReconcilingBlocksRecovery(harness);
   TestRestartLoadsTimedOutAsTerminalAudit(harness);
   TestRestartLoadsUnknownReconcilingAsUnresolved(harness);
   TestTimeoutWithIndeterminateOutcomeEntersUnknownReconciling(harness);
   TestDuplicateTerminalEventEmittedOnce(harness);
   TestStartupReconciliationIsReadOnly(harness);
   Print("TestPendingExecutionTerminalization: all tests passed");
  }
