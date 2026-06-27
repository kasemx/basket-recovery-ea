#ifndef BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_COMMAND_QUEUE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_IN_MEMORY_COMMAND_QUEUE_MQH

#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Commands/CommandBase.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryCommandQueue : public ICommandQueue
  {
private:
   ICommand *m_items[];
   string    m_completedKeys[];
   int       m_count;

   int FindIndexByIdempotencyKey(const string idempotencyKey) const
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].IdempotencyKey()==idempotencyKey)
            return i;
        }
      return -1;
     }

   bool IsCompletedKey(const string idempotencyKey) const
     {
      for(int i=0;i<ArraySize(m_completedKeys);i++)
        {
         if(m_completedKeys[i]==idempotencyKey)
            return true;
        }
      return false;
     }

public:
                     CInMemoryCommandQueue(void)
     {
      m_count=0;
      ArrayResize(m_items,0);
      ArrayResize(m_completedKeys,0);
     }

   virtual          ~CInMemoryCommandQueue(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL)
           {
            delete m_items[i];
            m_items[i]=NULL;
           }
        }
     }

   virtual CVoidResult Enqueue(ICommand *command)
     {
      if(command==NULL)
         return CVoidResult::Fail(BRE_ERR_COMMAND_INVALID,"Command is null");

      if(command.IdempotencyKey()!="" && IsCompletedKey(command.IdempotencyKey()))
         return CVoidResult::Ok();

      int existingIndex=FindIndexByIdempotencyKey(command.IdempotencyKey());
      if(existingIndex>=0)
         return CVoidResult::Ok();

      ArrayResize(m_items,m_count+1);
      m_items[m_count]=command;
      m_count++;
      return CVoidResult::Ok();
     }

   virtual ICommand* DequeueNext(void)
     {
      if(m_count==0)
         return NULL;

      int bestIndex=-1;
      int bestPriority=-1;
      datetime bestTime=0;

      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]==NULL)
            continue;
         if(m_items[i].Status()!=BRE_COMMAND_STATUS_PENDING)
            continue;

         if(bestIndex<0 ||
            m_items[i].Priority()>bestPriority ||
            (m_items[i].Priority()==bestPriority && (bestTime==0 || m_items[i].EnqueuedAt()<bestTime)))
           {
            bestIndex=i;
            bestPriority=m_items[i].Priority();
            bestTime=m_items[i].EnqueuedAt();
           }
        }

      if(bestIndex<0)
         return NULL;

      return m_items[bestIndex];
     }

   virtual CVoidResult MarkCompleted(const CCommandId &commandId)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Id().Value()==commandId.Value())
           {
            int size=ArraySize(m_completedKeys);
            ArrayResize(m_completedKeys,size+1);
            m_completedKeys[size]=m_items[i].IdempotencyKey();
            delete m_items[i];
            m_items[i]=NULL;
            return CVoidResult::Ok();
           }
        }
      return CVoidResult::Fail(BRE_ERR_COMMAND_INVALID,"Command not found for completion");
     }

   virtual CVoidResult MarkFailed(const CCommandId &commandId,const int errorCode,const string &message)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Id().Value()==commandId.Value())
           {
            CCommandBase *commandBase=(CCommandBase*)m_items[i];
            if(commandBase!=NULL)
               commandBase.SetStatus(BRE_COMMAND_STATUS_FAILED);
            return CVoidResult::Ok();
           }
        }
      return CVoidResult::Fail(errorCode,message);
     }

   virtual ICommand* FindByIdempotencyKey(const string idempotencyKey)
     {
      int index=FindIndexByIdempotencyKey(idempotencyKey);
      if(index<0)
         return NULL;
      return m_items[index];
     }

   virtual int PendingCount(void) const
     {
      int pending=0;
      for(int i=0;i<m_count;i++)
        {
         if(m_items[i]!=NULL && m_items[i].Status()==BRE_COMMAND_STATUS_PENDING)
            pending++;
        }
      return pending;
     }
  };

#endif
