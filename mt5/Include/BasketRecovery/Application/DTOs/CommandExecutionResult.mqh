#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_EXECUTION_RESULT_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_EXECUTION_RESULT_MQH

#include <BasketRecovery/Domain/Events/DomainEvent.mqh>

class CCommandExecutionResult
  {
private:
   CDomainEvent *m_events[];
   int            m_eventCount;

public:
                     CCommandExecutionResult(void)
     {
      m_eventCount=0;
      ArrayResize(m_events,0);
     }

                     CCommandExecutionResult(const CCommandExecutionResult &other)
     {
      m_eventCount=other.m_eventCount;
      ArrayResize(m_events,m_eventCount);
      for(int i=0;i<m_eventCount;i++)
         m_events[i]=other.m_events[i];
      ((CCommandExecutionResult&)other).m_eventCount=0;
      ArrayResize(((CCommandExecutionResult&)other).m_events,0);
     }

                    ~CCommandExecutionResult(void)
     {
      ClearEvents();
     }

   int               EventCount(void) const { return m_eventCount; }

   CDomainEvent*     EventAt(const int index) const
     {
      if(index<0 || index>=m_eventCount)
         return NULL;
      return m_events[index];
     }

   CDomainEvent*     ReleaseEventAt(const int index)
     {
      if(index<0 || index>=m_eventCount)
         return NULL;
      CDomainEvent *released=m_events[index];
      for(int i=index;i<m_eventCount-1;i++)
         m_events[i]=m_events[i+1];
      m_eventCount--;
      ArrayResize(m_events,m_eventCount);
      return released;
     }

   void              AddEvent(CDomainEvent *domainEvent)
     {
      if(domainEvent==NULL)
         return;
      ArrayResize(m_events,m_eventCount+1);
      m_events[m_eventCount]=domainEvent;
      m_eventCount++;
     }

   void              ClearEvents(void)
     {
      for(int i=0;i<m_eventCount;i++)
        {
         if(m_events[i]!=NULL)
           {
            delete m_events[i];
            m_events[i]=NULL;
           }
        }
      m_eventCount=0;
      ArrayResize(m_events,0);
     }

   void              TransferEventsTo(CCommandExecutionResult &target)
     {
      for(int i=0;i<m_eventCount;i++)
        {
         target.AddEvent(m_events[i]);
         m_events[i]=NULL;
        }
      m_eventCount=0;
      ArrayResize(m_events,0);
     }
  };

#endif
