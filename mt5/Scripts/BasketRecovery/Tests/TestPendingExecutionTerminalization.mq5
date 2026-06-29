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
#include <BasketRecovery/Infrastructure/Snapshot/InMemoryBrokerExecutionHistoryReader.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionReconciliationHydrator.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionPersistedFillEvidence.mqh>
#include <BasketRecovery/Domain/Execution/BrokerHistoricalOrderEvidencePolicy.mqh>
#include <BasketRecovery/Domain/Execution/BrokerExecutionVolumePolicy.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionReconciliationTransitionGate.mqh>
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
   CInMemoryBrokerExecutionHistoryReader   *historyReader;
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
      historyReader=new CInMemoryBrokerExecutionHistoryReader();
      failingReader=new CFailingBrokerPositionReader();
      reconciliationScheduler=new CExecutionReconciliationScheduler(registry,brokerReader,NULL,8,lifecycle,historyReader);
      timeoutMonitor=new CExecutionTimeoutMonitor(registry,reconciliationScheduler,brokerReader,NULL,clock,lifecycle,historyReader);
     }

                    ~CTerminalizationHarness(void)
     {
      if(timeoutMonitor!=NULL) delete timeoutMonitor;
      if(reconciliationScheduler!=NULL) delete reconciliationScheduler;
      if(failingReader!=NULL) delete failingReader;
      if(brokerReader!=NULL) delete brokerReader;
      if(historyReader!=NULL) delete historyReader;
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
      historyReader.Clear();
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
                                                                                           &notifier,
                                                                                           h.historyReader);
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
                                                                                           &notifier,
                                                                                           h.historyReader);
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
                                                                            NULL,
                                                                            h.historyReader);
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
                                                                                           NULL,
                                                                                           h.historyReader);
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
                                                                                           NULL,
                                                                                           h.historyReader);
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

   CExecutionTimeoutMonitor indeterminateMonitor(h.registry,h.reconciliationScheduler,h.failingReader,NULL,h.clock,h.lifecycle,h.historyReader);
   h.historyReader.SetQueryAvailable(false);
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
                                                                            NULL,
                                                                            h.historyReader);
   CTestAssert::EqualInt(1,restartedRegistry.Count(),"restart loads persisted entry without broker submit");
  }

void TestMissingOpenPositionDoesNotReject(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-no-open",CBasketId("basket-no-open"));
   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "missing open position alone must not produce REJECTED");
  }

void TestHistoricalDealMatchResolvesFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-hist-fill",CBasketId("basket-hist-fill"));
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.10);
   correlation.SetSummary("historical_deal_fill");
   h.historyReader.SetCorrelation("req-hist-fill",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,"historical deal match must resolve FILLED");
   CTestAssert::True(MathAbs(matchedVolume-0.10)<0.0000001,"matched volume must come from history");
  }

void TestFilledThenManuallyClosedRemainsFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("basket-manual-close");
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-manual-close",basketId);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetBrokerDealId(88001);
   entry.SetBrokerCorrelation(broker);
   h.store.SavePreparedState(entry,BuildEnvelope(entry));

   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.10);
   correlation.SetSummary("historical_deal_fill");
   h.historyReader.SetCorrelation("req-manual-close",correlation);

   CPendingExecutionRegistry restartedRegistry;
   CPendingExecutionLifecycleService restartedLifecycle(&restartedRegistry,h.store,h.events,h.clock);
   CTestFillNotifier notifier(h.stepTracker);
   h.stepTracker.MarkSubmitted(basketId.Value(),4,"req-manual-close");
   int reconciled=CPendingExecutionStartupReconciliationService::ReconcilePersistedEntries(h.store,
                                                                                           &restartedRegistry,
                                                                                           &restartedLifecycle,
                                                                                           h.brokerReader,
                                                                                           &notifier,
                                                                                           h.historyReader);
   CTestAssert::EqualInt(1,reconciled,"manual-close history must reconcile once");
   CPendingExecutionEntry updated;
   CTestAssert::True(restartedRegistry.TryGetByExecutionRequestId("req-manual-close",updated),"entry restored");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)updated.Status(),
                         "filled then manually closed must remain FILLED");
   CTestAssert::False(CRecoveryPendingExecutionChecker::HasUnresolvedForBasket(restartedRegistry,basketId),
                      "terminal FILLED must not block recovery");
  }

