#ifndef BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_COPY_IMPL_MQH
#define BASKET_RECOVERY_DOMAIN_BASKET_AGGREGATE_COPY_IMPL_MQH

CBasketAggregate::CBasketAggregate(const CBasketAggregate &other)
  {
   m_id=other.m_id;
   m_correlationKey=other.m_correlationKey;
   m_direction=other.m_direction;
   m_symbol=other.m_symbol;
   m_lifecycleState=other.m_lifecycleState;
   m_modeFlags=other.m_modeFlags;
   m_profileSnapshot=other.m_profileSnapshot;
   m_hasProfileSnapshot=other.m_hasProfileSnapshot;
   m_runtimeState=other.m_runtimeState;
   m_versionState=other.m_versionState;
   m_signal=other.m_signal;
   m_metadata=other.m_metadata;
   m_creationBindingOpen=other.m_creationBindingOpen;
   m_positionSnapshotCount=other.m_positionSnapshotCount;
   m_commandHistoryCount=other.m_commandHistoryCount;
   m_eventHistoryCount=other.m_eventHistoryCount;
   ArrayResize(m_positionSnapshots,m_positionSnapshotCount);
   for(int i=0;i<m_positionSnapshotCount;i++)
     {
      if(other.m_positionSnapshots[i]!=NULL)
        {
         m_positionSnapshots[i]=new CPositionSnapshot();
         m_positionSnapshots[i].SetBasketId(other.m_positionSnapshots[i].BasketId());
         m_positionSnapshots[i].SetVersion(other.m_positionSnapshots[i].Version());
         m_positionSnapshots[i].SetUpdatedAt(other.m_positionSnapshots[i].UpdatedAt());
         m_positionSnapshots[i].SetOpenCount(other.m_positionSnapshots[i].OpenCount());
         m_positionSnapshots[i].SetTransactionCount(other.m_positionSnapshots[i].TransactionCount());
        }
      else
         m_positionSnapshots[i]=NULL;
     }
   ArrayResize(m_commandHistory,m_commandHistoryCount);
   for(int i=0;i<m_commandHistoryCount;i++)
      m_commandHistory[i]=other.m_commandHistory[i];
   ArrayResize(m_eventHistory,m_eventHistoryCount);
   for(int i=0;i<m_eventHistoryCount;i++)
      m_eventHistory[i]=other.m_eventHistory[i];
  }

#endif
