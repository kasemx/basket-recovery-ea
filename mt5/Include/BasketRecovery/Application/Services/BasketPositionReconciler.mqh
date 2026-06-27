#ifndef BRE_APP_BASKET_POSITION_RECONCILER_MQH
#define BRE_APP_BASKET_POSITION_RECONCILER_MQH

#include <BasketRecovery/Application/Ports/IBrokerPositionReader.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Domain/Reconciliation/ReconciliationResult.mqh>
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

   CVoidResult       SuspendBasketIfRequired(const CReconciliationResult &result)
     {
      if(!result.RequiresSuspension() || m_repository==NULL || result.BasketId().IsEmpty())
         return CVoidResult::Ok();

      CResult<CBasketAggregate> loaded=m_repository.Load(result.BasketId());
      if(loaded.IsFail())
         return CVoidResult::Fail(loaded.ErrorCode(),loaded.ErrorMessage());

      CBasketAggregate basket;
      if(!loaded.TryGetValue(basket))
         return CVoidResult::Fail(BRE_ERR_BASKET_NOT_FOUND,"Basket aggregate missing");

      if(basket.LifecycleState()==BRE_STATE_ACTIVE)
        {
         basket.SetLifecycleState(BRE_STATE_SUSPENDED);
         CVoidResult saveResult=m_repository.Save(basket);
         if(saveResult.IsFail())
            return saveResult;
        }

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
      AuditResult(result);
      if(result.HasIssues())
         return SuspendBasketIfRequired(result);

      if(m_snapshotStore==NULL || result.BasketId().IsEmpty())
         return CVoidResult::Ok();

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

      return m_snapshotStore.ReplaceEntries(result.BasketId(),matched,matchedCount);
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
         CReconciliationResult result=ReconcileBasket(basketIds[i],brokerEntries,brokerCount);
         CVoidResult applyResult=ApplyReconciliationResult(result,brokerEntries,brokerCount);
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
         CReconciliationResult result=ReconcileBasket(basket.Id(),brokerEntries,brokerCount);
         ApplyReconciliationResult(result,brokerEntries,brokerCount);
         processed++;
        }

      return processed;
     }
  };

#endif