void TestExplicitBrokerRejectResolvesRejected(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-explicit-reject",CBasketId("basket-explicit-reject"));
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasRejectEvidence(true);
   correlation.SetSummary("historical_order_reject");
   h.historyReader.SetCorrelation("req-explicit-reject",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)resolved,"explicit broker reject must resolve REJECTED");
  }

void TestIndeterminateNoHistoryResolvesUnknownReconciling(CTerminalizationHarness &h)
  {
   h.Reset();
   h.historyReader.SetQueryAvailable(false);
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-indeterminate-history",CBasketId("basket-indeterminate-history"));
   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "indeterminate no-history state must resolve UNKNOWN_RECONCILING");
  }

void TestRealManualCloseRecordFixtureResolvesFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CBasketId basketId("sprint7d-demo-btc-001");
   CPendingExecutionEntry entry;
   entry.SetExecutionRequestId("recovery-manual:375360093-3A70-2EF6");
   entry.SetIdempotencyKey("recovery-candidate:sprint7d-demo-btc-001:step:1:q:0");
   entry.SetBasketId(basketId);
   entry.SetExpectedBasketVersion(25);
   entry.SetStrategyProfileHash("B2667CFA");
   entry.SetIntentType(BRE_EXEC_INTENT_OPEN_POSITION);
   entry.SetSymbol("BTCUSD");
   entry.SetRequestedVolume(0.01);
   entry.SetFilledVolume(0.0);
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   entry.SetDeadlineUtc(1782682703);
   entry.SetCorrelationToken("89848F7C");
   entry.SetBrokerComment("BRE|89848F7C|-btc-001|O|14D2");
   entry.SetPreparedAtUtc(1782682643);
   entry.SetPreparedQuoteTimestampUtc(1782682643);

   CBrokerSubmissionEnvelope envelope;
   envelope.SetExecutionRequestId(entry.ExecutionRequestId());
   envelope.SetIdempotencyKey(entry.IdempotencyKey());
   envelope.SetBasketId(basketId);
   envelope.SetSymbol("BTCUSD");
   envelope.SetMagicNumber(202606001);
   envelope.SetBrokerComment(entry.BrokerComment());
   envelope.SetCorrelationToken(entry.CorrelationToken());
   envelope.SetRequestedVolume(0.01);
   envelope.SetPreparedAtUtc(1782682643);
   h.store.SavePreparedState(entry,envelope);

   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.01);
   correlation.SetSummary("historical_deal_fill");
   h.historyReader.SetCorrelation("recovery-manual:375360093-3A70-2EF6",correlation);

   CPendingExecutionEntry hydrated=entry;
   CTestAssert::True(CPendingExecutionReconciliationHydrator::TryHydrate(hydrated,GetPointer(h.store)),
                     "hydrator must merge envelope metadata");
   CTestAssert::EqualInt(202606001,(int)hydrated.BrokerCorrelation().MagicNumber(),"hydrator must restore magic");
   CTestAssert::True(hydrated.SubmittedAtUtc()>0,"hydrator must restore submitted anchor from prepared time");

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(hydrated,h.brokerReader,matchedVolume,h.historyReader,1782682800);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,
                         "real manual-close fixture must resolve FILLED");
  }

void TestFilledTerminalStateIsMonotonic(CTerminalizationHarness &h)
  {
   CTestAssert::False(CPendingExecutionReconciliationTransitionGate::CanResolveFromBrokerRead(
                         BRE_TRADE_EXEC_STATUS_FILLED,BRE_TRADE_EXEC_STATUS_TIMED_OUT),
                      "FILLED must never transition to TIMED_OUT");
   CTestAssert::False(CPendingExecutionReconciliationTransitionGate::CanResolveFromBrokerRead(
                         BRE_TRADE_EXEC_STATUS_FILLED,BRE_TRADE_EXEC_STATUS_REJECTED),
                      "FILLED must never transition to REJECTED");
   CTestAssert::True(CPendingExecutionPersistedFillEvidence::IsTerminalFillMonotonic(
                        BRE_TRADE_EXEC_STATUS_FILLED,BRE_TRADE_EXEC_STATUS_FILLED),
                     "FILLED remains FILLED");
  }

