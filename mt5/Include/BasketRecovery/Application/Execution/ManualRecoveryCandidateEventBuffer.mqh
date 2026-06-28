#ifndef BRE_APP_MANUAL_RECOVERY_CANDIDATE_EVENT_BUFFER_MQH
#define BRE_APP_MANUAL_RECOVERY_CANDIDATE_EVENT_BUFFER_MQH

#include <BasketRecovery/Domain/Events/ManualRecoveryCandidateDomainEvent.mqh>

class CManualRecoveryCandidateEventBuffer
  {
private:
   CManualRecoveryCandidateDomainEvent m_events[];
   int                                 m_capacity;

public:
                     CManualRecoveryCandidateEventBuffer(const int capacity=256)
     {
      m_capacity=capacity>0 ? capacity : 256;
     }

   bool              TryEmit(const CManualRecoveryCandidateDomainEvent &event)
     {
      int size=ArraySize(m_events);
      if(size>=m_capacity)
         return false;
      ArrayResize(m_events,size+1);
      m_events[size]=event;
      return true;
     }

   int               Count(void) const { return ArraySize(m_events); }

   bool              EventAt(const int index,CManualRecoveryCandidateDomainEvent &event) const
     {
      if(index<0 || index>=ArraySize(m_events))
         return false;
      event=m_events[index];
      return true;
     }

   void              Clear(void) { ArrayResize(m_events,0); }
  };

#endif
