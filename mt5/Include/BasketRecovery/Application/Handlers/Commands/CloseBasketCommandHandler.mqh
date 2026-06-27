#ifndef BASKET_RECOVERY_APPLICATION_CLOSE_BASKET_COMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_CLOSE_BASKET_COMMAND_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Commands/CloseBasketCommand.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CCloseBasketCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository         *m_repository;
   CStateTransitionHandler   *m_transitionHandler;
   IClock                    *m_clock;
   IUniqueIdGenerator        *m_idGenerator;

public:
                     CCloseBasketCommandHandler(IBasketRepository *repository,
                                                  CStateTransitionHandler *transitionHandler,
                                                  IClock *clock,
                                                  IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_transitionHandler=transitionHandler;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual          ~CCloseBasketCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_CLOSE_BASKET;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CCloseBasketCommand *closeCommand=(CCloseBasketCommand*)command;
      if(closeCommand==NULL || m_repository==NULL || m_transitionHandler==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Close basket dependencies are missing");

      CResult<CBasketAggregate> loadResult=m_repository.Load(closeCommand.BasketId());
      if(loadResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loadResult.ErrorCode(),loadResult.ErrorMessage());

      CBasketAggregate aggregate;
      if(!loadResult.TryGetValue(aggregate))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Aggregate missing after load");

      CCommandId commandId=closeCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : closeCommand.Id();
      CEventId eventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CTransitionRequest request=CTransitionRequest::ForClose(aggregate.Id(),commandId,eventId,closeCommand.Reason());
      CResult<CCommandExecutionResult> lifecycleResult=m_transitionHandler.ProcessLifecycle(aggregate,request,timestampUtc);
      if(lifecycleResult.IsFail())
         return lifecycleResult;

      CVoidResult validation=CBasketValidator::Validate(aggregate);
      if(validation.IsFail())
         return CResult<CCommandExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      CVoidResult saveResult=m_repository.Save(aggregate);
      if(saveResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      CCommandExecutionResult executionResult;
      CCommandExecutionResult lifecycleExecution;
      if(lifecycleResult.TryGetValue(lifecycleExecution))
        {
         while(lifecycleExecution.EventCount()>0)
           {
            CDomainEvent *event=lifecycleExecution.ReleaseEventAt(0);
            if(event!=NULL)
               executionResult.AddEvent(event);
           }
        }

      CDomainEvent *closedEvent=new CDomainEvent();
      closedEvent.SetEventType(BRE_EVENT_BASKET_CLOSING);
      closedEvent.SetBasketId(aggregate.Id());
      closedEvent.SetOccurredAt(timestampUtc.Value());
      executionResult.AddEvent(closedEvent);

      return BreResultOkAdopting(executionResult);
     }
  };

#endif