void TestNoPrematureTimedOutWithoutHistoryEvidence(CTerminalizationHarness &h)
  {
   h.Reset();
   h.historyReader.SetQueryAvailable(false);
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-no-premature-timeout",CBasketId("basket-no-premature"));
   entry.SetDeadlineUtc(h.clock.Now()+3600);
   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "no history evidence before deadline must stay UNKNOWN_RECONCILING");
  }

void TestDeadlineBeforeEvidenceWindow(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-deadline-not-evidence-window",CBasketId("basket-deadline-window"));
   entry.SetPreparedAtUtc(1000);
   entry.SetSubmittedAtUtc(1000);
   entry.SetDeadlineUtc(1060);
   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,1120);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "submission deadline alone must not produce TIMED_OUT before evidence window");
  }

void TestStaleSubmittedWithPersistedFillVolumeRepairsFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-stale-filled-volume",CBasketId("basket-stale-filled"));
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   entry.SetFilledVolume(0.10);
   entry.SetDeadlineUtc(h.clock.Now()+3600);
   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,
                         "persisted fill volume must repair stale SUBMITTED to FILLED");
  }

void TestAmbiguousFingerprintPolicyCountsTwo(CTerminalizationHarness &h)
  {
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-ambiguous-fingerprint",CBasketId("basket-ambiguous-fingerprint"));
   entry.SetCorrelationToken("89848F7C");
   entry.SetBrokerComment("BRE|89848F7C|-btc-001|O|14D2");
   entry.SetPreparedAtUtc(1000);
   entry.SetSubmittedAtUtc(1000);
   entry.SetRequestedVolume(0.01);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetMagicNumber(202606001);
   entry.SetBrokerCorrelation(broker);

   SFingerprintDealCandidate candidates[2];
   candidates[0].time=1010;
   candidates[0].symbol="BTCUSD";
   candidates[0].magic=202606001;
   candidates[0].volume=0.01;
   candidates[0].entryType=DEAL_ENTRY_IN;
   candidates[0].dealType=DEAL_TYPE_BUY;
   candidates[1].time=1020;
   candidates[1].symbol="BTCUSD";
   candidates[1].magic=202606001;
   candidates[1].volume=0.01;
   candidates[1].entryType=DEAL_ENTRY_IN;
   candidates[1].dealType=DEAL_TYPE_BUY;

   int count=CBrokerExecutionFingerprintCandidatePolicy::CountMatchingCandidates(entry,candidates,600);
   CTestAssert::EqualInt(2,count,"two fingerprint candidates must be counted without selecting one");
  }

void TestAmbiguousFingerprintStaysReconciling(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-ambiguous-fingerprint-resolve",CBasketId("basket-ambiguous-resolve"));
   entry.SetPreparedAtUtc(1000);
   entry.SetSubmittedAtUtc(1000);
   entry.SetDeadlineUtc(1060);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetFingerprintCandidateCount(2);
   correlation.SetEvidenceMethod("fingerprint_ambiguous");
   correlation.SetSummary("fingerprint_ambiguous");
   h.historyReader.SetCorrelation("req-ambiguous-fingerprint-resolve",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,1782680000);
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "ambiguous fingerprint must remain UNKNOWN_RECONCILING");
  }

void TestReadOnlyResolveDoesNotPersist(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-readonly-no-persist",CBasketId("basket-readonly-no-persist"));
   entry.SetStatus(BRE_TRADE_EXEC_STATUS_SUBMITTED);
   h.store.SaveEntryState(entry);

   double matchedVolume=0.0;
   CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());

   CPendingExecutionEntry entries[];
   int count=h.store.RestoreEntries(entries);
   CTestAssert::EqualInt(1,count,"entry must remain in store");
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_SUBMITTED,(int)entries[0].Status(),
                         "read-only resolve must not persist lifecycle mutation");
  }

