#ifndef BRE_APP_BREAK_EVEN_MODIFICATION_EVENT_BUFFER_MQH
#define BRE_APP_BREAK_EVEN_MODIFICATION_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/BreakEvenModificationDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CBreakEvenModificationEventBuffer
  {
private:
   CBreakEvenModificationDomainEvent m_events[];
   string                            m_seenKeys[];
   int                               m_count;

   int               FindKeyIndex(const string key) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_seenKeys[i]==key)
            return i;
        }
      return -1;
     }

   string            BuildEventKey(const ENUM_BRE_EVENT_TYPE eventType,
                                   const string idempotencyKey) const
     {
      return CEventTypeHelper::ToString(eventType)+":"+idempotencyKey;
     }

public:
                     CBreakEvenModificationEventBuffer(void)
     {
      m_count=0;
     }

   bool              HasSeenIdempotencyKey(const string idempotencyKey) const
     {
      if(idempotencyKey=="")
         return false;
      for(int i=0;i<m_count;i++)
        {
         if(m_events[i].Audit().Request().IdempotencyKey()==idempotencyKey)
            return true;
        }
      return false;
     }

   bool              TryEmit(const CBreakEvenModificationDomainEvent &event)
     {
      string key=BuildEventKey(event.EventType(),event.Audit().Request().IdempotencyKey());
      if(key=="" || FindKeyIndex(key)>=0)
         return false;

      ArrayResize(m_events,m_count+1);
      ArrayResize(m_seenKeys,m_count+1);
      m_events[m_count]=event;
      m_seenKeys[m_count]=key;
      m_count++;
      return true;
     }

   int               Count(void) const { return m_count; }

   bool              EventAt(const int index,CBreakEvenModificationDomainEvent &event) const
     {
      if(index<0 || index>=m_count)
         return false;
      event=m_events[index];
      return true;
     }
  };

#endif
