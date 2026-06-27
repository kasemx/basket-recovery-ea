#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_DISPATCHER_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_DISPATCHER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

struct SCommandHandlerRegistration
  {
   ICommandHandler *handler;
   int              priority;
  };

class CCommandDispatcher
  {
private:
   SCommandHandlerRegistration m_handlers[];
   int                         m_handlerCount;

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
                     CCommandDispatcher(void)
     {
      m_handlerCount=0;
      ArrayResize(m_handlers,0);
     }

                    ~CCommandDispatcher(void) {}

   void              RegisterHandler(ICommandHandler *handler,const int priority)
     {
      if(handler==NULL)
         return;

      int insertIndex=FindInsertIndex(priority);
      ArrayResize(m_handlers,m_handlerCount+1);

      for(int i=m_handlerCount;i>insertIndex;i--)
         m_handlers[i]=m_handlers[i-1];

      m_handlers[insertIndex].handler=handler;
      m_handlers[insertIndex].priority=priority;
      m_handlerCount++;
     }

   int               HandlerCount(void) const { return m_handlerCount; }

   CResult<CCommandExecutionResult> Dispatch(ICommand *command)
     {
      if(command==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Command is null");

      for(int i=0;i<m_handlerCount;i++)
        {
         if(m_handlers[i].handler==NULL)
            continue;
         if(!m_handlers[i].handler.CanHandle(command))
            continue;
         return m_handlers[i].handler.Execute(command);
        }

      return CResult<CCommandExecutionResult>::Fail(BRE_ERR_HANDLER_NOT_FOUND,
                                                    StringFormat("No handler for command type %d",command.Type()));
     }
  };

#endif
