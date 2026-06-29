#ifndef BRE_APP_BREAK_EVEN_CANDIDATE_EVENT_BUFFER_MQH
#define BRE_APP_BREAK_EVEN_CANDIDATE_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/BreakEvenCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CBreakEvenCandidateEventBuffer
  {
private:
   CBreakEvenCandidateDomainEvent m_events[];
   string                         m_seenKeys[];
   int                            m_count;

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
                                   const CBasketId &basketId,
                                   const ulong quoteSequence) const
     {
      return CEventTypeHelper::ToString(eventType)+":"+basketId.Value()+":"+IntegerToString((long)quoteSequence);
     }

public:
                     CBreakEvenCandidateEventBuffer(void)
     {
      m_count=0;
     }

   bool              HasSeenQuoteSequence(const CBasketId &basketId,
                                          const ulong quoteSequence) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_events[i].BasketId().Value()==basketId.Value() &&
            m_events[i].QuoteSequence()==quoteSequence)
            return true;
        }
      return false;
     }

   bool              TryEmit(const CBreakEvenCandidateDomainEvent &event)
     {
      string key=BuildEventKey(event.EventType(),event.BasketId(),event.QuoteSequence());
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

   bool              EventAt(const int index,CBreakEvenCandidateDomainEvent &event) const
     {
      if(index<0 || index>=m_count)
         return false;
      event=m_events[index];
      return true;
     }

   void              Clear(void)
     {
      m_count=0;
      ArrayResize(m_events,0);
      ArrayResize(m_seenKeys,0);
     }
  };

#endif
