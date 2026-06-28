#ifndef BRE_APP_RECOVERY_CANDIDATE_EVENT_BUFFER_MQH
#define BRE_APP_RECOVERY_CANDIDATE_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/RecoveryCandidateDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CRecoveryCandidateEventBuffer
  {
private:
   CRecoveryCandidateDomainEvent m_events[];
   string                        m_seenKeys[];
   int                           m_count;

   int               FindKeyIndex(const string key) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_seenKeys[i]==key)
            return i;
        }
      return -1;
     }

   string            BuildEventKey(const CBasketId &basketId,
                                   const int stepIndex,
                                   const ulong quoteSequence) const
     {
      return basketId.Value()+":step:"+IntegerToString(stepIndex)+":q:"+IntegerToString((long)quoteSequence);
     }

public:
                     CRecoveryCandidateEventBuffer(void)
     {
      m_count=0;
     }

   bool              HasSeen(const CBasketId &basketId,const int stepIndex,const ulong quoteSequence) const
     {
      string key=BuildEventKey(basketId,stepIndex,quoteSequence);
      return FindKeyIndex(key)>=0;
     }

   bool              TryEmit(const CRecoveryCandidateDomainEvent &event)
     {
      string key=BuildEventKey(event.BasketId(),event.Audit().RecoveryStepIndex(),event.QuoteSequence());
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

   bool              EventAt(const int index,CRecoveryCandidateDomainEvent &event) const
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
