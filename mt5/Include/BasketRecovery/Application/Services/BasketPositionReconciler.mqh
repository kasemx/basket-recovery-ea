#ifndef BRE_APP_BASKET_POSITION_RECONCILER_MQH
#define BRE_APP_BASKET_POSITION_RECONCILER_MQH

#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Execution/PendingExecutionRegistry.mqh>
#include <BasketRecovery/Application/Execution/Ports/IPendingExecutionStore.mqh>
#include <BasketRecovery/Application/Risk/RecoveryPendingExecutionChecker.mqh>
#include <BasketRecovery/Domain/Reconciliation/ReconciliationResult.mqh>
#include <BasketRecovery/Domain/Reconciliation/BasketReconciliationApplyOutcome.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBasketPositionReconciler
  {
private:
   IBrokerPositionReader  *m_reader;
   IPositionSnapshotStore *m_snapshotStore;
   IBasketRepository      *m_repository;
   ILogger                *m_logger;
   IClock                 *m_clock;
   int                     m_nextBasketIndex;

   bool              NearlyEqual(const double left,const double right) const
     {
      return MathAbs(left-right)<=0.0000001;
     }

   static string     LifecycleStateLabel(const ENUM_BRE_BASKET_LIFECYCLE_STATE state)
     {
      return CBasketLifecycleStateHelper::ToString(state);
     }

   string            ResolveBasketStartupReconcileFailureReason(const CReconciliationResult &result,
                                                                const SBasketReconciliationApplyOutcome &outcome,
                                                                const string errorMessage) const
     {
      if(StringFind(errorMessage,"Basket file is missing")>=0 ||
         StringFind(errorMessage,"Basket aggregate missing")>=0 ||
         StringFind(errorMessage,"Basket id is empty")>=0 ||
         StringFind(errorMessage,"Basket not found")>=0)
         return "missing_basket";

      if(outcome.missing_position_count>0)
         return "missing_live_position";

      if(outcome.mismatch_position_count>0)
        {
         if(outcome.expected_ticket>0 && outcome.live_ticket>0 && outcome.expected_ticket!=outcome.live_ticket)
            return "ticket_mismatch";
         if(outcome.expected_ticket>0 && outcome.live_ticket>0 &&
            !NearlyEqual(outcome.expected_volume,outcome.live_volume))
            return "volume_mismatch";
         return "volume_mismatch";
        }

      if(outcome.orphan_position_count>0)
         return "orphan_position";

      if(outcome.unresolved_execution_count>0 || outcome.current_ticket_unresolved_count>0)
         return "stale_pending";

      if(StringFind(outcome.resume_failure_reason,"unresolved_pending")>=0)
         return "stale_pending";

      if(outcome.lifecycle_before!=BRE_STATE_NONE && outcome.lifecycle_after!=BRE_STATE_NONE &&
         outcome.lifecycle_before!=outcome.lifecycle_after)
         return "lifecycle_conflict";

      if(StringFind(errorMessage,"snapshot")>=0 || StringFind(errorMessage,"broker")>=0)
         return "broker_snapshot_failure";

      if(result.HasIssues())
        {
         if(result.MismatchCount()>0)
            return "volume_mismatch";
         if(result.OrphanCount()>0)
            return "orphan_position";
         if(result.MissingCount()>0)
            return "missing_live_position";
        }

      return "unknown";
     }

   void              PrintBasketStartupReconcileFailureDiagnostics(const string step,
                                                                 const CVoidResult &failure,
                                                                 const CReconciliationResult &result,
                                                                 const SBasketReconciliationApplyOutcome &outcome) const
     {
      if(failure.ErrorCode()!=BRE_ERR_BASKET_NOT_FOUND)
         return;

      string reason=ResolveBasketStartupReconcileFailureReason(result,outcome,failure.ErrorMessage());
      Print("basket_startup_reconcile_failure_step=",step);
      Print("basket_startup_reconcile_failure_reason=",reason);
      Print("basket_startup_reconcile_basket_id=",result.BasketId().Value());
      Print("basket_startup_reconcile_expected_ticket=",IntegerToString((long)outcome.expected_ticket));
      Print("basket_startup_reconcile_live_ticket=",IntegerToString((long)outcome.live_ticket));
      Print("basket_startup_reconcile_expected_volume=",DoubleToString(outcome.expected_volume,8));
      Print("basket_startup_reconcile_live_volume=",DoubleToString(outcome.live_volume,8));
      Print("basket_startup_reconcile_pending_count=",IntegerToString(outcome.unresolved_execution_count));
      Print("basket_startup_reconcile_orphan_count=",IntegerToString(outcome.orphan_position_count));
      Print("basket_startup_reconcile_lifecycle_before=",LifecycleStateLabel(outcome.lifecycle_before));
     }

   int               CountBrokerForBasket(const CBasketId &basketId,
                                          const CPositionSnapshotEntry &brokerEntries[],
                                          const int brokerCount) const
     {
      int count=0;
      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].BasketId()==basketId)
            count++;
        }
      return count;
     }

   bool              FindBrokerByTicket(const ulong ticket,
                                        const CPositionSnapshotEntry &brokerEntries[],
                                        const int brokerCount,
                                        CPositionSnapshotEntry &outEntry) const
     {
      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].Ticket()==ticket)
           {
            outEntry=brokerEntries[i];
            return true;
           }
        }
      return false;
     }

   bool              FindLocalByTicket(const ulong ticket,
                                       const CPositionSnapshotEntry &localEntries[],
                                       const int localCount,
                                       CPositionSnapshotEntry &outEntry) const
     {
      for(int i=0;i<localCount;i++)
        {
         if(localEntries[i].Ticket()==ticket && localEntries[i].Status()==BRE_POSITION_SNAPSHOT_OPEN)
           {
            outEntry=localEntries[i];
            return true;
           }
        }
      return false;
     }

   void              CopyLocalEntries(const CBasketId &basketId,CPositionSnapshotEntry &outEntries[],int &outCount) const
     {
      outCount=0;
      ArrayResize(outEntries,0);
      if(m_snapshotStore==NULL)
         return;

      CPositionSnapshot *snapshot=m_snapshotStore.Get(basketId);
      if(snapshot==NULL)
         return;

      outCount=snapshot.EntryCount();
      ArrayResize(outEntries,outCount);
      for(int i=0;i<outCount;i++)
         snapshot.EntryAt(i,outEntries[i]);
     }

   int               CountOpenLocalEntries(const CPositionSnapshotEntry &localEntries[],const int localCount) const
     {
      int count=0;
      for(int i=0;i<localCount;i++)
        {
         if(localEntries[i].Status()==BRE_POSITION_SNAPSHOT_OPEN)
            count++;
        }
      return count;
     }

   CVoidResult       BootstrapLocalSnapshotFromBrokerIfEmpty(const CBasketId &basketId,
                                                             const CPositionSnapshotEntry &brokerEntries[],
                                                             const int brokerCount)
     {
      if(m_snapshotStore==NULL || basketId.IsEmpty())
         return CVoidResult::Ok();

      CPositionSnapshotEntry localEntries[];
      int localCount=0;
      CopyLocalEntries(basketId,localEntries,localCount);
      if(CountOpenLocalEntries(localEntries,localCount)>0)
         return CVoidResult::Ok();

      m_snapshotStore.CreateEmpty(basketId);

      CPositionSnapshotEntry matched[];
      int matchedCount=0;
      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].BasketId()!=basketId)
            continue;
         ArrayResize(matched,matchedCount+1);
         matched[matchedCount]=brokerEntries[i];
         matchedCount++;
        }

      return m_snapshotStore.ReplaceEntries(basketId,matched,matchedCount);
     }

   string            BuildBlockingReason(const CReconciliationResult &result) const
     {
      if(!result.HasIssues())
         return "";

      return StringFormat("orphan_count=%d;missing_count=%d;mismatch_count=%d",
                          result.OrphanCount(),result.MissingCount(),result.MismatchCount());
     }

   void              FillTicketVolumeDiagnostics(const CBasketId &basketId,
                                                 const CPositionSnapshotEntry &localEntries[],
                                                 const int localCount,
                                                 const CPositionSnapshotEntry &brokerEntries[],
                                                 const int brokerCount,
                                                 SBasketReconciliationApplyOutcome &outcome) const
     {
      outcome.expected_ticket=0;
      outcome.expected_volume=0.0;
      outcome.live_ticket=0;
      outcome.live_volume=0.0;

      for(int i=0;i<localCount;i++)
        {
         if(localEntries[i].Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;
         outcome.expected_ticket=localEntries[i].Ticket();
         outcome.expected_volume=localEntries[i].Volume();
         break;
        }

      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].BasketId()!=basketId)
            continue;
         outcome.live_ticket=brokerEntries[i].Ticket();
         outcome.live_volume=brokerEntries[i].Volume();
         break;
        }
     }

   bool              TryLoadLifecycleState(const CBasketId &basketId,ENUM_BRE_BASKET_LIFECYCLE_STATE &outState) const
     {
      outState=BRE_STATE_NONE;
      if(m_repository==NULL || basketId.IsEmpty())
         return false;

      CResult<CBasketAggregate> loaded=m_repository.Load(basketId);
      if(loaded.IsFail())
         return false;

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return false;

      outState=basket.LifecycleState();
      return true;
     }

   CReconciliationResult ReconcileBasketEntries(const CBasketId &basketId,
                                                const CPositionSnapshotEntry &localEntries[],
                                                const int localCount,
                                                const CPositionSnapshotEntry &brokerEntries[],
                                                const int brokerCount) const
     {
      CReconciliationResult result=CReconciliationResult::Create(basketId);

      for(int i=0;i<localCount;i++)
        {
         CPositionSnapshotEntry localEntry=localEntries[i];
         if(localEntry.Status()!=BRE_POSITION_SNAPSHOT_OPEN)
            continue;

         CPositionSnapshotEntry brokerEntry;
         if(!FindBrokerByTicket(localEntry.Ticket(),brokerEntries,brokerCount,brokerEntry))
           {
            result.AddMissing(CMissingPositionReport::Create(localEntry));
            continue;
           }

         if(!NearlyEqual(localEntry.StopLoss(),brokerEntry.StopLoss()) ||
            !NearlyEqual(localEntry.TakeProfit(),brokerEntry.TakeProfit()) ||
            !NearlyEqual(localEntry.Volume(),brokerEntry.Volume()))
           {
            result.AddMismatch(CPositionMismatchReport::Create(localEntry,brokerEntry,"SL/TP/volume mismatch"));
           }
        }

      for(int i=0;i<brokerCount;i++)
        {
         CPositionSnapshotEntry brokerEntry=brokerEntries[i];
         if(brokerEntry.BasketId()!=basketId)
            continue;

         CPositionSnapshotEntry localEntry;
         if(!FindLocalByTicket(brokerEntry.Ticket(),localEntries,localCount,localEntry))
            result.AddOrphan(COrphanPositionReport::Create(brokerEntry));
        }

      if(result.HasIssues())
         result.SetRequiresSuspension(true);

      return result;
     }

   void              AuditResult(const CReconciliationResult &result) const
     {
      if(m_logger==NULL || !result.HasIssues())
         return;

      m_logger.Warn("RECONCILIATION",result.BasketId().Value(),
                    "",
                    StringFormat("Reconciliation issues | orphans=%d missing=%d mismatches=%d suspend=%s",
                                 result.OrphanCount(),result.MissingCount(),result.MismatchCount(),
                                 result.RequiresSuspension() ? "yes" : "no"),
                    BRE_ERR_RECONCILIATION_MISMATCH);
     }

   CVoidResult       SuspendBasketIfRequired(const CReconciliationResult &result,
                                             string &persistedWriteResult)
     {
      persistedWriteResult="not_required";
      if(!result.RequiresSuspension() || m_repository==NULL || result.BasketId().IsEmpty())
         return CVoidResult::Ok();

      CResult<CBasketAggregate> loaded=m_repository.Load(result.BasketId());
      if(loaded.IsFail())
        {
         persistedWriteResult="load_failed:"+loaded.ErrorMessage();
         return CVoidResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());
        }

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
        {
         persistedWriteResult="basket_missing";
         return CVoidResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");
        }

      if(basket.LifecycleState()==BRE_STATE_ACTIVE)
        {
         basket.SetLifecycleState(BRE_STATE_SUSPENDED);
         CVoidResult saveResult=m_repository.Save(basket);
         if(saveResult.IsFail())
           {
            persistedWriteResult="save_failed:"+saveResult.ErrorMessage();
            return saveResult;
           }
         persistedWriteResult="suspended";
         return CVoidResult::Ok();
        }

      persistedWriteResult="already_suspended";
      return CVoidResult::Ok();
     }

   void              FillTicketScopedPendingCounts(const CBasketId &basketId,
                                                   const CPositionSnapshotEntry &brokerEntries[],
                                                   const int brokerCount,
                                                   CPendingExecutionRegistry *pendingRegistry,
                                                   IPendingExecutionStore *pendingStore,
                                                   SBasketReconciliationApplyOutcome &outcome) const
     {
      outcome.unresolved_execution_count=0;
      outcome.current_ticket_unresolved_count=0;
      outcome.foreign_ticket_unresolved_count=0;
      if(pendingRegistry==NULL)
         return;
      ulong openTickets[];
      int openTicketCount=CRecoveryPendingExecutionChecker::CollectOpenTicketsForBasket(basketId,
                                                                                      brokerEntries,
                                                                                      brokerCount,
                                                                                      openTickets);
      CRecoveryPendingExecutionChecker::CountTicketScopedUnresolved(*pendingRegistry,
                                                                    basketId,
                                                                    openTickets,
                                                                    openTicketCount,
                                                                    pendingStore,
                                                                    outcome.unresolved_execution_count,
                                                                    outcome.current_ticket_unresolved_count,
                                                                    outcome.foreign_ticket_unresolved_count);
     }

   CVoidResult       ResumeBasketIfReconciliationClean(const CReconciliationResult &result,
                                                       const CPositionSnapshotEntry &brokerEntries[],
                                                       const int brokerCount,
                                                       CPendingExecutionRegistry *pendingRegistry,
                                                       IPendingExecutionStore *pendingStore,
                                                       SBasketReconciliationApplyOutcome &outcome) const
     {
      outcome.resume_attempted=false;
      outcome.resume_result=false;
      outcome.resume_failure_reason="";

      if(result.HasIssues())
        {
         outcome.resume_failure_reason="reconciliation_not_clean";
         return CVoidResult::Ok();
        }

      if(m_repository==NULL || result.BasketId().IsEmpty())
        {
         outcome.resume_failure_reason="repository_unavailable";
         return CVoidResult::Ok();
        }

      if(pendingRegistry!=NULL)
        {
         ulong openTickets[];
         int openTicketCount=CRecoveryPendingExecutionChecker::CollectOpenTicketsForBasket(result.BasketId(),
                                                                                           brokerEntries,
                                                                                           brokerCount,
                                                                                           openTickets);
         if(CRecoveryPendingExecutionChecker::HasBlockingUnresolvedForOpenTickets(*pendingRegistry,
                                                                                  result.BasketId(),
                                                                                  openTickets,
                                                                                  openTicketCount,
                                                                                  pendingStore))
           {
            outcome.resume_attempted=true;
            outcome.resume_result=false;
            outcome.resume_failure_reason="unresolved_pending_execution";
            return CVoidResult::Ok();
           }
        }

      CResult<CBasketAggregate> loaded=m_repository.Load(result.BasketId());
      if(loaded.IsFail())
        {
         outcome.resume_attempted=true;
         outcome.resume_result=false;
         outcome.resume_failure_reason="load_failed:"+loaded.ErrorMessage();
         return CVoidResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());
        }

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
        {
         outcome.resume_attempted=true;
         outcome.resume_result=false;
         outcome.resume_failure_reason="basket_missing";
         return CVoidResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");
        }

      outcome.max_risk_lockout=basket.ModeFlags().MaxRiskLockout();

      if(basket.LifecycleState()!=BRE_STATE_SUSPENDED)
        {
         outcome.resume_failure_reason="not_suspended";
         return CVoidResult::Ok();
        }

      outcome.resume_attempted=true;

      if(basket.ModeFlags().MaxRiskLockout())
        {
         outcome.resume_result=false;
         outcome.resume_failure_reason="max_risk_lockout";
         return CVoidResult::Ok();
        }

      basket.SetLifecycleState(BRE_STATE_ACTIVE);
      CVoidResult saveResult=m_repository.Save(basket);
      if(saveResult.IsFail())
        {
         outcome.resume_result=false;
         outcome.resume_failure_reason="save_failed:"+saveResult.ErrorMessage();
         outcome.persisted_basket_write_result="save_failed:"+saveResult.ErrorMessage();
         return saveResult;
        }

      outcome.resume_result=true;
      outcome.resume_failure_reason="ok";
      outcome.persisted_basket_write_result="resumed_active";
      return CVoidResult::Ok();
     }

