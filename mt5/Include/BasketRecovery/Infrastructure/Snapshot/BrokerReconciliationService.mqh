#ifndef BASKET_RECOVERY_INFRASTRUCTURE_BROKER_RECONCILIATION_SERVICE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_BROKER_RECONCILIATION_SERVICE_MQH

#include <BasketRecovery/Application/Ports/IBrokerReconciliationService.mqh>
#include <BasketRecovery/Application/Ports/IPositionSnapshotStore.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CBrokerReconciliationService : public IBrokerReconciliationService
  {
private:
   IPositionSnapshotStore *m_snapshotStore;
   IClock                 *m_clock;
   ILogger                *m_logger;

   CBasketId ExtractBasketIdFromComment(const string comment) const
     {
      int prefixIndex=StringFind(comment,"BR:");
      if(prefixIndex<0)
         return CBasketId("");

      string remainder=StringSubstr(comment,prefixIndex+3);
      int separatorIndex=StringFind(remainder,":");
      if(separatorIndex>=0)
         remainder=StringSubstr(remainder,0,separatorIndex);

      return CBasketId(remainder);
     }

   bool BasketKeyExists(const CBasketId &basketId,const CBasketId &knownIds[],const int knownCount) const
     {
      for(int i=0;i<knownCount;i++)
        {
         if(knownIds[i]==basketId)
            return true;
        }
      return false;
     }

public:
                     CBrokerReconciliationService(IPositionSnapshotStore *snapshotStore,
                                                  IClock *clock,
                                                  ILogger *logger)
     {
      m_snapshotStore=snapshotStore;
      m_clock=clock;
      m_logger=logger;
     }

   virtual          ~CBrokerReconciliationService(void) {}

   virtual CVoidResult ReconcileAtStartup(void)
     {
      if(m_snapshotStore==NULL)
         return CVoidResult::Fail(BRE_ERR_SNAPSHOT_NOT_FOUND,"Snapshot store is not registered");

      CBasketId knownIds[];
      int knownCount=0;

      int totalPositions=PositionsTotal();
      for(int i=0;i<totalPositions;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
            continue;

         if(!PositionSelectByTicket(ticket))
            continue;

         string comment=PositionGetString(POSITION_COMMENT);
         CBasketId basketId=ExtractBasketIdFromComment(comment);
         if(basketId.IsEmpty())
            continue;

         if(BasketKeyExists(basketId,knownIds,knownCount))
            continue;

         ArrayResize(knownIds,knownCount+1);
         knownIds[knownCount]=basketId;
         knownCount++;

         CVoidResult createResult=m_snapshotStore.CreateEmpty(basketId);
         if(createResult.IsFail())
            return createResult;
        }

      if(m_logger!=NULL)
         m_logger.Info("SYSTEM","Reconciliation","",
                       StringFormat("Startup reconciliation completed | snapshots=%d",m_snapshotStore.Count()));

      return CVoidResult::Ok();
     }
  };

#endif