void TestHistoricalOrderFilledResolvesFilledWithoutDeal(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-order-fill-no-deal",CBasketId("basket-order-fill"));
   entry.SetRequestedVolume(0.01);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.01);
   correlation.SetEvidenceMethod("historical_order_fingerprint_fill");
   correlation.SetSummary("historical_order_fingerprint_fill");
   correlation.SetOrderFilledCandidateCount(1);
   h.historyReader.SetCorrelation("req-order-fill-no-deal",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,
                         "unique historical filled order must resolve FILLED without deal history");
  }

void TestCancelledOrderDoesNotResolveFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-cancelled-order",CBasketId("basket-cancelled-order"));
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasRejectEvidence(true);
   correlation.SetEvidenceMethod("historical_order_reject");
   correlation.SetSummary("historical_order_reject");
   h.historyReader.SetCorrelation("req-cancelled-order",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_REJECTED,(int)resolved,
                         "cancelled/rejected order must not resolve FILLED");
  }

void TestPartialHistoricalOrderResolvesPartiallyFilled(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-partial-order",CBasketId("basket-partial-order"));
   entry.SetRequestedVolume(0.02);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.01);
   correlation.SetEvidenceMethod("persisted_broker_order_partial");
   correlation.SetSummary("historical_order_partial");
   correlation.SetOrderFilledCandidateCount(1);
   h.historyReader.SetCorrelation("req-partial-order",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_PARTIALLY_FILLED,(int)resolved,
                         "provable partial historical order must resolve PARTIALLY_FILLED");
  }

void TestAmbiguousHistoricalOrderFillStaysReconciling(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-ambiguous-order-fill",CBasketId("basket-ambiguous-order"));
   entry.SetPreparedAtUtc(1000);
   entry.SetSubmittedAtUtc(1000);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetOrderFilledCandidateCount(2);
   correlation.SetEvidenceMethod("order_fill_ambiguous");
   correlation.SetSummary("order_fill_ambiguous");
   h.historyReader.SetCorrelation("req-ambiguous-order-fill",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_RECONCILING,(int)resolved,
                         "two matching filled order candidates must remain UNKNOWN_RECONCILING");
  }

void TestCloseDealDoesNotBlockHistoricalOrderFill(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-close-deal-order-fill",CBasketId("basket-close-deal-order"));
   entry.SetRequestedVolume(0.01);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.01);
   correlation.SetFingerprintCandidateCount(0);
   correlation.SetEvidenceMethod("historical_order_fingerprint_fill");
   correlation.SetSummary("historical_order_fingerprint_fill");
   correlation.SetOrderFilledCandidateCount(1);
   h.historyReader.SetCorrelation("req-close-deal-order-fill",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,
                         "later close deal mismatch must not block unique historical order fill");
  }

void TestUnrelatedDealVolumeMismatchDoesNotBlockOrderFill(CTerminalizationHarness &h)
  {
   h.Reset();
   CPendingExecutionEntry entry=BuildSubmittedEntry("req-unrelated-deal-mismatch",CBasketId("basket-unrelated-deal"));
   entry.SetRequestedVolume(0.01);
   CBrokerExecutionHistoryCorrelation correlation;
   correlation.SetQueryAvailable(true);
   correlation.SetHasFillEvidence(true);
   correlation.SetFillVolume(0.01);
   correlation.SetFingerprintCandidateCount(0);
   correlation.SetEvidenceMethod("historical_order_fingerprint_fill");
   correlation.SetSummary("historical_order_fingerprint_fill");
   correlation.SetOrderFilledCandidateCount(1);
   h.historyReader.SetCorrelation("req-unrelated-deal-mismatch",correlation);

   double matchedVolume=0.0;
   ENUM_BRE_TRADE_EXECUTION_STATUS resolved=
      CExecutionReconciliationResolver::Resolve(entry,h.brokerReader,matchedVolume,h.historyReader,h.clock.Now());
   CTestAssert::EqualInt((int)BRE_TRADE_EXEC_STATUS_FILLED,(int)resolved,
                         "unrelated deal volume mismatch must not block exact matching filled order");
  }

