#ifndef BASKET_RECOVERY_APPLICATION_EVENT_HANDLING_RESULT_MQH
#define BASKET_RECOVERY_APPLICATION_EVENT_HANDLING_RESULT_MQH

#include <BasketRecovery/Application/Commands/ICommand.mqh>

class CEventHandlingResult
  {
private:
   ICommand *m_commands[];
   int       m_commandCount;

public:
                     CEventHandlingResult(void)
     {
      m_commandCount=0;
      ArrayResize(m_commands,0);
     }

                    ~CEventHandlingResult(void)
     {
      ClearCommands();
     }

   int               CommandCount(void) const { return m_commandCount; }

   ICommand*         CommandAt(const int index) const
     {
      if(index<0 || index>=m_commandCount)
         return NULL;
      return m_commands[index];
     }

   void              AddCommand(ICommand *command)
     {
      if(command==NULL)
         return;
      ArrayResize(m_commands,m_commandCount+1);
      m_commands[m_commandCount]=command;
      m_commandCount++;
     }

   void              ClearCommands(void)
     {
      for(int i=0;i<m_commandCount;i++)
        {
         if(m_commands[i]!=NULL)
           {
            delete m_commands[i];
            m_commands[i]=NULL;
           }
        }
      m_commandCount=0;
      ArrayResize(m_commands,0);
     }

   void              TransferCommandsTo(CEventHandlingResult &target)
     {
      for(int i=0;i<m_commandCount;i++)
        {
         target.AddCommand(m_commands[i]);
         m_commands[i]=NULL;
        }
      m_commandCount=0;
      ArrayResize(m_commands,0);
     }
  };

#endif