public:
                     CBasketPositionReconciler(IBrokerPositionReader *reader,
                                               IPositionSnapshotStore *snapshotStore,
                                               IBasketRepository *repository,
                                               ILogger *logger,
                                               IClock *clock)
     {
      m_reader=reader;
      m_snapshotStore=snapshotStore;
      m_repository=repository;
      m_logger=logger;
      m_clock=clock;
      m_nextBasketIndex=0;
     }

   CReconciliationResult ReconcileBasket(const CBasketId &basketId,
                                         const CPositionSnapshotEntry &brokerEntries[],
                                         const int brokerCount) const
     {
      CPositionSnapshotEntry localEntries[];
      int localCount=0;
      CopyLocalEntries(basketId,localEntries,localCount);
      return ReconcileBasketEntries(basketId,localEntries,localCount,brokerEntries,brokerCount);
     }

   CVoidResult       ApplyReconciliationResult(const CReconciliationResult &result,
                                               const CPositionSnapshotEntry &brokerEntries[],
                                               const int brokerCount)
     {
      SBasketReconciliationApplyOutcome outcome;
      outcome.Reset();
      return ApplyReconciliationResultWithOutcome(result,brokerEntries,brokerCount,NULL,NULL,outcome);
     }

   CVoidResult       ApplyReconciliationResultWithOutcome(const CReconciliationResult &result,
                                                          const CPositionSnapshotEntry &brokerEntries[],
                                                          const int brokerCount,
                                                          CPendingExecutionRegistry *pendingRegistry,
                                                          IPendingExecutionStore *pendingStore,
                                                          SBasketReconciliationApplyOutcome &outcome)
     {
      outcome.Reset();
      outcome.orphan_position_count=result.OrphanCount();
      outcome.missing_position_count=result.MissingCount();
      outcome.mismatch_position_count=result.MismatchCount();
      outcome.reconciliation_clean=!result.HasIssues();
      outcome.blocking_reason=BuildBlockingReason(result);

      FillTicketScopedPendingCounts(result.BasketId(),brokerEntries,brokerCount,pendingRegistry,pendingStore,outcome);

      CPositionSnapshotEntry localEntries[];
      int localCount=0;
      CopyLocalEntries(result.BasketId(),localEntries,localCount);
      FillTicketVolumeDiagnostics(result.BasketId(),localEntries,localCount,brokerEntries,brokerCount,outcome);

      TryLoadLifecycleState(result.BasketId(),outcome.lifecycle_before);

      AuditResult(result);
      if(result.HasIssues())
        {
         CVoidResult suspendResult=SuspendBasketIfRequired(result,outcome.persisted_basket_write_result);
         TryLoadLifecycleState(result.BasketId(),outcome.lifecycle_after);
         if(suspendResult.IsFail())
           {
            PrintBasketStartupReconcileFailureDiagnostics("suspend_basket_if_required",suspendResult,result,outcome);
            return suspendResult;
           }
         return suspendResult;
        }

      CVoidResult resumeResult=ResumeBasketIfReconciliationClean(result,brokerEntries,brokerCount,pendingRegistry,pendingStore,outcome);
      if(resumeResult.IsFail())
        {
         TryLoadLifecycleState(result.BasketId(),outcome.lifecycle_after);
         PrintBasketStartupReconcileFailureDiagnostics("resume_basket_if_reconciliation_clean",resumeResult,result,outcome);
         return resumeResult;
        }

      if(outcome.persisted_basket_write_result=="")
         outcome.persisted_basket_write_result="unchanged";

      if(m_snapshotStore==NULL || result.BasketId().IsEmpty())
        {
         outcome.snapshot_write_result="snapshot_store_unavailable";
         TryLoadLifecycleState(result.BasketId(),outcome.lifecycle_after);
         return CVoidResult::Ok();
        }

      CPositionSnapshotEntry matched[];
      int matchedCount=0;
      for(int i=0;i<brokerCount;i++)
        {
         if(brokerEntries[i].BasketId()!=result.BasketId())
            continue;
         ArrayResize(matched,matchedCount+1);
         matched[matchedCount]=brokerEntries[i];
         matchedCount++;
        }

      CVoidResult replaceResult=m_snapshotStore.ReplaceEntries(result.BasketId(),matched,matchedCount);
      if(replaceResult.IsFail())
         outcome.snapshot_write_result="replace_failed:"+replaceResult.ErrorMessage();
      else
         outcome.snapshot_write_result="ok";

      TryLoadLifecycleState(result.BasketId(),outcome.lifecycle_after);
      return replaceResult;
     }

   CVoidResult       ReconcileAndApplyForBasket(const CBasketId &basketId,
                                                const CPositionSnapshotEntry &brokerEntries[],
                                                const int brokerCount,
                                                CPendingExecutionRegistry *pendingRegistry,
                                                SBasketReconciliationApplyOutcome &outcome,
                                                IPendingExecutionStore *pendingStore=NULL)
     {
      outcome.Reset();

      FillTicketScopedPendingCounts(basketId,brokerEntries,brokerCount,pendingRegistry,pendingStore,outcome);

      TryLoadLifecycleState(basketId,outcome.lifecycle_before);

      CPositionSnapshotEntry localBeforeBootstrap[];
      int localBeforeCount=0;
      CopyLocalEntries(basketId,localBeforeBootstrap,localBeforeCount);

      CVoidResult bootstrapResult=BootstrapLocalSnapshotFromBrokerIfEmpty(basketId,brokerEntries,brokerCount);
      if(bootstrapResult.IsFail())
        {
         outcome.blocking_reason="bootstrap_failed:"+bootstrapResult.ErrorMessage();
         TryLoadLifecycleState(basketId,outcome.lifecycle_after);
         return bootstrapResult;
        }

      CReconciliationResult result=ReconcileBasket(basketId,brokerEntries,brokerCount);
      CVoidResult applyResult=ApplyReconciliationResultWithOutcome(result,brokerEntries,brokerCount,pendingRegistry,pendingStore,outcome);
      if(outcome.lifecycle_before==BRE_STATE_NONE)
         TryLoadLifecycleState(basketId,outcome.lifecycle_before);
      return applyResult;
     }

   CVoidResult       ReconcileAtStartup(void)
     {
      if(m_reader==NULL || m_snapshotStore==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Reconciliation dependencies missing");

      CPositionSnapshotEntry brokerEntries[];
      CResult<int> readResult=m_reader.ReadOpenPositions(brokerEntries,256);
      if(readResult.IsFail())
         return CVoidResult::Fail(readResult.ErrorCode(),readResult.ErrorMessage());

      int brokerCount=0;
      readResult.TryGetValue(brokerCount);

      CBasketId basketIds[];
      int basketCount=0;
      for(int i=0;i<brokerCount;i++)
        {
         CBasketId basketId=brokerEntries[i].BasketId();
         if(basketId.IsEmpty())
            continue;

         bool exists=false;
         for(int j=0;j<basketCount;j++)
           {
            if(basketIds[j]==basketId)
              {
               exists=true;
               break;
              }
           }
         if(exists)
            continue;

         ArrayResize(basketIds,basketCount+1);
         basketIds[basketCount]=basketId;
         basketCount++;
         m_snapshotStore.CreateEmpty(basketId);
        }

      for(int i=0;i<basketCount;i++)
        {
         CVoidResult bootstrapResult=BootstrapLocalSnapshotFromBrokerIfEmpty(basketIds[i],brokerEntries,brokerCount);
         if(bootstrapResult.IsFail())
            return bootstrapResult;

         CReconciliationResult result=ReconcileBasket(basketIds[i],brokerEntries,brokerCount);
         SBasketReconciliationApplyOutcome outcome;
         outcome.Reset();
         CVoidResult applyResult=ApplyReconciliationResultWithOutcome(result,brokerEntries,brokerCount,NULL,NULL,outcome);
         if(applyResult.IsFail())
            return applyResult;
        }

      if(m_logger!=NULL)
         m_logger.Info("SYSTEM","Reconciliation","",
                       StringFormat("Startup reconciliation completed | baskets=%d broker_positions=%d",
                                    basketCount,brokerCount));

      return CVoidResult::Ok();
     }

   int               RunPeriodicCycle(const int maxBasketsPerCycle)
     {
      if(m_repository==NULL || m_reader==NULL || maxBasketsPerCycle<=0)
         return 0;

      CPositionSnapshotEntry brokerEntries[];
      CResult<int> readResult=m_reader.ReadOpenPositions(brokerEntries,256);
      if(readResult.IsFail())
         return 0;

      int brokerCount=0;
      readResult.TryGetValue(brokerCount);

      CBasketAggregate baskets[];
      int basketCount=m_repository.LoadAll(baskets);
      if(basketCount<=0)
         return 0;

      int processed=0;
      int scanned=0;
      while(processed<maxBasketsPerCycle && scanned<basketCount)
        {
         if(m_nextBasketIndex>=basketCount)
            m_nextBasketIndex=0;

         CBasketAggregate basket=baskets[m_nextBasketIndex];
         m_nextBasketIndex++;
         scanned++;

         if(basket.LifecycleState()!=BRE_STATE_ACTIVE && basket.LifecycleState()!=BRE_STATE_SUSPENDED)
            continue;
         if(CountBrokerForBasket(basket.Id(),brokerEntries,brokerCount)<=0 &&
            (m_snapshotStore==NULL || m_snapshotStore.Get(basket.Id())==NULL))
            continue;

         m_snapshotStore.CreateEmpty(basket.Id());
         BootstrapLocalSnapshotFromBrokerIfEmpty(basket.Id(),brokerEntries,brokerCount);
         CReconciliationResult result=ReconcileBasket(basket.Id(),brokerEntries,brokerCount);
         ApplyReconciliationResult(result,brokerEntries,brokerCount);
         processed++;
        }

      return processed;
     }
  };

#endif
