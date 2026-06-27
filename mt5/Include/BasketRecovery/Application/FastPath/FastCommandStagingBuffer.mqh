#ifndef BRE_APP_FAST_COMMAND_STAGING_BUFFER_MQH
#define BRE_APP_FAST_COMMAND_STAGING_BUFFER_MQH

#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CFastCommandStagingBuffer : public ICommandQueue
  {
private:
   ICommand *m_items[];
   int       m_count;

   bool      HasIdempotencyKey(const string key) const
     {
      if(key=="")
         return false;
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].IdempotencyKey()==key)
            return true;
        }
      return false;
     }

   int FindIndexByIdempotencyKey(const string idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].IdempotencyKey()==idempotencyKey)
            return i;
        }
      return -1;
     }

   int FindIndexByCommandId(const CCommandId &commandId) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Id().Value()==commandId.Value())
            return i;
        }
      return -1;
     }

   void RemoveAt(const int index)
     {
      if(index<0 || index>=m_count)
         return;
      for(int i=index;i<m_count-1;i++)
         m_items[i]=m_items[i+1];
      m_count--;
      ArrayResize(m_items,m_count);
     }

public:
                     CFastCommandStagingBuffer(void)
     {
      m_count=0;
     }

   virtual          ~CFastCommandStagingBuffer(void)
     {
      Clear();
     }

   virtual CVoidResult Enqueue(ICommand *command)
     {
      if(command==NULL)
         return CVoidResult::Fail(BRE_ERR_COMMAND_INVALID,"Command is null");

      if(HasIdempotencyKey(command.IdempotencyKey()))
        {
         delete command;
         return CVoidResult::Ok();
        }

      ArrayResize(m_items,m_count+1);
      m_items[m_count]=command;
      m_count++;
      return CVoidResult::Ok();
     }

   virtual ICommand* DequeueNext(void)
     {
      if(m_count==0)
         return NULL;
      ICommand *command=m_items[0];
      for(int i=0;i<m_count-1;i++)
         m_items[i]=m_items[i+1];
      m_count--;
      ArrayResize(m_items,m_count);
      return command;
     }

   virtual int       PendingCount(void) const { return m_count; }

   virtual CVoidResult MarkCompleted(const CCommandId &commandId)
     {
      int index=FindIndexByCommandId(commandId);
      if(index<0)
         return CVoidResult::Fail(BRE_ERR_COMMAND_INVALID,"Command not found for completion");
      if(m_items[index]!=NULL)
        {
         delete m_items[index];
         m_items[index]=NULL;
        }
      RemoveAt(index);
      return CVoidResult::Ok();
     }

   virtual CVoidResult MarkFailed(const CCommandId &commandId,const int errorCode,const string &message)
     {
      int index=FindIndexByCommandId(commandId);
      if(index<0)
         return CVoidResult::Fail(errorCode,message);
      CCommandBase *commandBase=(CCommandBase*)m_items[index];
      if(commandBase!=NULL)
         commandBase.SetStatus(BRE_COMMAND_STATUS_FAILED);
      return CVoidResult::Ok();
     }

   virtual ICommand* FindByIdempotencyKey(const string idempotencyKey)
     {
      int index=FindIndexByIdempotencyKey(idempotencyKey);
      if(index<0)
         return NULL;
      return m_items[index];
     }

   int               FlushTo(ICommandQueue *targetQueue)
     {
      if(targetQueue==NULL)
         return 0;

      int flushed=0;
      while(m_count>0)
        {
         ICommand *command=DequeueNext();
         if(command==NULL)
            break;
         if(targetQueue.Enqueue(command).IsOk())
            flushed++;
         else
            delete command;
        }
      return flushed;
     }

   void              Clear(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL)
           {
            delete m_items[i];
            m_items[i]=NULL;
           }
        }
      m_count=0;
      ArrayResize(m_items,0);
     }
  };

#endif
