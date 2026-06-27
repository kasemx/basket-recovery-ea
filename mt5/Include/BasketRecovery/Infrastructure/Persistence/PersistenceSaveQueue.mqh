#ifndef BASKET_RECOVERY_INFRASTRUCTURE_PERSISTENCE_SAVE_QUEUE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_PERSISTENCE_SAVE_QUEUE_MQH

#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>

class CPersistenceSaveQueue
  {
private:
   CBasketAggregate  m_pendingAggregates[];
   string            m_pendingKeys[];
   int               m_pendingCount;
   int               m_debounceMs;
   ulong             m_lastEnqueueTickMs;

   int FindIndex(const string basketId) const
     {
      for(int i=0;i<m_pendingCount;i++)
        {
         if(m_pendingKeys[i]==basketId)
            return i;
        }
      return -1;
     }

public:
                     CPersistenceSaveQueue(const int debounceMs=500)
     {
      m_pendingCount=0;
      m_debounceMs=debounceMs;
      m_lastEnqueueTickMs=0;
      ArrayResize(m_pendingAggregates,0);
      ArrayResize(m_pendingKeys,0);
     }

   void              SetDebounceMs(const int value) { m_debounceMs=value; }

   void              QueueSave(const CBasketAggregate &aggregate)
     {
      if(aggregate.Id().IsEmpty())
         return;

      string basketId=aggregate.Id().Value();
      int index=FindIndex(basketId);
      if(index<0)
        {
         ArrayResize(m_pendingAggregates,m_pendingCount+1);
         ArrayResize(m_pendingKeys,m_pendingCount+1);
         m_pendingAggregates[m_pendingCount]=aggregate;
         m_pendingKeys[m_pendingCount]=basketId;
         m_pendingCount++;
        }
      else
        {
         m_pendingAggregates[index]=aggregate;
        }

      m_lastEnqueueTickMs=(ulong)GetTickCount();
     }

   bool              HasPending(void) const { return m_pendingCount>0; }

   bool              ShouldFlush(void) const
     {
      if(m_pendingCount==0)
         return false;
      if(m_debounceMs<=0)
         return true;
      ulong elapsed=(ulong)GetTickCount()-m_lastEnqueueTickMs;
      return elapsed>=(ulong)m_debounceMs;
     }

   CVoidResult       Flush(IBasketRepository &repository)
     {
      for(int i=0;i<m_pendingCount;i++)
        {
         CVoidResult saveResult=repository.Save(m_pendingAggregates[i]);
         if(saveResult.IsFail())
            return saveResult;
        }

      m_pendingCount=0;
      ArrayResize(m_pendingAggregates,0);
      ArrayResize(m_pendingKeys,0);
      return CVoidResult::Ok();
     }
  };

#endif
