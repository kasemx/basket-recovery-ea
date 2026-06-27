#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_EVENT_BUS_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_EVENT_BUS_MQH

#include <BasketRecovery/Application/Ports/IEventBus.mqh>
#include <BasketRecovery/Application/Ports/IEventHandler.mqh>

struct SEventHandlerRegistration
  {
   IEventHandler      *handler;
   int                 priority;
  };

class CInMemoryEventBus : public IEventBus
  {
private:
   CDomainEvent               *m_queue[];
   int                         m_queueCount;
   SEventHandlerRegistration   m_handlers[];
   int                         m_handlerCount;

   int FindHandlerInsertIndex(const int priority) const
     {
      for(int i=0;i<m_handlerCount;i++)
        {
         if(m_handlers[i].priority>priority)
            return i;
        }
      return m_handlerCount;
     }

public:
                     CInMemoryEventBus(void)
     {
      m_queueCount=0;
      m_handlerCount=0;
      ArrayResize(m_queue,0);
      ArrayResize(m_handlers,0);
     }

   virtual          ~CInMemoryEventBus(void)
     {
      for(int i=0;i<m_queueCount;i++)
        {
         if(m_queue[i]!=NULL)
           {
            delete m_queue[i];
            m_queue[i]=NULL;
           }
        }
     }

   virtual void     Publish(CDomainEvent *domainEvent)
     {
      if(domainEvent==NULL)
         return;

      ArrayResize(m_queue,m_queueCount+1);
      m_queue[m_queueCount]=domainEvent;
      m_queueCount++;
     }

   virtual void     Subscribe(const ENUM_BRE_EVENT_TYPE eventType,IEventHandler *handler)
     {
      if(handler==NULL)
         return;

      int insertIndex=FindHandlerInsertIndex(handler.Priority());
      ArrayResize(m_handlers,m_handlerCount+1);

      for(int i=m_handlerCount;i>insertIndex;i--)
         m_handlers[i]=m_handlers[i-1];

      m_handlers[insertIndex].handler=handler;
      m_handlers[insertIndex].priority=handler.Priority();
      m_handlerCount++;
     }

   virtual void     DrainQueue(void)
     {
      for(int q=0;q<m_queueCount;q++)
        {
         if(m_queue[q]==NULL)
            continue;

         for(int h=0;h<m_handlerCount;h++)
           {
            if(m_handlers[h].handler==NULL)
               continue;
            if(!m_handlers[h].handler.CanHandle(m_queue[q]))
               continue;

            CResult<CEventHandlingResult> result=m_handlers[h].handler.Handle(m_queue[q]);
            if(result.IsOk())
              {
               CEventHandlingResult handlingResult;
               if(result.TryGetValue(handlingResult))
                  handlingResult.ClearCommands();
              }
           }

         delete m_queue[q];
         m_queue[q]=NULL;
        }

      m_queueCount=0;
      ArrayResize(m_queue,0);
     }

   virtual int      QueueSize(void) const
     {
      return m_queueCount;
     }
  };

#endif
