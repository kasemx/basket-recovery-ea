#ifndef BASKET_RECOVERY_APPLICATION_ICOMMAND_QUEUE_MQH
#define BASKET_RECOVERY_APPLICATION_ICOMMAND_QUEUE_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/Commands/ICommand.mqh>

class ICommandQueue
  {
public:
   virtual          ~ICommandQueue(void) {}
   virtual CVoidResult Enqueue(ICommand *command)=0;
   virtual ICommand* DequeueNext(void)=0;
   virtual CVoidResult MarkCompleted(const CCommandId &commandId)=0;
   virtual CVoidResult MarkFailed(const CCommandId &commandId,const int errorCode,const string &message)=0;
   virtual ICommand* FindByIdempotencyKey(const string idempotencyKey)=0;
   virtual int       PendingCount(void) const=0;
  };

#endif
