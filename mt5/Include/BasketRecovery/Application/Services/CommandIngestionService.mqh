#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_INGESTION_SERVICE_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_INGESTION_SERVICE_MQH

#include <BasketRecovery/Application/Ports/ICommandSource.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCommandIngestionService
  {
private:
   ICommandSource *m_commandSource;
   ICommandQueue  *m_commandQueue;
   ILogger        *m_logger;
   bool            m_fetchInFlight;
   int             m_lastEnqueuedCount;
   int             m_lastDuplicateCount;
   int             m_lastAckCount;
   int             m_lastRejectedCount;

   bool              ShouldSkipDuplicate(const ICommand *command) const
     {
      if(command==NULL)
         return true;
      if(command.IdempotencyKey()=="")
         return false;
      return m_commandQueue.FindByIdempotencyKey(command.IdempotencyKey())!=NULL;
     }

public:
                     CCommandIngestionService(ICommandSource *commandSource,
                                              ICommandQueue *commandQueue,
                                              ILogger *logger)
     {
      m_commandSource=commandSource;
      m_commandQueue=commandQueue;
      m_logger=logger;
      m_fetchInFlight=false;
      m_lastEnqueuedCount=0;
      m_lastDuplicateCount=0;
      m_lastAckCount=0;
      m_lastRejectedCount=0;
     }

   int               LastEnqueuedCount(void) const { return m_lastEnqueuedCount; }
   int               LastDuplicateCount(void) const { return m_lastDuplicateCount; }
   int               LastAckCount(void) const { return m_lastAckCount; }
   int               LastRejectedCount(void) const { return m_lastRejectedCount; }
   bool              IsFetchInFlight(void) const { return m_fetchInFlight; }

   CVoidResult       PollAndEnqueue(void)
     {
      m_lastEnqueuedCount=0;
      m_lastDuplicateCount=0;
      m_lastAckCount=0;
      m_lastRejectedCount=0;

      if(m_commandSource==NULL || m_commandQueue==NULL)
         return CVoidResult::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Command ingestion dependencies are missing");

      if(!m_commandSource.IsAvailable())
         return CVoidResult::Ok();

      if(m_fetchInFlight)
         return CVoidResult::Ok();

      m_fetchInFlight=true;

      ICommand *commands[];
      CResult<int> fetchResult=m_commandSource.FetchPending(commands);
      if(fetchResult.IsFail())
        {
         m_fetchInFlight=false;
         if(m_logger!=NULL)
            m_logger.Warn("REST","PollFailed","",fetchResult.ErrorMessage(),fetchResult.ErrorCode());
         return CVoidResult::Fail(fetchResult.ErrorCode(),fetchResult.ErrorMessage());
        }

      int fetchedCount=0;
      fetchResult.TryGetValue(fetchedCount);
      m_lastRejectedCount=m_commandSource.LastValidationRejectedCount();

      for(int i=0;i<ArraySize(commands);i++)
        {
         ICommand *command=commands[i];
         if(command==NULL)
            continue;

         if(ShouldSkipDuplicate(command))
           {
            m_lastDuplicateCount++;
            CVoidResult ackResult=m_commandSource.Acknowledge(command.Id());
            if(ackResult.IsOk())
               m_lastAckCount++;
            delete command;
            continue;
           }

         CVoidResult enqueueResult=m_commandQueue.Enqueue(command);
         if(enqueueResult.IsFail())
           {
            if(m_logger!=NULL)
               m_logger.Warn("REST","EnqueueFailed",command.BasketId().Value(),enqueueResult.ErrorMessage(),enqueueResult.ErrorCode());
            delete command;
            continue;
           }

         m_lastEnqueuedCount++;
         CVoidResult ackResult=m_commandSource.Acknowledge(command.Id());
         if(ackResult.IsOk())
            m_lastAckCount++;
         else if(m_logger!=NULL)
            m_logger.Warn("REST","AckFailed",command.Id().Value(),ackResult.ErrorMessage(),ackResult.ErrorCode());
        }

      m_fetchInFlight=false;

      if(m_logger!=NULL && (m_lastEnqueuedCount>0 || m_lastDuplicateCount>0 || m_lastRejectedCount>0))
         m_logger.Debug("REST","PollCompleted","",
                        StringFormat("fetched=%d enqueued=%d duplicates=%d rejected=%d acked=%d pending=%d",
                                     fetchedCount,
                                     m_lastEnqueuedCount,
                                     m_lastDuplicateCount,
                                     m_lastRejectedCount,
                                     m_lastAckCount,
                                     m_commandQueue.PendingCount()));

      return CVoidResult::Ok();
     }
  };

#endif
