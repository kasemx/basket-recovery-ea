#ifndef BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_EVENT_BUFFER_MQH
#define BRE_APP_PROFIT_LEVEL_CLOSE_CANDIDATE_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/ProfitLevelCloseCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CProfitLevelCloseCandidateEventBuffer
  {
private:
   CProfitLevelCloseCandidateDomainEvent m_events[];
   string                                m_seenKeys[];
   int                                   m_count;

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
                                   const string profitLevelId,
                                   const ulong quoteSequence) const
     {
      return CEventTypeHelper::ToString(eventType)+":"+basketId.Value()+":"+profitLevelId+":"+IntegerToString((long)quoteSequence);
     }

public:
                     CProfitLevelCloseCandidateEventBuffer(void)
     {
      m_count=0;
     }

   bool              HasSeen(const ENUM_BRE_EVENT_TYPE eventType,
                             const CBasketId &basketId,
                             const string profitLevelId,
                             const ulong quoteSequence) const
     {
      string key=BuildEventKey(eventType,basketId,profitLevelId,quoteSequence);
      return FindKeyIndex(key)>=0;
     }

   bool              HasSeenQuoteSequence(const CBasketId &basketId,
                                          const string profitLevelId,
                                          const ulong quoteSequence) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_events[i].BasketId().Value()==basketId.Value() &&
            m_events[i].Audit().ProfitLevelId()==profitLevelId &&
            m_events[i].QuoteSequence()==quoteSequence)
            return true;
        }
      return false;
     }

   bool              TryEmit(const CProfitLevelCloseCandidateDomainEvent &event)
     {
      string key=BuildEventKey(event.EventType(),event.BasketId(),event.Audit().ProfitLevelId(),event.QuoteSequence());
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

   bool              EventAt(const int index,CProfitLevelCloseCandidateDomainEvent &event) const
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
