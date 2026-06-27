#ifndef BASKET_RECOVERY_APPLICATION_COMMAND_PROCESSOR_MQH
#define BASKET_RECOVERY_APPLICATION_COMMAND_PROCESSOR_MQH

#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Ports/ICommandQueue.mqh>
#include <BasketRecovery/Application/Ports/IIdempotencyStore.mqh>
#include <BasketRecovery/Application/DTOs/CommandExecutionResult.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCommandProcessor
  {
private:
   ICommandQueue       *m_commandQueue;
   CCommandDispatcher  *m_commandDispatcher;
   CEventDispatcher    *m_eventDispatcher;
   IIdempotencyStore   *m_idempotencyStore;
   int                  m_maxIterations;
   int                  m_maxCommandsPerPhase;

   void              EnqueueGeneratedEvents(CCommandExecutionResult &executionResult,
                                            CDomainEvent *phaseEvents[],
                                            int &phaseEventCount)
     {
      int eventCount=executionResult.EventCount();
      for(int i=0;i<eventCount;i++)
        {
         CDomainEvent *event=executionResult.ReleaseEventAt(0);
         if(event==NULL)
            break;
         ArrayResize(phaseEvents,phaseEventCount+1);
         phaseEvents[phaseEventCount]=event;
         phaseEventCount++;
        }
     }

   CVoidResult       ProcessPhaseTwo(CDomainEvent *phaseEvents[],
                                     const int phaseEventCount,
                                     int &commandsGenerated)
     {
      commandsGenerated=0;

      for(int i=0;i<phaseEventCount;i++)
        {
         CDomainEvent *event=phaseEvents[i];
         if(event==NULL)
            continue;

         CResult<CEventHandlingResult> dispatchResult=m_eventDispatcher.Dispatch(event);
         delete event;
         phaseEvents[i]=NULL;

         if(dispatchResult.IsFail())
            return CVoidResult::Fail(dispatchResult.ErrorCode(),dispatchResult.ErrorMessage());

         CEventHandlingResult handlingResult;
         if(!dispatchResult.TryGetValue(handlingResult))
            continue;

         for(int c=0;c<handlingResult.CommandCount();c++)
           {
            ICommand *command=handlingResult.CommandAt(c);
            if(command==NULL)
               continue;

            CVoidResult enqueueResult=m_commandQueue.Enqueue(command);
            if(enqueueResult.IsFail())
               return enqueueResult;
            commandsGenerated++;
           }
         handlingResult.ClearCommands();
        }

      return CVoidResult::Ok();
     }

   CVoidResult       ProcessPhaseOne(int &commandsProcessed,
                                     int &eventsGenerated,
                                     CDomainEvent *phaseEvents[])
     {
      commandsProcessed=0;
      eventsGenerated=0;

      for(int i=0;i<m_maxCommandsPerPhase;i++)
        {
         ICommand *command=m_commandQueue.DequeueNext();
         if(command==NULL)
            break;

         string idempotencyKey=command.IdempotencyKey();
         if(idempotencyKey!="" && m_idempotencyStore!=NULL && m_idempotencyStore.IsProcessed(idempotencyKey))
           {
            m_commandQueue.MarkCompleted(command.Id());
            continue;
           }

         CResult<CCommandExecutionResult> dispatchResult=m_commandDispatcher.Dispatch(command);
         if(dispatchResult.IsFail())
           {
            m_commandQueue.MarkFailed(command.Id(),dispatchResult.ErrorCode(),dispatchResult.ErrorMessage());
            continue;
           }

         CCommandExecutionResult executionResult;
         if(!dispatchResult.TryGetValue(executionResult))
           {
            m_commandQueue.MarkCompleted(command.Id());
            continue;
           }

         EnqueueGeneratedEvents(executionResult,phaseEvents,eventsGenerated);

         if(idempotencyKey!="" && m_idempotencyStore!=NULL)
           {
            CVoidResult markResult=m_idempotencyStore.MarkProcessed(idempotencyKey);
            if(markResult.IsFail())
               return markResult;
           }

         m_commandQueue.MarkCompleted(command.Id());
         commandsProcessed++;
        }

      return CVoidResult::Ok();
     }

public:
                     CCommandProcessor(ICommandQueue *commandQueue,
                                       CCommandDispatcher *commandDispatcher,
                                       CEventDispatcher *eventDispatcher,
                                       IIdempotencyStore *idempotencyStore)
     {
      m_commandQueue=commandQueue;
      m_commandDispatcher=commandDispatcher;
      m_eventDispatcher=eventDispatcher;
      m_idempotencyStore=idempotencyStore;
      m_maxIterations=8;
      m_maxCommandsPerPhase=16;
     }

   void              SetMaxIterations(const int value)
     {
      if(value>0)
         m_maxIterations=value;
     }

   void              SetMaxCommandsPerPhase(const int value)
     {
      if(value>0)
         m_maxCommandsPerPhase=value;
     }

   int               MaxIterations(void) const { return m_maxIterations; }

   CVoidResult       RunCycle(int &totalCommandsProcessed,int &totalEventsProcessed)
     {
      totalCommandsProcessed=0;
      totalEventsProcessed=0;

      if(m_commandQueue==NULL || m_commandDispatcher==NULL || m_eventDispatcher==NULL)
         return CVoidResult::Fail(BRE_ERR_SERVICE_NOT_REGISTERED,"Command processor dependencies are missing");

      for(int iteration=0;iteration<m_maxIterations;iteration++)
        {
         CDomainEvent *phaseEvents[];
         int phaseEventCount=0;
         int commandsProcessed=0;
         int commandsGenerated=0;

         CVoidResult phaseOneResult=ProcessPhaseOne(commandsProcessed,phaseEventCount,phaseEvents);
         if(phaseOneResult.IsFail())
            return phaseOneResult;

         totalCommandsProcessed+=commandsProcessed;
         totalEventsProcessed+=phaseEventCount;

         CVoidResult phaseTwoResult=ProcessPhaseTwo(phaseEvents,phaseEventCount,commandsGenerated);
         if(phaseTwoResult.IsFail())
            return phaseTwoResult;

         if(commandsProcessed==0 && phaseEventCount==0 && commandsGenerated==0)
            break;

         if(iteration==m_maxIterations-1 && commandsGenerated>0)
            return CVoidResult::Fail(BRE_ERR_PROCESSOR_LOOP_LIMIT,"Command processor iteration limit reached");
        }

      return CVoidResult::Ok();
     }
  };

#endif
