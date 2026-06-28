#ifndef BRE_APP_RECOVERY_RISK_EVENT_BUFFER_MQH
#define BRE_APP_RECOVERY_RISK_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/RecoveryRiskDomainEvent.mqh>
#include <BasketRecovery/Domain/Enums/EventType.mqh>

class CRecoveryRiskEventBuffer
  {
private:
   CRecoveryRiskDomainEvent m_events[];
   string                 m_seenKeys[];
   ulong                  m_lastEmitMs[];
   int                    m_count;
   int                    m_dedupeWindowMs;

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
                                   const string decisionId,
                                   const ulong quoteSequence) const
     {
      return IntegerToString((int)eventType)+":"+decisionId+":"+IntegerToString((long)quoteSequence);
     }

public:
                     CRecoveryRiskEventBuffer(const int dedupeWindowMs=30000)
     {
      m_count=0;
      m_dedupeWindowMs=dedupeWindowMs;
     }

   bool              TryEmit(const CRecoveryRiskDomainEvent &event)
     {
      string key=BuildEventKey(event.EventType(),event.StrategyDecisionId(),event.QuoteSequence());
      if(key=="")
         return false;

      ulong nowMs=GetTickCount64();
      int index=FindKeyIndex(key);
      if(index>=0 && m_dedupeWindowMs>0)
        {
         ulong elapsed=nowMs-m_lastEmitMs[index];
         if(elapsed<(ulong)m_dedupeWindowMs)
            return false;
         m_events[index]=event;
         m_lastEmitMs[index]=nowMs;
         return true;
        }

      ArrayResize(m_events,m_count+1);
      ArrayResize(m_seenKeys,m_count+1);
      ArrayResize(m_lastEmitMs,m_count+1);
      m_events[m_count]=event;
      m_seenKeys[m_count]=key;
      m_lastEmitMs[m_count]=nowMs;
      m_count++;
      return true;
     }

   int               Count(void) const { return m_count; }

   bool              EventAt(const int index,CRecoveryRiskDomainEvent &event) const
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
      ArrayResize(m_lastEmitMs,0);
     }
  };

#endif
