#ifndef BASKET_RECOVERY_APPLICATION_ACTIVATE_BASKET_COMMAND_HANDLER_MQH
#define BASKET_RECOVERY_APPLICATION_ACTIVATE_BASKET_COMMAND_HANDLER_MQH

#include <BasketRecovery/Application/Ports/ICommandHandler.mqh>
#include <BasketRecovery/Application/Ports/IBasketRepository.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Application/Ports/IUniqueIdGenerator.mqh>
#include <BasketRecovery/Application/Handlers/StateTransitionHandler.mqh>
#include <BasketRecovery/Application/Commands/ActivateBasketCommand.mqh>
#include <BasketRecovery/Domain/Requests/TransitionRequest.mqh>
#include <BasketRecovery/Domain/Validation/BasketValidator.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CActivateBasketCommandHandler : public ICommandHandler
  {
private:
   IBasketRepository         *m_repository;
   CStateTransitionHandler   *m_transitionHandler;
   IClock                    *m_clock;
   IUniqueIdGenerator        *m_idGenerator;

   void              TransferEvents(CCommandExecutionResult &target,CCommandExecutionResult &source)
     {
      while(source.EventCount()>0)
        {
         CDomainEvent *event=source.ReleaseEventAt(0);
         if(event!=NULL)
            target.AddEvent(event);
        }
     }

public:
                     CActivateBasketCommandHandler(IBasketRepository *repository,
                                                     CStateTransitionHandler *transitionHandler,
                                                     IClock *clock,
                                                     IUniqueIdGenerator *idGenerator)
     {
      m_repository=repository;
      m_transitionHandler=transitionHandler;
      m_clock=clock;
      m_idGenerator=idGenerator;
     }

   virtual          ~CActivateBasketCommandHandler(void) {}

   virtual bool      CanHandle(const ICommand *command) const
     {
      return command!=NULL && command.Type()==BRE_COMMAND_ACTIVATE_BASKET;
     }

   virtual CResult<CCommandExecutionResult> Execute(ICommand *command)
     {
      CActivateBasketCommand *activateCommand=(CActivateBasketCommand*)command;
      if(activateCommand==NULL || m_repository==NULL || m_transitionHandler==NULL)
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_COMMAND_INVALID,"Activate basket dependencies are missing");

      CResult<CBasketAggregate> loadResult=m_repository.Load(activateCommand.BasketId());
      if(loadResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(loadResult.ErrorCode(),loadResult.ErrorMessage());

      CBasketAggregate aggregate;
      if(!loadResult.TryGetValue(aggregate))
         return CResult<CCommandExecutionResult>::Fail(BRE_ERR_BASKET_NOT_FOUND,"Aggregate missing after load");

      CCommandId commandId=activateCommand.Id().IsEmpty() ? CCommandId(m_idGenerator.NewGuid()) : activateCommand.Id();
      CEventId detailsEventId(m_idGenerator.NewGuid());
      CEventId lifecycleEventId(m_idGenerator.NewGuid());
      CUtcTime timestampUtc(m_clock!=NULL ? m_clock.Now() : 0);

      CTransitionRequest detailsRequest;
      detailsRequest.SetKind(BRE_TRANSITION_REQUEST_SIGNAL_DETAILS);
      detailsRequest.SetBasketId(aggregate.Id());
      detailsRequest.SetCommandId(commandId);
      detailsRequest.SetEventId(detailsEventId);
      detailsRequest.SetSignalDetailsPayload(activateCommand.Details());

      CResult<CCommandExecutionResult> detailsResult=m_transitionHandler.ProcessSignalDetails(aggregate,detailsRequest,timestampUtc);
      if(detailsResult.IsFail())
         return detailsResult;

      CTransitionRequest lifecycleRequest=CTransitionRequest::ForLifecycle(aggregate.Id(),commandId,lifecycleEventId,BRE_EVENT_BASKET_ACTIVATED);
      CResult<CCommandExecutionResult> lifecycleResult=m_transitionHandler.ProcessLifecycle(aggregate,lifecycleRequest,timestampUtc);
      if(lifecycleResult.IsFail())
         return lifecycleResult;

      CVoidResult validation=CBasketValidator::Validate(aggregate);
      if(validation.IsFail())
         return CResult<CCommandExecutionResult>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      CVoidResult saveResult=m_repository.Save(aggregate);
      if(saveResult.IsFail())
         return CResult<CCommandExecutionResult>::Fail(saveResult.ErrorCode(),saveResult.ErrorMessage());

      CCommandExecutionResult executionResult;
      CCommandExecutionResult detailsExecution;
      CCommandExecutionResult lifecycleExecution;
      if(detailsResult.TryGetValue(detailsExecution))
         TransferEvents(executionResult,detailsExecution);
      if(lifecycleResult.TryGetValue(lifecycleExecution))
         TransferEvents(executionResult,lifecycleExecution);

      return CResult<CCommandExecutionResult>::Ok(executionResult);
     }
  };

#endif
