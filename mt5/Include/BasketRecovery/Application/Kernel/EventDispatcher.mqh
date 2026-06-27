#ifndef BASKET_RECOVERY_APPLICATION_EVENT_DISPATCHER_MQH
#define BASKET_RECOVERY_APPLICATION_EVENT_DISPATCHER_MQH

#include <BasketRecovery/Application/Ports/IEventHandler.mqh>
#include <BasketRecovery/Shared/Types/ResultValueTransfer.mqh>

struct SEventDispatcherRegistration
  {
   IEventHandler *handler;
   int            priority;
  };

class CEventDispatcher
  {
private:
   SEventDispatcherRegistration m_handlers[];
   int                          m_handlerCount;

   int FindInsertIndex(const int priority) const
     {
      for(int i=0;i<m_handlerCount;i++)
        {
         if(m_handlers[i].priority>priority)
            return i;
        }
      return m_handlerCount;
     }

public:
                     CEventDispatcher(void)
     {
      m_handlerCount=0;
      ArrayResize(m_handlers,0);
     }

                    ~CEventDispatcher(void) {}

   void              RegisterHandler(IEventHandler *handler)
     {
      if(handler==NULL)
         return;

      int insertIndex=FindInsertIndex(handler.Priority());
      ArrayResize(m_handlers,m_handlerCount+1);

      for(int i=m_handlerCount;i>insertIndex;i--)
         m_handlers[i]=m_handlers[i-1];

      m_handlers[insertIndex].handler=handler;
      m_handlers[insertIndex].priority=handler.Priority();
      m_handlerCount++;
     }

   int               HandlerCount(void) const { return m_handlerCount; }

   CResult<CEventHandlingResult> Dispatch(CDomainEvent *domainEvent)
     {
      if(domainEvent==NULL)
         return CResult<CEventHandlingResult>::Fail(BRE_ERR_EVENT_INVALID,"Domain event is null");

      CEventHandlingResult aggregateResult;

      for(int i=0;i<m_handlerCount;i++)
        {
         if(m_handlers[i].handler==NULL)
            continue;
         if(!m_handlers[i].handler.CanHandle(domainEvent))
            continue;

         CResult<CEventHandlingResult> handlerResult=m_handlers[i].handler.Handle(domainEvent);
         if(handlerResult.IsFail())
            return handlerResult;

         CEventHandlingResult partial;
         if(BreResultTryAdoptValue(handlerResult,partial))
            partial.TransferCommandsTo(aggregateResult);
        }

      return BreResultOkAdopting(aggregateResult);
     }
  };

#endif