void TestOrderEvidencePolicyFilledStateAndExecutedVolume(CTerminalizationHarness &h)
  {
   CTestAssert::True(CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesFill(ORDER_STATE_FILLED),
                     "ORDER_STATE_FILLED must prove fill");
   CTestAssert::False(CBrokerHistoricalOrderEvidencePolicy::OrderStateProvesFill(ORDER_STATE_CANCELED),
                      "cancelled order must not prove fill");
   double executed=CBrokerHistoricalOrderEvidencePolicy::ComputeExecutedVolume(ORDER_STATE_FILLED,0.01,0.0);
   CTestAssert::True(CBrokerExecutionVolumePolicy::VolumesEquivalent(executed,0.01),
                     "filled order executed volume must equal initial volume");

   SFingerprintOrderCandidate candidates[2];
   candidates[0].time=1010;
   candidates[0].symbol="BTCUSD";
   candidates[0].magic=202606001;
   candidates[0].orderType=ORDER_TYPE_BUY;
   candidates[0].orderState=ORDER_STATE_FILLED;
   candidates[0].executedVolume=0.01;
   candidates[1].time=1020;
   candidates[1].symbol="BTCUSD";
   candidates[1].magic=202606001;
   candidates[1].orderType=ORDER_TYPE_BUY;
   candidates[1].orderState=ORDER_STATE_FILLED;
   candidates[1].executedVolume=0.01;

   CPendingExecutionEntry entry=BuildSubmittedEntry("req-order-policy-count",CBasketId("basket-order-policy"));
   entry.SetRequestedVolume(0.01);
   entry.SetPreparedAtUtc(1000);
   entry.SetSubmittedAtUtc(1000);
   CBrokerRequestCorrelation broker=entry.BrokerCorrelation();
   broker.SetMagicNumber(202606001);
   entry.SetBrokerCorrelation(broker);

   string comments[2]={"",""};
   int count=CBrokerHistoricalOrderEvidencePolicy::CountMatchingOrderCandidates(
      entry,candidates,600,false,comments);
   CTestAssert::EqualInt(2,count,"two filled order fingerprint candidates must be counted");
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
   TestMissingOpenPositionDoesNotReject(harness);
   TestHistoricalDealMatchResolvesFilled(harness);
   TestFilledThenManuallyClosedRemainsFilled(harness);
   TestExplicitBrokerRejectResolvesRejected(harness);
   TestIndeterminateNoHistoryResolvesUnknownReconciling(harness);
   TestRealManualCloseRecordFixtureResolvesFilled(harness);
   TestFilledTerminalStateIsMonotonic(harness);
   TestNoPrematureTimedOutWithoutHistoryEvidence(harness);
   TestDeadlineBeforeEvidenceWindow(harness);
   TestStaleSubmittedWithPersistedFillVolumeRepairsFilled(harness);
   TestAmbiguousFingerprintPolicyCountsTwo(harness);
   TestAmbiguousFingerprintStaysReconciling(harness);
   TestReadOnlyResolveDoesNotPersist(harness);
   TestHistoricalOrderFilledResolvesFilledWithoutDeal(harness);
   TestCancelledOrderDoesNotResolveFilled(harness);
   TestPartialHistoricalOrderResolvesPartiallyFilled(harness);
   TestAmbiguousHistoricalOrderFillStaysReconciling(harness);
   TestCloseDealDoesNotBlockHistoricalOrderFill(harness);
   TestUnrelatedDealVolumeMismatchDoesNotBlockOrderFill(harness);
   TestOrderEvidencePolicyFilledStateAndExecutedVolume(harness);
   Print("TestPendingExecutionTerminalization: all tests passed");
  }
